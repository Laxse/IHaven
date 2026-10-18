import AppKit
import ApplicationServices

/// 全局热键（#68）：App 不在前台也能一键「换一张」。
///
/// ## 为什么用 NSEvent monitor 而不是 Carbon `RegisterEventHotKey`
/// 本 App 是 ad-hoc 签名、无 Developer ID，也没有 Accessibility/Sandbox entitlement。
/// `RegisterEventHotKey` 依赖合法的 code signature，实测在 ad-hoc 签名下热键回调时灵时不灵
/// （签名不合法时系统直接不派发）。NSEvent 的 global monitor 是 AppKit 官方路径，
/// 与签名无关，只要用户在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」里放行即可。
///
/// ## 授权未就绪时的降级
/// `AXIsProcessTrusted()` 为假时**只装 local monitor**（App 前台仍可用），并触发一次系统授权
/// 弹窗。授权状态的变化要等 App 重启才被 NSEvent 承认，所以不做「授权后热插拔 global monitor」——
/// 那会在用户刚点完「允许」的瞬间仍然收不到事件，反而更难排查。
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    /// 「换一张」动作。返回 nil = 成功，非 nil = 失败描述（与 `setAsWallpaper` 口径一致）。
    /// 由装配点（`GlobalHotkeys.install`）注入，热键层不直接持有 ViewModel。
    var onShuffle: (() async -> String?)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isStarted = false

    private init() {}

    /// 默认热键 ⌥⌘S：keyCode 1 = 'S'，modifiers = Command + Option。
    /// 避开系统高频组合（⌘Space / ⌃⌘Q / 各 F 键）；⌥⌘ 前缀在本 App 语义里留给壁纸快捷操作。
    private let keyCode: UInt16 = 1
    private let modifiers: NSEvent.ModifierFlags = [.command, .option]
    /// `kAXTrustedCheckOptionPrompt` 的 CFString 值。直接引用 SDK 那个 `var` 会触发 Swift 6
    /// 严格并发的「共享可变状态」报错，故写字面量 —— AX API 按字符串值比对 key，行为一致。
    private let axPromptOptionKey = "AXTrustedCheckOptionPrompt"

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // local：App 前台时一定可用，无需授权。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event) else { return event }
            self.fire()
            return nil   // 吞掉，避免 ⌥⌘S 同时触发系统「显示存储对话框」之类
        }

        // global：需要辅助功能授权；未授权时触发一次系统提示（用户放行后重启生效）。
        if AXIsProcessTrusted() {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.matches(event) == true { self?.fire() }
            }
        } else {
            let options = [axPromptOptionKey: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        isStarted = false
    }

    /// 只认「恰好 ⌥⌘ + S」：多按一个 Shift 视为另一个组合，不触发（避免误判）。
    private func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }

    private func fire() {
        Task { _ = await onShuffle?() }
    }
}
