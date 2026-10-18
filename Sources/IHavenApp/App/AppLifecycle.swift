import AppKit

/// App 生命周期钩子：只负责一件事 —— 保证 IHaven 是**被激活的前台 App 且有一个 key window**。
///
/// ## 为什么需要显式激活
/// 键盘事件的投递链是「激活的 App → key window → first responder」。任一环断了，表现都是
/// **全 App 所有输入框打不了字**：主窗口搜索框、设置页签、AI 面板一起中招，且看起来
/// 「光标在、点得进、就是敲字没反应」（聚焦环是 SwiftUI 自己画的，与是否真收到按键无关）。
///
/// 断链最常见的场景是**进程由别的 App 拉起**：从 Xcode「Run」直接跑 SwiftPM 可执行文件时，
/// 窗口画出来了，但 App 没走 LaunchServices 的完整激活流程，keyDown 仍被投递给上一个 App。
/// `applicationDidFinishLaunching` 里补一次 `activate(ignoringOtherApps:)` 即可接上。
///
/// ## 为什么只在没有 key window 时才抢
/// `didBecomeActive` 期间可能正有 sheet / 菜单栏面板持有 key，无条件抢会把输入焦点从用户
/// 正在打字的地方拖走 —— 那就把「打不了字」换成「打错地方」。故只在 `keyWindow == nil`
/// 时兜底；候选按 `canBecomeKey` 过滤，天然排除桌面层壁纸窗口（`.borderless`，不能成为 key）。
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 前台 App：有 Dock 图标与完整菜单栏（与 Packaging/Info.plist 不设 LSUIElement 一致）。
        NSApp.setActivationPolicy(.regular)
        // 接上键盘投递链的第一环。App 已激活时这是 no-op，不会打扰用户。
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard NSApp.keyWindow == nil else { return }
        NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
}
