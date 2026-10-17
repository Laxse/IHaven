import CoreGraphics
import Foundation

/// 设置壁纸前的裁剪（用户反馈：「图片是纵向的时候设置壁纸会出现两边儿有黑边儿」）。
///
/// 单独成文件：`BrowseViewModel.swift` 已 290/300，逼近 ADR-009 的上限；extension 分文件后
/// 各文件单独计行数 —— 与 `BrowseViewModel+Favorites.swift` 同一条路子。
extension BrowseViewModel {
    /// 裁剪入口：先拿**本地**原图（离线命中优先，否则下载）。返回 nil = 拿不到，调用方提示重试。
    ///
    /// ⚠️ **必须是本地 fileURL，不能把远程 URL 递给裁剪 sheet**：远程 URL 进系统壁纸 API 会
    /// SIGABRT（见 `Platform/Wallpaper/SystemWallpaperEngine.swift`），裁剪写盘也读不到数据。
    /// `localOrDownload` 就是「`OfflineImageStore.localFile` 命中即用，否则 `downloader` 下」。
    func cropSource(for wallpaper: Wallpaper) async -> URL? {
        try? await localOrDownload(wallpaper.path)
    }

    /// 用裁剪产物设壁纸。返回 nil 表示成功，否则为错误文案（调用方弹 toast）。
    ///
    /// ⚠️ **模式写死 `.fill`，不读 `WallpaperTarget.fillMode()`**：产物宽高比已经等于目标屏，
    /// 但像素取整会有 ±1px 误差 —— 这 1px 在 `.fit`（完整可见）下会变成一条极细留白，而
    /// `.fill` 只会把边缘裁掉 1px，肉眼不可见。用户当前的填充模式在这里是被**有意覆盖**的。
    ///
    /// 尺寸用 `pixelSize`（裁剪产物的真实像素），不是 `wallpaper.width/height` —— 后者是原图
    /// 尺寸，记进「已设置」会让列表显示的分辨率与实际铺上去的那张对不上（既有链路有记 0 的
    /// 历史问题，这里不跟着学）。
    func applyCropped(_ file: URL, pixelSize: CGSize, wallpaper: Wallpaper) async -> String? {
        do {
            try wallpaperEngine.setWallpaper(fileURL: file,
                                             for: WallpaperTarget.resolveScreen(),
                                             mode: .fill,
                                             fillColor: WallpaperTarget.fillColor(for: wallpaper.colors))
            recordApplied(id: wallpaper.id,
                          thumbnailURL: wallpaper.aspectThumb,
                          originalURL: wallpaper.path,
                          localPath: file.path,
                          width: Int(pixelSize.width),
                          height: Int(pixelSize.height))
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
