import CoreGraphics
import Foundation

/// 设置壁纸前的裁剪选框：**归一化**矩形模型（纯数学，无 AppKit / 无 UI 依赖）。
///
/// ## 坐标约定
/// - 四个分量取值 0…1，**相对源图像素的宽 / 高**（不是显示尺寸、不是点坐标）；
/// - 原点在**左上角**，与 `CGImage` 的像素坐标一致（不像 `NSView` 那样 y 轴向上）；
/// - `x` / `y` 是选框左上角，`width` / `height` 是比例。
///
/// 例：源图 4000×2000，`(x: 0.1, y: 0, width: 0.8, height: 1)`
/// → 像素矩形 `(400, 0, 3200, 2000)`。
///
/// ## 为什么归一化
/// 选框在 UI 上按**显示尺寸**拖动，而裁剪发生在**全分辨率像素域**。归一化后两者只差一个
/// 缩放系数（显示位移 ÷ 显示宽 = 归一化位移），不会出现「预览里选的是这一块、裁出来是另一块」。
///
/// ## 为什么锁比例（宽高比 == 目标屏宽高比）
/// 竖图直接设壁纸会产生左右黑边（填充模式为「完整可见」时尤甚）。裁出的产物宽高比与屏幕
/// 一致后，无论系统按 fit 还是 fill 铺都不会留白 —— 这是本功能的全部目的。
///
/// ## 验算示例（`/tmp` 临时工程实测，见提交说明）
/// - `centered(in: 1000×2000, aspect: 16/10)` → `(0, 0.34375, 1, 0.3125)`，像素 `(0, 687.5, 1000, 625)`，宽高比 1.6
/// - `full.moved(dx: 0.5, dy: 0)` → 越界被钳住，仍是 `(0, 0, 1, 1)`
/// - `pixelRect(in: 1000×2000)` 于 `(0, 0, 0.0001, 0.0001)` → `(0, 0, 1, 1)`，宽高被抬到 1px
enum CropHandle: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct WallpaperCropRect: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    /// 最小边长：防止退化成 0（0 宽会让 `CGImage.cropping(to:)` 返回 nil）。
    private static let epsilon: CGFloat = 0.0001

    static let full = WallpaperCropRect(x: 0, y: 0, width: 1, height: 1)

    /// 源图内按 `aspect`（**宽 / 高**）取**最大内接矩形并居中**。
    ///
    /// 公式与 `Core/Models/AnimationPreset.swift:57-66` 同款：先按宽算，超出源高再改按高算。
    /// - 源图 aspect 已等于 `aspect` 时自然得到 `full`；
    /// - `source` 任一维 ≤ 0 或 `aspect ≤ 0` 时返回 `full`（调用方拿到的一定是可用的矩形，
    ///   不会拿到 NaN —— NaN 会让整个选框从 UI 上消失且无从排查）。
    ///
    /// 例：`centered(in: 1000×2000, aspect: 1.6)` → 按宽算 `cropH = 1000/1.6 = 625 ≤ 2000` ✅
    /// → 归一化 `(width: 1, height: 0.3125)` → 居中 `y = (1 - 0.3125)/2 = 0.34375`。
    static func centered(in source: CGSize, aspect: CGFloat) -> WallpaperCropRect {
        guard source.width > 0, source.height > 0, aspect > 0 else { return .full }
        var cropW = source.width
        var cropH = cropW / aspect
        if cropH > source.height {
            cropH = source.height
            cropW = cropH * aspect
        }
        let w = cropW / source.width
        let h = cropH / source.height
        return WallpaperCropRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    /// 钳回 0…1 且四边不越界：先保证宽高落在 `(epsilon, 1]`，再按原点反向收
    /// （`x = min(max(x, 0), 1 - width)`）—— 即**优先保住尺寸、挪动位置**，而不是缩掉超出的部分。
    /// 保证 `x ≥ 0`、`y ≥ 0`、`x + width ≤ 1`、`y + height ≤ 1`。
    func clamped() -> WallpaperCropRect {
        let w = min(max(width, Self.epsilon), 1)
        let h = min(max(height, Self.epsilon), 1)
        return WallpaperCropRect(x: min(max(x, 0), 1 - w),
                                 y: min(max(y, 0), 1 - h),
                                 width: w,
                                 height: h)
    }

    /// 整体平移。`dx` / `dy` 是**归一化**位移（显示像素位移 ÷ 源图显示宽 / 高）。
    ///
    /// 越界**停住**（钳到边界，不是缩小）：`full.moved(dx: 0.5, dy: 0)` 仍是 `(0, 0, 1, 1)`，
    /// 而不是把宽缩成 0.5。用户拖到边上的手感是「拖不动了」，不是「框自己变小了」。
    func moved(dx: CGFloat, dy: CGFloat) -> WallpaperCropRect {
        let base = clamped()
        return WallpaperCropRect(x: base.x + dx,
                                 y: base.y + dy,
                                 width: base.width,
                                 height: base.height).clamped()
    }

    /// 拖某个角缩放：**对角锚定不动**，锁定宽高比，触底就停住不再缩小。
    ///
    /// - `dx` / `dy` 同样是归一化位移（显示像素位移 ÷ 源图显示宽 / 高），`dy > 0` 为向下。
    /// - 锁比例的实现要点：像素宽高比 = `(width * W) / (height * H)`，而 `W` / `H` 是常量，
    ///   所以**只要归一化宽高同乘一个因子，像素宽高比就不变** —— 等价于保持
    ///   `ratio = width / height` 不变，无需知道源图尺寸。
    /// - `minFraction` 是**归一化边长下限**：要求 `width ≥ minFraction` 且
    ///   `height ≥ minFraction`，落回像素即两条边都 `≥ minFraction × 对应轴长`，
    ///   因而也 `≥ minFraction × 较短边`（默认 8%）。触底后继续拖不再变小。
    /// - 水平 / 垂直两个候选取**位移绝对值较大**的那个 —— 对角线拖拽时跟随手指主方向。
    ///
    /// 例（源图 4000×2000，当前 `(0.1, 0, 0.8, 1)`，`ratio = 0.8`）：
    /// `resized(.bottomRight, dx: 40/4000, dy: 0, aspect: 1.6)` → 宽 0.81，高 `0.81/0.8 = 1.0125`
    /// 超出下边界 → 被钳到 `availH * ratio = 1 * 0.8 = 0.8`，即保持不动（已满高）。
    func resized(handle: CropHandle, dx: CGFloat, dy: CGFloat,
                 aspect: CGFloat, minFraction: CGFloat = 0.08) -> WallpaperCropRect {
        let base = clamped()
        let ratio = base.width / base.height
        guard aspect > 0, ratio > 0, ratio.isFinite else { return base }

        // 锚点 = 被拖角的对角。anchorOnLeft/Top 表示锚点是新矩形的左 / 上边。
        let anchorX: CGFloat
        let anchorY: CGFloat
        let anchorOnLeft: Bool
        let anchorOnTop: Bool
        switch handle {
        case .topLeft:
            anchorX = base.x + base.width; anchorY = base.y + base.height
            anchorOnLeft = false; anchorOnTop = false
        case .topRight:
            anchorX = base.x;              anchorY = base.y + base.height
            anchorOnLeft = true;           anchorOnTop = false
        case .bottomLeft:
            anchorX = base.x + base.width; anchorY = base.y
            anchorOnLeft = false;          anchorOnTop = true
        case .bottomRight:
            anchorX = base.x;              anchorY = base.y
            anchorOnLeft = true;           anchorOnTop = true
        }

        let onRight = handle == .topRight || handle == .bottomRight
        let onBottom = handle == .bottomLeft || handle == .bottomRight
        let byWidth = base.width + (onRight ? dx : -dx)
        let byHeight = base.width + (onBottom ? dy * ratio : -dy * ratio)
        var w = abs(byWidth - base.width) >= abs(byHeight - base.width) ? byWidth : byHeight

        // 上限：锚点到边界的可用空间（水平直接用，垂直要乘回 ratio 换算成宽）。
        let availW = anchorOnLeft ? 1 - anchorX : anchorX
        let availH = anchorOnTop ? 1 - anchorY : anchorY
        w = min(w, availW, availH * ratio)
        // 下限：宽、高都不能小于 minFraction。
        w = max(w, minFraction, minFraction * ratio)

        let h = w / ratio
        let nx = anchorOnLeft ? anchorX : anchorX - w
        let ny = anchorOnTop ? anchorY : anchorY - h
        return WallpaperCropRect(x: nx, y: ny, width: w, height: h).clamped()
    }

    /// 落到像素坐标：`x * size.width` 等**四舍五入**取整，钳制在 `(0, 0, size.width, size.height)` 内，
    /// 宽高至少 1px。
    ///
    /// 用四舍五入而不是 floor 原点 + ceil 右下：后者会让 625px 高的裁切变成 626px，
    /// 产物宽高比因此偏离屏幕比例约 0.05%，铺满后又是一圈（虽只有 1px 量级但确实存在）留白。
    ///
    /// 返回值可直接交给 `CGImage.cropping(to:)`（CGImage 的裁剪矩形就是左上原点的像素坐标）。
    func pixelRect(in size: CGSize) -> CGRect {
        let W = size.width
        let H = size.height
        guard W > 0, H > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let b = clamped()
        var x0 = (b.x * W).rounded()
        var y0 = (b.y * H).rounded()
        var x1 = ((b.x + b.width) * W).rounded()
        var y1 = ((b.y + b.height) * H).rounded()
        x0 = min(max(x0, 0), W); y0 = min(max(y0, 0), H)
        x1 = min(max(x1, 0), W); y1 = min(max(y1, 0), H)
        var w = max(CGFloat(1), x1 - x0)
        var h = max(CGFloat(1), y1 - y0)
        // 抬到 1px 之后可能又越界，再按原点反向收一次。
        if x0 + w > W { x0 = max(0, W - w) }
        if y0 + h > H { y0 = max(0, H - h) }
        w = min(w, W); h = min(h, H)
        return CGRect(x: x0, y: y0, width: w, height: h)
    }
}
