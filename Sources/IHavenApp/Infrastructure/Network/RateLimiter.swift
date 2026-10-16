import Foundation

/// `/api/v1/*` 专用令牌桶：45 次 / 60 秒（PRD §6 F7 / ARCH §6.4.1）。
///
/// ⚠️ **只服务 API 端点，绝不用于图片请求。** 45/min 是 wallhaven **API** 的限额
/// （实测 `docs/VERIFIED-WALLHAVEN-DETAIL.md` §6：55 个并发 `/w/<id>` → 恰好 45 × 200 +
/// 10 × 429）。缩略图与原图走 `th.` / `w.wallhaven.cc` 图片 CDN 域名，**不占这个桶** ——
/// 把它们算进来等于「加载一张 12MB 原图 = 1 次配额」，一页 24 张就吃掉半个桶（ARCHITECTURE 曾写「每个请求类型都要过桶，包括图片请求」，已按实测订正）。
///
/// 桶的意义是**在客户端先把请求排好队**，而不是等服务端发 429 再退避（PRD §6 F7）。
actor RateLimiter {
    // MARK: 预设

    /// 生产默认。`IHAVEN_MOCK=1` 时自动退化成 `.unlimited` —— mock 服务本身不限流，
    /// 照常节流会让本地开发的每次翻页白等 1.33 秒。
    static let wallhaven = MockWallhaven.isEnabled ? unlimited : RateLimiter()

    /// 关闭态：`acquire()` 立即返回，`sync` 无副作用。
    static let unlimited = RateLimiter(capacity: nil)

    // MARK: 状态

    /// `nil` = 不限流。
    private let capacity: Double?
    private let nominalPerSecond: Double
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant
    /// 服务端窗口重置时刻（来自 `x-ratelimit-reset`）。**未到点前不补充令牌**：窗口是
    /// 固定的（服务端给了 reset 时间点，Laravel 风格限流），若按 0.75 次/秒提前补，
    /// 我们会在服务端还没重置时就再撞一次 429。
    private var windowEnd: ContinuousClock.Instant?
    private var retriesUsed = 0
    private var retriesWindowStart: ContinuousClock.Instant

    /// - parameter capacity: 桶容量（45 = 每分钟 45 次）；`nil` 表示不限流。
    /// - parameter windowSeconds: 容量对应的时间窗。
    init(capacity: Double? = 45, windowSeconds: Double = 60) {
        self.capacity = capacity
        self.nominalPerSecond = (capacity ?? 0) / windowSeconds
        self.tokens = capacity ?? .infinity
        self.lastRefill = .now
        self.retriesWindowStart = .now
    }

    // MARK: - 令牌

    /// 取 1 枚令牌；不足则挂起等待。**响应取消**：`Task.sleep` 取消时抛 `CancellationError`，
    /// 循环顶部再 `checkCancellation()` 兜住「睡醒才发现已取消」。
    func acquire() async throws {
        guard capacity != nil else { return }
        while true {
            try Task.checkCancellation()
            refill()
            if tokens >= 1 { tokens -= 1; return }
            try await Task.sleep(for: wait())
        }
    }

    /// 用服务端响应头把本地桶钳到**服务端视角**：本地计时无法知道窗口何时转，而
    /// `x-ratelimit-remaining` / `x-ratelimit-reset` 是权威值（实测存在，官方文档未提 ——
    /// `docs/VERIFIED-WALLHAVEN-DETAIL.md` §6）。每次响应都回写，客户端才真能做到
    /// 「从不撞 429」，而不是「撞了再退避」。
    func sync(remaining: Int?, resetEpoch: Int?) {
        guard capacity != nil, let remaining else { return }
        refill()
        // 只收紧、不放宽：服务端说还剩多少，本地就不该觉得自己比它宽裕。
        tokens = min(tokens, Double(remaining))
        guard let resetEpoch else { return }
        // `x-ratelimit-reset` 是秒级时间戳（可能被截断），真正重置落在 [reset, reset+1) 内：
        // 多等 1 秒，避免提前醒来又撞一次 429。
        let secondsToReset = Double(resetEpoch) - Date().timeIntervalSince1970 + 1
        windowEnd = secondsToReset > 0 ? .now + .seconds(secondsToReset) : nil
    }

    /// 取一次重试额度。**429 响应本身也扣配额**（VERIFIED §6），重试须比正常请求更稀有，
    /// 否则「列表页 + 详情页 + 用户点重试」会同时把配额烧光（PRD §6 F7：不无限重试）。
    func consumeRetryBudget() -> Bool {
        let now = ContinuousClock.Instant.now
        if seconds(now - retriesWindowStart) >= Self.retryWindowSeconds {
            retriesWindowStart = now
            retriesUsed = 0
        }
        guard retriesUsed < Self.retryBudget else { return false }
        retriesUsed += 1
        return true
    }

    // MARK: - 内部

    private static let retryBudget = 3
    private static let retryWindowSeconds: Double = 60
    private static let maxWaitSeconds: Double = 60

    private func refill() {
        guard let capacity else { lastRefill = .now; return }
        let now = ContinuousClock.Instant.now
        if let windowEnd {
            guard now >= windowEnd else { lastRefill = now; return }
            // 窗口已转：固定窗口语义下整桶补满，之后交回标称速率。
            self.windowEnd = nil
            tokens = capacity
            lastRefill = now
            return
        }
        tokens = min(capacity, tokens + seconds(now - lastRefill) * nominalPerSecond)
        lastRefill = now
    }

    /// 距取到下一枚令牌还要等多久。窗口未转时睡到重置那一刻
    /// （封顶 60 秒：服务端给了离谱的 reset 时间点也不至于把应用挂死）。
    private func wait() -> Duration {
        if let windowEnd, windowEnd > .now { return min(windowEnd - .now, .seconds(Self.maxWaitSeconds)) }
        return .seconds((1 - tokens) / nominalPerSecond)
    }

    private func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
