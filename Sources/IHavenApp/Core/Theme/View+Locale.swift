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
}
