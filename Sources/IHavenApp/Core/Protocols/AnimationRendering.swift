import CoreGraphics
import Foundation

/// 把一张静态图渲染成一组帧（ADR-016）。
///
/// 为什么**导入时一次生成、播放时只换图**：帧序列落盘后，播放侧只是 `NSImageView.image =`
/// 赋值，零解码零合成；若播放时才裁切，每一帧都要做一次 CPU 缩放，风扇直接起飞。
public protocol AnimationRendering: Sendable {
    /// 渲染帧序列到 `outputDir`，返回按顺序排列的帧文件 URL。
    /// - Parameter outputAspect：输出帧的宽高比（取主屏比例），裁切按此比例在源图上取最大内接矩形，
    ///   保证生成的帧铺满桌面时不拉伸变形。
    func render(source: URL, spec: AnimationSpec, outputDir: URL, outputAspect: CGFloat) throws -> [URL]
}
