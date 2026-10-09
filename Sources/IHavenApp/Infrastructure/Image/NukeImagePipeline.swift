import Foundation
import Nuke

/// Nuke 13 全局管线与预取封装（ADR-001）。
/// Nuke 13 的全局 `ImagePipelineActor` 提供 Swift 6 并发保证，避免自研管线在 LRU / 请求合并 /
/// 后台解压上的静默错误（ARCH §3.1）。`LazyImage`（NukeUI）在 Feature 层直接用于缩略图渲染。
enum NukeImagePipeline {
    /// 全局管线（默认配置即可；缩略图尺寸由 `ImageRequest.ThumbnailOptions` 按请求控制，见 ADR-001 注）。
    static let pipeline = ImagePipeline.shared

    /// 共享预取器。
    /// 注意：`ImagePrefetcher` 在 `deinit` 时会取消所有在途任务（见 Nuke 源码 `nonisolated deinit`），
    /// 因此绝不能用函数内的局部变量承载——一旦离开作用域即被释放并取消预取。这里用静态单例长期持有。
    private static let prefetcher = ImagePrefetcher()

    /// 预取一批缩略图（瀑布流滚动前预载，避免空白闪烁）。
    /// Nuke 13 的 `ImagePrefetcher` 没有 `init(requests:)` / `init(urls:)` 构造器，
    /// 必须先创建实例再调用 `startPrefetching(with:)`。重复的 URL 会被内部自动合并。
    static func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }
}
