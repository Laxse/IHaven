import SwiftUI

/// 主窗口（瀑布流）。严格对齐已批准线稿 main-window.svg：
/// 全宽 52px 工具栏（Liquid Glass G1）+ 208px 侧栏（Liquid Glass G2）+ 真 masonry 瀑布流 + 32px 状态栏。
/// 保持 `BrowseView(viewModel:keyStore:)` 签名与 `.sheet` 接线不变（IHavenApp 依赖）。
struct BrowseView: View {
    @Bindable var viewModel: BrowseViewModel
    let keyStore: KeyStore

    @State private var showFilter = false
    @State private var showKeyConfig = false
    @State private var showSidebar = true
    @State private var nav: NavItem = .discover
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showSidebar { sidebar.frame(width: IHaven.Layout.sidebarWidth) }
                mainArea
            }
            statusBar
        }
        .frame(minWidth: 880, minHeight: 600)
        .task { await reloadForNav() }
        .sheet(isPresented: $showFilter) {
            FilterView(viewModel: viewModel) { showFilter = false; Task { await reloadForNav() } }
        }
        .sheet(isPresented: $showKeyConfig) {
            KeyConfigView(store: keyStore) { showKeyConfig = false; Task { await reloadForNav() } }
        }
        .overlay(alignment: .bottom) { if let toast { toastView(toast) } }
    }

    // MARK: - 工具栏（52px，Liquid Glass）
    private var toolbar: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            Button { withAnimation { showSidebar.toggle() } } label: {
                Image(systemName: "sidebar.left").font(.system(size: IHaven.Icon.sm))
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            searchField
            Spacer(minLength: 0)
            filterChips
            Button { showFilter = true } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease")
            }
            .controlSize(.small)
            Button { select(.favorites) } label: { Image(systemName: "star") }
                .buttonStyle(.borderless)
            Button { showKeyConfig = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .frame(height: IHaven.Layout.toolbarHeight)
        .glassEffect(.regular)
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
    }

    // MARK: - 侧栏（208px，Liquid Glass）
    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(.discover)
                    Divider().padding(.vertical, 4)
                    sidebarRow(.landscape); sidebarRow(.anime); sidebarRow(.people)
                    Divider().padding(.vertical, 4)
                    sidebarRow(.favorites); sidebarRow(.wallpaperSet)
                    Divider().padding(.vertical, 4)
                    sidebarRow(.live); sidebarRow(.import)
                    Divider().padding(.vertical, 4)
                    sidebarRow(.settings); sidebarRow(.key)
                }
                .padding(.vertical, 8)
            }
            Spacer(minLength: 0)
        }
        .glassEffect(.regular)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        Button { select(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon).font(.system(size: IHaven.Icon.sm)).foregroundStyle(IHaven.Color.fg2)
                Text(item.label).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: IHaven.Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .background(nav == item ? IHaven.Color.surface : SwiftUI.Color.clear,
                    in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
    }

    // MARK: - 主内容区
    @ViewBuilder
    private var mainArea: some View {
        VStack(spacing: 0) {
            switch nav {
            case .favorites: favoritesContent
            case .live, .import: placeholder(item: nav)
            default: searchContent
            }
        }
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
                    .padding(IHaven.Layout.masonryGap)
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
                .padding(IHaven.Layout.masonryGap)
            }
        }
    }

    private func placeholder(item: NavItem) -> some View {
        VStack(spacing: 12) {
            Image(systemName: item.icon).font(.system(size: 40)).foregroundStyle(IHaven.Color.meta)
            Text(item.label).font(IHaven.Font.system(.lg, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
            Text("此功能将在后续版本提供。").font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 状态栏（32px，Liquid Glass）
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
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .frame(height: IHaven.Layout.statusBarHeight)
        .glassEffect(.regular)
    }

    // MARK: - 筛选 chip 摘要 + 清除全部
    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(browseActiveFilterChips(query: viewModel.query), id: \.self) { chip in
                Text(chip)
                    .font(IHaven.Font.system(.xs, IHaven.Font.weightEmphasize))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(IHaven.Color.accent)
                    .background(IHaven.Color.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(IHaven.Color.accent.opacity(0.34)))
            }
            if !browseActiveFilterChips(query: viewModel.query).isEmpty {
                Button { clearFilters() } label: {
                    Text("清除全部筛选").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.focus)
                }
                .buttonStyle(.plain)
            }
        }
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
        case .discover: viewModel.query.categories = .general; viewModel.query.q = ""
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
