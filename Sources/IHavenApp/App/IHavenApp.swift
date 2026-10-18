import SwiftUI

@main
struct IHavenApp: App {
    @State private var keyStore = FileKeyProvider()
    @State private var browseViewModel: BrowseViewModel?
    /// 剪贴板（关于页复制微信号用）。与 `savePanel` 同为 Platform 实现：**只在装配点创建一次**
    /// 再往下传，因为 Feature 层不允许出现 `SystemClipboard` 这个具体类型名（ARCH §4）。
    private let clipboard: ClipboardWriting = SystemClipboard()
    /// 设置 · 存储页签的数据源（图片缓存 / 帧序列占用与清理，ADR-017）。
    private let storage: StorageUsage = DiskStorageUsage()
    @AppStorage(UserPreferenceKey.appearance) private var appearance: String = "system"
    /// 动态壁纸播放引擎（F9，ADR-015 §五）。与 `clipboard` 同理：Platform 实现只在装配点创建一次。
    private let dynamicEngine = DynamicWallpaperEngine()
    /// 本地库 ViewModel（导入图片 + 本地视频）。BrowseView 与两个页签共用同一个实例。
    @State private var library: LocalLibraryViewModel?

    init() {
        // 必须早于任何 `Text` 渲染：`.lproj` 得先落到 `Bundle.main`，随后 SwiftUI 查表才查得到。
        MainBundleLocalizations.materializeIfNeeded()
        // 必须早于任何视图构建：`LazyImage` 在初始化那一刻就把 `.shared` 抄进自己的实例里，
        // 晚一步装，瀑布流和详情页就都用不上 `DataCache`，高清图仍是每次重新下载。
        NukeImagePipeline.install()
        // 性能护栏：只持有引擎引用，真正 start() 由设置 · 性能页签触发（用户没打开就不采样）。
        PerformanceGuard.shared.attach(dynamicEngine)
    }

    var body: some Scene {
        // id 与 `MenuBarPanelView.mainWindowID` 同源；且必须是 `Window` 而不是 `WindowGroup`
        // —— 后者的 id 标识「窗口组」，每次 open 都新开一个实例（详见该常量的注释）。
        Window("IHaven", id: MenuBarPanelView.mainWindowID) {
            Group {
                if let vm = browseViewModel, let library {
                    BrowseView(viewModel: vm, keyStore: keyStore, clipboard: clipboard,
                               storage: storage, library: library)
                } else {
                    ProgressView("初始化…").task { await bootstrap() }
                }
            }
            .preferredColorScheme(appearanceScheme)
            .appLocale()
        }
        // 线稿画布 1280×800：默认窗口若只有 minWidth 880，瀑布流会退化到 2 列，观感与线稿不符。
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)   // 隐藏系统标题栏；交通灯驻留在系统保留的标题栏安全区内（无自绘标题栏）
        // 把内容最小尺寸（根 .frame(minWidth:880,minHeight:600)）钉成窗口可拖拽最小值：
        // 否则用户可把窗口缩到下限以下，根布局超出窗口被裁、侧栏被挤出左缘（瀑布流宽度回归的诱因之一）。
        .windowResizability(.contentMinSize)

        // F3 菜单栏面板（PRD）：与主窗口共用 browseViewModel / library 两个实例（ADR-004 关键约束
        // —— 单一 @Observable，不用通知广播）。两者在 bootstrap() 前是 nil，nil 分支在面板内部。
        // ⚠️ 必须 .window 样式：PRD F3 要搜索框，.menu 样式下 TextField 落不了焦。
        MenuBarExtra("IHaven", systemImage: "photo") {
            MenuBarPanelView(viewModel: browseViewModel, library: library)
        }
        .menuBarExtraStyle(.window)

        // ⌘⇧K 一键全停（DESIGN §6.3 可访问性硬要求）：动态壁纸的桌面层窗口是 ignoresMouseEvents 的，
        // 点不到它，必须有一条不看鼠标的停止路径。
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("停止动态壁纸") { dynamicEngine.stop() }
                    .keyboardShortcut("K", modifiers: [.command, .shift])
                    .disabled(!dynamicEngine.isPlaying)
            }
        }
    }

    /// "system" → nil（跟随系统）；否则覆盖整窗外观（设置 · 外观页签）。
    private var appearanceScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    /// 装配依赖：文件 KeyStore（KeyProvider/KeyStore，ADR-010）+ GRDB（WallpaperDatabase，失败降级 InMemory）
    /// + 静态壁纸引擎（WallpaperEngine）+ 下载器（ImageDownloading）+ WallhavenClient（Network）
    /// + 存盘面板（FileSavePresenting）+ 剪贴板（ClipboardWriting）+ 本地导入（F8：探测 /
    /// 缩略图 / 导入服务 / 文件面板）+ 动态壁纸播放（F9）。
    /// 全部具体实现落在 Infrastructure / Platform / App，Feature 仅见 Core 协议（ARCH §4 单向依赖）。
    /// ⚠️ 后两项必须在这里显式传入：若改由 `BrowseViewModel.init` 给默认值，Feature 层就会出现
    /// `SystemSavePanel` / `SystemClipboard` 这两个 Platform 具体类型名，而 convention-gate 只查
    /// Core 反向依赖与 F9，查不到这种破例 —— 它会静默腐烂。装配点唯一是硬要求。
    private func bootstrap() async {
        MockWallhaven.configureIfNeeded()   // 开发期 IHAVEN_MOCK=1 时接管请求，无需 VPN
        // 限流退避的广播点：客户端写、视图模型读。同一份实例注入两端，
        // 视图才能显示「正在等待 API 限流恢复」（PRD §6 F7）。
        let throttle = ThrottleSignal()
        let client = WallhavenClient(keyProvider: keyStore, throttle: throttle)
        let database: WallpaperDatabase = (try? GRDBWallpaperDatabase()) ?? InMemoryWallpaperDatabase()
        let engine = SystemWallpaperEngine()
        let downloader = ImageFileDownloader()
        // 轮换日程（PRD F13）：规则存 database，铺壁纸走 engine。关窗后进程仍活着，
        // 所以启动即开；没有启用规则时 reschedule() 会直接返回，不占资源。
        WallpaperScheduler.shared.configure(database: database, engine: engine)
        WallpaperScheduler.shared.start()
        let savePanel = SystemSavePanel()
        // F8：导入管线。`AVMediaProbe` 一个类型同时实现探测与缩略图产出 —— 两者都只是
        ///「读媒体元信息 / 产小图」，拆成两个类型只会多一层无意义转发。
        let probe = AVMediaProbe()
        let libraryViewModel = LocalLibraryViewModel(
            importer: LocalImportService(probe: probe, thumbnails: probe, store: database),
            panel: SystemFileImportPanel(),
            database: database,
            engine: engine,
            dynamicEngine: dynamicEngine,
            renderer: AnimationRenderer()
        )
        browseViewModel = BrowseViewModel(
            client: client,
            keyProvider: keyStore,
            database: database,
            wallpaperEngine: engine,
            downloader: downloader,
            savePanel: savePanel,
            clipboard: clipboard,
            throttle: throttle
        )
        library = libraryViewModel
    }
}
