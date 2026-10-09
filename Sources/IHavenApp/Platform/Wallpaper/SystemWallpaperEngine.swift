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
        let options = Self.options(for: mode, fillColor: fillColor)
        // NSWorkspace.setDesktopImageURL 始终需要 forScreen:，无无-screen 重载。
        guard let target = screen ?? NSScreen.main else {
            throw NSError(
                domain: "SystemWallpaperEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无可用的屏幕来设置壁纸"]
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
        switch mode {
        case .fit:
            options[.allowClipping] = NSNumber(booleanLiteral: false)
            if let color = fillColor { options[.fillColor] = color } // 仅 CalibratedRGB，alpha 被忽略（ARCH §6.2.1）
        case .fill:
            options[.allowClipping] = NSNumber(booleanLiteral: true)
        }
        return options
    }
}
