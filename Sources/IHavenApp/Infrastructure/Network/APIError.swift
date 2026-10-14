import Foundation

/// 客户端可判定的错误分类（ARCH §6.2.3 / ADR-006）。
public enum APIError: LocalizedError {
    case http(status: Int)                       // 非 2xx（先判状态码，再解码）
    case decode(Error)                           // JSON 解析失败（实测常见：空串 URL 字段 / 错误路径返回 HTML）
    case invalidParameter(String)                // 客户端预校验未过（ratios/resolutions 非法）
    case transport(Error)                        // 网络层错误
    case unauthorizedKey                         // 401：Key 失效（唯一含义 —— 仅适用于 /search，见 Trap 16）
    /// 404：壁纸不存在。详情页是**可达**状态 —— 壁纸会被作者或站点下架，用户也可能从
    /// 收藏 /「已设置」历史点进来。必须给独立文案：落到 `.http(status:)` 只会显示「HTTP 404」，
    /// 违反 SPEC §7.3「错误文案必须指向可执行的下一步」。
    case notFound
    /// 429：触发速率限制（实测 45 次/分钟，与搜索共享同一个桶，详情请求每次 −1，
    /// 错误请求同样扣配额）。详情页 + 滚动翻页的组合下极易触顶，属常见状态而非边缘状态。
    case rateLimited
    /// 401 且本地未配置 Key：只可能出现在 `/w/<id>` 上，含义是「这是张 NSFW 壁纸，
    /// 需要登录态才能看」（Trap 19）。文案指向可执行的下一步（SPEC §7.3）。
    case nsfwRequiresKey

    public var errorDescription: String? {
        switch self {
        // 这些描述会直接显示在错误态里，故走 String(localized:) 而非裸字面量（否则固化成中文）。
        case .http(let s): return "HTTP \(s)"
        // 用 localizedDescription 显式取文案：直接插值 Error 会触发 appendInterpolation 弃用警告
        // （本地化插值对未知类型只给调试描述）。
        case .decode(let e): return String(localized: "响应解析失败：\(e.localizedDescription)")
        case .invalidParameter(let p): return String(localized: "参数非法：\(p)")
        case .transport(let e): return String(localized: "网络错误：\(e.localizedDescription)")
        case .unauthorizedKey: return String(localized: "API Key 失效（401，唯一含义：Key 无效）")
        case .notFound: return String(localized: "这张壁纸已不存在，可能已被作者或站点下架。返回列表看看其它壁纸")
        case .rateLimited: return String(localized: "请求太频繁，已触发每分钟 45 次的调用上限。请稍候再试")
        case .nsfwRequiresKey: return String(localized: "这是 NSFW 壁纸，需要 API Key 才能查看。请在设置中填写 API Key 后重试")
        }
    }
}
