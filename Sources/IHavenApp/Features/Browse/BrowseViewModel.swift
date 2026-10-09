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
        guard case .loaded = loadState else { return }
        query.page += 1
        do {
            let page = try await client.search(query)
            wallpapers.append(contentsOf: page.data)
        } catch {
            query.page -= 1
            loadState = .failed(error.localizedDescription)
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
}
