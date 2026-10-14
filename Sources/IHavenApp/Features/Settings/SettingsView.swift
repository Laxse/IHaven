import SwiftUI

/// 设置面板页签（原独立「密钥」侧栏项的归宿）。
enum SettingsTab: String, CaseIterable, Identifiable {
    case apiKey, appearance, content, about
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .apiKey: "密钥"; case .appearance: "外观"; case .content: "内容"; case .about: "关于"
        }
    }
}

/// 设置面板：页签式（密钥 / 外观 / 内容 / 关于）。密钥并入此面板，不再是独立入口。
/// 保存密钥后回调 `onSaved` 让浏览层重载；关闭由「完成」触发 `onClose`；
/// 「内容 · 允许成人内容」被关掉时回调 `onContentPolicyChanged`（ADR-012）。
struct SettingsView: View {
    let store: KeyStore
    /// 打开时落在哪个页签（筛选面板里点灰置的 NSFW 档会直接跳到「内容」页签）。
    var initialTab: SettingsTab = .apiKey
    var onSaved: () -> Void
    /// 内容策略开关被关掉时回调：由调用方收回已开启的 NSFW 档并重查（ADR-012）。
    var onContentPolicyChanged: () -> Void = {}
    var onClose: () -> Void

    @State private var tab: SettingsTab = .apiKey
    @State private var draft: String
    @State private var savedHint = false
    @AppStorage(UserPreferenceKey.appearance) private var appearance: String = "system"
    @AppStorage(UserPreferenceKey.language) private var language: String = AppLanguage.default.rawValue
    @AppStorage(UserPreferenceKey.nsfwAllowed) private var nsfwAllowed = false

    init(store: KeyStore,
         initialTab: SettingsTab = .apiKey,
         onSaved: @escaping () -> Void,
         onContentPolicyChanged: @escaping () -> Void = {},
         onClose: @escaping () -> Void) {
        self.store = store
        self.initialTab = initialTab
        self.onSaved = onSaved
        self.onContentPolicyChanged = onContentPolicyChanged
        self.onClose = onClose
        _tab = State(initialValue: initialTab)
        _draft = State(initialValue: store.currentKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(IHaven.Color.border)
            content
            Divider().overlay(IHaven.Color.border)
            footer
        }
        .frame(width: 560, height: 460)
        .background(IHaven.Color.bg)
    }

    // MARK: - 头部（标题 + 页签）
    private var header: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            Text("设置").font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        .padding(IHaven.Space.s7.rawValue)
    }

    // MARK: - 内容区
    @ViewBuilder
    private var content: some View {
        ScrollView {
            switch tab {
            case .apiKey: apiKeyTab
            case .appearance: appearanceTab
            case .content: contentTab
            case .about: aboutTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(IHaven.Space.s7.rawValue)
    }

    // MARK: - 页签 · 密钥
    private var apiKeyTab: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("Wallhaven API Key")
            Text("Key 经 X-API-Key 请求头下发；空 / 纯空白视为未配置（Trap 14）。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Circle().fill(isConfigured ? IHaven.Color.success : IHaven.Color.meta).frame(width: 8, height: 8)
                // 三元直接写在字面量上会先固化成 String，故两侧各自构造 LocalizedStringKey。
                Text(isConfigured ? LocalizedStringKey("已配置") : LocalizedStringKey("未配置"))
                    .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                if savedHint { Text("已保存").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.success) }
            }
            SecureField("X-API-Key", text: $draft)
                .textFieldStyle(.plain).font(IHaven.Font.system(.md))
                .padding(.horizontal, IHaven.Space.s5.rawValue).frame(height: 32)
                .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Button("保存") { save() }.buttonStyle(.borderedProminent)
                Button("清除") { save(clear: true) }.buttonStyle(.bordered)
            }
            Text("存储位置：~/.ihaven/apikey（ADR-010）—— 仅存本机文件，绝不进日志与崩溃报告。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
    }

    // MARK: - 页签 · 外观
    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("主题")
            Text("覆盖系统外观；默认跟随系统，修改后立即生效。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Picker("", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack(spacing: IHaven.Space.s4.rawValue) {
                swatch(IHaven.Color.bg, "背景")
                swatch(IHaven.Color.surface, "卡片")
                swatch(IHaven.Color.accent, "强调色")
                swatch(IHaven.Color.fg, "文字")
            }
            sectionTitle("语言")
            Text("切换后立即生效，无需重启。").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { item in
                    Text(LocalizedStringKey(item.displayKey)).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    /// `name` 必须是 `LocalizedStringKey`：写成 `String` 会走 `Text(_: StringProtocol)` 重载，
    /// 编译期就固化，永远不查表 —— 切英文时这四个色名会钉在中文上。
    private func swatch(_ color: SwiftUI.Color, _ name: LocalizedStringKey) -> some View {
        VStack(spacing: IHaven.Space.s3.rawValue) {
            RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).fill(color).frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
            Text(name).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 页签 · 内容（NSFW 开关，ADR-012）

    /// 开关只表达「本机使用者是否愿意看到成人内容」，与账号权限无关：
    /// 不做任何探测（ADR-011 已论证探测会吃掉配额、且失败态会被误报成「无权限」）。
    private var contentTab: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("成人内容")
            Text("默认关闭。开启后，筛选面板的 NSFW 档位才允许勾选，结果中可能包含裸露、暴力或色情等不适合在工作场合浏览的内容。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Toggle(isOn: $nsfwAllowed) {
                Text("允许成人内容（NSFW）").font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg)
            }
            .toggleStyle(.switch)
            .onChange(of: nsfwAllowed) { _, allowed in
                if !allowed { onContentPolicyChanged() }   // 关掉时把已勾选的 NSFW 档收回并重查
            }
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Circle().fill(nsfwAllowed ? IHaven.Color.warn : IHaven.Color.success).frame(width: 8, height: 8)
                Text(nsfwAllowed ? LocalizedStringKey("已开启") : LocalizedStringKey("已关闭"))
                    .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
            }
        }
    }

    // MARK: - 页签 · 关于
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("关于 IHaven")
            Text("macOS 原生壁纸工具：从 Wallhaven 发现壁纸，一键设为桌面壁纸。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            infoRow("版本", appVersion)
            infoRow("技术栈", "Swift 6 · SwiftUI · Nuke · GRDB")
            infoRow("数据位置", "~/.ihaven/apikey")
            // value 是 String 通道（要参与拼接/判断），用 String(localized:) 而非裸字面量。
            infoRow("数据来源", isMock ? String(localized: "Mock（免 VPN）")
                                      : String(localized: "Wallhaven 在线服务"))
        }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s5.rawValue) {
            Text(label).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2).frame(width: 72, alignment: .leading)
            Text(value).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }

    // MARK: - 底部
    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button("完成") { onClose() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(IHaven.Space.s6.rawValue)
    }

    // MARK: - 行为
    private var isConfigured: Bool { !store.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isMock: Bool { ProcessInfo.processInfo.environment["IHAVEN_MOCK"] == "1" }
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    private func save(clear: Bool = false) {
        try? store.save(clear ? "" : draft)
        if clear { draft = "" }
        savedHint = true
        onSaved()
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); savedHint = false }
    }
}
