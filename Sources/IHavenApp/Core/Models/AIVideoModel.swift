import Foundation

/// AI 图生视频的模型条目（#70 多厂商直连）。
///
/// ## 为什么删掉了 `imageInputKey` / `promptInputKey`（2026-10-19）
/// 这两个字段是「统一走聚合层 Replicate」时代的产物：那时所有模型都发同一套扁平请求体，
/// 差异只体现在「底图字段叫什么」，所以挂在模型身上够用。
///
/// 改成**直连各家厂商**后就不成立了 —— 各家请求体形状完全不同，一个「底图键名」根本抹不平：
/// - Google Veo：`instances[].image.inlineData{mimeType,data}`，裸 base64，**不带** `data:` 前缀
/// - MiniMax / 火山方舟：`content[]`，元素是 `{type:"image_url",image_url:{url:"data:…"}}`，
///   还要额外给个 `role:"first_frame"`
/// - 阿里百炼：`input.media[{type:"first_frame",url:…}]`
/// - 快手可灵：`contents[{type:"first_frame",url:…}]`
/// - 生数 Vidu：`images:["data:…"]`，是**裸数组**
///
/// 键名看着相似，但层级、包装结构、`data:` 前缀规则全都不同；继续写在模型上只会误导
/// （照着 `image` 去填 Google 就是 422）。差异原属各家协议，故**交给各家自己的策略实现**，
/// 模型层只保留「选哪一家的哪个模型」这一件事。
///
/// ## 为什么 `id` 不再是 `owner/name`
/// 直连后各家只认自己的模型名（`veo-3.1-fast-generate-preview`、`MiniMax-H3` …），
/// 带厂商前缀的聚合层命名反而会让请求发出 404 / model not found。
///
/// ## 为什么模型放在 Core
/// Infrastructure（发请求要模型名）与 Features（面板要列模型、显示说明）读的是同一份，
/// 且这份是纯数据 + 用户偏好，没有 Platform 依赖。
struct AIVideoModel: Identifiable, Sendable, Equatable {
    /// **厂商自己的**模型标识（如 `veo-3.1-fast-generate-preview`、`MiniMax-H3`）。
    /// 同一个 `id` 在不同厂商下含义不同，因此**只在所属厂商的 `models` 里有意义**。
    let id: String
    /// 展示名（lproj key，中文原文即 key，与全库一致）。
    let nameKey: String
    /// 一行说明：规格 / 单价 / 特点（lproj key）。
    let noteKey: String
}
