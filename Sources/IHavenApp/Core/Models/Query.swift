import Foundation

/// 搜索查询（用户在筛选面板配置的所有维度）。
public struct BrowseQuery: Sendable, Equatable {
    public var q: String = ""
    public var purity = PurityFilter.browseDefault
    public var categories: CategoryFilter = .default
    public var sorting: Sorting = .dateAdded
    public var order: Order = .desc
    public var topRange: TopRange = .month
    public var atleast: String = ""                      // 仅校验格式，不下发上界（Trap 11/10）
    public var resolution: Resolution = .unspecified
    public var ratio: Ratio = .unspecified
    public var color: String = ""                         // "" 表示不限制
    public var page: Int = 1
    public var seed: String = ""

    public init() {}

    /// 筛选标识：除 `page` / `seed` 外的全部维度。用于区分「筛选变更」（要重查并回到第 1 页）
    /// 与「翻页」（`page` 递增，不得触发重查）。
    public var filterKey: String {
        "\(q)|\(purity.rawValue)|\(categories.rawValue)|\(sorting.rawValue)|\(order.rawValue)"
            + "|\(topRange.rawValue)|\(atleast)|\(resolution.rawValue)|\(ratio.rawValue)|\(color)"
    }
}

/// 纯度筛选（三位 purity 串：bit0=sfw, bit1=sketchy, bit2=nsfw）。
public struct PurityFilter: Sendable, Hashable {
    public var sfw: Bool
    public var sketchy: Bool
    public var nsfw: Bool

    public var rawValue: String {
        "\(sfw ? 1 : 0)\(sketchy ? 1 : 0)\(nsfw ? 1 : 0)"
    }

    public init(sfw: Bool, sketchy: Bool, nsfw: Bool) {
        self.sfw = sfw
        self.sketchy = sketchy
        self.nsfw = nsfw
    }

    /// 浏览默认档：全年龄 + 轻微暗示 开、NSFW 关（filter-panel.svg：全年龄 ON / 轻微暗示 ON / NSFW OFF）。
    /// NSFW 不再做权限门禁 —— 三档一律可自由切换（2026-10-11 产品决定，见 ADR-011）。
    public static let browseDefault = PurityFilter(sfw: true, sketchy: true, nsfw: false)
}

public enum CategoryFilter: String, Sendable, CaseIterable {
    case all = "111"
    case general = "100"
    case anime = "010"
    case people = "001"
    /// 默认「全部」（filter-panel.svg 分类分段控件默认选中首项「全部」，侧栏「发现」也落到全部）。
    public static let `default` = CategoryFilter.all
}

public enum Sorting: String, Sendable, CaseIterable {
    case dateAdded = "date_added"
    case relevance, random, views, favorites, toplist, toplistRandom = "toplist_random"
}

public enum Order: String, Sendable { case desc, asc }

public enum TopRange: String, Sendable, CaseIterable {
    case day = "1d", threeDays = "3d", week = "1w"
    case month = "1M", threeMonths = "3M", sixMonths = "6M", year = "1y"
}

/// 比例：封闭枚举（Trap 13 —— 非法值不得在客户端构造，必须构造前抛出）。
public enum Ratio: String, Sendable, CaseIterable {
    case unspecified = ""
    case r9x16 = "9x16", r10x16 = "10x16", r9x18 = "9x18"
    case r1x1 = "1x1", r3x2 = "3x2", r4x3 = "4x3", r5x4 = "5x4"
    case r16x9 = "16x9", r16x10 = "16x10"
    case r21x9 = "21x9", r32x9 = "32x9", r48x9 = "48x9"
}

/// 分辨率：封闭枚举（Trap 13）。
public enum Resolution: String, Sendable, CaseIterable {
    case unspecified = ""
    case r1280x720 = "1280x720", r1280x800 = "1280x800"
    case r1920x1080 = "1920x1080", r1920x1200 = "1920x1200"
    case r2560x1440 = "2560x1440", r3840x2160 = "3840x2160"
}
