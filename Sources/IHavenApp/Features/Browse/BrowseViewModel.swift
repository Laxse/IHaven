import Foundation
import SwiftUI

/// 浏览（瀑布流）视图模型。仅依赖领域协议（WallhavenAPIProtocol / KeyProvider / WallpaperDatabase /
/// WallpaperEngine / ImageDownloading），不依赖任何 Infrastructure 具体类型（ARCH §4 单向依赖）。
@MainActor
@Observable
final class BrowseViewModel {
    enum LoadState: Sendable {
        case idle, loading, loaded, failed(String)
    }

    var loadState: LoadState = .idle
    var wallpapers: [Wallpaper] = []
    var query = BrowseQuery()
    /// Trap 18：未配置 Key 时结果为静默缩水，产品层提示，技术层不尝试探测缩水。
    var resultsIncomplete: Bool = false
    /// 当前已收藏的壁纸 id 集合（UI 即时反查）。
    var favoriteIDs: Set<String> = []
    /// 收藏列表（侧栏「收藏」视图数据源，来自数据库）。
    var favorites: [Favorite] = []
    /// 已设壁纸记录（侧栏「已设置」视图数据源，来自数据库，按设置时间倒序）。
    var applied: [AppliedWallpaper] = []

    private let client: WallhavenAPIProtocol
    private let keyProvider: KeyProvider
    private let database: WallpaperDatabase
    private let wallpaperEngine: WallpaperEngine
    private let downloader: ImageDownloading
    private let savePanel: FileSavePresenting
    private let clipboard: ClipboardWriting

    init(client: WallhavenAPIProtocol,
         keyProvider: KeyProvider,
         database: WallpaperDatabase,
         wallpaperEngine: WallpaperEngine,
         downloader: ImageDownloading,
         savePanel: FileSavePresenting = SystemSavePanel(),
         clipboard: ClipboardWriting = SystemClipboard()) {
        self.client = client
        self.keyProvider = keyProvider
        self.database = database
        self.wallpaperEngine = wallpaperEngine
        self.downloader = downloader
        self.savePanel = savePanel
        self.clipboard = clipboard
        // 以当前（默认）筛选键打底：启动时若 page/seed 之类的字段被改一次，onChange 也会触发
        // scheduleFilterReload，此时 filterKey 并未变化，靠这个初值直接拦掉，避免多打一次搜索请求。
        lastFilterKey = query.filterKey
    }

    func reload() async {
        loadState = .loading
        resultsIncomplete = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            let page = try await client.search(query)
            wallpapers = page.data
            refreshFavorites()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 详情页点标签 / 「更多类似」：用 `+tag` 表达式回到第 1 页重查（多词标签的空格必须原样保留）。
    func search(_ text: String) {
        query.q = text
        query.page = 1
        // 同步防抖基准：否则随后一次筛选变更会因为 filterKey 与基准不一致而多打一次请求。
        lastFilterKey = query.filterKey
        Task { await reload() }
    }

    func nextPage() async {
        guard case .loaded = loadState, !loadingMore else { return }
        loadingMore = true
        query.page += 1
        do {
            let page = try await client.search(query)
            wallpapers.append(contentsOf: page.data)
        } catch {
            query.page -= 1
            loadState = .failed(error.localizedDescription)
        }
        loadingMore = false
    }

    /// 翻页在途标记：防止触底哨兵在加载中重复触发导致 page 跳号 / 重复请求。
    private var loadingMore = false

    // MARK: - 筛选变更（DESIGN §4.3：150ms debounce 再请求）

    private var filterReloadTask: Task<Void, Never>?
    private var lastFilterKey = ""

    /// 筛选面板任一维度变更 → 150ms 防抖后回到第 1 页重查。
    /// 只有 `BrowseQuery.filterKey`（不含 page/seed）变化才算筛选变更，翻页不会触发重查。
    func scheduleFilterReload() {
        guard query.filterKey != lastFilterKey else { return }
        lastFilterKey = query.filterKey
        filterReloadTask?.cancel()
        filterReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.query.page = 1
            await self.reload()
        }
    }

    // MARK: - 收藏（F6）

    func toggleFavorite(_ wp: Wallpaper) {
        if database.isFavorite(id: wp.id) {
            try? database.removeFavorite(id: wp.id)
            favoriteIDs.remove(wp.id)
        } else {
            let fav = Favorite(id: wp.id,
                              thumbnailURL: wp.thumbs.small,
                              originalURL: wp.path,
                              addedAt: Date())
            try? database.addFavorite(fav)
            favoriteIDs.insert(wp.id)
        }
    }

    func refreshFavorites() {
        favoriteIDs = Set((try? database.favorites().map(\.id)) ?? [])
    }

    /// 载入收藏列表（侧栏「收藏」视图用）。
    func loadFavorites() {
        favorites = (try? database.favorites()) ?? []
        refreshFavorites()
        loadState = .loaded
    }

    /// 载入已设壁纸记录（侧栏「已设置」视图用）。
    func loadApplied() {
        applied = (try? database.applied()) ?? []
        loadState = .loaded
    }

    /// 把一条历史记录重新设为壁纸：本地文件仍在就直接用（省一次下载），被清理了才回退重新下载原图。
    func reapply(_ item: AppliedWallpaper) async -> String? {
        let file: URL
        if FileManager.default.fileExists(atPath: item.localPath) {
            file = URL(fileURLWithPath: item.localPath)
        } else {
            do { file = try await downloader.download(item.originalURL) }
            catch { return error.localizedDescription }
        }
        do {
            try wallpaperEngine.setWallpaper(fileURL: file, for: nil, mode: .fill, fillColor: nil)
            try? database.addApplied(AppliedWallpaper(id: item.id,
                                                       thumbnailURL: item.thumbnailURL,
                                                       originalURL: item.originalURL,
                                                       localPath: file.path,
                                                       width: item.width,
                                                       height: item.height,
                                                       appliedAt: Date()))
            loadApplied()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 设置里关掉「允许成人内容」后调用：把已勾选的 NSFW 档收回并回到第 1 页重查（ADR-012）。
    /// 开关表达的是本机意愿，与账号权限无关，因此不做任何探测。
    func disableNSFWIfNeeded() {
        guard query.purity.nsfw else { return }
        query.purity.nsfw = false
        query.page = 1
        Task { await reload() }
    }

    /// 从「已设置」移除一条记录（只删记录，不动桌面当前壁纸、不动收藏）。
    func removeApplied(id: String) {
        try? database.removeApplied(id: id)
        loadApplied()
    }

    /// 从收藏列表移除（FavoriteCard 上的星标动作）。
    func removeFavorite(id: String) {
        try? database.removeFavorite(id: id)
        favoriteIDs.remove(id)
    }

    /// 详情页状态工厂：把本视图持有的领域协议注入 `DetailViewState`。
    /// 放在这里是为了不动 `IHavenApp.swift` 的装配代码；`DetailViewState` 侧只见协议（ARCH §4）。
    func makeDetailState(wallpaper: Wallpaper) -> DetailViewState {
        DetailViewState(wallpaper: wallpaper,
                        client: client,
                        engine: wallpaperEngine,
                        downloader: downloader,
                        savePanel: savePanel,
                        clipboard: clipboard) { [weak self] item, file in
            self?.recordApplied(id: item.id, thumbnailURL: item.thumbs.small, originalURL: item.path,
                                localPath: file.path, width: item.width, height: item.height)
        }
    }

    /// 清空全部筛选维度（工具栏「清除全部筛选」）。保留当前分类（由侧栏控制）。
    func clearFilters() {
        query.q = ""
        query.purity = .browseDefault
        query.atleast = ""
        query.ratio = .unspecified
        query.color = ""
        query.sorting = .dateAdded
        query.order = .desc
        query.topRange = .month
        query.page = 1
    }

    // MARK: - 设为壁纸（F1 / F2）

    /// 下载原图到本地后调用 WallpaperEngine 设置静态壁纸。返回 nil 表示成功，否则为错误描述。
    func setAsWallpaper(_ wp: Wallpaper) async -> String? {
        do {
            let file = try await downloader.download(wp.path)
            try wallpaperEngine.setWallpaper(fileURL: file, for: nil, mode: .fill, fillColor: nil)
            recordApplied(id: wp.id, thumbnailURL: wp.thumbs.small, originalURL: wp.path,
                          localPath: file.path, width: wp.width, height: wp.height)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 设壁纸成功后才落记录：没真的设上就不该出现在「已设置」里。
    private func recordApplied(id: String, thumbnailURL: URL?, originalURL: URL,
                               localPath: String, width: Int, height: Int) {
        try? database.addApplied(AppliedWallpaper(id: id,
                                                  thumbnailURL: thumbnailURL,
                                                  originalURL: originalURL,
                                                  localPath: localPath,
                                                  width: width,
                                                  height: height,
                                                  appliedAt: Date()))
    }

    /// 从收藏项直接设置壁纸（收藏视图用；下载 originalURL 后调用引擎）。
    func setWallpaperFromFavorite(_ fav: Favorite) async -> String? {
        do {
            let file = try await downloader.download(fav.originalURL)
            try wallpaperEngine.setWallpaper(fileURL: file, for: nil, mode: .fill, fillColor: nil)
            // Favorite 不持有尺寸（见 FavoriteCard 注释），尺寸记 0 → 卡片不显示分辨率。
            recordApplied(id: fav.id, thumbnailURL: fav.thumbnailURL, originalURL: fav.originalURL,
                          localPath: file.path, width: 0, height: 0)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
