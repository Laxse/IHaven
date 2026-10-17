import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 按选框裁出「与屏幕同宽高比」的壁纸文件（CoreGraphics / ImageIO）。
///
/// 产物宽高比 == 目标屏宽高比，所以系统无论按「完整可见」还是「填充」铺都不会留黑边 ——
/// 这是竖图设壁纸出现左右黑边的根治办法。
///
/// ⚠️ **与 `AnimationRenderer` 的两点刻意不同**（不要照搬它）：
/// 1. `AnimationRenderer.workMaxPixel = 1920` 是给**动态壁纸帧序列**降采样用的；壁纸必须
///    **全分辨率**，这里用 16384（只缩不放：ImageIO 的 MaxPixelSize 不会把小图放大）。
/// 2. 写 JPEG 在本文件自建一份私有实现 —— `AnimationRenderer` 已 297/300 行，不值得为复用
///    把它推到上限，且两者的 quality 语义不同（帧序列 0.72 / 壁纸 0.92）。
enum WallpaperCropWriter {
    /// 全分辨率 + **已应用 EXIF 方向**的 CGImage。
    ///
    /// `kCGImageSourceCreateThumbnailWithTransform: true` 是关键：wallhaven 的图和手机拍的
    /// 照片普遍带 EXIF orientation，不先转正的话「用户在预览里框的那一块」和「按像素坐标
    /// 裁出来的那一块」会差一个 90° 旋转 —— 属于肉眼可见但极难归因的错裁。
    /// 写法同 `AnimationRenderer.swift:20-27`。
    static func loadOriented(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else { throw CropError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 16384,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw CropError.unreadable
        }
        return image
    }

    /// 按归一化 `rect` 裁 `source` 并写 JPEG（quality 0.92）到 `dir`，返回产物 fileURL。
    ///
    /// 文件名 `<原文件名去扩展名>-crop-<宽>x<高>.jpg`，宽高是**裁剪后的像素值** —— 同名源图
    /// 裁出不同尺寸不会互相覆盖，也便于事后核对「这张产物对应哪块屏」。
    static func write(source: URL, rect: WallpaperCropRect, to dir: URL) throws -> URL {
        let image = try loadOriented(source)
        let pixel = rect.pixelRect(in: CGSize(width: image.width, height: image.height))
        guard !pixel.isNull, pixel.width > 1, pixel.height > 1,
              let cropped = image.cropping(to: pixel) else { throw CropError.cropFailed }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let name = String(format: "%@-crop-%dx%d.jpg", base, Int(pixel.width), Int(pixel.height))
        let url = dir.appendingPathComponent(name)
        try writeJPEG(cropped, to: url)
        return url
    }

    /// 私有 JPEG 写出（照 `AnimationRenderer.writeJPEG` 的写法，quality 提到 0.92）。
    private static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
        try? FileManager.default.removeItem(at: url)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { throw CropError.writeFailed }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CropError.writeFailed }
        try data.write(to: url, options: .atomic)
    }
}
