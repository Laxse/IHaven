import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO 实现的媒体探测与缩略图产出（ADR-015 §三、§六；ADR-016 改为仅静态图）。
///
/// 全部是 `async throws` 或同步 throws，内部不做任何 UI 假设，可在任意线程执行。
struct AVMediaProbe: MediaProbing, ThumbnailProducing {

    // MARK: - 探测

    func probe(_ url: URL) async throws -> MediaProbe {
        // 先按扩展名把「确定不支持」的挡掉：视频 / 动图格式 ImageIO 未必报错，
        // 若混过探测就会在生成时才失败 —— 正是 ADR-008 要避免的顺序。
        // ADR-016 起动态壁纸改为由静态图生成，所以视频在这里就被明确拒绝（给出具体原因）。
        if let reason = Self.unsupportedReason(url.pathExtension) {
            return MediaProbe(kind: .image, width: 0, height: 0, duration: nil,
                              isSupported: false, rejectReason: reason)
        }

        // 静态图：ImageIO 零解码读属性（只读元信息，不解码像素）。能读到尺寸即受支持。
        if let image = Self.imageSize(of: url) {
            return MediaProbe(kind: .image, width: image.width, height: image.height,
                              duration: nil, isSupported: true, rejectReason: nil)
        }

        return MediaProbe(kind: .image, width: 0, height: 0, duration: nil, isSupported: false,
                          rejectReason: String(localized: "无法识别为受支持的静态图片，可能已损坏或不是图片文件"))
    }

    // MARK: - 缩略图

    func makeThumbnail(source: URL, maxPixel: Int, destination: URL) throws {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw MediaError.unreadable
        }
        // 不整图解码：`kCGImageSourceThumbnailMaxPixelSize` 直接产出小图（ARCH §6.2.2）。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw MediaError.thumbnailFailed
        }
        try Self.writeJPEG(thumb, to: destination)
    }

    // MARK: - 内部

    /// 明确不支持的格式：视频一律拒（动态壁纸改由静态图生成），GIF 亦不支持。
    /// 理由直接面向用户 —— ADR-008:71 要求错误信息具体、可行动。
    static func unsupportedReason(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv", "3gp":
            return String(localized: "动态壁纸已改为由静态图生成，不再导入视频文件，请导入一张静态图片")
        case "gif":
            return String(localized: "GIF 暂不支持，请导入 JPG / PNG 等静态图片")
        default:
            return nil
        }
    }

    private static func imageSize(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        guard let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0
        else { return nil }
        return (w, h)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.82) throws {
        try? FileManager.default.removeItem(at: url)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { throw MediaError.thumbnailFailed }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MediaError.thumbnailFailed }
        try data.write(to: url, options: .atomic)
    }
}

enum MediaError: LocalizedError {
    case unreadable
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "无法读取该文件，可能已损坏或没有读取权限")
        case .thumbnailFailed: String(localized: "生成缩略图失败，该文件可能不是受支持的图片 / 视频")
        }
    }
}
