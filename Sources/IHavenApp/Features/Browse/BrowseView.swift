import SwiftUI

/// 主窗口（瀑布流）：严格对齐线稿 main-window.svg，52px 工具栏 + 208px 侧栏 + 真 masonry + 32px 状态栏；保持 `BrowseView(viewModel:keyStore:)` 签名不变。
struct BrowseView: View {
    @Bindable var viewModel: BrowseViewModel
    let keyStore: KeyStore

    @State private var showFilter = false
    @State private var showSettings = false
    /// 打开设置时落在哪个页签（点筛选面板里锁定的 NSFW 档 → 直接到「内容」）。
    @State private var settingsTab: SettingsTab = .apiKey
    @State private var showSidebar = true
    @State private var nav: NavItem = .discover
    @State private var toast: String?
    /// 详情页：非 nil 即进入二级页面（`←` / `→` 在 `viewModel.wallpapers` 结果集内切换）。
    @State private var detail: Wallpaper?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showSidebar { sidebar }
                mainArea
            }
            // HStack 占满宽度并左对齐，避免主区内容超出窗口宽时整体居中溢出把 sidebar 挤到左缘外被裁剪。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            browseStatusBar(resultsIncomplete: viewModel.resultsIncomplete,
                            count: nav == .favorites ? viewModel.favorites.count : viewModel.wallpapers.count)
        }
        .frame(minWidth: 880, minHeight: 600)
        .task { await reloadForNav() }
        .sheet(isPresented: $showSettings) {
            // initialTab：普通入口落「密钥」，从筛选面板锁定的 NSFW 档点进来则直达「内容」。
            // onContentPolicyChanged：关掉开关时收回已勾选的 NSFW 档并重查（ADR-012）。
            SettingsView(store: keyStore,
                         initialTab: settingsTab,
                         onSaved: { Task { await reloadForNav() } },
                         onContentPolicyChanged: { viewModel.disableNSFWIfNeeded() },
                         onClose: { showSettings = false })
                // @State 只在首次构造时取 initialTab，换页签必须靠 id 强制重建，否则停在上一个页签。
                .id(settingsTab)
                // 语言要自己挂一次：被呈现的 sheet 不跟根视图的环境更新，挂上后由 sheet 自己
                // 读偏好重注入 —— 否则主窗口切了英文、设置面板还是中文。
                .appLocale()
        }
        .overlay(alignment: .bottom) { if let toast { browseToastView(toast) } }
    }

    // MARK: - 工具栏（52px，chrome 底 + 1px hairline）
    private var toolbar: some View {
        HStack(spacing: 0) {
            // 交通灯在系统保留的标题栏安全区内（实测 y10~22pt）：左侧 12pt 使开关按钮槽中心 x=26 对齐侧栏图标列。
            BrowseIconButton(systemName: "sidebar.left") { withAnimation { showSidebar.toggle() } }
                .padding(.leading, 12)
            browseSearchField(text: $viewModel.query.q) { Task { await reloadForNav() } }
                .padding(.leading, 16)   // 线稿基准：搜索框左缘 x=56
            Spacer(minLength: 0)
            browseFilterChips(query: viewModel.query) { clearFilters() }
            browseFilterButton(isPresented: $showFilter, viewModel: viewModel,
                               onOpenContentSettings: { openSettings(.content) })
                .padding(.leading, 20)
            BrowseIconButton(systemName: "star") { select(.favorites) }
                .padding(.leading, 28)
            BrowseIconButton(systemName: "gearshape") { openSettings(.apiKey) }
                .padding(.leading, 8)
        }
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: IHaven.Layout.toolbarHeight)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
        }
    }

    // MARK: - 侧栏（208px，chrome 底 + 1px hairline）
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(.discover)
                sidebarDivider
                sidebarRow(.landscape); sidebarRow(.anime); sidebarRow(.people)
                sidebarDivider
                sidebarRow(.favorites); sidebarRow(.wallpaperSet)
                sidebarDivider
                sidebarRow(.live); sidebarRow(.import)
                sidebarDivider
                sidebarRow(.settings)
            }
            .padding(.vertical, 8)
        }
        .frame(width: IHaven.Layout.sidebarWidth)  // 先固定宽度再填充高度，保证 ScrollView 恰好 208px、不溢出挤偏主区
        .frame(maxHeight: .infinity)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .trailing) {
            Rectangle().fill(IHaven.Color.border).frame(width: 1)
        }
    }

    private var sidebarDivider: some View {
        Rectangle().fill(IHaven.Color.borderSoft).frame(height: 1)
            .padding(.horizontal, IHaven.Space.s5.rawValue).padding(.vertical, IHaven.Space.s2.rawValue)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        let selected = nav == item
        return Button { select(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: IHaven.Icon.sm))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                    // 固定图标槽：SF Symbol 宽窄不一，槽内居中使图标成列、标签对齐到同一 x
                    .frame(width: 20, alignment: .center)
                Text(item.label)
                    .font(IHaven.Font.system(.md))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                Spacer(minLength: 0)
            }
            // 行内 8pt：图标槽落在 16~36（中心 26，与工具栏开关图标同列）、标签左缘 46（线稿基准）
            .padding(.horizontal, IHaven.Space.s4.rawValue)
            .frame(height: IHaven.Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? IHaven.Color.void : SwiftUI.Color.clear,
                    in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .padding(.horizontal, IHaven.Space.s4.rawValue)
    }

    // MARK: - 主内容区

    /// ⚠️ **详情页是 overlay 盖在主区上，不是 `if/else` 二选一** —— 这是「详情页返回后滚动条
    /// 跑到顶上」的根因。`if/else` 会在进入详情那一刻把 `searchContent` 的 `ScrollView`
    /// **整个从视图树上摘掉**，`detail = nil` 返回时只能新建一棵，而新建的 ScrollView 偏移恒为 0，
    /// 于是无论之前滚到哪里都回到顶部。改成 overlay 后底层 ScrollView 自始至终没离开过视图树，
    /// 偏移原样保留；详情页自己是不透明整块，视觉上与「换了页」完全一致。
    private var mainArea: some View {
        VStack(spacing: 0) {
            switch nav {
            case .favorites: favoritesContent
            case .wallpaperSet:
                AppliedWallpapersView(viewModel: viewModel, onDiscover: { select(.discover) }, onMessage: { showToast($0) })
            case .live, .import: browsePlaceholder(item: nav)
            default: searchContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
        .overlay {
            if let detail {
                detailPage(detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(IHaven.Color.bg)
            }
        }
    }

    /// 详情页（二级页面）。`.id` 让切换壁纸时整体重建：详情请求、大图都要跟着换。
    private func detailPage(_ wallpaper: Wallpaper) -> some View {
        DetailView(wallpaper: wallpaper,
                   context: viewModel.wallpapers,
                   viewModel: viewModel,
                   onClose: { detail = nil },
                   onNavigate: { detail = $0 },
                   onSearch: { query in detail = nil; viewModel.search(query) },
                   onToggleFavorite: { viewModel.toggleFavorite(wallpaper) },
                   onMessage: { showToast($0) })
            .id(wallpaper.id)
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("加载中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.wallpapers.isEmpty {
                browseEmptyState(title: "没有匹配的壁纸",
                           body: "当前筛选组合下没有结果。放宽分辨率或比例通常能找到更多。",
                           action: "清除全部筛选") { clearFilters() }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        MasonryView(items: viewModel.wallpapers,
                                    spacing: IHaven.Layout.masonryGap,
                                    minColumnWidth: IHaven.Layout.masonryColMin,
                                    aspectRatio: { CGFloat($0.width) / CGFloat($0.height) }) { wp in
                            WallpaperCard(wallpaper: wp,
                                          isFavorite: viewModel.favoriteIDs.contains(wp.id),
                                          onOpen: { detail = wp },
                                          onToggleFavorite: { viewModel.toggleFavorite(wp) },
                                          onSetWallpaper: { setWallpaper(wp) })
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
        case .failed(let msg):
            browseErrorState(msg)
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if viewModel.favorites.isEmpty {
            browseEmptyState(title: "还没有收藏",
                       body: "在瀑布流中悬停任意壁纸并点亮星标，或按 ⌘D。",
                       action: "去发现壁纸") { select(.discover) }
        } else {
            ScrollView {
                MasonryView(items: viewModel.favorites,
                            spacing: IHaven.Layout.masonryGap,
                            minColumnWidth: IHaven.Layout.masonryColMin,
                            aspectRatio: { _ in 1.6 }) { fav in
                    FavoriteCard(favorite: fav,
                                 onToggleFavorite: { viewModel.removeFavorite(id: fav.id); viewModel.loadFavorites() },
                                 onSetWallpaper: { setWallpaperFromFavorite(fav) })
                }
                .padding(IHaven.Space.s6.rawValue)
            }
        }
    }

    // MARK: - 行为
    private func select(_ item: NavItem) {
        switch item {
        case .settings: openSettings(.apiKey); return
        case .favorites: nav = .favorites; viewModel.loadFavorites(); return
        // 「已设置」读本地记录，不发网络请求；落入 default 会走 reload 白打一次搜索。
        case .wallpaperSet: nav = item; viewModel.loadApplied(); return
        case .live, .import: nav = item; return
        default: break
        }
        nav = item
        applyCategory(item)
        Task { await viewModel.reload() }
    }

    private func applyCategory(_ item: NavItem) {
        switch item {
        case .discover: viewModel.query.categories = .all; viewModel.query.q = ""
        case .landscape: viewModel.query.categories = .general; viewModel.query.q = "nature"
        case .anime: viewModel.query.categories = .anime; viewModel.query.q = ""
        case .people: viewModel.query.categories = .people; viewModel.query.q = ""
        default: break
        }
    }

    private func clearFilters() { viewModel.clearFilters(); Task { await reloadForNav() } }

    /// 打开设置面板并落在指定页签；须先收起筛选 popover（它会盖住 sheet，并存还会抢焦点）。
    private func openSettings(_ tab: SettingsTab) {
        showFilter = false
        settingsTab = tab
        showSettings = true
    }

    private func reloadForNav() async {
        switch nav {
        case .favorites: viewModel.loadFavorites()
        case .live, .import: break
        default: await viewModel.reload()
        }
    }

    private func setWallpaper(_ wp: Wallpaper) { Task { showToast((await viewModel.setAsWallpaper(wp)) ?? String(localized: "已设为壁纸")) } }
    private func setWallpaperFromFavorite(_ fav: Favorite) { Task { showToast((await viewModel.setWallpaperFromFavorite(fav)) ?? String(localized: "已设为壁纸")) } }

    private func showToast(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == msg { toast = nil }
        }
    }
}
