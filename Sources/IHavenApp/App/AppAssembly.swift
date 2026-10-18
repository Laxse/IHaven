import Foundation

/// 依赖装配（从 `IHavenApp.bootstrap()` 整体迁出）。
///
/// **为什么迁出**：`IHavenApp.swift` 有 120 行硬上限（convention-gate），而 AI 图生视频（#70）
/// 又要往里加几条接线，入口放不下。装配逻辑本身属于 App 层（选具体实现、注入协议），
/// 搬到这个专用文件后 `IHavenApp` 只剩「调用装配 + 赋值」，更贴合「入口只装配」。
///
/// 逻辑与迁出前逐行一致，仅在 `LocalLibraryViewModel` 处新增 AI 三依赖（协议 + 共享 Key 单例）。
@MainActor
enum AppAssembly {
    struct Output {
        let browseViewModel: BrowseViewModel
        let library: LocalLibraryViewModel
    }

    static func assemble(keyStore: FileKeyProvider,
                         dynamicEngine: DynamicWallpaperEngine,
                         clipboard: ClipboardWriting) async -> Output {
        MockWallhaven.configureIfNeeded()   // 开发期 IHAVEN_MOCK=1 时接管请求，无需 VPN
        // 限流退避的广播点：客户端写、视图模型读。同一份实例注入两端。
        let throttle = ThrottleSignal()
        let client = WallhavenClient(keyProvider: keyStore, throttle: throttle)
        let database: WallpaperDatabase = (try? GRDBWallpaperDatabase()) ?? InMemoryWallpaperDatabase()
        let engine = SystemWallpaperEngine()
        let downloader = ImageFileDownloader()
        // 轮换日程（PRD F13）：规则存 database，铺壁纸走 engine。启动即开；无启用规则时
        // reschedule() 直接返回，不占资源。
        WallpaperScheduler.shared.configure(database: database, engine: engine)
        WallpaperScheduler.shared.start()
        let savePanel = SystemSavePanel()
        // F8：导入管线。`AVMediaProbe` 一个类型同时实现探测与缩略图产出。
        let probe = AVMediaProbe()
        let libraryViewModel = LocalLibraryViewModel(
            importer: LocalImportService(probe: probe, thumbnails: probe, store: database),
            panel: SystemFileImportPanel(),
            database: database,
            engine: engine,
            dynamicEngine: dynamicEngine,
            renderer: AnimationRenderer(),
            // AI 图生视频（#70，Plan B）：Feature 只见 Core 协议，具体实现在此装配。
            // Key 用 `AIKeyStore.shared` 单例 —— 与设置面板（写）同一实例，存完即刻生效。
            // 未配 Key 时生成入口自会提示去设置，不影响其它功能。
            aiVideo: ReplicateVideoClient(keyProvider: AIKeyStore.shared),
            videoFrames: AVFoundationFrameExtractor(),
            aiKey: AIKeyStore.shared
        )
        let browseViewModel = BrowseViewModel(
            client: client,
            keyProvider: keyStore,
            database: database,
            wallpaperEngine: engine,
            downloader: downloader,
            savePanel: savePanel,
            clipboard: clipboard,
            throttle: throttle
        )
        return Output(browseViewModel: browseViewModel, library: libraryViewModel)
    }
}
