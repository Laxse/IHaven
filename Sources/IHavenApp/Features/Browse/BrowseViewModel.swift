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

    private let client: WallhavenAPIProtocol
    private let keyProvider: KeyProvider
    private let database: WallpaperDatabase
    private let wallpaperEngine: WallpaperEngine
    private let downloader: ImageDownloading

    init(client: WallhavenAPIProtocol,
         keyProvider: KeyProvider,
         database: WallpaperDatabase,
         wallpaperEngine: WallpaperEngine,
         downloader: ImageDownloading) {
        self.client = client
        self.keyProvider = keyProvider
        self.database = database
        self.wallpaperEngine = wallpaperEngine
        self.downloader = downloader
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

    /// 从收藏列表移除（FavoriteCard 上的星标动作）。
    func removeFavorite(id: String) {
        try? database.removeFavorite(id: id)
        favoriteIDs.remove(id)
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
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 从收藏项直接设置壁纸（收藏视图用；下载 originalURL 后调用引擎）。
    func setWallpaperFromFavorite(_ fav: Favorite) async -> String? {
        do {
            let file = try await downloader.download(fav.originalURL)
            try wallpaperEngine.setWallpaper(fileURL: file, for: nil, mode: .fill, fillColor: nil)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
