import SwiftUI

/// 主窗口（瀑布流）：严格对齐线稿 main-window.svg，52px 工具栏 + 208px 侧栏 + 真 masonry + 32px 状态栏；保持 `BrowseView(viewModel:keyStore:)` 签名不变。
struct BrowseView: View {
    @Bindable var viewModel: BrowseViewModel
    let keyStore: KeyStore
    /// 设置面板（关于页复制微信号）用；实现由 `IHavenApp.bootstrap()` 装配注入（ARCH §4）。
    let clipboard: ClipboardWriting
    /// 存储页签的数据源（设置面板）。与 `clipboard` 同理，实现由装配点注入（ADR-017）。
    let storage: StorageUsage
    /// 本地库（导入图片 / 本地视频）。F8 与 F9 共用同一个实例：导入管线只有一份
    /// （PRD 附录 A-6b），两个页签只是按 `kind` 过滤出不同子集。
    @Bindable var library: LocalLibraryViewModel

    @State private var showFilter = false
    @State private var showSettings = false
    /// 打开设置时落在哪个页签（点筛选面板里锁定的 NSFW 档 → 直接到「内容」）。
    @State private var settingsTab: SettingsTab = .apiKey
    @State private var showSidebar = true
    @State private var nav: NavItem = .discover
    @State private var toast: String?
    /// 详情页：非 nil 即进入二级页面（`←` / `→` 在 `viewModel.wallpapers` 结果集内切换）。
    @State private var detail: Wallpaper?
    /// 全窗口**唯一**的删除确认：瀑布流本地项 / 导入页 / 动态壁纸页三处共用。
    /// 三处各自挂 `.alert` 会彼此竞争并被父级 `.sheet` 抑制（子视图模态被抢占），
    /// 表现就是「点了删除按钮什么都没发生」；收敛到一处后确认语义也天然一致。
    @State private var pendingDelete: ImportedWallpaper?
    @State private var crop: CropRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                // `.sheet` 挂内层，与 body 上的 `.alert` 分处不同层级，避免模态互相抑制。
                .sheet(isPresented: $showSettings) {
                    // initialTab：普通入口落「密钥」，从筛选面板锁定的 NSFW 档点进来则直达「内容」。
                    // onContentPolicyChanged：关掉开关时收回已勾选的 NSFW 档并重查（ADR-012）。
                    SettingsView(store: keyStore,
                                 clipboard: clipboard,
                                 storage: storage,
                                 animationIDs: animationIDs,
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
            HStack(spacing: 0) {
                if showSidebar { BrowseSidebar(nav: nav, onSelect: select) }
                mainArea
            }
            // HStack 占满宽度并左对齐，避免主区内容超出窗口宽时整体居中溢出把 sidebar 挤到左缘外被裁剪。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            browseStatusBar(resultsIncomplete: viewModel.resultsIncomplete,
                            isOffline: viewModel.isOffline,
                            waitingSeconds: viewModel.throttleSeconds,
                            count: nav == .favorites ? viewModel.favorites.count : viewModel.wallpapers.count)
        }
        .frame(minWidth: 880, minHeight: 600)
        .task { await reloadForNav() }
        .overlay(alignment: .bottom) { if let toast { browseToastView(toast) } }
        .alert(item: $pendingDelete) { item in
            // 三元表达式会推断成 String（走 Text(_:StringProtocol) 不本地化），须显式标注。
            let title: LocalizedStringKey = item.isAnimation ? "确定删除这个动态壁纸？" : "确定删除这个导入项？"
            return Alert(
                title: Text(title),
                message: Text(item.fileName),
                primaryButton: .destructive(Text("删除")) {
                    library.remove(item)
                    showToast(String(localized: "已删除"))
                },
                secondaryButton: .cancel(Text("取消")))
        }
        // 裁剪 sheet 与 `.alert` 同级挂最外层（子视图挂模态会被父级抑制，见本文件 L24-27）；
        // aspect / screenLabel 现读现算，不存进 CropRequest —— 用户可能在呈现期间换目标屏。
        .sheet(item: $crop) { req in
            WallpaperCropSheet(sourceURL: req.sourceURL,
                               aspect: WallpaperTarget.cropAspect(),
                               screenLabel: WallpaperTarget.cropScreenLabel(),
                               onCancel: { crop = nil },
                               onApply: { url, size in crop = nil; applyCrop(req, url: url, size: size) })
                // 被呈现的 sheet 不跟根视图环境更新，须自己挂一次（View+Locale.swift:15-21）。
                .appLocale()
        }
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

    // MARK: - 主内容区

    /// ⚠️ **详情页是 overlay 盖在主区上，不是 `if/else` 二选一** —— 这是「详情页返回后滚动条
    /// 跑到顶上」的根因：`if/else` 会在进入详情那一刻把 `searchContent` 的 `ScrollView`
    /// **整个从视图树上摘掉**，返回时只能新建一棵、偏移恒为 0。overlay 下底层 ScrollView 始终
    /// 在视图树上，偏移原样保留；详情页是不透明整块，视觉上与「换了页」一致。
    private var mainArea: some View {
        VStack(spacing: 0) {
            switch nav {
            case .favorites: favoritesContent
            case .wallpaperSet:
                AppliedWallpapersView(viewModel: viewModel, onDiscover: { select(.discover) }, onMessage: { showToast($0) })
            case .live:
                DynamicWallpaperView(library: library, onMessage: { showToast($0) }, onDeleteRequest: { pendingDelete = $0 })
            case .import:
                ImportView(library: library, onMessage: { showToast($0) },
                           onDeleteRequest: { pendingDelete = $0 },
                           onCropRequest: { cropImported($0) })
            default: browseSearchContent(viewModel: viewModel, gridItems: gridItems,
                                         onClearFilters: { clearFilters() }) { gridCard($0) }
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

    /// 瀑布流统一网格项：网络项 + 本地导入项（PRD:697 要求两者同瀑布流展示，本地项有可区分标识）。
    /// 本地项**不参与筛选与翻页** —— 筛选参数是 wallhaven 搜索参数，对本地文件无意义。
    private var gridItems: [WallpaperGridItem] {
        viewModel.wallpapers.map(WallpaperGridItem.network)
            + library.images.map(WallpaperGridItem.local)
    }

    @ViewBuilder
    private func gridCard(_ item: WallpaperGridItem) -> some View {
        switch item {
        case .network(let wp):
            WallpaperCard(wallpaper: wp,
                          isFavorite: viewModel.favoriteIDs.contains(wp.id),
                          onOpen: { detail = wp },
                          onToggleFavorite: { viewModel.toggleFavorite(wp) },
                          onSetWallpaper: { setWallpaper(wp) })
        case .local(let local):
            // 本地项没有网络详情页可开（详情页的字段全是 wallhaven 响应形状），
            // 因此单击 = 直接设为壁纸，与导入页卡片的主操作一致。
            LocalWallpaperCard(item: local,
                               primarySystemName: "display",
                               primaryHelp: "设为壁纸",
                               onPrimary: { setLocalWallpaper(local) },
                               onDelete: { pendingDelete = local },
                               onCrop: { cropImported(local) })
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
                   onMessage: { showToast($0) },
                   onCrop: { cropWallpaper(wallpaper) })
            .id(wallpaper.id)
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

    /// 仍在库中的动态壁纸 id（= 帧序列目录名）：存储页签据此判定哪些帧目录是孤儿。
    private var animationIDs: Set<String> {
        Set(library.imported.filter(\.isAnimation).map(\.id))
    }

    private func select(_ item: NavItem) {
        switch item {
        case .settings: openSettings(.apiKey); return
        // 「已设置」读本地记录，不发网络请求；落入 default 会走 reload 白打一次搜索。
        case .favorites: nav = .favorites; viewModel.loadFavorites(); return
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
    private func setLocalWallpaper(_ item: ImportedWallpaper) {
        Task { showToast((await library.setAsWallpaper(item)) ?? String(localized: "已设为壁纸")) }
    }
    private func setWallpaperFromFavorite(_ fav: Favorite) { Task { showToast((await viewModel.setWallpaperFromFavorite(fav)) ?? String(localized: "已设为壁纸")) } }

    // MARK: - 裁剪（竖图黑边，ADR-018）

    /// 网络壁纸：先取本地原图（失败提示重试）再弹 sheet。闭包里用参数 `wp`，不捕获 `@State detail`。
    private func cropWallpaper(_ wp: Wallpaper) {
        Task {
            guard let file = await viewModel.cropSource(for: wp) else {
                showToast(String(localized: "原图下载失败，请重试")); return
            }
            crop = CropRequest(id: wp.id, sourceURL: file, kind: .wallpaper(wp))
        }
    }

    private func cropImported(_ item: ImportedWallpaper) {
        crop = CropRequest(id: item.id, sourceURL: URL(fileURLWithPath: item.filePath), kind: .imported(item))
    }

    private func applyCrop(_ req: CropRequest, url: URL, size: CGSize) {
        Task {
            let error: String? = switch req.kind {
            case .wallpaper(let wp): await viewModel.applyCropped(url, pixelSize: size, wallpaper: wp)
            case .imported(let item): await library.applyCropped(url, pixelSize: size, item: item)
            }
            showToast(error ?? String(localized: "已设为壁纸"))
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == msg { toast = nil }
        }
    }
}
