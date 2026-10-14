import AppKit
import AVFoundation
import Foundation

/// 桌面层壁纸窗口工厂（ADR-003 / ADR-015 §五）。
///
/// 窗口配置逐项来自 `docs/VERIFIED-API.swift` §2（已过 api-gate 的类型检查），不是照抄社区代码：
/// - `level = .desktopWindow`：位于系统壁纸之上、桌面图标之下
/// - `collectionBehavior = [.canJoinAllSpaces, .stationary, …]`：跟随所有 Space 且切换时不重排
///   （ADR-003 的静帧兜底场景之一「切到全屏 Space 窗口未跟随」靠这一项消除）
/// - `sharingType = .none`：不参与屏幕共享与录屏，是隐私选择
/// - `ignoresMouseEvents = true`：壁纸不该吃掉点击
enum DesktopWallpaperWindow {
    /// AppKit 的窗口 / 视图全是 `@MainActor`，这个工厂必须是隔离的（Swift 6：非隔离上下文调用会报警）。
    @MainActor
    static func make(for screen: NSScreen, player: AVPlayerLayer) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        player.frame = view.bounds
        // 窗口跟随屏幕尺寸变化（外接显示器热插拔）时，播放层要一起长。
        player.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(player)
        window.contentView = view
        return window
    }
}
