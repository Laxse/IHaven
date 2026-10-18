import SwiftUI

/// 瀑布流导航项之外的补充：裁剪 sheet 的请求（`.sheet(item:)` 需要 `Identifiable`）。
///
/// ⚠️ **只带 sourceURL，不带 aspect / screenLabel**：两者都从 `WallpaperTarget` 现读
/// （`cropAspect()` / `cropScreenLabel()`）。存进请求里的话，用户在别的屏上改过目标屏、
/// 或 sheet 呈现期间插拔了显示器，选框锁的就是过期比例。
struct CropRequest: Identifiable {
    /// 裁剪完成后要设壁纸的源：网络壁纸走数据库记录，本地导入项走库里的那一条。
    enum Kind { case wallpaper(Wallpaper), imported(ImportedWallpaper) }
    let id: String
    let sourceURL: URL
    let kind: Kind
}

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
        // 面板内没有「完成」按钮（筛选即时生效），收起点外部或按 Esc 即可。
        FilterView(viewModel: viewModel, onOpenContentSettings: onOpenContentSettings)
            // 同 `.sheet`：被呈现的子树自己挂一次语言，不依赖环境从外向内传。
            .appLocale()
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

/// 状态栏（32px，chrome 底 + 顶部 1px hairline）。移出 BrowseView 只为守住 ADR-009 的 300 行上限。
///
/// `waitingSeconds > 0` 表示客户端正在退避等 API 配额（PRD §6 F7：不弹错误弹窗）。
/// 走状态栏而不是弹窗 / toast：它是常驻的、非模态的，不会打断用户正在做的滚动。
@MainActor
func browseStatusBar(resultsIncomplete: Bool, isOffline: Bool = false, waitingSeconds: Int = 0, count: Int) -> some View {
    HStack(spacing: 12) {
        if resultsIncomplete {
            Label("结果不完整（未配置 Key）", systemImage: "exclamationmark.triangle")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
        }
        if waitingSeconds > 0 {
            Label("API 调用已达上限，约 \(waitingSeconds) 秒后恢复", systemImage: "timer")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
        }
        // 离线常驻提示：**不弹窗、不用 toast** —— 两者都会打断用户，而离线时用户仍可正常
        // 用收藏 / 已设置 / 本地导入三页，并继续把已缓存的图设为壁纸。常驻一行就够了。
        if isOffline {
            Label("离线模式 · 已浏览的壁纸仍可设为壁纸", systemImage: "wifi.slash")
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

/// 列表区除「已加载」以外的四种态。**整块抽出来**是因为 `BrowseView.swift` 已经顶到
/// 300 行上限（`scripts/convention-gate.sh`），新增的 `.waiting` 分支没有落脚之处。
@MainActor
@ViewBuilder
func browseLoadStateView(_ state: BrowseViewModel.LoadState) -> some View {
    switch state {
    case .idle, .loading:
        ProgressView("加载中…").frame(maxWidth: .infinity, maxHeight: .infinity)
    case .waiting(let seconds):
        // 中性色而非 `danger`：等待限流恢复是**正常节流**，不是故障 —— 用警示色会让
        // 用户以为出问题了。这与「单图失败用中性色」是同一条原则（PRD §6 F1）。
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("正在等待 API 限流恢复（约 \(seconds) 秒）")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.meta)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded:
        EmptyView()
    case .failed(let msg):
        browseErrorState(msg)
    }
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

// MARK: - 瀑布流主区（从 BrowseView 整块搬来腾行数）

/// 「发现 / 风景 / 动漫 / 人物」页签的瀑布流主区。
///
/// ⚠️ **为什么整块搬出 `BrowseView`**：裁剪接线要在那里加 1 个 `@State` + 1 个 `.sheet(item:)`
/// + 3 个私有方法（约 40 行），而它已经 299/300（`scripts/convention-gate.sh`）。搬出这一块
/// 是唯一不破 ADR-009 的落点 —— 本文件里 `browseEmptyState` / `browseLoadStateView` /
/// `browseStatusBar` 都是同一套「顶层函数」先例。
///
/// `Card` 走泛型而不是 `AnyView`：`MasonryView` 本身是 `MasonryView<Item, Content: View>`，
/// 用 `some View` 包一层 `AnyView` 会让每个单元格多一次类型擦除，瀑布流是滚动热路径。
/// 瀑布流网格项：本地导入项 + 网络项。
///
/// ## 为什么本地项只在「发现」混入
/// PRD:697 的原话是「导入的图片与网络壁纸混合，**浏览**时两者在同一瀑布流展示」。而
/// 风景 / 动漫 / 人物 是明确的 wallhaven 分类 + 关键词检索（`BrowseView.applyCategory`
/// 下发 `q=nature` 等），用户的本地文件与这些查询毫无关系 —— 混进去等于污染检索结果，
/// 用户会以为「搜出来的怎么有我自己电脑里的图」。本地项本就有独立的「导入…」页签做完整管理。
///
/// ## 为什么排在最前而不是末尾
/// 网络结果是无限翻页**累加**的：原本拼在末尾，翻两页之后本地项就被推到几百张之外，
/// 实际上永远滚不到，等于没展示。置于最前则恒可见，且本地项数量有限不会挤压浏览。
///
/// 本地项**不参与筛选与翻页** —— 筛选参数是 wallhaven 搜索参数，对本地文件无意义
/// （文件头注释已记；若日后要改，应改成本地项也走同一套分辨率/比例过滤）。
func browseGridItems(_ network: [Wallpaper],
                     local: [ImportedWallpaper],
                     mixLocal: Bool) -> [WallpaperGridItem] {
    let online = network.map(WallpaperGridItem.network)
    guard mixLocal else { return online }
    return local.map(WallpaperGridItem.local) + online
}

@MainActor
@ViewBuilder
func browseSearchContent<Card: View>(viewModel: BrowseViewModel,
                                     gridItems: [WallpaperGridItem],
                                     onClearFilters: @escaping () -> Void,
                                     @ViewBuilder card: @escaping (WallpaperGridItem) -> Card) -> some View {
    switch viewModel.presentedLoadState {
    case .loaded:
        // 用 `gridItems` 而不是 `viewModel.wallpapers` 判空：离线或搜索零结果时，网络列表是
        // 空的但本地导入项仍在 —— 判后者会盖掉用户自己的图，给出「没有匹配的壁纸」的假空态。
        if gridItems.isEmpty {
            browseEmptyState(title: "没有匹配的壁纸",
                             body: "当前筛选组合下没有结果。放宽分辨率或比例通常能找到更多。",
                             action: "清除全部筛选", onAction: onClearFilters)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    MasonryView(items: gridItems,
                                spacing: IHaven.Layout.masonryGap,
                                minColumnWidth: IHaven.Layout.masonryColMin,
                                aspectRatio: { $0.aspectRatio }) { item in
                        card(item)
                    }
                    .padding(IHaven.Space.s6.rawValue)

                    // 底部加载指示（纯展示）；真正的触底加载由 ScrollView 的 onScrollGeometryChange 负责。
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        if viewModel.query.page > 1 {
                            ProgressView().controlSize(.small)
                            Text("加载更多…").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 40)
                }
            }
            // 触底加载：< 240pt 预取下一页。[!] 内容未超出视口时不算触底：首屏未布局时 contentSize=视口高，
            // distance≈0 会被误判成已触底而多拉一页（实测启动连发 page=1+page=2，即「初始加载 48 张」的根因）。
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height > $0.containerSize.height ? $0.contentSize.height - ($0.contentOffset.y + $0.containerSize.height) : .infinity } action: { _, distance in
                if distance < 240 { Task { await viewModel.nextPage() } }
            }
        }
    default:
        browseLoadStateView(viewModel.presentedLoadState)
    }
}
