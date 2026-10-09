import Foundation

/// wallhaven API 客户端（URLSession + async/await，无 Alamofire —— ARCH §6.4.1）。
///
/// 已固化的实测纪律（ADR-007 / SPEC §9.2 / §9.8 / ARCH §6.4.0）：
/// 1. 始终发送 `Accept: application/json`（Trap 10b）—— 否则错误路径返回 HTML，JSONDecoder 误报。
/// 2. Key 经 `X-API-Key` 头下发，**绝不作为查询参数**（旧版错误做法）；空 / 纯空白 Key 与未配置不可区分（Trap 14）。
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
            return try JSONDecoder().decode(WallhavenPage.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    func probeNSFWPermission() async -> NSFWProbeResult {
        // 固定宽：仅 purity=001，不带任何用户筛选（SPEC §9.2）。
        // 带筛选会让探测与主请求一样返回 0，判定失效。
        var comps = URLComponents(url: WallhavenEndpoint.search, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "purity", value: "001")]
        guard let url = comps.url else { return .error(APIError.transport(NSError(domain: "IHaven", code: -2))) }
        do {
            let (data, response) = try await session.data(for: Self.makeRequest(url: url, key: keyProvider.currentKey))
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                return .keyInvalid
            }
            try Self.assertSuccess(response)
            let page = try JSONDecoder().decode(WallhavenPage.self, from: data)
            return page.meta.total > 0 ? .authorized(total: page.meta.total) : .unauthorized
        } catch {
            if case APIError.unauthorizedKey = error { return .keyInvalid }
            return .error(error)
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
                                            userInfo: [NSLocalizedDescriptionKey: "非 HTTP 响应"]))
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
        if !q.color.isEmpty { items.append(.init(name: "color", value: q.color)) }
        items.append(.init(name: "page", value: String(q.page)))
        if !q.seed.isEmpty { items.append(.init(name: "seed", value: q.seed)) }
        comps.queryItems = items
        return comps.url!
    }
}

/// 端点与常量（ARCH §6.4.0 第四条：绝不使用 /settings 验证 Key 或判 NSFW）。
enum WallhavenEndpoint {
    static let base = URL(string: "https://wallhaven.cc/api/v1")!
    /// 常规搜索。**绝不为** Key 验证 / NSFW 探测 使用 /settings（Trap 15/17）。
    static let search = base.appendingPathComponent("search")
}
