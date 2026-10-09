import Foundation

/// 客户端可判定的错误分类（ARCH §6.2.3 / ADR-006）。
public enum APIError: LocalizedError {
    case http(status: Int)                       // 非 2xx（先判状态码，再解码）
    case decode(Error)                           // JSON 解析失败（多为 HTML 误喂）
    case invalidParameter(String)                // 客户端预校验未过（ratios/resolutions 非法）
    case transport(Error)                        // 网络层错误
    case unauthorizedKey                         // 401：Key 失效（唯一含义，见 Trap 16）

    public var errorDescription: String? {
        switch self {
        case .http(let s): return "HTTP \(s)"
        case .decode: return "响应解析失败（疑似错误路径返回了 HTML，未发 Accept: application/json）"
        case .invalidParameter(let p): return "参数非法：\(p)"
        case .transport(let e): return "网络错误：\(e.localizedDescription)"
        case .unauthorizedKey: return "API Key 失效（401，唯一含义：Key 无效）"
        }
    }
}
