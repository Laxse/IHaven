import Foundation

/// AI 图生视频（#70，Plan B）：由一张静态图 + 运动描述生成一段短视频，作为动态壁纸的**帧来源**。
///
/// 与 ADR-016 的关系：播放引擎不变（仍播 JPEG 帧序列），这里只是把「帧从哪来」从
/// 「本地渲静图」扩展成「AI 生成的视频抽帧」。Feature 只见本协议，具体提供商在 Infrastructure。
///
/// ⚠️ **异步且可能数十秒**：图生视频是提交任务 → 等待/轮询 → 下载，不是一次请求返回。
/// 调用方必须给「生成中」态，绝不能在主线程同步等。
public protocol AIVideoGenerating: Sendable {
    /// 生成短视频并**下载到本地缓存**，返回 MP4 文件 URL。调用方用完负责清理该临时文件。
    /// - Parameters:
    ///   - sourceImage: 本地静态图（被动画化的底图）。
    ///   - prompt: 运动 / 画面描述（如「云缓缓飘动，镜头缓慢推近」）。
    func generateVideo(sourceImage: URL, prompt: String) async throws -> URL
}

/// 视频 → 帧抽取（#70）：把一段 MP4 按目标帧率抽成 JPEG 帧序列，喂给现有帧动画引擎。
/// Feature 只见本协议；AVFoundation 实现在 Platform。
public protocol VideoFrameExtracting: Sendable {
    /// 把 `video` 按 `fps` 抽帧写入 `outputDir`（命名 `frame-%04d.jpg`，与
    /// `DynamicWallpaperEngine.frameURLs(in:)` 的字典序播放约定一致），返回按序排列的帧 URL。
    /// 长边超过 `maxLongEdge` 的帧等比缩小（控磁盘 / 内存）。
    /// - Parameter pingPong: true 时在正放序列后接一段「倒放」，让首末平滑折返、无缝循环 ——
    ///   AI 视频片段本身不为无缝设计，硬循环会跳，正反循环是最省的循环化手段。
    func extractFrames(from video: URL, fps: Double, maxLongEdge: Int, pingPong: Bool,
                       into outputDir: URL) async throws -> [URL]
}

/// AI 图生视频的错误分类。与 `APIError` 同思路：把provider / 网络 / 内容策略分层，
/// 让 UI 能给出可操作文案（缺 Key 去设置、被拦截改描述、额度不足换 Key），而不是一句「失败」。
public enum AIVideoError: LocalizedError, Sendable, Equatable {
    /// 用户没配 AI Key。
    case missingKey
    /// Key 无效（HTTP 401 / 403）。
    case invalidKey
    /// 额度不足 / 计费问题 / 触发限流（HTTP 402 / 429）。
    case quotaOrRate
    /// 描述或底图被 AI 服务商的安全策略拦截。
    case contentFiltered
    /// 服务端拒绝了请求本身（HTTP 422：参数 / 模型 / 输入 schema 不被接受）。
    case requestRejected(String)
    /// 网络层错误。
    case transport(String)
    /// 响应解析失败。
    case decode(String)
    /// 任务成功但没返回视频（异常终态）。
    case noOutput

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return String(localized: "尚未配置 AI Key，请在设置 ▸ AI 中填写后再生成。")
        case .invalidKey:
            return String(localized: "AI Key 无效（401/403），请在设置 ▸ AI 中检查。")
        case .quotaOrRate:
            return String(localized: "AI 额度不足或请求过于频繁，请稍后再试或更换 Key。")
        case .contentFiltered:
            return String(localized: "该描述或图片被 AI 服务商的安全策略拦截，请调整后重试。")
        case .requestRejected(let msg):
            return String(format: String(localized: "AI 服务拒绝了这次请求：%@"), msg)
        case .transport(let msg):
            return String(format: String(localized: "网络错误：%@"), msg)
        case .decode(let msg):
            return String(format: String(localized: "解析 AI 响应失败：%@"), msg)
        case .noOutput:
            return String(localized: "AI 未返回视频，请重试。")
        }
    }
}

/// 按厂商取 Key 提供方（#70 多厂商直连）。
///
/// 六家厂商各自发 Key、各自计费，Feature 层（设置面板 / 生成面板）只关心「当前选中这家有没有配」，
/// 不该知道 Key 存在哪个文件里 —— 故只暴露一个「按 vendorID 取提供方」的口子，
/// 具体实现见 App 层的 `AIKeyStore`。
///
/// **必须同一 vendorID 每次返回同一实例**：`FileKeyProvider` 把 Key 缓存在内存 `currentKey` 里，
/// 若设置面板（写）与生成客户端（读）各持一个实例，会出现「设置里刚存了 Key，客户端还读到空」。
public protocol AIVendorKeyProviding: Sendable {
    func keyProvider(for vendorID: String) -> KeyProvider
}
