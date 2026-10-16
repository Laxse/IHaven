import AppKit
import Foundation

/// 「壁纸铺到哪块屏、以什么模式铺、留白处填什么色」的统一读取点（PRD F2 剩余部分）。
///
/// 写成**静态函数 + UserDefaults**，而不是 `@Observable` 类注入到三个 ViewModel：三个调用点
/// （瀑布流 / 详情页 / 本地库）都是「设壁纸那一刻读一次」，没有需要实时刷新的 UI 状态，
/// 引入一个可观察对象只会多一条注入链和一次可能失效的追踪（`@AppStorage` 放进 `@Observable`
/// 时的自动观测并不可靠）。设置面板那侧仍走 `@AppStorage`，两边读写同一个 key。
///
/// ⚠️ **为什么填充色必须显式给、不能省略 `fillColor`**：实测省略 key **不会**回到系统默认，
/// 而是保留上一次写入的颜色（2026-10-17 实测）。所以「没有主色可用」时要给一个明确的中性色。
///
/// ⚠️ **为什么模式是 `fill` 时也要给色**：`allowClipping = true` 时没有留白，颜色被存下来但
/// 不产生视觉效果；给了无害，不给则会在用户切回 `fit` 时突然出现上一次的旧色。
enum WallpaperTarget {
    /// 用户选择的显示器；`nil` = 主屏（默认，或「上次选的屏已不在」时的回退）。
    static func resolveScreen() -> NSScreen? {
        let saved = UserDefaults.standard.integer(forKey: UserPreferenceKey.wallpaperTargetDisplay)
        guard saved != 0 else { return nil }
        let wanted = CGDirectDisplayID(bitPattern: Int32(saved))
        return NSScreen.screens.first { ($0.cgDirectDisplayID ?? kCGNullDirectDisplay) == wanted }
    }

    static func fillMode() -> WallpaperFillMode {
        WallpaperFillMode(rawValue: UserDefaults.standard
            .integer(forKey: UserPreferenceKey.wallpaperFillMode)) ?? .fill
    }

    /// 留白处填充色：优先用壁纸自己的主色（wallhaven 恒给 5 个），没有则给中性黑。
    static func fillColor(for colors: [String]) -> NSColor? {
        NSColor(hex8: colors.first ?? "") ?? neutralFillColor()
    }

    /// 中性回退色。**必须是显式颜色而不是省略 `fillColor`** —— 省略不会回到系统默认，
    /// 而是保留上一次写入的值（实测）。选黑：绝大多数壁纸的留白区用黑最不突兀。
    static func neutralFillColor() -> NSColor? { NSColor(hex8: "#000000") }

    /// 设置面板的候选项：主屏 + 各物理屏。
    static func screenOptions() -> [WallpaperScreenOption] {
        var options = [WallpaperScreenOption(id: 0, title: String(localized: "主屏"), detail: "")]
        for (index, screen) in NSScreen.screens.enumerated() {
            // ⚠️ `localizedName` 是 EDID 名，无 EDID 的显示器 / 虚拟屏会返回空串，
            // 那时按序号兜底 —— 空标题会让用户看到一个无法区分的空白项。
            let name = screen.localizedName.trimmingCharacters(in: .whitespaces)
            // 带参数的本地化走「取格式串再 String(format:)」，不直接插值进 String(localized:)
            // —— 后者生成的是占位键，和 lproj 里手写的 key 对不上。
            let title = name.isEmpty
                ? String(format: String(localized: "显示器 %lld"), index + 1)
                : name
            options.append(WallpaperScreenOption(id: Int(bitPattern: UInt(screen.cgDirectDisplayID ?? 0)),
                                                 title: title,
                                                 detail: resolutionText(screen)))
        }
        return options
    }

    /// 「显示器具有单独 Spaces」未开启时，多屏写入会被系统合并成一张 —— 这是 macOS 壁纸
    /// 最著名的静默失败（改完还要注销重登才生效）。设置面板必须在写入前提示，否则用户
    /// 只会看到「只生效一块屏」且完全无从判断原因。
    static func needsSeparateSpacesWarning() -> Bool {
        NSScreen.screens.count > 1 && !NSScreen.screensHaveSeparateSpaces
    }

    private static func resolutionText(_ screen: NSScreen) -> String {
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        return "\(Int(size.width))×\(Int(size.height)) @\(Int(scale))x"
    }
}

/// 显示器候选项。`id` 为 `CGDirectDisplayID`，`0` 表示主屏。
struct WallpaperScreenOption: Identifiable, Hashable {
    let id: Int
    let title: String
    let detail: String
}
