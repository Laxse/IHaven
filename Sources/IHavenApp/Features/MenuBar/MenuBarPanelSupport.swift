import SwiftUI

/// 菜单栏面板的零件库（PRD F3）。
///
/// 拆出去的唯一理由：`MenuBarPanelView.swift` 重做后必然顶到 ADR-009 的 300 行上限
/// （`scripts/convention-gate.sh:26-31`）。先例见 `Features/Browse/BrowseSupport.swift`：
/// 顶层函数 + 零件 struct，不为一个调用点造抽象层。

// MARK: - 状态行

/// 面板内联状态行的数据源。
///
/// 面板看不到主窗口的 toast（两个独立 scene，toast 挂在主窗口 overlay 上），设壁纸的结果
/// 必须自己显示出来，否则点「下一张」没有任何反馈。
/// `nil` = 成功 / 非 nil = `error.localizedDescription` 这个区分是现成的（与主窗口 toast
/// 同一口径），所以成功走 `success`、失败走 `danger`，不再一律中性色 —— 中性色会让
/// 「设壁纸失败」看起来和成功一样，用户以为已经换好了。
enum PanelStatus {
    case ok(String)
    case failed(String)

    var text: String {
        switch self { case .ok(let t), .failed(let t): return t }
    }

    var tint: Color {
        switch self { case .ok: IHaven.Color.success; case .failed: IHaven.Color.danger }
    }

    var symbol: String {
        switch self { case .ok: "checkmark.circle"; case .failed: "exclamationmark.triangle" }
    }
}

@MainActor
func panelStatusLine(_ status: PanelStatus) -> some View {
    HStack(spacing: IHaven.Space.s3.rawValue) {
        Image(systemName: status.symbol)
            .font(.system(size: 12))
            .foregroundStyle(status.tint)
        Text(status.text)
            .font(IHaven.Font.system(.xs))
            .foregroundStyle(status.tint)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, IHaven.Space.s5.rawValue)
    .padding(.bottom, IHaven.Space.s4.rawValue)
}

// MARK: - 缩略图

/// 当前壁纸卡的缩略图（72×44 横条）。
@MainActor
func panelThumb(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
    ThumbnailImage(url: url)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
}

/// 收藏格缩略图：1:1 正方形。
///
/// ⚠️ 早先是 60×38 的固定横条，竖图收藏会被压成一条完全认不出的色带 —— 收藏里竖图
/// 占比很高（手机 / 平板壁纸），这是这一格最实际的失效模式。
@MainActor
func panelSquareThumb(_ url: URL?, size: CGFloat) -> some View {
    ThumbnailImage(url: url)
        .aspectRatio(1, contentMode: .fill)
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
}

// MARK: - 当前壁纸卡

/// 当前壁纸卡：整块可点（= 打开主窗口），右侧 chevron 暗示可点。
/// 没有「已设置」记录时调用方整块不渲染 —— 面板是快捷入口，不留 40pt 的空位。
@MainActor
struct PanelCurrentCard: View {
    let item: AppliedWallpaper
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: IHaven.Space.s4.rawValue) {
                panelThumb(item.thumbnailURL, width: 72, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("当前壁纸")
                        .font(IHaven.Font.system(.xs))
                        .foregroundStyle(IHaven.Color.meta)
                    // `verbatim:`：id / 分辨率是数据不是文案，走 LocalizedStringKey 会去查表。
                    Text(verbatim: item.resolutionText ?? item.id)
                        // 这一行是这个面板里唯一有信息量的具体数据，比搜索框占位文字还弱就不对了。
                        .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
                        .foregroundStyle(IHaven.Color.fg)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(IHaven.Color.meta)
            }
            .padding(IHaven.Space.s5.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? IHaven.Color.surfaceOverlay : IHaven.Color.surface,
                        in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(IHaven.Motion.fast, value: hover)
    }
}

// MARK: - 操作行

/// 图标钮（32×32，无描边）：「上一张 / 下一张」。
///
/// ⚠️ **为什么无描边**：一排放三个带框按钮视觉太重，会把最高频的「换一张」压成同级。
/// 只在 hover 时给 `surface` 填充 —— 有反馈，但不抢主按钮。
/// ⚠️ **命中区 32**：`IHaven.Layout.hitPointerMin` 是 28，图标本身只有十几 pt，
/// 不给外框 + `.contentShape(Rectangle())` 的话实际可点区域只有字形那一小块。
@MainActor
struct PanelIconButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let disabled: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(IHaven.Color.fg)
                .frame(width: 32, height: 32)
                .background(hover && !disabled ? IHaven.Color.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 禁用是**正确的可供性**（没有结果集可翻），但禁用本身不解释原因 —— 光有一个
        // 点不动的箭头，用户只会反复点。`.help` 把原因说清楚。
        .disabled(disabled)
        .help(help)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hover = $0 }
        .animation(IHaven.Motion.fast, value: hover)
    }
}

/// 图标位：进行中换成不确定态 `ProgressView` 并锁定槽宽，按钮宽度与文案位置都不跳
/// （同 `Features/Detail/DetailActions.swift:103`，多了锁宽这一步 —— 那里按钮是整行的，
/// 这里「换一张」的宽度取决于图标，不锁就会在点击瞬间抖一下）。
@MainActor
@ViewBuilder
func panelLeadingIcon(busy: Bool, systemName: String) -> some View {
    if busy {
        ProgressView().controlSize(.small)
            .frame(width: IHaven.Icon.sm, height: IHaven.Icon.sm)
    } else {
        Image(systemName: systemName)
            .font(.system(size: IHaven.Icon.sm))
            .frame(width: IHaven.Icon.sm, height: IHaven.Icon.sm)
    }
}

/// 「换一张」：面板里最高频的操作（PRD F3「一键换壁纸」），accent 实底 + 占满剩余宽度。
/// 忙碌时图标位换成转圈、文案变「正在设置…」，让用户知道是慢而不是没反应。
@MainActor
struct PanelShuffleButton: View {
    let busy: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                panelLeadingIcon(busy: busy, systemName: "shuffle")
                // 显式 LocalizedStringKey：三元里的字面量会被推断成 String，编译期固化后查不到表
                // （`Features/Detail/DetailActions.swift:26`）。
                Text(busy ? LocalizedStringKey("正在设置…") : LocalizedStringKey("换一张"))
            }
            .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
            .foregroundStyle(IHaven.Color.accentOn)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(hover && !busy ? IHaven.Color.accentHover : IHaven.Color.accent,
                        in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        // 提示全局热键：App 不在前台也能 ⌥⌘S 换一张（#68，需辅助功能授权）。写在这里而不是
        // 只写进文档，是因为这个按钮是用户唯一会主动寻找「换壁纸」入口的地方。
        .help("换一张（⌥⌘S）")
        .onHover { hover = $0 }
        .animation(IHaven.Motion.fast, value: hover)
    }
}

// MARK: - 收藏格

/// 收藏格：1:1 正方形，hover 时描边转 accent。
@MainActor
struct PanelFavoriteTile: View {
    let favorite: Favorite
    let size: CGFloat
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            panelSquareThumb(favorite.thumbnailURL, size: size)
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                    .stroke(hover ? IHaven.Color.accent : IHaven.Color.borderSoft, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("设为壁纸")
        .onHover { hover = $0 }
        .animation(IHaven.Motion.fast, value: hover)
    }
}
