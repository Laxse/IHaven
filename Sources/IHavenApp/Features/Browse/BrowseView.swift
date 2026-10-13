import SwiftUI

/// 主窗口（瀑布流）。严格对齐已批准线稿 main-window.svg：
/// 全宽 52px 工具栏（Liquid Glass G1）+ 208px 侧栏（Liquid Glass G2）+ 真 masonry 瀑布流 + 32px 状态栏。
/// 保持 `BrowseView(viewModel:keyStore:)` 签名不变（IHavenApp 依赖）；筛选面板改为工具栏锚定 popover。
struct BrowseView: View {
    @Bindable var viewModel: BrowseViewModel
    let keyStore: KeyStore

    @State private var showFilter = false
    @State private var showKeyConfig = false
    @State private var showSidebar = true
    @State private var nav: NavItem = .discover
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showSidebar { sidebar }
                mainArea
            }
            // HStack 占满宽度并左对齐，避免主区内容超出窗口宽时整体居中溢出把 sidebar 挤到左缘外被裁剪。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            statusBar
        }
        .frame(minWidth: 880, minHeight: 600)
        .task { await reloadForNav() }
        .sheet(isPresented: $showKeyConfig) {
            KeyConfigView(store: keyStore) { showKeyConfig = false; Task { await reloadForNav() } }
        }
        .overlay(alignment: .bottom) { if let toast { toastView(toast) } }
    }

    // MARK: - 工具栏（52px，chrome 底 + 1px hairline）
    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarIconButton("sidebar.left") { withAnimation { showSidebar.toggle() } }
            searchField.padding(.leading, 20)
            Spacer(minLength: 0)
            filterChips
            filterButton.padding(.leading, 20)
            toolbarIconButton("star") { select(.favorites) }
                .padding(.leading, 28)
            toolbarIconButton("gearshape") { showKeyConfig = true }
                .padding(.leading, 8)
        }
        // 内边距按线稿：leading 8 / trailing 16（齿轮右边缘距窗口 16）。
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: IHaven.Layout.toolbarHeight)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
        }
    }

    /// 「筛选」按钮：线稿固定 76×28，系统 `Label` + `.controlSize(.small)` 只有 62×22.7，故自绘底+描边。
    private var filterButton: some View {
        Button { showFilter = true } label: {
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
        // 线稿要求筛选面板挂在工具栏下方（popover），而不是居中 sheet。
        .popover(isPresented: $showFilter, arrowEdge: .bottom) {
            FilterView(viewModel: viewModel) { showFilter = false; Task { await reloadForNav() } }
        }
    }

    /// 工具栏图标按钮统一规格：28×28 + 圆角 6 + 1px 描边（侧栏开关 / 星标 / 齿轮共用）。
    private func toolbarIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: IHaven.Icon.sm))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(IHaven.Color.meta)
            TextField("搜索壁纸、标签、上传者", text: $viewModel.query.q)
                .textFieldStyle(.plain)
                .onSubmit { Task { await reloadForNav() } }
        }
        .padding(.horizontal, IHaven.Space.s4.rawValue)
        .frame(width: 280, height: 28)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
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
                sidebarRow(.settings); sidebarRow(.key)
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
            .padding(.horizontal, IHaven.Space.s5.rawValue)
            .padding(.vertical, IHaven.Space.s2.rawValue)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        let selected = nav == item
        return Button { select(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: IHaven.Icon.sm))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                Text(item.label)
                    .font(IHaven.Font.system(.md))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: IHaven.Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? IHaven.Color.void : SwiftUI.Color.clear,
                    in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .padding(.horizontal, IHaven.Space.s4.rawValue)
    }

    // MARK: - 主内容区
    @ViewBuilder
    private var mainArea: some View {
        VStack(spacing: 0) {
            switch nav {
            case .favorites: favoritesContent
            case .live, .import: browsePlaceholder(item: nav)
            default: searchContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
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
                    MasonryView(items: viewModel.wallpapers,
                                spacing: IHaven.Layout.masonryGap,
                                minColumnWidth: IHaven.Layout.masonryColMin,
                                aspectRatio: { CGFloat($0.width) / CGFloat($0.height) }) { wp in
                        WallpaperCard(wallpaper: wp,
                                      isFavorite: viewModel.favoriteIDs.contains(wp.id),
                                      onToggleFavorite: { viewModel.toggleFavorite(wp) },
                                      onSetWallpaper: { setWallpaper(wp) })
                    }
                    .padding(IHaven.Space.s6.rawValue)
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

    // MARK: - 状态栏（32px，chrome 底 + 1px hairline）
    private var statusBar: some View {
        HStack(spacing: 12) {
            if viewModel.resultsIncomplete {
                Label("结果不完整（未配置 Key）", systemImage: "exclamationmark.triangle")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
            }
            Spacer(minLength: 0)
            let count = nav == .favorites ? viewModel.favorites.count : viewModel.wallpapers.count
            Text("已加载 \(count) 张").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
        .padding(.horizontal, IHaven.Space.s6.rawValue)
        .frame(maxWidth: .infinity)
        .frame(height: IHaven.Layout.statusBarHeight)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .top) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
        }
    }

    // MARK: - 筛选 chip 摘要 + 清除全部
    private var filterChips: some View {
        browseFilterChips(query: viewModel.query) { clearFilters() }
    }

    // MARK: - 行为
    private func select(_ item: NavItem) {
        switch item {
        case .settings, .key: showKeyConfig = true; return
        case .favorites: nav = .favorites; viewModel.loadFavorites(); return
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

    private func clearFilters() {
        viewModel.clearFilters()
        Task { await reloadForNav() }
    }

    private func reloadForNav() async {
        switch nav {
        case .favorites: viewModel.loadFavorites()
        case .live, .import: break
        default: await viewModel.reload()
        }
    }

    private func setWallpaper(_ wp: Wallpaper) {
        Task { showToast((await viewModel.setAsWallpaper(wp)) ?? "已设为壁纸") }
    }

    private func setWallpaperFromFavorite(_ fav: Favorite) {
        Task { showToast((await viewModel.setWallpaperFromFavorite(fav)) ?? "已设为壁纸") }
    }

    private func showToast(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == msg { toast = nil }
        }
    }

    private func toastView(_ msg: String) -> some View {
        browseToastView(msg)
    }
}
