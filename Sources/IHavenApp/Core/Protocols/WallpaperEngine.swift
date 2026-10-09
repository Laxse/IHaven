import AppKit
import Foundation

/// 壁纸设置引擎协议（Domain 层）。具体实现见 Platform/Wallpaper：
/// MVP 为 `SystemWallpaperEngine`（静态，`NSWorkspace.setDesktopImageURL`，ARCH §6.1）；
/// V2/F9 动态壁纸（XPC + AVPlayerLayer 逐屏隔离）将作为另一实现注入，Feature 无需改动。
public enum WallpaperFillMode: Int, Sendable, CaseIterable {
    /// 适应：图片完整可见，四周留白（ARCH §6.2 两档快捷预设之一）。
    case fit = 0
    /// 填充：铺满屏幕，可能裁边（系统默认，ARCH §6.2）。
    case fill = 1
}

public protocol WallpaperEngine: Sendable {
    /// 设置静态壁纸。`for: nil` 表示主屏。`fileURL` 必须为本地文件（NSWorkspace 不接受远程 URL）。
    func setWallpaper(fileURL: URL, for screen: NSScreen?, mode: WallpaperFillMode, fillColor: NSColor?) throws
    /// 反查当前壁纸（用于兼容系统设置展示）。
    func currentWallpaperURL(for screen: NSScreen?) -> URL?
}
