import SwiftUI

extension View {
    /// 条件注入界面语言：`nil` 表示跟随系统（不覆盖环境 locale）。
    /// 拆出这个修饰符是因为 `\.locale` 不接受可选值，直接在调用点写会逼出 AnyView。
    @ViewBuilder
    func locale(_ locale: Locale?) -> some View {
        if let locale {
            self.environment(\.locale, locale)
        } else {
            self
        }
    }

    /// 按「设置 · 外观 · 语言」的当前取值注入 `\.locale`。
    ///
    /// ⚠️ **为什么每个被呈现的子树都要各自挂一次，而不是只在根视图挂一次**：`.sheet` /
    /// `.popover` 呈现出来的视图不一定跟着根视图的环境更新 —— 实测主窗口切英文后已经整片变英文，
    /// 设置面板却还是中文。修饰符自己持有 `@AppStorage`，偏好一变就**在它所在的那棵子树内**
    /// 重新注入，不依赖环境从外向内传，所以被呈现的内容挂上它就能自己跟上。
    func appLocale() -> some View { AppLocaleContainer(content: self) }
}

/// 见 `View.appLocale()`：把语言偏好读进来再注入，使被呈现的子树也能独立跟随切换。
///
/// 用容器 View 而不是 `ViewModifier`，是因为**靠它自己的 `@AppStorage` 失效重渲染**是这个修复
/// 的全部依据 —— `View` 持有 `DynamicProperty` 会重算 `body` 是 SwiftUI 的确定行为，
/// 而 `ViewModifier` 里同样的写法没有这个保证。不赌。
struct AppLocaleContainer<Content: View>: View {
    @AppStorage(UserPreferenceKey.language) private var language: String = AppLanguage.default.rawValue
    let content: Content

    var body: some View {
        content.locale(AppLanguage(rawValue: language)?.locale ?? AppLanguage.default.locale)
    }
}
