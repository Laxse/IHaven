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

    /// 装配依赖：见 `AppAssembly.assemble`（从本文件迁出，为 AI 图生视频 #70 的接线腾出行数空间）。
    /// 入口只做「调用装配 + 赋值 + 挂全局热键」，不再内联一堆具体实现的构造。
    private func bootstrap() async {
        let output = await AppAssembly.assemble(keyStore: keyStore,
                                                dynamicEngine: dynamicEngine,
                                                clipboard: clipboard)
        browseViewModel = output.browseViewModel
        library = output.library
        GlobalHotkeys.install(viewModel: browseViewModel, library: library)   // #68 全局热键 ⌥⌘S 换一张
    }
}
