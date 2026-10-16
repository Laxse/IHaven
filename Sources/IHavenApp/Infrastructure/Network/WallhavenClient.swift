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
    /// `/search` 的重试上限（PRD §6 F7：最多 3 次）。
    private static let searchRetries = 3
    /// 详情页只给 1 次：详情请求与翻页同价，且 `DetailViewState` 已固化
    /// 「429 立刻重试必再撞限流、每次重试再扣 1 次配额」的判断 —— 返回列表再进来
    /// 就是最自然的重试路径，不需要在这里多烧额度。
    private static let detailRetries = 1

    private let session: URLSession
    private let keyProvider: KeyProvider
    private let limiter: RateLimiter
    /// 退避等待的广播点；`nil` 表示不广播（限流器为 `.unlimited` 时无意义）。
    private let throttle: ThrottleSignal?

    init(keyProvider: KeyProvider,
         session: URLSession = .shared,
         limiter: RateLimiter = .wallhaven,
         throttle: ThrottleSignal? = nil) {
        self.keyProvider = keyProvider
        self.session = session
        self.limiter = limiter
        self.throttle = throttle
    }

    var keyStatus: KeyStatus {
        keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .absent : .configured
    }

    func search(_ query: BrowseQuery) async throws -> WallhavenPage {
        let url = try Self.buildURL(query)
        let (data, response) = try await perform(maxRetries: Self.searchRetries) {
            try await session.data(for: Self.makeRequest(url: url, key: keyProvider.currentKey))
        }
        try Self.assertSuccess(response)
        do {
            let page = try JSONDecoder().decode(WallhavenPage.self, from: data)
            // ImagePipeline 层（Nuke）：结果返回即预取缩略图，避免滚动空白闪烁（ADR-001）。
            // 预取 `aspectThumb`（等比缩略图）：`thumbs.small` 恒为 300×200 硬裁件，
            // 预取它等于把裁坏的图提前塞进缓存（竖图上最明显）。
            NukeImagePipeline.prefetch(page.data.compactMap(\.aspectThumb))
            return page
        } catch {
            throw APIError.decode(error)
        }
    }

    func detail(id: String) async throws -> WallpaperDetail {
        // 每次调用消耗 1 次配额（与翻页同价），故只给 1 次重试额度 —— 重试策略统一在
        // `perform` 内按端点上限处理，本方法不再自称「不做任何重试」。
        let url = WallhavenEndpoint.wallpaper(id: id)
        let (data, response) = try await perform(maxRetries: Self.detailRetries) {
            try await session.data(for: Self.makeRequest(url: url, key: keyProvider.currentKey))
        }
        try Self.assertDetailSuccess(response, keyStatus: keyStatus)
        do {
            // 顶层是 `{"data":{…}}`（无 `meta`）：必须经 envelope 取里层对象，
            // 直接 decode(WallpaperDetail.self) 只会看到 `data` 这一个键。
            let detail = try JSONDecoder().decode(WallpaperDetailEnvelope.self, from: data).data
            // 详情页的**低清占位**先到：预取等比缩略图（列表页已预热，通常直接命中缓存）。
            NukeImagePipeline.prefetch([detail.base.aspectThumb].compactMap { $0 })
            return detail
        } catch {
            throw APIError.decode(error)
        }
    }

    // MARK: - 内部

    /// 发一次请求 + 退避重试。**只在 429 / 5xx 上重试** —— `401` / `404` / `400` /
    /// 解码失败 / 参数非法都是确定性失败，而实测「404 与 401 同样扣配额」
    /// （`docs/VERIFIED-WALLHAVEN-DETAIL.md` §6），对它们重试是纯烧额度。
    ///
    /// 状态码的**端点语义**分流仍留在调用方（`assertSuccess` / `assertDetailSuccess`）：
    /// 这里只回答「这个状态码值不值得再发一次」—— 那是状态码自身的属性，不是端点的属性。
    private func perform(maxRetries: Int,
                         _ send: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try await limiter.acquire()
            let pair = try await send()
            guard let http = pair.1 as? HTTPURLResponse else { return pair }
            await limiter.sync(remaining: Self.headerInt(http, "x-ratelimit-remaining"),
                               resetEpoch: Self.headerInt(http, "x-ratelimit-reset"))
            let code = http.statusCode
            guard code == 429 || code >= 500, attempt < maxRetries else { return pair }
            guard await limiter.consumeRetryBudget() else { return pair }
            attempt += 1
            let delay = Self.backoff(attempt: attempt, response: http)
            await MainActor.run { throttle?.waitingSeconds = Int(delay.rounded(.up)) }
            try await Task.sleep(for: .seconds(delay))
            await MainActor.run { throttle?.waitingSeconds = 0 }
        }
    }

    /// 退避时长：`min(1s × 2^(n-1) + jitter, 60s)`（ARCH §6.4.1）。
    /// jitter 是必需的：多个并发请求若在同一刻重试会形成同步重试风暴（ARCH 已记录）。
    /// 响应带 `retry-after` 时优先用它 —— 实测该头只在 429 出现（VERIFIED §6）。
    private static func backoff(attempt: Int, response: HTTPURLResponse) -> Double {
        let cap = 60.0
        if let raw = response.value(forHTTPHeaderField: "retry-after"), let after = Double(raw) {
            return min(max(after, 0), cap)
        }
        let base = min(pow(2.0, Double(attempt - 1)), cap)
        return min(base + Double.random(in: 0...base * 0.5), cap)
    }

    private static func headerInt(_ http: HTTPURLResponse, _ name: String) -> Int? {
        http.value(forHTTPHeaderField: name).flatMap(Int.init)
    }

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
        // /search 的 401 只有一义（Trap 16）。
        // ⚠️ 404 / 429 **刻意不在这里分流**：那是详情页才验证过的可达状态，
        // `/search` 的 404 可达性未实测，共用会把详情专属文案外推到列表页 —— 见 `assertStatus`。
        try assertStatus(response) { $0 == 401 ? .unauthorizedKey : nil }
    }

    /// ⚠️ **本方法只适用于 `/api/v1/w/<id>`，不得外推到 `/search`。**
    /// `/search` 的 401 恒等于「Key 无效」（Trap 16，见 `assertSuccess`）；而详情端点的 401 是
    /// **双语义** —— 「NSFW 壁纸 + 未配 Key」与「任意壁纸 + Key 无效」返回逐字节相同的
    /// `{"error":"Unauthorized"}`，无法从响应体区分（Trap 19 / VERIFIED-WALLHAVEN-DETAIL.md §5）。
    /// 因此这里只能靠**本地 Key 状态**分叉，绝不解析错误响应体（401/404 用 `error` 键，
    /// 429 却用 `message` 键 —— 单一 envelope 会把限流误报成解析失败）。
    private static func assertDetailSuccess(_ response: URLResponse, keyStatus: KeyStatus) throws {
        try assertStatus(response) { code in
            switch code {
            case 401: return keyStatus == .absent ? .nsfwRequiresKey : .unauthorizedKey
            // 404 / 429 单独分流：这两个在详情页是可达且常见的状态（壁纸会被下架；
            // 详情请求每次消耗 1 次配额，滚动 + 进详情容易触顶 45/min）。落到通用的
            // `.http(status:)` 只会显示一个状态码，不满足 SPEC §7.3「错误文案必须指向
            // 可执行的下一步」。**只对详情生效**，理由见 `assertStatus`。
            case 404: return .notFound
            case 429: return .rateLimited
            default: return nil
            }
        }
    }

    /// 状态码判定（Trap 10：先判状态码，非 2xx 直接抛错，不碰 data）。
    ///
    /// `specific` 由调用方按**端点**提供：传入状态码，返回该端点的专属错误；返回 `nil` 表示
    /// 该状态码在本端点上没有更具体的含义，退回通用的 `.http(status:)`。
    ///
    /// ⚠️ **为什么状态码映射必须按端点分开传，而不是写在这里**：两个端点的语义不同，写死
    /// 在共享函数里就等于默认「一个端点的结论适用于另一个端点」—— 而 ADR-007 的 Trap 16
    /// 与 Trap 19 记录的正反两面都在警告这件事：Trap 16（`/search` 的 401 只有一义）曾经被
    /// 外推到详情端点，结果把「未配 Key」误报成「Key 无效」（Trap 19）；反过来，详情端点的
    /// 404 若共用，列表页会显示「**这张壁纸**已不存在」这种与场景不符的文案。
    /// 因此「哪些状态码有专属含义」是**端点的属性**，不是状态码的属性。
    private static func assertStatus(_ response: URLResponse, specific: (Int) -> APIError?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(NSError(domain: "IHaven", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: String(localized: "非 HTTP 响应")]))
        }
        let code = http.statusCode
        if (200..<300).contains(code) { return }
        throw specific(code) ?? APIError.http(status: code)
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

    /// 默认指向真实服务（需 VPN）；`IHAVEN_MOCK=1` 时指向本地 mock 主机（见 MockWallhaven）。
    /// 两个端点必须共用同一个 base 判定，否则会出现「搜索走 mock、详情打真实服务」的错配。
    private static var currentBase: URL {
        MockWallhaven.isEnabled
            ? URL(string: "https://\(MockWallhaven.host)/api/v1")!
            : realBase
    }

    /// 常规搜索。**绝不为** Key 验证 / NSFW 探测 使用 /settings（Trap 15/17）。
    static var search: URL { currentBase.appendingPathComponent("search") }

    /// 壁纸详情 `w/<id>`。`<id>` 形如 `jel1jq`（实测恒 6 位字母数字）。
    /// 官方 help 页的示例 id `94x38z` **实测已 404**，切勿用于测试或 fixture
    /// （VERIFIED-WALLHAVEN-DETAIL.md §1）。
    static func wallpaper(id: String) -> URL {
        currentBase.appendingPathComponent("w").appendingPathComponent(id)
    }
}
