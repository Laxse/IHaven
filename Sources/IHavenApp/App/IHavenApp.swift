import SwiftUI

@main
struct IHavenApp: App {
    @State private var keyStore = FileKeyProvider()
    @State private var browseViewModel: BrowseViewModel?
    @AppStorage("ihaven.appearance") private var appearance: String = "system"

    var body: some Scene {
        WindowGroup("IHaven") {
            Group {
                if let vm = browseViewModel {
                    BrowseView(viewModel: vm, keyStore: keyStore)
                } else {
                    ProgressView("初始化…").task { await bootstrap() }
                }
            }
            .preferredColorScheme(appearanceScheme)
        }
        // 线稿画布 1280×800：默认窗口若只有 minWidth 880，瀑布流会退化到 2 列，观感与线稿不符。
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)   // 隐藏系统标题栏；交通灯浮于左上，由工具栏 72px 让位（无自绘标题栏）
        // 把内容最小尺寸（根 .frame(minWidth:880,minHeight:600)）钉成窗口可拖拽最小值：
        // 否则用户可把窗口缩到下限以下，根布局超出窗口被裁、侧栏被挤出左缘（瀑布流宽度回归的诱因之一）。
        .windowResizability(.contentMinSize)
    }

    /// "system" → nil（跟随系统）；否则覆盖整窗外观（设置 · 外观页签）。
    private var appearanceScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    /// 装配依赖：文件 KeyStore（KeyProvider/KeyStore，ADR-010）+ GRDB（WallpaperDatabase，失败降级 InMemory）
    /// + 静态壁纸引擎（WallpaperEngine）+ 下载器（ImageDownloading）+ WallhavenClient（Network）。
    /// 全部具体实现落在 Infrastructure / Platform / App，Feature 仅见 Core 协议（ARCH §4 单向依赖）。
    private func bootstrap() async {
        MockWallhaven.configureIfNeeded()   // 开发期 IHAVEN_MOCK=1 时接管请求，无需 VPN
        let client = WallhavenClient(keyProvider: keyStore)
        let database: WallpaperDatabase = (try? GRDBWallpaperDatabase()) ?? InMemoryWallpaperDatabase()
        let engine = SystemWallpaperEngine()
        let downloader = ImageFileDownloader()
        browseViewModel = BrowseViewModel(
            client: client,
            keyProvider: keyStore,
            database: database,
            wallpaperEngine: engine,
            downloader: downloader
        )
    }
}
