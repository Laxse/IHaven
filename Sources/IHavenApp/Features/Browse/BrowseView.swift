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

    @State var showFilter = false
    /// 设置页签当前停在哪一页。由本视图持有：设置是主区的一个**导航页签**（不再是 sheet），
    /// 进出不该丢掉上次看的那一页；筛选面板里点被锁的 NSFW 档时由 `openSettings(.content)` 改它。
    @State var settingsTab: SettingsTab = .apiKey
    @State private var showSidebar = true
    @State var nav: NavItem = .discover
    @State var toast: String?
    /// 详情页：非 nil 即进入二级页面（`←` / `→` 在结果集内切换）。
    @State var detail: Wallpaper?
    /// 详情页来源：决定 `←` / `→` 在哪一列里切换，以及「设为壁纸」的落库口径。
    /// `internal` 而非 `private`：`BrowseView+Navigation.swift` 要为 `detailSource` 写值。
    /// `.album` 携带的是**打开详情那一刻的相册成员快照**：`←` `→` 要在这个相册内翻，
    /// 而相册内容视图自己管理的 `items` 是它的 `@State`，详情页拿不到。早先复用 `.favorites`
    /// 凑数，结果 `←` `→` 跑到收藏列表里翻去了（用户反馈，2026-10-20）。
    enum DetailSource { case wallpapers, favorites, applied, album([Favorite]) }
    @State var detailSource: DetailSource = .wallpapers
    /// 全窗口**唯一**的删除确认：瀑布流本地项 / 导入页 / 动态壁纸页三处共用。
    /// 三处各自挂 `.alert` 会彼此竞争并被父级 `.sheet` 抑制（子视图模态被抢占），
    /// 表现就是「点了删除按钮什么都没发生」；收敛到一处后确认语义也天然一致。
    @State private var pendingDelete: ImportedWallpaper?
    @State var crop: CropRequest?
    /// 详情页「加入相册」的落点：非 nil 即弹出相册选择器 sheet。
    @State private var albumTarget: Wallpaper?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showSidebar { BrowseSidebar(nav: nav, onSelect: select) }
                mainArea
            }
            // HStack 占满宽度并左对齐，避免主区内容超出窗口宽时整体居中溢出把 sidebar 挤到左缘外被裁剪。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            browseStatusBar(resultsIncomplete: viewModel.resultsIncomplete,
                            isOffline: viewModel.isOffline,
                            waitingSeconds: viewModel.throttleSeconds,
                            count: nav == .favorites ? viewModel.favorites.count
                                   : (nav == .albums ? viewModel.albums.count : viewModel.wallpapers.count))
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
        // 「加入相册」选择器：与裁剪 sheet 同层挂在最外层，避免被父级 `.alert` 抑制。
        .sheet(item: $albumTarget) { wp in
            AlbumPickerSheet(viewModel: viewModel, wallpaper: wp, onMessage: { showToast($0) })
                .appLocale()
        }
    }

    // MARK: - 工具栏（52px，chrome 底 + 1px hairline）
    private var toolbar: some View {
        HStack(spacing: 0) {
            // 交通灯在系统保留的标题栏安全区内（实测 y10~22pt）：左侧 12pt 使开关按钮槽中心 x=26 对齐侧栏图标列。
            BrowseIconButton(systemName: "sidebar.left") { withAnimation { showSidebar.toggle() } }
                .padding(.leading, 12)
            // 回车提交是一次**新搜索**：page 必须回 1。留着旧页码会以「第 N 页」去查新关键词。
            browseSearchField(text: $viewModel.query.q) {
                viewModel.query.page = 1
                Task { await reloadForNav() }
            }
                .padding(.leading, 16)   // 线稿基准：搜索框左缘 x=56
            Spacer(minLength: 0)
            browseFilterChips(query: viewModel.query) { clearFilters() }
            // [!] 这里原先还有「收藏（星）」和「设置（齿轮）」两个图标按钮，2026-10-20 去掉：
            // ① 收藏按钮做的是 `select(.favorites)` —— 只是跳侧栏已有的「收藏」页签，
            //    而那个星标在瀑布流卡片和详情页上是「收藏这张图」，同一个图标两种语义，
            //    放在工具栏最右极易被当成后者（用户实测：点了发现界面跳走了，图没收藏）。
            //    收藏这张图的入口在卡片 hover 与详情页页头条，都在壁纸的语境里，不混淆。
            // ② 设置按钮与侧栏最底「设置」页签完全重复，留着只是多一个入口要维护。
            // 两个入口都还在，只是收敛到侧栏一处。
            browseFilterButton(isPresented: $showFilter, viewModel: viewModel,
                               onOpenContentSettings: { openSettings(.content) })
                .padding(.leading, 20)
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
                AppliedWallpapersView(viewModel: viewModel,
                                      onDiscover: { select(.discover) },
                                      onOpen: { detailSource = .applied; detail = Wallpaper(previewFrom: $0) },
                                      onMessage: { showToast($0) })
            case .timeline:
                AppliedTimelineView(viewModel: viewModel,
                                   onDiscover: { select(.discover) },
                                   onOpen: { detailSource = .applied; detail = Wallpaper(previewFrom: $0) },
                                   onMessage: { showToast($0) })
            case .albums:
                AlbumsView(viewModel: viewModel,
                           onDiscover: { select(.discover) },
                           onOpen: { album, fav in
                               detailSource = .album(viewModel.albumItems(albumId: album.id))
                               detail = Wallpaper(previewFrom: fav)
                           },
                           onMessage: { showToast($0) })
            case .live:
                DynamicWallpaperView(library: library, onMessage: { showToast($0) }, onDeleteRequest: { pendingDelete = $0 })
            case .import:
                ImportView(library: library, onMessage: { showToast($0) },
                           onDeleteRequest: { pendingDelete = $0 },
                           onCropRequest: { cropImported($0) })
            // 设置从 sheet 改成主区页签（2026-10-20）：每一项改完即时生效（AppStorage /
            // 直接落盘），sheet 底部那个「完成」没有任何待提交状态可提交，只是多一次点击。
            // onContentPolicyChanged：关掉开关时收回已勾选的 NSFW 档并重查（ADR-012）。
            case .settings:
                SettingsView(store: keyStore,
                             clipboard: clipboard,
                             storage: storage,
                             animationIDs: animationIDs,
                             cropReferencedPaths: cropReferencedPaths,
                             tab: $settingsTab,
                             onSaved: { Task { await reloadForNav() } },
                             onContentPolicyChanged: { viewModel.disableNSFWIfNeeded() })
            default: browseSearchContent(viewModel: viewModel, gridItems: viewModel.wallpapers,
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

    /// 瀑布流只放搜索结果 —— 本地导入项**不混入**，它们只在「导入…」页签里管理。
    ///
    /// PRD:697 原本要求「导入的图片与网络壁纸在同一瀑布流展示」，该混排已于 2026-10-18
    /// 由用户否决（见 `docs/decisions/OPEN-DECISIONS.md`）：本地文件与 wallhaven 的
    /// 分类 / 关键词检索毫无关系，混进去只是把用户的图塞进一个它不属于的列表，
    /// 还要额外挂「本地」标识去解释这个突兀的存在。
    @ViewBuilder
    private func gridCard(_ wp: Wallpaper) -> some View {
        WallpaperCard(wallpaper: wp,
                      isFavorite: viewModel.favoriteIDs.contains(wp.id),
                      onOpen: { detailSource = .wallpapers; detail = wp },
                      onToggleFavorite: { viewModel.toggleFavorite(wp) },
                      onSetWallpaper: { setWallpaper(wp) })
    }

    /// 详情页（二级页面）。`.id` 让切换壁纸时整体重建：详情请求、大图都要跟着换。
    /// 导航上下文随来源切换：`favorites` / `applied` 下 `←` / `→` 在对应列表内翻，而非发现结果集。
    private func detailPage(_ wallpaper: Wallpaper) -> some View {
        let context: [Wallpaper]
        switch detailSource {
        case .wallpapers: context = viewModel.wallpapers
        case .favorites: context = viewModel.favorites.map { Wallpaper(previewFrom: $0) }
        case .applied: context = viewModel.applied.map { Wallpaper(previewFrom: $0) }
        case .album(let items): context = items.map { Wallpaper(previewFrom: $0) }
        }
        return DetailView(wallpaper: wallpaper,
                          context: context,
                          // 现算而非快照：`toggleFavorite` 改的是 `viewModel.favoriteIDs`，
                          // 这里读它就会被 `@Observable` 追踪，星标即时反填。
                          isFavorite: viewModel.favoriteIDs.contains(wallpaper.id),
                          viewModel: viewModel,
                          onClose: { detail = nil; detailSource = .wallpapers },
                          onNavigate: { detail = $0 },
                          onSearch: { query in searchFromDetail(query) },
                          onToggleFavorite: { viewModel.toggleFavorite(wallpaper) },
                          onMessage: { showToast($0) },
                          onCrop: { cropWallpaper(wallpaper) },
                          onAddToAlbum: { albumTarget = wallpaper })
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
                                 onOpen: { detailSource = .favorites; detail = Wallpaper(previewFrom: fav) },
                                 onToggleFavorite: { viewModel.removeFavorite(id: fav.id); viewModel.loadFavorites() },
                                 onSetWallpaper: { setWallpaperFromFavorite(fav) })
                }
                .padding(IHaven.Space.s6.rawValue)
            }
        }
    }

}
