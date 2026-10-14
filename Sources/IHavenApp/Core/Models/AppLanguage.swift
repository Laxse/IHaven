import Foundation

/// 界面语言（设置 · 外观页签切换）。默认 `.zhHans`（用户指定：默认 Chinese）。
///
/// 本地化走 SwiftUI 原生链路：把 `locale` 注入环境后，`Text("发现")` 这类字面量会按
/// `Localizable.strings` 取对应语言的值；取不到就回退显示字面量本身 —— 字面量即中文，
/// 所以 zh-Hans.lproj 即使不写也能正确显示中文。
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    /// 跟随系统（不注入 locale，交给系统语言）。
    case system
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    /// 注入 SwiftUI 环境的 locale；`.system` 为 nil（不覆盖）。
    public var locale: Locale? {
        switch self {
        case .system: nil
        case .zhHans: Locale(identifier: "zh-Hans")
        case .en: Locale(identifier: "en")
        }
    }

    /// 选择器里显示的名字：语言名用该语言自身书写（通行做法，不翻译），
    /// 只有「跟随系统」需要随界面语言变化，故统一作为 LocalizedStringKey 的 key 使用。
    public var displayKey: String {
        switch self {
        case .system: "跟随系统"
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    public static let `default` = AppLanguage.zhHans
}
