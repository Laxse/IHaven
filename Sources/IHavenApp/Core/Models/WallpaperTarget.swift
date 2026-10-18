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
        resolveScreen(displayID: UserDefaults.standard.integer(forKey: UserPreferenceKey.wallpaperTargetDisplay))
    }

    /// 按 `CGDirectDisplayID` 解析屏幕；`0` = 主屏（返回 nil，交由 engine 用主屏）。
    /// 轮换规则按屏分类（#67）用这个重载 —— 每条规则各自带 `targetDisplay`，
    /// 不再共用全局「设壁纸目标屏」。屏已拔掉时返回 nil，engine 回退主屏。
    static func resolveScreen(displayID: Int) -> NSScreen? {
        guard displayID != 0 else { return nil }
        let wanted = CGDirectDisplayID(bitPattern: Int32(displayID))
        return NSScreen.screens.first { ($0.cgDirectDisplayID ?? kCGNullDirectDisplay) == wanted }
    }

    /// ⚠️ **必须判「有没有写过」，不能只看 `integer(forKey:)`**：未设置时它返回 0，
    /// 而 `rawValue == 0` 恰好是 `.fit`（完整可见、四周留白）—— 竖图铺到横屏上必然左右
    /// 黑边，且那句 `?? .fill` 永远轮不到（0 是合法 rawValue，不会走到 nil 分支）。
    /// 这是用户反馈「图片是纵向的时候设置壁纸会出现两边儿有黑边儿」的根因。
    static func fillMode() -> WallpaperFillMode {
        guard let raw = UserDefaults.standard.object(forKey: UserPreferenceKey.wallpaperFillMode) as? Int
        else { return .fill }
        return WallpaperFillMode(rawValue: raw) ?? .fill
    }

    /// 目标屏的宽高比（`frame.width / frame.height`），裁剪选框锁的就是它。
    ///
    /// 用点坐标而不是像素坐标：两者比值一致，不受 `backingScaleFactor` 影响，
    /// 而 `frame` 在屏不存在时不会给出可用值 —— 那种情况回退 16/10（常见笔记本比例）。
    static func cropAspect() -> CGFloat {
        guard let screen = resolveScreen() ?? NSScreen.main, screen.frame.height > 0 else { return 16.0 / 10.0 }
        return screen.frame.width / screen.frame.height
    }

    /// 目标屏描述，形如 `显示器 1 · 3024 × 1964`，显示在裁剪 sheet 标题下方 ——
    /// 用户需要知道「我在为哪块屏裁」，否则多屏时会裁错比例还以为是 bug。
    ///
    /// 带参数的本地化走「先取格式串再 `String(format:)`」，不把值插值进 `String(localized:)`
    /// （本文件 L46-50 有说明：后者生成的是占位键，和 lproj 里手写的 key 对不上）。
    static func cropScreenLabel() -> String {
        guard let screen = resolveScreen() ?? NSScreen.main else {
            return String(localized: "未检测到显示器，已按 16:10 锁定裁剪比例")
        }
        let name = screen.localizedName.trimmingCharacters(in: .whitespaces)
        // `localizedName` 是 EDID 名，无 EDID 的显示器 / 虚拟屏会返回空串 —— 空标题会让
        // 用户看到一条无法区分的空白描述，按 screenOptions() 的约定回退到「主屏」。
        let title = name.isEmpty ? String(localized: "主屏") : name
        let format = String(localized: "%@ · %lld × %lld")
        return String(format: format, title, Int(screen.frame.width), Int(screen.frame.height))
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
