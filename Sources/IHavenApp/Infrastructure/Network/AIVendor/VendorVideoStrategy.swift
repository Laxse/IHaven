import Foundation

/// 一家厂商的图生视频策略（#70 多厂商直连）。
///
/// ## 为什么是策略模式而不是「一个大客户端 + switch」
/// 六家的差异不是「几个参数不同」，而是**协议形状本身就不同**：鉴权头（Bearer / x-goog-api-key /
/// Token / 带异步头）、提交端点（模型在 body 里还是在路径里）、请求体（裸 base64 / data URI /
/// content 数组 / input.media）、轮询路径、结果 JSON 的层级、下载是否还要带鉴权 ——
/// 没有任何一项能用「一张参数映射表」抹平。硬塞进一个类型只会变成六个分支的 switch 迷宫，
/// 加第七家要改所有分支。
///
/// 于是把差异收口到「一家一个策略」，上层 `VendorVideoClient` 只剩一条与厂商无关的骨架：
/// 转 JPEG → 提交 → 轮询 → 下载。加厂商 = 加一个文件 + 注册表加一行，不碰任何已有策略。
///
/// ## 为什么 `submit` 返回 `String` 而不是「任务对象」
/// 各家的任务标识形态不一：Google 是 `operations/xxx`（可直接拼进轮询 URL），
/// MiniMax / Vidu 是裸 `task_id`，火山是 `id`。统一成不透明字符串是最小公约数 ——
/// 对上层没有任何意义，只有该策略自己的 `poll` 知道怎么用。
protocol AIVendorVideoStrategy: Sendable {
    /// 与 `AIVideoVendor.id` 一致（"google" / "minimax" / "vidu" / "alibaba" / "volcano" / "kling"）。
    var vendorID: String { get }

    /// 提交任务，返回**该厂商自己的任务标识**（task_id / operation name / 完整 URL 都行，对调用方不透明）。
    /// - Parameters:
    ///   - imageJPEG: 已压到 ≤1024 长边的 JPEG 数据（由上层统一转好，各家不必各写一遍）。
    ///   - prompt: 运动 / 画面描述。
    ///   - model: 选中厂商下的模型，**必属于本厂商**，策略直接使用 `model.id`。
    ///   - key: 已 trim 过、非空的用户 Key。
    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String

    /// 查一次任务。nil = 还在跑；非 nil = 完成，返回可下载 URL。终态失败直接 throw。
    ///
    /// **每次只查一次、不做等待**：节奏由上层统一控制（首等 5s、之后 3s、总上限 6 分钟），
    /// 否则六家的退避策略会各长各的，超时行为无法整体推断。
    func poll(task: String, key: String) async throws -> URL?

    /// 下载视频时要额外带的头（多数家为空）。
    ///
    /// [!] Google 的视频 URI 下载**必须带** `x-goog-api-key`，否则 403；其余各家返回的都是
    /// 短期公开 URL，带鉴权反而可能被 CDN 拒。故默认空实现、只让需要的家覆写。
    func downloadHeaders(key: String) -> [String: String]
}

extension AIVendorVideoStrategy {
    func downloadHeaders(key: String) -> [String: String] { [:] }
}
