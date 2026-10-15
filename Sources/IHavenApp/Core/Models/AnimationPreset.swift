import CoreGraphics
import Foundation

/// 动态壁纸的动画预设（ADR-016：由静态图本地生成，不接云端也能用）。
///
/// 三种预设都是**无缝循环**的（首帧与末帧构图完全一致），所以循环时不会有跳变：
/// - `breathe`：画面做缩放呼吸（放大再收回），居中不平移，天然无缝。
/// - `pan`：画面左右横移一个来回，居中不缩放，天然无缝。
/// - `zoomIn`：缩放缓推 + 竖向微移（Ken Burns 式），区别于纯呼吸，天然无缝。
public enum AnimationPreset: String, Codable, Sendable, CaseIterable {
    case zoomIn
    case breathe
    case pan

    /// 本地化 key（界面文案）。
    public var labelKey: String {
        switch self {
        case .zoomIn: "缓推"
        case .breathe: "呼吸"
        case .pan: "横移"
        }
    }
}

/// 一次生成的参数。全部有界，UI 滑块按这些范围给。
public struct AnimationSpec: Sendable, Equatable {
    public var preset: AnimationPreset
    /// 循环时长（秒）。
    public var seconds: Double
    /// 帧数。帧率 = frameCount / seconds；本地生成 + NSImageView 轮播，12fps 足够
    /// （这三种预设都是慢速运动，再高也只是浪费磁盘）。
    public var frameCount: Int
    /// 运动幅度，占画面的比例（0.04 ~ 0.24）。
    public var amplitude: Double

    public static let `default` = AnimationSpec(preset: .breathe, seconds: 12, frameCount: 144, amplitude: 0.12)

    public static let amplitudeRange: ClosedRange<Double> = 0.04...0.24
    public static let secondsRange: ClosedRange<Double> = 6...30

    public init(preset: AnimationPreset, seconds: Double, frameCount: Int, amplitude: Double) {
        self.preset = preset
        self.seconds = seconds
        self.frameCount = frameCount
        self.amplitude = amplitude
    }

    /// 第 `index` 帧（0 基）应裁出的源图区域，坐标基于 `source` 尺寸。
    ///
    /// 约定：返回值始终**包含在 source 内**，且宽高比与 `output` 一致
    /// （调用方先按 output 比例求交集，再交给本函数），所以裁完直接等比缩放不会变形。
    ///
    /// `t` ∈ [0, 1]：三种预设都满足 `t=0` 与 `t=1` 返回同一区域 → 无缝循环。
    public func cropRect(at index: Int, in source: CGSize, outputAspect: CGFloat) -> CGRect {
        guard source.width > 0, source.height > 0, frameCount > 0 else {
            return CGRect(origin: .zero, size: source)
        }
        let t = Double(index) / Double(max(1, frameCount - 1))

        // 基准裁切区：等比缩到能覆盖 output 比例的最大内接矩形（即 aspect-fill 的源侧）。
        var cropW = source.width
        var cropH = cropW / outputAspect
        if cropH > source.height {
            cropH = source.height
            cropW = cropH * outputAspect
        }

        switch preset {
        case .breathe:
            // 缩放量在一个周期内往复：0 → +amp → 0。首末帧同为「无缩放」，天然无缝。
            let scale = 1.0 + amplitude * (1.0 - cos(2 * .pi * t)) / 2.0
            cropW /= scale
            cropH /= scale
        case .pan:
            // 裁切区固定在最大（1+amp），只横向平移一个来回。首末帧居中，天然无缝。
            cropW /= (1.0 + amplitude)
            cropH /= (1.0 + amplitude)
            let maxDX = source.width - cropW
            let dx = maxDX * (1.0 - cos(2 * .pi * t)) / 2.0
            return CGRect(x: dx, y: (source.height - cropH) / 2, width: cropW, height: cropH)
        case .zoomIn:
            // 缓推 + 竖向微移（Ken Burns）：缩放往复，同时裁切区在竖直方向上下一个来回。
            // 与「呼吸」区分：呼吸只缩放不平移、居中；此处带竖向漂移，读感是「缓缓推进并下沉」。
            // 首末帧同为「满幅居中」，天然无缝。
            let scale = 1.0 + amplitude * (1.0 - cos(2 * .pi * t)) / 2.0
            cropW /= scale
            cropH /= scale
            let maxDY = source.height - cropH
            let dy = maxDY * (1.0 - cos(2 * .pi * t)) / 2.0
            return CGRect(x: (source.width - cropW) / 2, y: dy, width: cropW, height: cropH)
        }

        // 居中裁切（breathe / zoomIn 共用）。
        return CGRect(x: (source.width - cropW) / 2, y: (source.height - cropH) / 2,
                      width: cropW, height: cropH)
    }
}
