import SwiftUI

/// 工具栏图标按钮：28×28 + 圆角 6 + 1px 描边，hover 补 `void` 底（工具栏、详情页页头条、
/// 导入/动态壁纸卡片浮层共用）。放在 Shared 的理由同 `MasonryView`：跨 Feature 复用，
/// 且 `Features/DynamicWallpaper` 不得出现 `Features/Browse` 字样（convention-gate F9 规则）。
/// 提成类型而不是函数：hover 态要 `@State`，函数返回值里挂不住。
struct BrowseIconButton: View {
    let systemName: String
    var help: LocalizedStringKey = ""
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: IHaven.Icon.sm))
                .frame(width: 28, height: 28)
                .background(hovered ? IHaven.Color.void : SwiftUI.Color.clear,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
        .help(help)
        .onHover { hovered = $0 }
    }
}
