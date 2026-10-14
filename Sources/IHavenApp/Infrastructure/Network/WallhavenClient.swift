import Foundation

/// wallhaven API 客户端（URLSession + async/await，无 Alamofire —— ARCH §6.4.1）。
///
/// 已固化的实测纪律（ADR-007 / SPEC §9.2 / §9.8 / ARCH §6.4.0）：
/// 1. 始终发送 `Accept: application/json`（Trap 10b）—— 否则错误路径返回 HTML，JSONDecoder 误报。
/// 2. Key 经 `X-API-Key` 头下发，**绝不作为查询参数**；空 / 纯空白 Key 与未配置不可区分（Trap 14）。
///    澄清（2026-10-14 实测）：服务端**确实也接受**把 Key 放进 URL 查询串的形式 —— 详情端点实测
///    返回 200，无效值时同样正确返回 401。所以禁令的理由是**不安全**（Key 会出现在服务器日志、
///    `Referer` 与代理缓存里），**而不是「服务端不支持」**。**禁令本身继续有效，不得削弱。**
///    （本行刻意不写出该查询参数名的字面形式 —— `scripts/security-gate.sh` 禁止其出现在源码中。
///     该参数形态的实测记录见 `docs/VERIFIED-WALLHAVEN-DETAIL.md` §1。）
/// 3. 先判 HTTP 状态码，非 2xx 走错误分支不碰 data（Trap 10）；禁止先解码再判状态码。
/// 4. 四条全局禁令（ARCH §6.4.0）：不用 /settings 验 Key；不用 200 判 Key 有效；探测不带用户筛选；不用 data.purity 判 NSFW。
/// 5. ratios / resolutions 为封闭枚举，非法值在构造时即抛错，绝不下发（Trap 13）。
/// 6. 未配置 Key 时结果集静默缩水且无可检测字段（Trap 18 / SPEC §9.8）—— 产品层提示，技术层不尝试探测缩水。
///
/// `@unchecked Sendable`：初始化后 `session` 与 `keyProvider` 引用不再变更（effective-immutable），
/// 二者均为 Sendable（`URLSession` 本就 Sendable；`KeyProvider` 协议约束为 Sendable），
/// 故跨隔离边界（如 @MainActor 视图模型调用 `await client.search`）发送 client 安全。
final class WallhavenClient: WallhavenAPIProtocol, @unchecked Sendable {
    private let session: URLSession
    private let keyProvider: KeyProvider

    init(keyProvider: KeyProvider, session: URLSession = .shared) {
        self.keyProvider = keyProvider
        self.session = session
    }

    var keyStatus: KeyStatus {
        keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .absent : .configured
    }

    func search(_ query: BrowseQuery) async throws -> WallhavenPage {
        let url = try Self.buildURL(query)
        let (data, response) = try await session.data(for: Self.makeRequest(url: url, key: keyProvider.currentKey))
        try Self.assertSuccess(response)
        do {
            let page = try JSONDecoder().decode(WallhavenPage.self, from: data)
            // ImagePipeline 层（Nuke）：结果返回即预取缩略图，避免滚动空白闪烁（ADR-001）。
            NukeImagePipeline.prefetch(page.data.compactMap { $0.thumbs.small })
            return page
        } catch {
            throw APIError.decode(error)
        }
    }

    // MARK: - 内部

    private static func makeRequest(url: URL, key: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")        // 纪律 1
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            req.setValue(trimmed, forHTTPHeaderField: "X-API-Key")           // 纪律 2
        }
        return req
    }

    private static func assertSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(NSError(domain: "IHaven", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: String(localized: "非 HTTP 响应")]))
        }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw APIError.unauthorizedKey                               // Trap 16：401 仅表示 Key 无效
        default: throw APIError.http(status: http.statusCode)
        }
    }

    private static func buildURL(_ q: BrowseQuery) throws -> URL {
        var comps = URLComponents(url: WallhavenEndpoint.search, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if !q.q.isEmpty { items.append(.init(name: "q", value: q.q)) }
        items.append(.init(name: "purity", value: q.purity.rawValue))
        items.append(.init(name: "categories", value: q.categories.rawValue))
        items.append(.init(name: "sorting", value: q.sorting.rawValue))
        items.append(.init(name: "order", value: q.order.rawValue))
        if q.sorting == .toplist {
            items.append(.init(name: "topRange", value: q.topRange.rawValue))
        }
        // atleast：仅校验格式，不下发上界（Trap 11/10）
        if !q.atleast.isEmpty {
            guard q.atleast.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil else {
                throw APIError.invalidParameter("atleast=\(q.atleast)")
            }
            items.append(.init(name: "atleast", value: q.atleast))
        }
        // ratios / resolutions：封闭枚举，unspecified 不下发（Trap 13）
        if q.resolution != .unspecified { items.append(.init(name: "resolutions", value: q.resolution.rawValue)) }
        if q.ratio != .unspecified { items.append(.init(name: "ratios", value: q.ratio.rawValue)) }
        // 参数名是复数 `colors`（6 位 hex，不带 #）。实测：下发单数 `color` 会被 wallhaven 静默忽略
        // —— total 952937（= 未筛选）、24 条里只有 4 条命中目标色；改成 `colors` 后
        // total 60509、24/24 命中，与无 Key 请求同样生效。
        if !q.color.isEmpty { items.append(.init(name: "colors", value: q.color)) }
        items.append(.init(name: "page", value: String(q.page)))
        if !q.seed.isEmpty { items.append(.init(name: "seed", value: q.seed)) }
        comps.queryItems = items
        return comps.url!
    }
}

/// 端点与常量（ARCH §6.4.0 第四条：绝不使用 /settings 验证 Key 或判 NSFW）。
enum WallhavenEndpoint {
    private static let realBase = URL(string: "https://wallhaven.cc/api/v1")!
    /// 常规搜索。**绝不为** Key 验证 / NSFW 探测 使用 /settings（Trap 15/17）。
    /// 默认指向真实服务（需 VPN）；`IHAVEN_MOCK=1` 时指向本地 mock 主机（见 MockWallhaven）。
    static var search: URL {
        let base = MockWallhaven.isEnabled
            ? URL(string: "https://\(MockWallhaven.host)/api/v1")!
            : realBase
        return base.appendingPathComponent("search")
    }
}
