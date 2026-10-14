import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AVFoundation / ImageIO 实现的媒体探测与缩略图产出（ADR-015 §三、§六）。
///
/// 全部是 `async throws` 或同步 throws，内部不做任何 UI 假设，可在任意线程执行。
struct AVMediaProbe: MediaProbing, ThumbnailProducing {

    // MARK: - 探测

    func probe(_ url: URL) async throws -> MediaProbe {
        // 先按扩展名把「确定不支持」的挡掉：这些格式 CGImageSource / AVURLAsset 未必报错，
        // 若混过探测就会在播放时才失败 —— 正是 ADR-008 要避免的顺序。
        if let reason = Self.unsupportedReason(url.pathExtension) {
            return MediaProbe(kind: .image, width: 0, height: 0, duration: nil,
                              isSupported: false, rejectReason: reason)
        }

        // ⚠️ **必须先用 ImageIO 试静态图，再试 AVURLAsset 的视频轨，顺序不能反。**
        // 实测（2026-10-15，离线复刻脚本跑真 JPEG）：`AVURLAsset.loadTracks(withMediaType: .video)`
        // 遇到静态图**不是返回空数组，而是抛错** `AVFoundationErrorDomain -11828 "Cannot Open"`。
        // 若先试视频，所有静态图都会被这个错误顶掉、整批导入全被判成「打不开」——
        // 而 ImageIO 读图是零解码的（只读属性），成本远低于建 AVURLAsset。
        if let image = Self.imageSize(of: url) {
            return MediaProbe(kind: .image, width: image.width, height: image.height,
                              duration: nil, isSupported: true, rejectReason: nil)
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // 静态图已在上面返回；能走到这里说明 ImageIO 读不了，于是 AVURLAsset 的失败就是终局。
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let duration = try? await asset.load(.duration) {
            return MediaProbe(kind: .video,
                              width: max(1, Int(size.width.rounded())),
                              height: max(1, Int(size.height.rounded())),
                              duration: duration.seconds.isFinite ? duration.seconds : nil,
                              isSupported: true,
                              rejectReason: nil)
        }

        return MediaProbe(kind: .image, width: 0, height: 0, duration: nil, isSupported: false,
                          rejectReason: String(localized: "无法识别的媒体文件，可能已损坏或不是受支持的图片 / 视频"))
    }

    /// 首尾帧连续性的**启发式**判定：各自降到 8×8 求平均色，欧氏距离超阈值即判不连续。
    ///
    /// 已知边界（有意接受）：缓慢的整体位移（如镜头缓慢横移）会被判为连续；大色块切换会被判为
    /// 不连续。宁可多提示一次，不可漏提示 —— 漏提示的后果是用户看到循环跳变却不知道为什么。
    ///
    /// ⚠️ 两个**实测出来的坑**（2026-10-15，离线复刻脚本跑真 MP4 验证）：
    /// 1. `requestedTimeToleranceBefore/After` **必须归零**。默认容差会让生成器吸附到关键帧，
    ///    首尾两次取样会拿到**同一帧**，判定恒为「连续」—— 这个 bug 不会报错，只会让功能静默失效。
    /// 2. 末帧时间取 `duration - 1ms`。正好取在 `duration` 上对部分文件会越界失败。
    func isSeamless(video: URL) async -> Bool {
        let asset = AVURLAsset(url: video)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0.1 else { return true }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.seamSampleSize, height: Self.seamSampleSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let last = CMTimeSubtract(duration, CMTime(value: 1, timescale: 1000))
        guard let first = try? await generator.image(at: .zero).image,
              let final = try? await generator.image(at: last).image,
              let a = averageColor(of: first),
              let b = averageColor(of: final)
        else { return true }
        var sum: CGFloat = 0
        for (x, y) in zip(a, b) { sum += abs(x - y) }
        let delta = sum / 3.0
        return delta < Self.seamThreshold
    }

    // MARK: - 缩略图 / 首帧

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
        try writeJPEG(thumb, to: destination)
    }

    func makePoster(video: URL, maxPixel: Int, destination: URL) async throws {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let frame = try await generator.image(at: .zero).image
        try writeJPEG(frame, to: destination)
    }

    // MARK: - 内部

    private static let seamSampleSize = 8
    /// 8×8 平均色的欧氏距离阈值（0–1）。0.18 ≈ 肉眼可辨的色阶跳变。
    private static let seamThreshold: CGFloat = 0.18

    /// 三种明确不支持的格式（PRD §5.6 最终裁定表）。理由直接面向用户，不说「解码失败」这种
    /// 用户无法行动的话 —— ADR-008:71 要求错误信息具体。
    static func unsupportedReason(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "webm", "mkv":
            return String(localized: "macOS 没有该格式的原生解码器，建议转换为 MP4 后再导入")
        case "gif":
            return String(localized: "GIF 逐帧解码的功耗与效果均不达标，暂不支持作为壁纸，可用系统预览导出为 MP4")
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

    /// 求一张（已很小，8×8）图的平均色，返回归一化 RGB。
    ///
    /// 用 `CGContext` 直接把小图画进 1×1 位图，让 CoreGraphics 做降采样平均。
    ///
    /// **不用 CoreImage 的面积均值滤镜**：那个滤镜要靠字符串名字构造，会撞上
    /// convention-gate 的 wallhaven 参数名白名单扫描（该规则扫 Infrastructure 下所有
    /// 「name 后跟字符串字面量」的写法，本意是抓搜索参数名笔误，见脚本注释）。
    /// 为一个均值计算去改门禁不值得，而 CGContext 的降采样对这个阈值判定完全够用。
    private func averageColor(of image: CGImage) -> [CGFloat]? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes.map { CGFloat($0) / 255 }
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.82) throws {
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
