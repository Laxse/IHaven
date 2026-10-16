import Foundation

/// 护栏的对外快照：当前触发了哪些档、占用读数、以及**每档在本机是否可用**。
///
/// `unavailableReasons` 不是可选的装饰：台式机没有电池、`CGWindowList` 读不到窗口时，
/// UI 必须说清「这一档为什么没在工作」，而不是把开关灰在那儿让用户猜。
/// 灰着一个不解释的开关 = 用户以为功能坏了。
public struct GuardSnapshot: Sendable, Equatable {
    public var cpuPercent: Double = 0
    /// 进程内存（`phys_footprint`，与活动监视器「内存」列同口径）。
    public var processBytes: Int64 = 0
    /// 系统内存压力：`1 - (free + inactive) / total`，0~100。
    public var systemPressurePercent: Double = 0
    /// 护栏当前是否正持有着一次自动暂停。
    public var isPausedByGuard = false
    public var activeTriggers: Set<PerformanceTrigger> = []
    /// 档位 → 本机不可用的原因文案；空字典表示全都可用。
    public var unavailableReasons: [PerformanceTrigger: String] = [:]

    public init() {}
}
