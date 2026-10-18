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
/// ## 授权按需索取，启动绝不弹框
/// global monitor 需要辅助功能授权，但**启动时不该为此弹窗**——那会让用户一打开 App 就被
/// 索要一个他还没打算用的可选功能的权限。所以：启动只装 local monitor（前台可用，无需授权）；
/// global monitor 仅在「用户在设置里开了开关」且已授权时才装，未授权则**在用户主动开开关时**
/// 弹一次系统授权框。开关状态持久化在 `UserPreferenceKey.globalHotkeyEnabled`。
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    /// 「换一张」动作。返回 nil = 成功，非 nil = 失败描述（与 `setAsWallpaper` 口径一致）。
    /// 由装配点（`GlobalHotkeys.install`）注入，热键层不直接持有 ViewModel。
    var onShuffle: (() async -> String?)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isStarted = false
    private var activationObserver: NSObjectProtocol?

    private init() {}

    /// 默认热键 ⌥⌘S：keyCode 1 = 'S'，modifiers = Command + Option。
    /// 避开系统高频组合（⌘Space / ⌃⌘Q / 各 F 键）；⌥⌘ 前缀在本 App 语义里留给壁纸快捷操作。
    private let keyCode: UInt16 = 1
    private let modifiers: NSEvent.ModifierFlags = [.command, .option]
    /// `kAXTrustedCheckOptionPrompt` 的 CFString 值。直接引用 SDK 那个 `var` 会触发 Swift 6
    /// 严格并发的「共享可变状态」报错，故写字面量 —— AX API 按字符串值比对 key，行为一致。
    private let axPromptOptionKey = "AXTrustedCheckOptionPrompt"

    /// 当前是否已获辅助功能授权（设置页显示状态用）。
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 用户是否开了全局热键开关（持久化）。
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserPreferenceKey.globalHotkeyEnabled)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // local：App 前台即可用，无需授权，也不弹框。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event) else { return event }
            self.fire()
            return nil   // 吞掉，避免 ⌥⌘S 同时触发系统「显示存储对话框」之类
        }

        // global：仅当「已开开关 + 已授权」才装。启动不弹授权框。
        syncGlobalMonitor()

        // 用户去系统设置授权后返回 App：重新核对一次，尽量免重启补装 global monitor。
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncGlobalMonitor() }
            }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        removeGlobalMonitor()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        isStarted = false
    }

    /// 设置里开 / 关全局热键。开启时若未授权，就地触发一次系统授权弹窗（按需索取）。
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: UserPreferenceKey.globalHotkeyEnabled)
        if enabled {
            syncGlobalMonitor()
            // 开了开关但还没授权 → 弹一次系统提示，用户去「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」放行。
            if globalMonitor == nil {
                let options = [axPromptOptionKey: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
        } else {
            removeGlobalMonitor()
        }
    }

    /// 按「开关 + 授权」现状装配 / 拆除 global monitor。幂等，可反复调。
    func syncGlobalMonitor() {
        if Self.isEnabled && AXIsProcessTrusted(), globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.matches(event) == true { self?.fire() }
            }
        } else if (!Self.isEnabled || !AXIsProcessTrusted()), globalMonitor != nil {
            removeGlobalMonitor()
        }
    }

    private func removeGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
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
