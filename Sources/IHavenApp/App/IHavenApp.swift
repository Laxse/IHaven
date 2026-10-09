import SwiftUI

@main
struct IHavenApp: App {
    @State private var keyStore = KeychainKeyProvider()
    @State private var browseViewModel: BrowseViewModel?

    var body: some Scene {
        WindowGroup {
            if let vm = browseViewModel {
                BrowseView(viewModel: vm, keyStore: keyStore)
            } else {
                ProgressView("初始化…").task { await bootstrap() }
            }
        }
    }

    /// 装配依赖：Keychain（KeyProvider/KeyStore）+ GRDB（WallpaperDatabase，失败降级 InMemory）
    /// + 静态壁纸引擎（WallpaperEngine）+ 下载器（ImageDownloading）+ WallhavenClient（Network）。
    /// 全部具体实现落在 Infrastructure / Platform / App，Feature 仅见 Core 协议（ARCH §4 单向依赖）。
    private func bootstrap() async {
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
