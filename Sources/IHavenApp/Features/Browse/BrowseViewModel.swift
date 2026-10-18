import Foundation
import SwiftUI

/// 浏览（瀑布流）视图模型。仅依赖领域协议（WallhavenAPIProtocol / KeyProvider / WallpaperDatabase /
/// WallpaperEngine / ImageDownloading），不依赖任何 Infrastructure 具体类型（ARCH §4 单向依赖）。
@MainActor
@Observable
final class BrowseViewModel {
    enum LoadState: Sendable {
        case idle, loading, loaded, failed(String)
        /// 客户端正在等 API 配额恢复（退避重试中）。**不是错误态** —— PRD §6 F7 要求
        /// 「期间在界面显示『正在等待 API 限流恢复』，不弹出错误弹窗打断操作」。
        case waiting(seconds: Int)
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
    /// 相册列表（侧栏「相册」视图数据源，来自数据库）。
    var albums: [Album] = []

    private let client: WallhavenAPIProtocol
    private let keyProvider: KeyProvider
    /// `internal` 而非 `private`：`BrowseViewModel+Albums.swift` 的 extension 要用
    /// （该文件的存在本身就是为绕过 ADR-009 的 300 行上限）。
    let database: WallpaperDatabase
    /// `internal` 而非 `private`：`BrowseViewModel+Favorites.swift` 的 extension 要用
    /// （该文件的存在本身就是为绕过 ADR-009 的 300 行上限）。
    let wallpaperEngine: WallpaperEngine
    let downloader: ImageDownloading
    private let savePanel: FileSavePresenting
    private let clipboard: ClipboardWriting
    /// 限流退避广播点（由 `WallhavenClient` 写入，ViewModel 只读）。
    private let throttle: ThrottleSignal

    init(client: WallhavenAPIProtocol,
         keyProvider: KeyProvider,
         database: WallpaperDatabase,
         wallpaperEngine: WallpaperEngine,
         downloader: ImageDownloading,
         savePanel: FileSavePresenting,
         clipboard: ClipboardWriting,
         throttle: ThrottleSignal) {
        self.client = client
        self.keyProvider = keyProvider
        self.database = database
        self.wallpaperEngine = wallpaperEngine
        self.downloader = downloader
        self.savePanel = savePanel
        self.clipboard = clipboard
        self.throttle = throttle
        // 以当前（默认）筛选键打底：启动时若 page/seed 之类的字段被改一次，onChange 也会触发
        // scheduleFilterReload，此时 filterKey 并未变化，靠这个初值直接拦掉，避免多打一次搜索请求。
        lastFilterKey = query.filterKey
    }

    /// 最近一次加载失败是否为网络不可达。供状态栏常驻提示用（离线时不打断操作）。
    private(set) var isOffline = false

    /// 距配额恢复还剩多少秒（`0` = 未在等待）。供状态栏常驻提示用。
    var throttleSeconds: Int { throttle.waitingSeconds }

    /// 视图实际应渲染的加载态：退避等待期间把 `.loading` 覆盖为 `.waiting`。
    ///
    /// 写成计算属性而不是在 `reload()` 里赋值，是因为等待发生在 `client.search` **内部**
    /// （`WallhavenClient.perform` 的退避 sleep），`reload()` 此刻正挂在 `await` 上，
    /// 没有第二个执行点可以回头改 `loadState`。读 `throttle.waitingSeconds` 会被
    /// SwiftUI 的 `@Observable` 追踪，等待开始 / 结束时界面自动重绘。
    var presentedLoadState: LoadState {
        if case .loading = loadState, throttle.waitingSeconds > 0 {
            return .waiting(seconds: throttle.waitingSeconds)
        }
        return loadState
    }

    func reload() async {
        loadState = .loading
        resultsIncomplete = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            let page = try await client.search(query)
            wallpapers = page.data
            refreshFavorites()
            isOffline = false
            loadState = .loaded
        } catch {
            isOffline = (error as? APIError)?.isOffline ?? false
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
                              thumbnailURL: wp.aspectThumb,
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
            try wallpaperEngine.setWallpaper(fileURL: file, for: WallpaperTarget.resolveScreen(),
                                             mode: WallpaperTarget.fillMode(),
                                             // AppliedWallpaper 不存主色，用中性回退。
                                             fillColor: WallpaperTarget.neutralFillColor())
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
            self?.recordApplied(id: item.id, thumbnailURL: item.aspectThumb, originalURL: item.path,
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
            let file = try await localOrDownload(wp.path)
            try wallpaperEngine.setWallpaper(fileURL: file, for: WallpaperTarget.resolveScreen(),
                                             mode: WallpaperTarget.fillMode(),
                                             fillColor: WallpaperTarget.fillColor(for: wp.colors))
            recordApplied(id: wp.id, thumbnailURL: wp.aspectThumb, originalURL: wp.path,
                          localPath: file.path, width: wp.width, height: wp.height)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 设壁纸成功后才落记录：没真的设上就不该出现在「已设置」里。
    /// `internal`：`BrowseViewModel+Favorites.swift` 的 extension 要用。
    func recordApplied(id: String, thumbnailURL: URL?, originalURL: URL,
                               localPath: String, width: Int, height: Int) {
        try? database.addApplied(AppliedWallpaper(id: id,
                                                  thumbnailURL: thumbnailURL,
                                                  originalURL: originalURL,
                                                  localPath: localPath,
                                                  width: width,
                                                  height: height,
                                                  appliedAt: Date()))
    }


    /// 本地优先取原图。原来三条链路都是**无条件先下载再设置**，同一张图每设一次就重下一次，
    /// 断网时直接失败 —— 而它很可能已经在本地（以前下载过，或详情页打开过、进了 Nuke
    /// `DataCache`）。见 `OfflineImageStore`。
    ///
    /// 抽成函数而不是在调用点写 `?? try await`：`??` 右侧是 autoclosure，不支持 async/throws。
    /// `internal` 而非 `private`：`BrowseViewModel+Favorites.swift` 的 extension 要用。
    func localOrDownload(_ remote: URL) async throws -> URL {
        // 本地文件（已设置里导入项落盘的 `file://`）直接复用，免一次下载也避免把 file URL 塞给下载器。
        if remote.isFileURL { return remote }
        if let cached = OfflineImageStore.localFile(for: remote) { return cached }
        return try await downloader.download(remote)
    }
}
