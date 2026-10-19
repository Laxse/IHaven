import Foundation

/// 一个 AI 图生视频的**模型厂商**（#70 多厂商直连）。
///
/// ## 为什么要有「厂商」这一层
/// 原先是「统一走 Replicate 聚合层，一把 Key 打天下」，用户否决了这个方向：要用各自的模型厂商。
/// 于是流程变成 **选厂商 → 去该厂商官网拿 Key → 填进 IHaven → 再选该厂商下的模型**。
///
/// 关键点在于：**每家的 Key 是各自官网发的、独立计费**，而且 HTTP 协议各不相同 ——
/// 请求体形状、鉴权头、轮询路径、结果字段全都不一样（详见 `AIVideoModel` 里的落库说明）。
/// 所以「厂商」不是一个可折叠的字符串选项，而是**策略的选择器**：选定厂商就选定了一整套协议
/// 实现（由 Infrastructure 层的各家策略承担）与一个独立的 Key 文件。
///
/// ## 为什么 `id` 必须是纯 ASCII 小写
/// 它有三处用途：UserDefaults 的持久化值、下拉列表的稳定标识、以及 Key 文件名后缀
/// （`~/.ihaven/ai-key-<id>`，见 `AIKeyStore`）。含空格或大写会让文件名在读写出错时难以排查。
struct AIVideoVendor: Identifiable, Sendable, Equatable {
    /// 持久化到 UserDefaults 的稳定标识，纯 ASCII 小写："google" / "minimax" / "vidu" /
    /// "alibaba" / "volcano" / "kling"。同时也是 Key 文件名后缀（`~/.ihaven/ai-key-<id>`）。
    let id: String
    /// 展示名（lproj key，中文原文即 key，与全库一致）。
    let nameKey: String
    /// 去哪拿 Key（设置面板要做成可点链接）。
    let keyPageURL: URL
    /// Key 长什么样 / 在控制台哪一步生成（lproj key）。
    let keyHintKey: String
    /// 一行说明：计费方式与网络要求（lproj key）。
    let noteKey: String
    /// 这家厂商可选的图生视频模型。**至少 1 个**，为空会让下拉没选项。
    let models: [AIVideoModel]
}

/// 可选厂商目录。**换厂商 / 换模型只动这个文件** —— 客户端与 UI 都从这里取。
/// （原先的 `AIVideoModelCatalog` 已被本名录取代：模型不再全局唯一，而是挂在厂商下面。）
enum AIVideoVendorCatalog {
    // MARK: - 厂商清单
    //
    // 下面的 `URL(string:)!`：全是写死的 https 字面量，构造不可能失败；用一个兜底 URL 反而会把
    // 「官网链接写错了」静默成「点了跳到别处」，不如让它启动即崩。

    /// Google 放第一：境外标杆，且 AI Studio 一键出 Key，新用户最容易跑通全流程。
    private static let google = AIVideoVendor(
        id: "google",
        nameKey: "Google（Veo）",
        keyPageURL: URL(string: "https://aistudio.google.com/apikey")!,
        keyHintKey: "在 Google AI Studio 里 Create API key，AIza… 开头",
        noteKey: "按秒计费（Fast 档约 $0.10/秒）· 需能访问 Google 服务",
        models: [
            AIVideoModel(id: "veo-3.1-generate-preview",
                         nameKey: "Veo 3.1",
                         noteKey: "质量标杆 · 约 $0.40/秒"),
            AIVideoModel(id: "veo-3.1-fast-generate-preview",
                         nameKey: "Veo 3.1 Fast",
                         noteKey: "更快更省 · 约 $0.10/秒"),
        ])

    private static let minimax = AIVideoVendor(
        id: "minimax",
        nameKey: "MiniMax（海螺）",
        keyPageURL: URL(string: "https://platform.minimax.cn/user-center/basic-information/interface-key")!,
        keyHintKey: "控制台 ▸ 接口密钥，eyJ… 开头的 JWT 或长串",
        noteKey: "国内直连 · 按次计费 · 生成约 1~3 分钟",
        models: [
            AIVideoModel(id: "MiniMax-H3",
                         nameKey: "Hailuo H3",
                         noteKey: "6 秒 · 1080p"),
        ])

    private static let vidu = AIVideoVendor(
        id: "vidu",
        nameKey: "生数 Vidu",
        keyPageURL: URL(string: "https://platform.vidu.cn/")!,
        keyHintKey: "控制台 ▸ API Key，复制后直接粘贴",
        noteKey: "国内直连 · 按次计费 · 最长 16 秒",
        models: [
            AIVideoModel(id: "viduq3-pro",
                         nameKey: "Vidu Q3 Pro",
                         noteKey: "1080p · 带音频"),
        ])

    private static let alibaba = AIVideoVendor(
        id: "alibaba",
        nameKey: "阿里百炼（万相）",
        keyPageURL: URL(string: "https://bailian.console.aliyun.com/?tab=model#/api-key")!,
        keyHintKey: "控制台 ▸ API-KEY，sk- 开头",
        noteKey: "国内直连 · 按次计费 · 需开通百炼",
        models: [
            AIVideoModel(id: "wan2.5-i2v-preview",
                         nameKey: "万相 2.5 图生视频",
                         noteKey: "1080p · 支持首帧"),
        ])

    private static let volcano = AIVideoVendor(
        id: "volcano",
        nameKey: "火山方舟（Seedance）",
        keyPageURL: URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apikey")!,
        keyHintKey: "控制台 ▸ API Key 管理，一串 UUID",
        noteKey: "国内直连 · 按 token 计费 · 充值后还需在「开通管理」里启用模型",
        models: [
            // [!] 方舟的 model id **必须带版本日期后缀**（2026-10-19 真机实测）：
            // 发 `doubao-seedance-2-0` 得到 404「The model or endpoint doubao-seedance-2-0
            // does not exist」；补成 `-260128` 才被识别，随后又报 ModelNotOpen。
            // 换模型 / 加模型前先 `GET /api/v3/models` 查真实 id 与 status：
            // status 为 Shutdown / Retiring 的一律不可用，只有 null 的才是当前在售。
            AIVideoModel(id: "doubao-seedance-2-0-260128",
                         nameKey: "Seedance 2.0",
                         noteKey: "带音频 · 生成快"),
            AIVideoModel(id: "doubao-seedance-2-5-260628",
                         nameKey: "Seedance 2.5",
                         noteKey: "更新一代 · 需在控制台开通"),
        ])

    private static let kling = AIVideoVendor(
        id: "kling",
        nameKey: "快手可灵",
        keyPageURL: URL(string: "https://app.klingai.com/")!,
        keyHintKey: "控制台 ▸ API 密钥，复制长钥直接粘贴",
        noteKey: "国内直连 · 按次计费",
        models: [
            AIVideoModel(id: "kling-3.0",
                         nameKey: "可灵 3.0",
                         noteKey: "1080p · 画面最稳"),
        ])

    /// 全部厂商，顺序即 UI 下拉的展示顺序。
    static let all: [AIVideoVendor] = [google, minimax, vidu, alibaba, volcano, kling]

    /// 未知厂商 id 时的回落。用 `all[0]` 而不是另建常量 —— 换首选厂商只需调 `all` 的顺序。
    static var fallback: AIVideoVendor { all[0] }

    // MARK: - 查询

    /// 按 id 取厂商；未知 id（厂商已下线 / 手改过偏好）回落到默认，不让 UI 出现空选项。
    static func vendor(id: String?) -> AIVideoVendor {
        guard let id else { return fallback }
        return all.first { $0.id == id } ?? fallback
    }

    /// 用户当前选中的厂商。
    ///
    /// **必须现读现用**：这个是 `static func` 而不是缓存好的 `static let`，因为 UserDefaults
    /// 在进程运行期间会被设置面板改写。若 init 时缓存成常量，用户换了厂商后本次会话还在用老厂商
    /// 的策略与老厂商的 Key 文件，要重启才生效。
    static func selected() -> AIVideoVendor {
        vendor(id: UserDefaults.standard.string(forKey: UserPreferenceKey.aiVideoVendor))
    }

    /// 用户当前选中的模型。
    ///
    /// ## 为什么只在选中厂商自己的 models 里找
    /// 模型 id **不是全局唯一的命名空间**：换厂商后旧偏好里存的模型 id 属于上一家。若跨厂商全局
    /// 查找（或直接返回旧模型），会出现「刚选了 A 厂的 Key，却拿着 B 厂的模型名去发请求」——
    /// 结果是 404 / model not found，而且错误信息不会提示是串厂商了，极难排查。
    /// 因此找不到就**强制回落该厂商的第一个模型**，返回的模型必定属于当前厂商。
    static func selectedModel() -> AIVideoModel {
        let vendor = selected()
        guard let id = UserDefaults.standard.string(forKey: UserPreferenceKey.aiVideoModel),
              let model = vendor.models.first(where: { $0.id == id })
        else { return vendor.models[0] }
        return model
    }
}
