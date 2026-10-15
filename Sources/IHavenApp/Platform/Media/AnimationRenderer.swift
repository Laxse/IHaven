import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// CoreGraphics / ImageIO 实现的帧序列渲染器（ADR-016）。
///
/// 两步：先把源图**降采样**到工作尺寸（不整图解码 8K 原图，ARCH §6.2.2），再逐帧裁剪 + 缩放。
struct AnimationRenderer: AnimationRendering {
    /// 工作尺寸长边上限。1920 覆盖绝大多数显示器 @1x；@2x 屏会由窗口层再放大一次，
    /// 慢速运动下这点软化看不出来，而磁盘与生成时间差一倍。
    static let workMaxPixel = 1920

    func render(source: URL, spec: AnimationSpec, outputDir: URL, outputAspect: CGFloat) throws -> [URL] {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else { throw MediaError.unreadable }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.workMaxPixel,
        ]
        guard let base = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw MediaError.thumbnailFailed
        }

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let sourceSize = CGSize(width: base.width, height: base.height)

        var frames: [URL] = []
        frames.reserveCapacity(spec.frameCount)
        for index in 0..<max(1, spec.frameCount) {
            let rect = spec.cropRect(at: index, in: sourceSize, outputAspect: outputAspect)
                .intersection(CGRect(origin: .zero, size: sourceSize))
            guard !rect.isNull, rect.width > 1, rect.height > 1,
                  let cropped = base.cropping(to: rect) else { throw MediaError.thumbnailFailed }
            let url = outputDir.appendingPathComponent(String(format: "frame-%04d.jpg", index))
            try Self.writeJPEG(cropped, to: url)
            frames.append(url)
        }
        return frames
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.72) throws {
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
