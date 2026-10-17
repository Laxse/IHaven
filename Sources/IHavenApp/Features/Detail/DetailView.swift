import SwiftUI

/// 壁纸详情二级页面 `/wall/:id`（SPEC §8.1）：40pt 页头条 + 大图区 + 右侧 300px 信息栏。
///
/// 本视图**不持有导航栈**：关闭、上下张切换、发起搜索全部由 `BrowseView` 以回调提供
/// （也没有前进栈，故 `⌘]` 不绑定任何行为）。
struct DetailView: View {
    let wallpaper: Wallpaper
    /// 结果集（`←` / `→` 在结果集内切换）；当前项不在其中时两个方向都无效。
    let context: [Wallpaper]
    var onClose: () -> Void
    var onNavigate: (Wallpaper) -> Void
    var onSearch: (String) -> Void
    var onToggleFavorite: () -> Void
    var onMessage: (String) -> Void
    /// 裁剪入口：只**上抛**给 `BrowseView`（那里挂 `.sheet(item:)`）。本视图自己挂模态会被
    /// 父级 `.sheet` 抑制，表现为点了没反应（见 `BrowseView.swift` L24-27）。
    var onCrop: () -> Void

    @State private var state: DetailViewState
    @State private var inspectorVisible = true
    /// 键盘入口依赖焦点：`onKeyPress` 只在被聚焦的子树上触发，故进入详情页时主动把焦点落在根视图。
    @FocusState private var rootFocused: Bool

    init(wallpaper: Wallpaper,
         context: [Wallpaper],
         viewModel: BrowseViewModel,
         onClose: @escaping () -> Void,
         onNavigate: @escaping (Wallpaper) -> Void,
         onSearch: @escaping (String) -> Void,
         onToggleFavorite: @escaping () -> Void,
         onMessage: @escaping (String) -> Void,
         onCrop: @escaping () -> Void) {
        self.wallpaper = wallpaper
        self.context = context
        self.onClose = onClose
        self.onNavigate = onNavigate
        self.onSearch = onSearch
        self.onToggleFavorite = onToggleFavorite
        self.onMessage = onMessage
        self.onCrop = onCrop
        _state = State(initialValue: viewModel.makeDetailState(wallpaper: wallpaper))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                DetailImageView(wallpaper: wallpaper,
                                failure: state.detailFailure,
                                message: state.detailMessage,
                                retryable: state.detailRetryable,
                                onRetry: { Task { await state.retryDetail() } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(IHaven.Color.border).frame(width: 1)
                if inspectorVisible {
                    DetailInspector(wallpaper: wallpaper,
                                    detail: state.detail,
                                    state: state,
                                    onSearch: onSearch,
                                    onMessage: onMessage,
                                    onCrop: onCrop)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IHaven.Color.bg)
        .task { await state.loadDetail(); rootFocused = true }
        // 键盘入口：视图必须可聚焦，按键才会走到 `onKeyPress`；聚焦环对整块内容区无意义，故关掉。
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handle($0) }
    }

    /// 页头条（40pt，横跨主区全宽）：最左返回，中间 `id · 分辨率`，最右信息栏开关。
    /// 不做面包屑：侧栏已有选中态，第二级只是 id，无信息增量。
    private var header: some View {
        HStack(spacing: 0) {
            BrowseIconButton(systemName: "chevron.left", help: "返回") { onClose() }
                .padding(.leading, IHaven.Space.s6.rawValue)
            Spacer(minLength: 0)
        }
        .frame(height: IHaven.Layout.detailHeaderHeight)
        .overlay {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text(verbatim: wallpaper.id).foregroundStyle(IHaven.Color.muted)
                Text("·").foregroundStyle(IHaven.Color.muted)
                Text("\(wallpaper.width) × \(wallpaper.height)").foregroundStyle(IHaven.Color.fg2)
            }
            .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
        }
        .overlay(alignment: .trailing) {
            BrowseIconButton(systemName: "sidebar.trailing", help: "显示 / 隐藏信息栏") {
                inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .padding(.trailing, IHaven.Space.s6.rawValue)
        }
    }

    // MARK: - 键盘

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            // 不再有缩放档位：大图恒为「完整显示」，Esc 没有中间层可退，直接关闭详情页。
            onClose(); return .handled
        case .leftArrow:
            step(-1); return .handled
        case .rightArrow:
            step(1); return .handled
        case "[" where press.modifiers == .command:
            onClose(); return .handled
        case "d" where press.modifiers == .command:
            onToggleFavorite(); return .handled
        default:
            return .ignored
        }
    }

    /// `←` / `→`：在结果集内切上 / 下一张（不跨页，也不构造前进栈）。
    private func step(_ delta: Int) {
        guard let index = context.firstIndex(where: { $0.id == wallpaper.id }),
              context.indices.contains(index + delta) else { return }
        onNavigate(context[index + delta])
    }
}
