import SwiftUI

/// 菜单栏面板（PRD F3）：当前壁纸 / 搜索 / 上一张 / 下一张 / 换一张 / 收藏 + 打开主窗口。
///
/// ⚠️ 三条必须守住的约束（每条都对应一个真实失效模式）：
/// 1. **状态不自建**。`viewModel` / `library` 就是主窗口那两个实例，由 `IHavenApp` 注入。
///    菜单栏面板与主窗口是两个 SwiftUI scene（ADR-004 关键约束：单一 `@Observable`、不用通知
///    广播）—— 这里 new 一个就变成两套状态，「下一张」在主窗口里看不见。
/// 2. **必须由 `IHavenApp` 用 `.menuBarExtraStyle(.window)` 挂**：PRD F3 要搜索框，`.menu`
///    样式渲染的是 NSMenuItem 宿主，`TextField` 落不了焦。
/// 3. **自己挂 `.appLocale()` 与 `preferredColorScheme`**：被呈现的子树不跟随根视图的环境更新，
///    理由见 `Core/Theme/View+Locale.swift:15-20`。
///
/// 版式：宽 320，水平内边距 12；分组之间 12、组内 8；底栏上方一条通栏 hairline。
@MainActor
struct MenuBarPanelView: View {
    /// 主窗口 ID。`IHavenApp` 的 `WindowGroup` 与这里同源：漂移的后果是「打开主窗口」
    /// 静默失效（id 对不上时 `openWindow` 什么都不做，且不报错）。
    static let mainWindowID = "main"

    /// 主窗口的浏览状态。`bootstrap()` 完成前是 nil（`IHavenApp` 的 `@State`），故有 nil 分支。
    let viewModel: BrowseViewModel?
    /// 本地库（导入的静态图），「换一张」的第三级候选源。
    let library: LocalLibraryViewModel?

    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserPreferenceKey.appearance) private var appearance: String = "system"
    @State private var queryText = ""
    /// 「上一张 / 下一张」在 `viewModel.wallpapers` 内的游标。结果集换了会被夹回范围内。
    @State private var cursor = 0
    /// 内联状态行。成功 / 失败分色（`PanelStatus`），不再共用中性色。
    @State private var status: PanelStatus?
    @State private var isBusy = false
    /// 搜索框聚焦态：驱动描边换 accent（凹陷可输入 vs 凸起可点，靠这个区分）。
    @FocusState private var searchFocused: Bool

    /// 面板宽度。300 → 320：操作行改成「1 主 + 2 图标」后需要呼吸空间，
    /// 且让 4 个 1:1 收藏格落在 68pt（(320 − 24 − 3×8) ÷ 4）这个舒适尺寸上。
    private static let width: CGFloat = 320
    /// 收藏一次显示几条：面板是高频快捷入口，不是收藏管理器，多了要滚动。
    private static let favoriteLimit = 4
    /// 收藏格边长：面板内宽减去两侧 12 与 3 个 8 间距后四等分。
    private static let favoriteTileSize =
        (width - IHaven.Space.s5.rawValue * 2 - IHaven.Space.s4.rawValue * 3) / 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let viewModel {
                panelContent(viewModel)
            } else {
                initializing
            }
        }
        .frame(width: Self.width)
        .background(IHaven.Color.bg)
        .preferredColorScheme(colorScheme)
        // 同 `.sheet` / `.popover`：这棵子树自己挂一次语言，不依赖环境从外向内传。
        .appLocale()
    }

    // MARK: - 未装配

    private var initializing: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            ProgressView().controlSize(.small)
            Text("初始化…").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
        }
        .padding(IHaven.Space.s6.rawValue)
    }

    // MARK: - 主体

    private func panelContent(_ vm: BrowseViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            currentWallpaper(vm)
            searchField(vm)
            actions(vm)
            if let status { panelStatusLine(status) }
            favorites(vm)
            // 通栏 hairline：两侧不再各加 padding，让底栏与上部分组分得更清楚。
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
            footer
        }
        // 顶部内边距挂在这里而不是卡片上：没有「已设置」记录时卡片整块不渲染，
        // 挂卡片上就会让面板顶部贴边（搜索框顶到菜单栏面板的上边缘）。
        .padding(.top, IHaven.Space.s5.rawValue)
        // 面板每次展开都刷新：`favorites` / `applied` 是惰性数组，不拉就是空的。
        .task { refresh(vm) }
    }

    /// 当前壁纸（最近一条「已设置」记录）。没有历史就整块省略，不留空位。
    @ViewBuilder
    private func currentWallpaper(_ vm: BrowseViewModel) -> some View {
        if let item = vm.applied.first {
            PanelCurrentCard(item: item) { openMainWindow() }
                .padding(.horizontal, IHaven.Space.s5.rawValue)
                .padding(.bottom, IHaven.Space.s5.rawValue)
        }
    }

    /// 搜索框：`surfaceSunken` 底 + 无描边 = 凹陷可输入；聚焦时才描 accent 边。
    private func searchField(_ vm: BrowseViewModel) -> some View {
        let shape = RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous)
        return HStack(spacing: IHaven.Space.s3.rawValue) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(IHaven.Color.meta)
            TextField("搜索壁纸、标签、上传者", text: $queryText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { submit(vm) }
        }
        .padding(.horizontal, IHaven.Space.s4.rawValue)
        .frame(height: 32)
        .background(IHaven.Color.surfaceSunken, in: shape)
        .overlay(shape.stroke(searchFocused ? IHaven.Color.accent : Color.clear, lineWidth: 1))
        .animation(IHaven.Motion.fast, value: searchFocused)
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.bottom, IHaven.Space.s4.rawValue)
    }

    private func actions(_ vm: BrowseViewModel) -> some View {
        let empty = vm.wallpapers.isEmpty
        return HStack(spacing: IHaven.Space.s3.rawValue) {
            PanelIconButton(systemImage: "chevron.left",
                            help: empty ? LocalizedStringKey("先在主窗口搜索或浏览，才有可切换的结果集")
                                        : LocalizedStringKey("上一张"),
                            disabled: empty || isBusy) { step(-1, vm) }
            PanelIconButton(systemImage: "chevron.right",
                            help: empty ? LocalizedStringKey("先在主窗口搜索或浏览，才有可切换的结果集")
                                        : LocalizedStringKey("下一张"),
                            disabled: empty || isBusy) { step(1, vm) }
            PanelShuffleButton(busy: isBusy) { shuffle(vm) }
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.bottom, IHaven.Space.s5.rawValue)
    }

    /// 收藏。**为空时整块不渲染**：一行「还没有收藏」要占 40pt，只为传达「没有内容」，
    /// 面板是快捷入口，这个信息不值 40pt。
    @ViewBuilder
    private func favorites(_ vm: BrowseViewModel) -> some View {
        if !vm.favorites.isEmpty {
            VStack(alignment: .leading, spacing: IHaven.Space.s4.rawValue) {
                Text("收藏")
                    .font(IHaven.Font.system(.xs, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.meta)
                HStack(spacing: IHaven.Space.s4.rawValue) {
                    ForEach(Array(vm.favorites.prefix(Self.favoriteLimit))) { fav in
                        PanelFavoriteTile(favorite: fav, size: Self.favoriteTileSize) {
                            applyFavorite(fav, vm)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, IHaven.Space.s5.rawValue)
            .padding(.bottom, IHaven.Space.s5.rawValue)
        }
    }

    /// 底栏。层级只靠字重 + 色阶：不再用 `IHaven.Color.focus`（那是焦点环语义色，
    /// 亮色态是 #1B6FC4 蓝，跟全 App 的琥珀 accent 不是一个色相，看着像系统默认超链接）。
    private var footer: some View {
        HStack(spacing: IHaven.Space.s5.rawValue) {
            Button(action: openMainWindow) {
                Text("打开主窗口")
                    .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { NSApp.terminate(nil) } label: {
                Text("退出 IHaven")
                    .font(IHaven.Font.system(.sm))
                    .foregroundStyle(IHaven.Color.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.vertical, IHaven.Space.s5.rawValue)
    }

    // MARK: - 行为

    private func refresh(_ vm: BrowseViewModel) {
        // ⚠️ `loadFavorites()` / `loadApplied()` 内部会把 `loadState` 置为 `.loaded`。面板是另一个
        // scene，无条件调用会把主窗口正在展示的失败态悄悄换成空态（错误文案消失）—— 主窗口在
        // failed 时一律不刷新。根治是让这两个方法不碰 `loadState`，那属 BrowseViewModel 的边界。
        if case .failed = vm.loadState { return }
        vm.loadFavorites()
        vm.loadApplied()
        if let library, library.images.isEmpty { library.load() }
    }

    private func submit(_ vm: BrowseViewModel) {
        vm.search(queryText)
        // 结果落在主窗口的瀑布流里：不 activate 的话窗口会开在菜单栏面板后面。
        openMainWindow()
    }

    private func openMainWindow() {
        openWindow(id: Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 在当前结果集内按游标移动，越界回绕。
    private func step(_ delta: Int, _ vm: BrowseViewModel) {
        // 兜底：按钮在结果集为空时已经 disabled，正常走不到这里。留着是防「点下去之后
        // 结果集被并发清空」这个窗口 —— 那时下标会直接越界崩，而不是给一句提示。
        guard !vm.wallpapers.isEmpty else {
            status = .failed(String(localized: "还没有搜索结果，先在主窗口浏览或搜索。"))
            return
        }
        let count = vm.wallpapers.count
        cursor = ((cursor + delta) % count + count) % count
        applyWallpaper(vm.wallpapers[min(cursor, count - 1)], vm)
    }

    /// 随机一张。源按「当前结果集 → 收藏 → 本地导入」降级，全空才给明确文案。
    private func shuffle(_ vm: BrowseViewModel) {
        if !vm.wallpapers.isEmpty {
            cursor = Int.random(in: vm.wallpapers.indices)
            applyWallpaper(vm.wallpapers[cursor], vm)
        } else if let fav = vm.favorites.randomElement() {
            applyFavorite(fav, vm)
        } else if let item = library?.images.randomElement() {
            applyLocal(item)
        } else {
            status = .failed(String(localized: "没有可换的壁纸，先在主窗口浏览或搜索。"))
        }
    }

    private func applyWallpaper(_ wp: Wallpaper, _ vm: BrowseViewModel) {
        guard begin() else { return }
        Task { finish(await vm.setAsWallpaper(wp)) }
    }

    private func applyFavorite(_ fav: Favorite, _ vm: BrowseViewModel) {
        guard begin() else { return }
        Task { finish(await vm.setWallpaperFromFavorite(fav)) }
    }

    private func applyLocal(_ item: ImportedWallpaper) {
        guard begin(), let library else { return }
        Task { finish(await library.setAsWallpaper(item)) }
    }

    /// 开始一次设壁纸动作；返回 false 表示已有动作在途，调用方直接放弃（避免并发重复下载同一张图）。
    private func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        status = nil
        return true
    }

    /// 约定：`nil` = 成功，非 nil = `error.localizedDescription`（与主窗口 toast 同一口径）。
    private func finish(_ result: String?) {
        isBusy = false
        if let result {
            status = .failed(result)
        } else {
            status = .ok(String(localized: "已设为壁纸"))
        }
    }

    /// 与 `IHavenApp.appearanceScheme` 同逻辑：面板是独立 scene，不继承主窗口的 `preferredColorScheme`。
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
}
