import SwiftUI

/// 线稿 38pt 标题栏：隐藏系统标题栏（`.windowStyle(.hiddenTitleBar)`）后自绘，对齐 `IHaven.Layout.titlebarHeight`。
/// 左侧预留交通灯空间，底 1px hairline 与 toolbar 同构。仅依赖 Core 设计令牌（ARCH §4 单向依赖），结构体无持有状态。
struct BrowseTitleBar: View {
    var body: some View {
        HStack(spacing: 0) {
            // 交通灯（关闭/最小化/缩放）由系统绘制在窗口左上，预留 ~72px 避免重叠。
            Spacer().frame(width: 72)
            Text("IHaven")
                .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.fg)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IHaven.Layout.titlebarHeight)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
        }
    }
}
