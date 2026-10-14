import SwiftUI

/// 侧栏导航项（对齐线稿 SF Symbols 对照）。密钥不再是独立项，已并入设置面板页签。
enum NavItem: Hashable {
    case discover, landscape, anime, people, favorites, wallpaperSet, live, `import`, settings
    /// 用 `LocalizedStringKey` 而非 `String`：侧栏标签直接进 `Text(...)`，
    /// 落成 String 就固化成中文、永远查不到 Localizable.strings。
    var label: LocalizedStringKey {
        switch self {
        case .discover: "发现"; case .landscape: "风景"; case .anime: "动漫"; case .people: "人物"
        case .favorites: "收藏"; case .wallpaperSet: "已设置"; case .live: "动态壁纸"
        case .import: "导入…"; case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .discover: "square.grid.2x2"; case .landscape: "mountain.2.fill"; case .anime: "sparkles"
        case .people: "person.fill"; case .favorites: "star"; case .wallpaperSet: "display.2"
        case .live: "play.circle"; case .import: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}

/// 筛选 chip 摘要生成（对齐线稿 toolbar 的筛选 chip 摘要）。
func browseActiveFilterChips(query: BrowseQuery) -> [String] {
    var r: [String] = []
    if !query.atleast.isEmpty { r.append(browseResolutionLabel(query.atleast)) }
    // 摘要对用户展示分组名（「比例: 横构图」）而非下发值；未命中分组时回退原始值。
    // chip 文案是「固定标签 + 动态值」的拼接，用 String(localized:) 让固定部分可翻译（插值仍生效）。
    if query.ratio != .unspecified {
        r.append(String(localized: "比例: \(RatioGroup.label(for: query.ratio) ?? query.ratio.rawValue)"))
    }
    if !query.color.isEmpty { r.append(String(localized: "色: #\(query.color)")) }
    if query.purity != PurityFilter.browseDefault { r.append(String(localized: "纯度")) }
    return r
}

func browseResolutionLabel(_ atleast: String) -> String {
    switch atleast {
    case "1920x1080": return "≥1080p"
    case "2560x1440": return "≥1440p"
    case "3840x2160": return "≥4K"
    case "5120x2880": return "≥5K"
    default: return "≥\(atleast)"
    }
}

/// 工具栏筛选 chip 摘要 + 「清除全部筛选」（对齐线稿 summaryBar）。
@MainActor
func browseFilterChips(query: BrowseQuery, onClear: @escaping () -> Void) -> some View {
    let chips = browseActiveFilterChips(query: query)
    return HStack(spacing: 6) {
        ForEach(chips, id: \.self) { chip in
            Text(chip)
                .font(IHaven.Font.system(.xs, IHaven.Font.weightEmphasize))
                .padding(.horizontal, 10).padding(.vertical, 4)
                // DESIGN v4.2：accent 在 accent.opacity(0.12) 底上对比度只有 3.20:1（浅色），不达标；accentHover 为 4.64:1。
                .foregroundStyle(IHaven.Color.accentHover)
                .background(IHaven.Color.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(IHaven.Color.accent.opacity(0.34)))
        }
        if !chips.isEmpty {
            Button(action: onClear) {
                Text("清除全部筛选").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.focus)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 工具栏图标按钮：28×28 + 圆角 6 + 1px 描边，hover 补 `void` 底（工具栏与详情页页头条共用）。
/// 提成类型而不是函数：hover 态要 `@State`，函数返回值里挂不住。
struct BrowseIconButton: View {
    let systemName: String
    var help: LocalizedStringKey = ""
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: IHaven.Icon.sm))
                .frame(width: 28, height: 28)
                .background(hovered ? IHaven.Color.void : SwiftUI.Color.clear,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
        .help(help)
        .onHover { hovered = $0 }
    }
}

/// 「筛选」按钮：线稿固定 76×28，系统 `Label` + `.controlSize(.small)` 只有 62×22.7，故自绘底+描边。
@MainActor
func browseFilterButton(isPresented: Binding<Bool>,
                        viewModel: BrowseViewModel,
                        onOpenContentSettings: @escaping () -> Void) -> some View {
    Button { isPresented.wrappedValue = true } label: {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
            Text("筛选").font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
        }
        .padding(.horizontal, 12)
        .frame(width: 76, height: 28)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 关闭回调只收起 popover：筛选即时生效（FilterView 内 150ms 防抖已回到第 1 页重查），再 reload 会重复请求。
    .popover(isPresented: isPresented, arrowEdge: .bottom) {
        FilterView(viewModel: viewModel, onOpenContentSettings: onOpenContentSettings) {
            isPresented.wrappedValue = false
        }
    }
}

/// 工具栏搜索框（280×28）。
@MainActor
func browseSearchField(text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(IHaven.Color.meta)
        TextField("搜索壁纸、标签、上传者", text: text)
            .textFieldStyle(.plain).onSubmit(onSubmit)
    }
    .padding(.horizontal, IHaven.Space.s4.rawValue)
    .frame(width: 280, height: 28)
    .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
    .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
}

/// 未实现功能的占位态（动态壁纸 / 导入）。
@MainActor
func browsePlaceholder(item: NavItem) -> some View {
    VStack(spacing: 12) {
        Image(systemName: item.icon).font(.system(size: 40)).foregroundStyle(IHaven.Color.meta)
        Text(item.label).font(IHaven.Font.system(.lg, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
        Text("此功能将在后续版本提供。").font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// 状态栏（32px，chrome 底 + 顶部 1px hairline）。移出 BrowseView 只为守住 ADR-009 的 300 行上限。
@MainActor
func browseStatusBar(resultsIncomplete: Bool, count: Int) -> some View {
    HStack(spacing: 12) {
        if resultsIncomplete {
            Label("结果不完整（未配置 Key）", systemImage: "exclamationmark.triangle")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
        }
        Spacer(minLength: 0)
        Text("已加载 \(count) 张").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
    }
    .padding(.horizontal, IHaven.Space.s6.rawValue)
    .frame(maxWidth: .infinity)
    .frame(height: IHaven.Layout.statusBarHeight)
    .background(IHaven.Color.bgChrome)
    .overlay(alignment: .top) { Rectangle().fill(IHaven.Color.border).frame(height: 1) }
}

/// 空态 / 错误态 / Toast（对齐线稿占位与反馈）。
@MainActor
func browseEmptyState(title: LocalizedStringKey, body: LocalizedStringKey, action: LocalizedStringKey,
                      onAction: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Text(title).font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(body).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 360)
        Button(action: onAction) { Text(action) }.buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
func browseErrorState(_ msg: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(IHaven.Color.danger)
        Text("加载失败").font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
func browseToastView(_ msg: String) -> some View {
    Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.hudFg)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(IHaven.Color.hudBg, in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue).stroke(IHaven.Color.border))
        .padding(.bottom, 16)
}
