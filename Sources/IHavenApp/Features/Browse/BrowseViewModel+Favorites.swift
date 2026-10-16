import Foundation

/// 「从收藏直接设壁纸」（PRD F6 / F3）。
///
/// 单独成文件：`BrowseViewModel.swift` 已逼近 ADR-009 的 300 行上限，而 extension 分文件后
/// 各文件单独计行数 —— 这是不触门禁的唯一落点。
extension BrowseViewModel {
    /// 从收藏项直接设置壁纸（收藏视图与菜单栏面板共用；下载 originalURL 后调用引擎）。
    func setWallpaperFromFavorite(_ fav: Favorite) async -> String? {
        do {
            let file = try await localOrDownload(fav.originalURL)
            try wallpaperEngine.setWallpaper(fileURL: file, for: WallpaperTarget.resolveScreen(),
                                             mode: WallpaperTarget.fillMode(),
                                             // Favorite 不存主色（见 FavoriteCard 注释），用中性回退。
                                             fillColor: WallpaperTarget.neutralFillColor())
            // Favorite 不持有尺寸（见 FavoriteCard 注释），尺寸记 0 → 卡片不显示分辨率。
            recordApplied(id: fav.id, thumbnailURL: fav.thumbnailURL, originalURL: fav.originalURL,
                          localPath: file.path, width: 0, height: 0)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
