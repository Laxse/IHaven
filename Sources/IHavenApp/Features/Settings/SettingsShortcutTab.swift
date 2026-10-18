import SwiftUI

/// 设置 · 快捷键页签（#68）：全局热键 ⌥⌘S 的开关 + 辅助功能授权状态。
///
/// 默认关闭：**启动时不索取辅助功能权限**（那是用户一打开 App 就被可选功能弹框的根因）。
/// 用户在这里主动开开关时，若未授权才弹一次系统授权框；授权后返回即生效（manager 监听了
/// didBecomeActive 补装 global monitor）。
struct SettingsShortcutTab: View {
    @AppStorage(UserPreferenceKey.globalHotkeyEnabled) private var enabled = false
    @State private var trusted = GlobalHotkeyManager.isTrusted
    /// 只为让自检行随定时器重算；焦点状态是现读现算的。
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("全局热键")
            Text("⌥⌘S 一键「换一张」，App 不在前台也能用。默认关闭；开启需在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」中授权 IHaven。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { enabled },
                set: { new in
                    enabled = new
                    GlobalHotkeyManager.shared.setEnabled(new)
                    trusted = GlobalHotkeyManager.isTrusted
                })) {
                Text("启用 ⌥⌘S 全局换一张").font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg)
            }
            .toggleStyle(.switch)

            if enabled && !trusted {
                Label("尚未获得辅助功能授权，全局热键暂不可用（App 前台时仍可用）。去系统设置授权后返回即生效。",
                      systemImage: "exclamationmark.triangle")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            focusLine
        }
        .onAppear { trusted = GlobalHotkeyManager.isTrusted }
        // 用户去系统设置授权再切回 App：刷新授权状态显示。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = GlobalHotkeyManager.isTrusted
        }
        // 自检行要反映「此刻」的焦点，故 1 秒一查：用户正打不了字时打开这一页，一眼能看出断在哪一环。
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    /// 键盘焦点自检：把「按键到底有没有落到本 App 上」直接显示出来。
    ///
    /// 排查「所有输入框都打不了字」时，这一行能一步区分三种病因，省掉一轮试错：
    /// App 未激活（按键被发给上一个 App）/ 已激活但没有 key window（按键无处投递）/ 正常。
    private var focusLine: some View {
        let _ = tick
        let appActive = NSApp.isActive
        let hasKey = NSApp.keyWindow != nil
        let state: LocalizedStringKey
        if !appActive {
            state = "App 未激活 · 按键会发给上一个 App"
        } else if !hasKey {
            state = "App 已激活 · 但当前没有 key 窗口"
        } else {
            state = "App 已激活 · 主窗口是 key 窗口"
        }
        return HStack(spacing: IHaven.Space.s2.rawValue) {
            Circle().fill(appActive && hasKey ? IHaven.Color.success : IHaven.Color.warn).frame(width: 8, height: 8)
            Text("键盘焦点自检").foregroundStyle(IHaven.Color.fg2)
            Text(state).foregroundStyle(IHaven.Color.meta)
        }
        .font(IHaven.Font.system(.xs))
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }
}
