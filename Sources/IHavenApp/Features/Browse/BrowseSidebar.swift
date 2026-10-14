import SwiftUI

/// 侧栏（208px，chrome 底 + 1px hairline）。从 `BrowseView` 拆出：该文件已到 295 行，
/// 逼近单文件 300 行的门禁上限（ADR-009），而侧栏是纯展示 + 一个回调，拆出去零风险。
struct BrowseSidebar: View {
    let nav: NavItem
    var onSelect: (NavItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(.discover)
                sidebarDivider
                sidebarRow(.landscape); sidebarRow(.anime); sidebarRow(.people)
                sidebarDivider
                sidebarRow(.favorites); sidebarRow(.wallpaperSet)
                sidebarDivider
                sidebarRow(.live); sidebarRow(.import)
                sidebarDivider
                sidebarRow(.settings)
            }
            .padding(.vertical, 8)
        }
        // 先固定宽度再填充高度，保证 ScrollView 恰好 208px、不溢出挤偏主区
        .frame(width: IHaven.Layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .trailing) {
            Rectangle().fill(IHaven.Color.border).frame(width: 1)
        }
    }

    private var sidebarDivider: some View {
        Rectangle().fill(IHaven.Color.borderSoft).frame(height: 1)
            .padding(.horizontal, IHaven.Space.s5.rawValue).padding(.vertical, IHaven.Space.s2.rawValue)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        let selected = nav == item
        return Button { onSelect(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: IHaven.Icon.sm))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                    // 固定图标槽：SF Symbol 宽窄不一，槽内居中使图标成列、标签对齐到同一 x
                    .frame(width: 20, alignment: .center)
                Text(item.label)
                    .font(IHaven.Font.system(.md))
                    .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                Spacer(minLength: 0)
            }
            // 行内 8pt：图标槽落在 16~36（中心 26，与工具栏开关图标同列）、标签左缘 46（线稿基准）
            .padding(.horizontal, IHaven.Space.s4.rawValue)
            .frame(height: IHaven.Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? IHaven.Color.void : SwiftUI.Color.clear,
                    in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .padding(.horizontal, IHaven.Space.s4.rawValue)
    }
}
