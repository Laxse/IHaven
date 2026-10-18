import SwiftUI

/// 设置面板页签（原独立「密钥」侧栏项的归宿）。
enum SettingsTab: String, CaseIterable, Identifiable {
    case apiKey, appearance, content, storage, performance, schedule, shortcut, ai, about
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .apiKey: "密钥"; case .appearance: "外观"; case .content: "内容"
        case .storage: "存储"; case .performance: "性能"; case .schedule: "轮换"
        case .shortcut: "快捷键"; case .ai: "AI"; case .about: "关于"
        }
    }
}

/// 设置面板：页签式（密钥 / 外观 / 内容 / 关于）。密钥并入此面板，不再是独立入口。
/// 保存密钥后回调 `onSaved` 让浏览层重载；关闭由「完成」触发 `onClose`；
/// 「内容 · 允许成人内容」被关掉时回调 `onContentPolicyChanged`（ADR-012）。
struct SettingsView: View {
    let store: KeyStore
    /// 关于页复制微信号用。只声明协议，实现由 `IHavenApp.bootstrap()` 装配注入（ARCH §4）。
    let clipboard: ClipboardWriting
    /// 存储页签的数据源（图片缓存 / 帧序列占用与清理）。实现由装配点注入（ADR-017）。
    let storage: StorageUsage
    /// 仍在库中的动态壁纸 id：存储页签用它判断哪些帧序列目录是「未使用」的孤儿。
    let animationIDs: Set<String>
    /// 仍被「已设置」记录引用的裁剪件路径：存储页签据此判断哪些裁剪文件是孤儿（ADR-018 清理策略）。
    let cropReferencedPaths: Set<String>
    /// 性能护栏（PRD F10）。App 级单例，默认参数取 `shared` —— 这样 `BrowseView`（已顶到
    /// 300 行上限）一行都不用改；与 `ImagePipeline.shared` / `NukeImagePipeline.pipeline` 同性质。
    var performance: PerformanceGuard = .shared
    /// 轮换日程执行器。同为 App 级单例（已由 `IHavenApp.bootstrap()` configure 过）。
    var schedule: WallpaperScheduler = .shared
    /// AI 图生视频的 Key 存储（#70）。App 级单例默认值 —— 与 `schedule` / `performance` 同一套路：
    /// 设置面板（写）与生成客户端（读）必须持有同一实例，故取 shared 而非各 new 一个。
    var aiStore: KeyStore = AIKeyStore.shared
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
    /// 壁纸铺放：目标显示器（0 = 主屏）与填充模式。与 `WallpaperTarget` 读写同一批 key。
    @AppStorage(UserPreferenceKey.wallpaperTargetDisplay) private var wallpaperTargetDisplay = 0
    @AppStorage(UserPreferenceKey.wallpaperFillMode) private var wallpaperFillMode = WallpaperFillMode.fill.rawValue

    init(store: KeyStore,
         clipboard: ClipboardWriting,
         storage: StorageUsage,
         animationIDs: Set<String>,
         cropReferencedPaths: Set<String> = [],
         initialTab: SettingsTab = .apiKey,
         onSaved: @escaping () -> Void,
         onContentPolicyChanged: @escaping () -> Void = {},
         onClose: @escaping () -> Void) {
        self.store = store
        self.clipboard = clipboard
        self.storage = storage
        self.animationIDs = animationIDs
        self.cropReferencedPaths = cropReferencedPaths
        self.initialTab = initialTab
        self.onSaved = onSaved
        self.onContentPolicyChanged = onContentPolicyChanged
        self.onClose = onClose
        _tab = State(initialValue: initialTab)
        _draft = State(initialValue: store.currentKey)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(IHaven.Color.border).frame(width: 1)
            detail
        }
        .frame(width: 640, height: 540)
        .background(IHaven.Color.bg)
    }

    /// 侧栏分类：竖向排列（9 个横向 segmented 会挤爆宽度，用户实测）。**不用 `List(selection:)`** ——
    /// 它会抢占键盘焦点做 type-select，把按键从右侧 SecureField / TextField 手里抢走、导致打不了字
    /// （用户实测）；改用普通按钮行，选中项给 accent 底色，观感同 source list 但不拦键盘。
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IHaven.Space.s1.rawValue) {
                ForEach(SettingsTab.allCases) { item in
                    sidebarRow(item)
                }
            }
            .padding(.vertical, IHaven.Space.s4.rawValue)
            .padding(.horizontal, IHaven.Space.s3.rawValue)
        }
        .background(IHaven.Color.bgChrome)
        .frame(width: 172)
        .frame(maxHeight: .infinity)
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        Button {
            tab = item
        } label: {
            Text(item.label)
                .font(IHaven.Font.system(.sm, tab == item ? IHaven.Font.weightEmphasize : IHaven.Font.weightRead))
                .foregroundStyle(tab == item ? IHaven.Color.accentOn : IHaven.Color.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, IHaven.Space.s4.rawValue)
                .frame(height: 28)
                .background(tab == item ? IHaven.Color.accent : SwiftUI.Color.clear,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 右侧详情：当前页签名作标题 + 可滚动内容 + 底部完成。
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tab.label)
                .font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce))
                .foregroundStyle(IHaven.Color.fg)
                .padding(IHaven.Space.s6.rawValue)
            content
            Divider().overlay(IHaven.Color.border)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - 内容区
    @ViewBuilder
    private var content: some View {
        ScrollView {
            switch tab {
            case .apiKey: apiKeyTab
            case .appearance: appearanceTab
            case .content: contentTab
            case .storage: SettingsStorageTab(storage: storage, animationIDs: animationIDs,
                                             cropReferencedPaths: cropReferencedPaths)
            case .performance: SettingsPerformanceTab(guardProvider: performance)
            case .schedule: SettingsScheduleTab(scheduler: schedule)
            case .shortcut: SettingsShortcutTab()
            case .ai: SettingsAITab(store: aiStore)
            case .about: SettingsAboutTab(clipboard: clipboard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(IHaven.Space.s6.rawValue)
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
            sectionTitle("壁纸")
            Text("所有「设为壁纸」按钮共用这两项；填充色优先取壁纸自身的主色。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Picker("", selection: $wallpaperTargetDisplay) {
                ForEach(WallpaperTarget.screenOptions()) { option in
                    // 主屏项 detail 为空串，只显示标题；有分辨率的带上「@2x」便于区分同型号屏。
                    if option.detail.isEmpty {
                        Text(option.title).tag(option.id)
                    } else {
                        Text("\(option.title) · \(option.detail)").tag(option.id)
                    }
                }
            }
            .pickerStyle(.menu).labelsHidden()
            // macOS 壁纸按 Space 而非按显示器设置：未开「显示器具有单独 Spaces」时多屏写入
            // 会被系统合并成一张，且该开关修改后要注销重登才生效。不给这句提示，用户只会
            // 看到「只生效一块屏」而无从判断原因（PRD F2 验收门禁）。
            if WallpaperTarget.needsSeparateSpacesWarning() {
                Label("未开启「显示器具有单独 Spaces」，多屏壁纸可能只在一块屏生效。请在系统设置 ▸ 桌面与程序坞中开启（修改后需注销重新登录）。",
                      systemImage: "exclamationmark.triangle")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("", selection: $wallpaperFillMode) {
                Text("适应（完整可见，四周留白）").tag(WallpaperFillMode.fit.rawValue)
                Text("填充（铺满屏幕，可能裁边）").tag(WallpaperFillMode.fill.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden()
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

    private func save(clear: Bool = false) {
        try? store.save(clear ? "" : draft)
        if clear { draft = "" }
        savedHint = true
        onSaved()
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); savedHint = false }
    }
}
