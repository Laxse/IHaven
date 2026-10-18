import SwiftUI

/// 设置 · 快捷键页签（#68）：全局热键 ⌥⌘S 的开关 + 辅助功能授权状态。
///
/// 默认关闭：**启动时不索取辅助功能权限**（那是用户一打开 App 就被可选功能弹框的根因）。
/// 用户在这里主动开开关时，若未授权才弹一次系统授权框；授权后返回即生效（manager 监听了
/// didBecomeActive 补装 global monitor）。
struct SettingsShortcutTab: View {
    @AppStorage(UserPreferenceKey.globalHotkeyEnabled) private var enabled = false
    @State private var trusted = GlobalHotkeyManager.isTrusted

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
        }
        .onAppear { trusted = GlobalHotkeyManager.isTrusted }
        // 用户去系统设置授权再切回 App：刷新授权状态显示。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = GlobalHotkeyManager.isTrusted
        }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }
}
