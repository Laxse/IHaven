import Foundation

/// AI 图生视频的模型条目（#70 多模型 · 聚合层 Replicate）。
///
/// ## 为什么每个模型都要自带 `imageInputKey`
/// 各家模型的**底图入参键名没有统一约定**，写错就是 422 Unprocessable Entity：
/// - `minimax/video-01` → `first_frame_image`
/// - `wan-video/wan-2.7-i2v` → `first_frame`
/// - `kwaivgi/kling-v2.5-turbo-pro` / `vidu/q3-pro` → `start_image`
///   （可灵的 `image` 已被官方标 deprecated："Use start_image instead"，必须发 `start_image`）
/// - `bytedance/seedance-2.0-fast` / `google/veo-3.1-fast` → `image`
///
/// 以上逐条按 Replicate 模型页内嵌的 openapi schema description 核对（2026-10-19），
/// **不是凭印象填的** —— 凭印象填 `image` 已经让我们白跑过一次 422。
///
/// ## 为什么模型放在 Core
/// Infrastructure（发请求要键名）与 Features（面板要列模型、显示说明）读的是同一份，
/// 且这份是纯数据 + 用户偏好，没有 Platform 依赖。
struct AIVideoModel: Identifiable, Sendable, Equatable {
    /// Replicate 的 `owner/name`，同时是持久化到 UserDefaults 的值。
    let id: String
    /// 展示名（lproj key，中文原文即 key，与全库一致）。
    let nameKey: String
    /// 一行说明：规格 / 单价 / 特点（lproj key）。
    let noteKey: String
    /// 底图入参键名。
    let imageInputKey: String
    /// 描述入参键名。当前各家都是 `prompt`，仍逐条列出，将来有异只需改这一行。
    let promptInputKey: String

    init(id: String, nameKey: String, noteKey: String,
         imageInputKey: String, promptInputKey: String = "prompt") {
        self.id = id
        self.nameKey = nameKey
        self.noteKey = noteKey
        self.imageInputKey = imageInputKey
        self.promptInputKey = promptInputKey
    }
}

/// 可选模型目录。**换聚合层 / 换模型只动这个文件** —— 客户端与 UI 都从这里取。
enum AIVideoModelCatalog {
    /// 唯一真机打通过端点的那个，故作默认。
    private static let hailuo = AIVideoModel(
        id: "minimax/video-01",
        nameKey: "Hailuo video-01（MiniMax）",
        noteKey: "6 秒 · 720p · 约 $0.5/次 · IHaven 默认",
        imageInputKey: "first_frame_image")

    static let all: [AIVideoModel] = [
        hailuo,
        AIVideoModel(id: "wan-video/wan-2.7-i2v",
                     nameKey: "万相 2.7（阿里）",
                     noteKey: "1080p · 开源模型里最省 · 支持首尾帧",
                     imageInputKey: "first_frame"),
        AIVideoModel(id: "kwaivgi/kling-v2.5-turbo-pro",
                     nameKey: "可灵 2.5 Turbo Pro（快手）",
                     noteKey: "1080p · 约 $0.07/秒 · 画面最稳",
                     imageInputKey: "start_image"),
        AIVideoModel(id: "bytedance/seedance-2.0-fast",
                     nameKey: "Seedance 2.0 Fast（字节）",
                     noteKey: "带原生音频 · 生成快 · 效果强",
                     imageInputKey: "image"),
        AIVideoModel(id: "google/veo-3.1-fast",
                     nameKey: "Veo 3.1 Fast（Google）",
                     noteKey: "带原生音频 · 质量标杆 · 约 $0.08/秒 起",
                     imageInputKey: "image"),
        AIVideoModel(id: "vidu/q3-pro",
                     nameKey: "Vidu Q3 Pro（生数）",
                     noteKey: "最长 16 秒 · 1080p · 带音频",
                     imageInputKey: "start_image"),
    ]

    static let fallback = hailuo

    /// 按 id 取；未知 id（模型下架 / 手改过偏好）回落到默认，不让 UI 出现空选项。
    static func model(id: String?) -> AIVideoModel {
        guard let id else { return fallback }
        return all.first { $0.id == id } ?? fallback
    }

    /// 用户在生成面板里选的模型。现读现用（不缓存成常量）——否则改了模型要重启才生效。
    static func selected() -> AIVideoModel {
        model(id: UserDefaults.standard.string(forKey: UserPreferenceKey.aiVideoModel))
    }
}
