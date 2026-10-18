import Foundation

/// 一条壁纸轮换规则（PRD F13）。
///
/// **一张表 + `mode` 字段，而不是「间隔表」和「时段表」两张**：两类规则 90% 字段重合，
/// 拆表等于把同一套 CRUD 写两遍（PRD 附录 A-6b 对 F8/F9 立过同样的先例）。
public struct WallpaperSchedule: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    /// 用户可见名，例如「工作日白天」。
    public var name: String
    public var isEnabled: Bool

    public var mode: Mode
    /// `mode == .interval` 时有效：每隔多少分钟换一次。
    public var intervalMinutes: Int
    /// `mode == .timeWindow` 时有效：自 00:00 起的分钟数（9:00 → 540，18:00 → 1080）。
    public var startMinute: Int
    public var endMinute: Int
    /// `Calendar.component(.weekday)` 取值（1 = 周日）；空数组 = 每天。
    /// 存 CSV 而不是位掩码：一行 `split(",")` 搞定，且人读 SQL 时一眼看懂。
    public var weekdays: [Int]

    public var source: Source
    /// 目标屏（`CGDirectDisplayID`；`0` = 主屏）。每条规则各自指定，实现多屏分类轮换（#67）：
    /// 同一条来源可拆成「客厅屏放风景相册 / 书房屏放工作相册」两条规则，互不干扰。
    public var targetDisplay: Int
    /// `source == .album` 时有效：轮换哪个相册的成员；其余来源为 nil。
    public var albumID: String?
    public var order: Order
    /// 顺序轮换的游标。**必须落库** —— 否则 App 重启后每次都从头开始。
    public var cursor: Int
    public var lastRunAt: Date?
    /// 上一次换上的壁纸 id，避免随机连续两次抽到同一张。
    public var lastWallpaperID: String?
    public var createdAt: Date

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case interval
        case timeWindow
    }

    public enum Source: String, Codable, Sendable, CaseIterable {
        case favorites
        /// 「已设置」历史里**本地文件仍在**的那些。
        case applied
        /// 本地导入（`Application Support`，不会被系统回收）—— 最稳的来源。
        case imported
        /// 某个本地相册（F-组织）里**本地文件仍在**的成员；具体相册由 `albumID` 指定。
        case album
    }

    public enum Order: String, Codable, Sendable, CaseIterable {
        case random
        case sequential
    }

    public init(id: String = UUID().uuidString,
                name: String,
                isEnabled: Bool = true,
                mode: Mode = .interval,
                intervalMinutes: Int = 60,
                startMinute: Int = 540,
                endMinute: Int = 1080,
                weekdays: [Int] = [],
                source: Source = .imported,
                targetDisplay: Int = 0,
                albumID: String? = nil,
                order: Order = .random,
                cursor: Int = 0,
                lastRunAt: Date? = nil,
                lastWallpaperID: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.mode = mode
        self.intervalMinutes = intervalMinutes
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
        self.source = source
        self.targetDisplay = targetDisplay
        self.albumID = albumID
        self.order = order
        self.cursor = cursor
        self.lastRunAt = lastRunAt
        self.lastWallpaperID = lastWallpaperID
        self.createdAt = createdAt
    }

    /// 这一时刻是否落在规则的时间窗内（仅 `timeWindow` 模式有意义）。
    ///
    /// 用「自零点起的分钟数」而不是 `Date`：时段是每日重复的**壁钟语义**，
    /// 存 `Date` 会引入时区与夏时制歧义，存分钟数做比较就是 `Int` 比较。
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        if !weekdays.isEmpty {
            guard weekdays.contains(calendar.component(.weekday, from: date)) else { return false }
        }
        guard mode == .timeWindow else { return true }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        // 允许跨零点时段（如 22:00–02:00）。
        if startMinute <= endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}
