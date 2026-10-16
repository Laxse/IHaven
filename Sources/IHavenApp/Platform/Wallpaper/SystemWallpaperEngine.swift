import AppKit
import Foundation

/// 静态壁纸引擎（MVP，ARCH §6.1）：`NSWorkspace.setDesktopImageURL`。
///
/// 动态壁纸（XPC Service + AVPlayerLayer 逐屏隔离，ARCH §5）属 V2/F9，不在本次范围；
/// 届时作为 `WallpaperEngine` 的另一实现注入，Feature 层无需改动。
///
/// 仅暴露两档快捷预设（适应 / 填充，覆盖 90% 场景，ARCH §6.2）；不暴露 Stretch（比例失真，与本产品定位冲突）。
final class SystemWallpaperEngine: WallpaperEngine {
    func setWallpaper(fileURL: URL, for screen: NSScreen?, mode: WallpaperFillMode, fillColor: NSColor?) throws {
        // ⚠️ 实测（2026-10-17）：远程 URL 会让 AppKit 抛 NSInternalInconsistencyException
        // 并**直接 SIGABRT（exit 134）**，走的是 ObjectiveClass 异常而不是 Swift 错误 ——
        // 协议的 `throws` 在这里给的是虚假安全感。所有调用点都必须先拿本地路径再进来，
        // 这里再兜一层，把崩溃降级成可读的错误。
        guard fileURL.isFileURL else {
            throw NSError(
                domain: "SystemWallpaperEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "只能设置本地图片作为壁纸")]
            )
        }
        let options = Self.options(for: mode, fillColor: fillColor)
        // NSWorkspace.setDesktopImageURL 始终需要 forScreen:，无无-screen 重载。
        guard let target = screen ?? NSScreen.main else {
            throw NSError(
                domain: "SystemWallpaperEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "无可用的屏幕来设置壁纸")]
            )
        }
        try NSWorkspace.shared.setDesktopImageURL(fileURL, for: target, options: options)
    }

    func currentWallpaperURL(for screen: NSScreen?) -> URL? {
        if let screen { return NSWorkspace.shared.desktopImageURL(for: screen) }
        return NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    private static func options(for mode: WallpaperFillMode, fillColor: NSColor?) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        // 系统仅支持等比缩放 + 是否裁切；Stretch（scaleAxesIndependently）忽略 AllowClipping 且会失真，故不提供。
        let scaling = NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue)
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [.imageScaling: scaling]
        // ⚠️ 实测（2026-10-17）：**不能转换到 Generic RGB 的颜色会让 AppKit 直接 SIGABRT**
        // （`NSColor(patternImage:)` 必崩，动态目录色能过）。alpha 一律被丢弃，这点与旧注释一致；
        // 但「仅 CalibratedRGB」不是静默降级，是不可转换时崩溃 —— 所以先做一次色彩空间转换，
        // 拿不到就丢掉填充色，而不是把原色塞进字典。
        let safeColor = fillColor?.usingColorSpace(NSColorSpace.genericRGB)
        switch mode {
        case .fit:
            options[.allowClipping] = NSNumber(booleanLiteral: false)
            if let safeColor { options[.fillColor] = safeColor } // alpha 被系统忽略
        case .fill:
            options[.allowClipping] = NSNumber(booleanLiteral: true)
        }
        return options
    }
}
