import AppKit
import SwiftUI

// MARK: - Hex 初始化（支持 #RRGGBB / #RRGGBBAA / 0x…）
extension NSColor {
    convenience init?(hex8 string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        else if s.hasPrefix("0x") { s.removeFirst(2) }
        let len = s.count
        guard (len == 6 || len == 8), let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if len == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255
            a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// IHaven 设计 Token 的 SwiftUI 映射（design-tokens.json v2.0）。
/// 暗/亮双主题通过 `NSColor` 动态 provider 实现，代码层不做 if/else（token 约定）。
/// 仅依赖 Core，可被任意 Feature 层引用（ARCH §4 单向依赖）。
enum IHaven {
    /// 颜色：基础色板（暗 + 亮动态）+ 语义别名。
    enum Color {
        // primitive（A1 身份色）
        static let void          = SwiftUI.Color(nsColor: IHavenDynamic("#0B0D10", "#E4E6EA"))
        static let surfaceSunken = SwiftUI.Color(nsColor: IHavenDynamic("#101317", "#ECEEF1"))
        static let surfaceBase   = SwiftUI.Color(nsColor: IHavenDynamic("#16191E", "#F5F6F8"))
        static let surfaceRaised = SwiftUI.Color(nsColor: IHavenDynamic("#1D2128", "#FFFFFF"))
        static let surfaceOverlay = SwiftUI.Color(nsColor: IHavenDynamic("#252A32", "#FFFFFF"))
        static let fg            = SwiftUI.Color(nsColor: IHavenDynamic("#F2F5F8", "#12151A"))
        static let fg2           = SwiftUI.Color(nsColor: IHavenDynamic("#B6BEC9", "#414852"))
        static let muted         = SwiftUI.Color(nsColor: IHavenDynamic("#7E8794", "#6B7480"))
        static let meta          = SwiftUI.Color(nsColor: IHavenDynamic("#5A626D", "#9AA2AD"))
        static let border        = SwiftUI.Color(nsColor: IHavenBorder(0.12, 0.14))
        static let borderSoft    = SwiftUI.Color(nsColor: IHavenBorder(0.06, 0.06))
        static let accent        = SwiftUI.Color(nsColor: IHavenDynamic("#E8A33D", "#B06A10"))
        static let accentHover   = SwiftUI.Color(nsColor: IHavenDynamic("#C4842A", "#8E5309"))
        static let accentActive  = SwiftUI.Color(nsColor: IHavenDynamic("#F2C177", "#C8801F"))
        static let accentOn      = SwiftUI.Color(nsColor: NSColor(hex8: "#16120A") ?? .black)
        static let success       = SwiftUI.Color(nsColor: IHavenDynamic("#4FA85C", "#2F7A3D"))
        static let warn          = SwiftUI.Color(nsColor: IHavenDynamic("#D9A441", "#9A6B12"))
        static let danger        = SwiftUI.Color(nsColor: IHavenDynamic("#D8574B", "#B3382C"))
        static let focus         = SwiftUI.Color(nsColor: IHavenDynamic("#7FB8E8", "#1B6FC4"))
        // semantic 别名（A2 layer）
        static let bg            = surfaceBase
        static let bgChrome      = surfaceSunken
        static let surface       = surfaceRaised
        static let surfaceImageGap = void
        static let hudBg         = surfaceOverlay
        static let hudFg         = fg
    }

    /// 字体：尺寸 / 字重（macOS 基准字号 13，非 16）。
    enum Font {
        enum Size: CGFloat { case xs = 11, sm = 12, md = 13, lg = 15, xl = 17, xxl = 22, xxxl = 28 }
        static let weightRead = SwiftUI.Font.Weight.regular
        static let weightEmphasize = SwiftUI.Font.Weight.medium
        static let weightAnnounce = SwiftUI.Font.Weight.semibold

        static func system(_ size: Size, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size.rawValue, weight: weight)
        }
    }

    /// 间距（A1-structure）。
    enum Space: CGFloat {
        case s0 = 0, s1 = 2, s2 = 4, s3 = 6, s4 = 8, s5 = 12, s6 = 16, s7 = 20, s8 = 24, s10 = 32, s12 = 40, s16 = 64
    }

    /// 圆角（A1-structure），xl 为面板/sheet 上限，禁止 ≥24。
    enum Radius: CGFloat {
        case xs = 4, sm = 6, md = 8, lg = 10, xl = 12
        static let pill: CGFloat = 9999
    }

    /// 布局常量（A1-structure chrome / grid / hitTarget）。
    enum Layout {
        static let titlebarHeight: CGFloat = 38
        static let toolbarHeight: CGFloat = 52
        static let rowHeight: CGFloat = 32
        static let sidebarWidth: CGFloat = 208
        static let statusBarHeight: CGFloat = 32
        static let masonryColMin: CGFloat = 240
        static let masonryColMax: CGFloat = 340
        static let masonryGap: CGFloat = 8
        static let containerMax: CGFloat = 1600
        static let hitPointerMin: CGFloat = 28
    }

    /// 图标尺寸（SF Symbols）。
    enum Icon {
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 24
    }

    /// 动效：临界阻尼（dampingFraction 1.0，禁止弹跳，P0 红线）。
    enum Motion {
        static let instant: Double = 0.08
        static let fast = SwiftUI.Animation.easeOut(duration: 0.15)
        static let base = SwiftUI.Animation.spring(response: 0.30, dampingFraction: 1.0)
        static let slow = SwiftUI.Animation.spring(response: 0.36, dampingFraction: 1.0)
        static let hoverRevealDelay: Double = 0.09
    }
}

// MARK: - 双主题动态色 helpers
private func IHavenDynamic(_ dark: String, _ light: String) -> NSColor {
    NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex8: isDark ? dark : light) ?? .clear
    })
}

private func IHavenBorder(_ darkAlpha: Double, _ lightAlpha: Double) -> NSColor {
    NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 1, alpha: darkAlpha) : NSColor(white: 0, alpha: lightAlpha)
    })
}
