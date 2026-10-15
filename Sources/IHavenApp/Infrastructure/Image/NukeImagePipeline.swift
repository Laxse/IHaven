import Foundation
import Nuke

/// Nuke 13 全局管线与预取封装（ADR-001）。
/// Nuke 13 的全局 `ImagePipelineActor` 提供 Swift 6 并发保证，避免自研管线在 LRU / 请求合并 /
/// 后台解压上的静默错误（ARCH §3.1）。`LazyImage`（NukeUI）在 Feature 层直接用于缩略图渲染。
///
/// ⚠️ **为什么不能继续用 `ImagePipeline.shared` 的默认配置**（实测 2026-10-16，`5ypv78`）：
/// 默认配置是 `.withURLCache`，等于「只有 HTTP 缓存 + 内存缓存」，两头都不装高清图：
///
/// 1. **内存侧根本不收。**
///    `ImageCache.shared` 默认 `costLimit` = 物理内存 15%（封顶 768MB），而 `entryCostLimit`
///    默认 **0.1** —— Nuke 的语义是「单条成本超过缓存上限 10% 就**直接不存**」。
///    一张 3805×5700 的高清图解码后约 **87MB** > 768MB × 0.1 = **76.8MB**，于是永远进不了内存缓存。
///    实测：同一个进程里第二次加载同一张高清图 **2925 ms**（首次 3819 ms），几乎等于重下一次。
/// 2. **磁盘侧也抓不到。**
///    默认只有 `URLCache`（**内存容量 0**、磁盘 150MB）。本机实测
///    `~/Library/Caches/com.ihaven.app` 共 402 条缓存，**全部是 `th.wallhaven.cc` 缩略图**，
///    `w.wallhaven.cc/full/`（高清图）**一条都没有**。
///
/// 结论：看过的每一张高清图，下次进来都要重新下载一遍 —— 这就是「感觉每次都在重新加载」的来源。
///
/// 修法：换成 Nuke 的激进磁盘缓存 `DataCache`（存原始字节，与 HTTP 头无关、不会再去回源校验），
/// 并把内存缓存的单条上限放宽到能装下一张高清图。实测同一进程内第二次加载 **0 ms**，
/// 冷启动（内存空）也能直接命中 `DataCache` 里的 4.6MB 原始字节，不再走网络。
enum NukeImagePipeline {
    /// 把配好的管线写回 `ImagePipeline.shared`。
    ///
    /// ⚠️ **必须走 `shared` 而不是自己留一份**：NukeUI 的 `LazyImage` 内部是
    /// `private var pipeline: ImagePipeline = .shared`（在视图初始化那一刻取值），
    /// 只有替换 `shared` 本体，全项目的 `LazyImage` 才会落到这套缓存上。
    /// 因此也必须在 `IHavenApp.init()` 里、早于任何视图构建地调用。
    static func install() {
        ImagePipeline.shared = ImagePipeline(configuration: makeConfiguration())
    }

    /// 全局管线。写成计算属性而不是 `static let`：后者会在首次访问时**固化**当时的 `shared`，
    /// 万一 `install()` 之后又有别的静态先访问过，就会拿到被替换前的旧管线。
    static var pipeline: ImagePipeline { ImagePipeline.shared }

    /// 共享预取器。
    /// 注意：`ImagePrefetcher` 在 `deinit` 时会取消所有在途任务（见 Nuke 源码 `nonisolated deinit`），
    /// 因此绝不能用函数内的局部变量承载——一旦离开作用域即被释放并取消预取。这里用静态单例长期持有。
    private static let prefetcher = ImagePrefetcher(pipeline: pipeline)

    /// 预取一批缩略图（瀑布流滚动前预载，避免空白闪烁）。
    /// Nuke 13 的 `ImagePrefetcher` 没有 `init(requests:)` / `init(urls:)` 构造器，
    /// 必须先创建实例再调用 `startPrefetching(with:)`。重复的 URL 会被内部自动合并。
    static func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }

    // MARK: - 配置

    /// 磁盘缓存上限：512MB。一张高清图 2–10MB，够放上百张；`DataCache` 按 LRU 自行淘汰。
    private static let diskSizeLimit = 512 * 1024 * 1024
    /// 内存缓存上限：256MB（默认 768MB 对常驻的桌面应用偏大）。
    private static let memoryCostLimit = 256 * 1024 * 1024
    /// 单条上限占缓存的比例：默认 0.1 会把高清图挡在门外，放宽到 0.5（即单条最大 128MB）。
    private static let memoryEntryCostLimit = 0.5

    private static func makeConfiguration() -> ImagePipeline.Configuration {
        // `withDataCache` 会顺手把 `urlCache` 置为 nil（HTTP 缓存关掉）：
        // 两套磁盘缓存并存只会让命中行为不可预测，留一套可控的即可。
        var config = ImagePipeline.Configuration.withDataCache(
            name: "com.ihaven.Images",
            sizeLimit: diskSizeLimit
        )
        // 存原始字节（默认策略就是它，写出来是为了让「高清图一定要落盘」这件事显式可见）。
        config.dataCachePolicy = .storeOriginalData

        let memoryCache = ImageCache(costLimit: memoryCostLimit, countLimit: 200)
        memoryCache.entryCostLimit = memoryEntryCostLimit
        config.imageCache = memoryCache
        return config
    }
}
