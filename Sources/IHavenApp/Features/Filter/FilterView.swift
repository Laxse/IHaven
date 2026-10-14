import SwiftUI

/// 筛选面板（工具栏下 popover，320 × maxHeight 560，对齐 filter-panel.svg）。
/// 6 分组：分类 / 纯度 / 分辨率 / 比例 / 色调 / 排序，组间距 16，控件在 288pt 内容宽内左对齐。
///
/// [!] 分段控件必须自绘：原生 `.pickerStyle(.segmented)` 的最小宽度由标签字宽决定，
///     分辨率 6 档实测 ≈384pt（288 放不下），会把整个 VStack 撑到 384 → popover 居中裁掉左右各 32pt：
///     组标题（x=16）被整条裁没、每行左端少一项、行右侧留空 —— 实测截图与线稿的差异全部来自这一条。
///     线稿给的就是自绘规格：容器 h24 / r6 / 等宽项（分类·排序 72pt，分辨率 48pt）、选中项为内缩药丸。
struct FilterView: View {
    @Bindable var viewModel: BrowseViewModel
    /// 「完成」按钮：仅收起 popover。筛选为即时生效（见 `BrowseViewModel.scheduleFilterReload`，150ms 防抖）。
    var onApply: () -> Void

    /// 最低分辨率 6 档（绑定 `atleast`，值为下发给 API 的 "WxH" 串）；线稿 6 项 × 48pt。
    /// label 用 `LocalizedStringKey`：存成 `String` 会在编译期固化，永远查不到 Localizable.strings。
    private let atleastOptions: [(label: LocalizedStringKey, value: String)] = [
        ("不限", ""), ("≥1080p", "1920x1080"), ("≥1440p", "2560x1440"),
        ("≥4K", "3840x2160"), ("≥5K", "5120x2880"), ("超宽", "3440x1440")
    ]

    /// 6 列 × 24px + 5 × 8px = 184px，小于内容宽 288px；线稿里色格左对齐占 184px，
    /// 固定宽度可避免 LazyVGrid 把剩余空间均摊到列上。
    private let paletteColumns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6)
    private let paletteGridWidth: CGFloat = 184

    var body: some View {
        VStack(spacing: 0) {
            // 内容高 ≈576pt > 视口 516pt（560 - 44 页脚），必然可滚；钉死初始锚点在顶部，
            // 否则面板打开时有可能停在底部、把「分类」组滚出视野。
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("分类") { categoryGroup }
                    group("纯度") { purityGroup }
                    group("分辨率") { resolutionGroup }
                    group("比例") { ratioGroup }
                    group("色调") { colorGroup }
                    group("排序") { sortingGroup }
                }
                .padding(16)
                .frame(width: 320, alignment: .leading)   // 钉死内容宽：任何子控件都不再把面板撑宽
            }
            .defaultScrollAnchor(.top)
            footer
        }
        .frame(width: 320)
        .frame(maxHeight: 560)
        .background(IHaven.Color.bg)
        // 面板内任一维度变更 → 150ms 防抖重查（DESIGN §4.3）；翻页不算筛选变更。
        .onChange(of: viewModel.query) { _, _ in viewModel.scheduleFilterReload() }
    }

    /// 统一组容器：11pt medium muted 标题 + 6pt 间距的无边框控件。
    @ViewBuilder
    private func group<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IHaven.Color.muted)
            content()
        }
    }

    // MARK: - 页脚（线稿未定义；用户要求「确认按钮」，故补一条 44pt 页脚：清除全部 + 完成）

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
            HStack(spacing: 12) {
                Button { viewModel.clearFilters() } label: {
                    Text("清除全部").font(.system(size: 12)).foregroundStyle(IHaven.Color.fg2)   // 清除非破坏性，用 fg2（DESIGN §4.3）
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { onApply() } label: {
                    Text("完成")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IHaven.Color.accentOn)
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(IHaven.Color.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .background(IHaven.Color.bg)
    }

    // MARK: - 1. 分类（全部 / 风景 / 动漫 / 人物，各 72pt）

    private var categoryGroup: some View {
        // 元组数组字面量里的字符串会被推断成 String（泛型 + ExpressibleByStringLiteral 推不出
        // LocalizedStringKey），故显式包一层；atleastOptions 因为声明了元素类型，字面量能正确推断。
        FilterSegmented(options: [(value: CategoryFilter.all, label: LocalizedStringKey("全部")),
                                  (value: .general, label: LocalizedStringKey("风景")),
                                  (value: .anime, label: LocalizedStringKey("动漫")),
                                  (value: .people, label: LocalizedStringKey("人物"))],
                        selection: viewModel.query.categories) { viewModel.query.categories = $0 }
    }

    // MARK: - 2. 纯度（三档 chip 90×28 / 间距 9 → 3×90+2×9 = 288）

    /// 三档一律可点（NSFW 不做门禁灰置，ADR-011）。默认档：全年龄 ON + 轻微暗示 ON + NSFW OFF。
    private var purityGroup: some View {
        HStack(spacing: 9) {
            PurityTextChip(title: "全年龄", isOn: $viewModel.query.purity.sfw)
            PurityTextChip(title: "轻微暗示", isOn: $viewModel.query.purity.sketchy)
            PurityTextChip(title: "NSFW", isOn: $viewModel.query.purity.nsfw)
        }
    }

    // MARK: - 3. 分辨率（6 档分段 6×48 + 精确分辨率整行）

    private var resolutionGroup: some View {
        VStack(spacing: 8) {
            FilterSegmented(options: atleastOptions.map { ($0.value, $0.label) },
                            selection: viewModel.query.atleast) { viewModel.query.atleast = $0 }
            ExactResolutionRow(selection: $viewModel.query.resolution)
        }
    }

    // MARK: - 4. 比例（5 格 × 51pt，再点已选中项即取消）

    private var ratioGroup: some View {
        HStack(spacing: 8) {
            ForEach(RatioGroup.all) { item in
                let selected = viewModel.query.ratio == item.ratio
                RatioTile(group: item, isSelected: selected) {
                    viewModel.query.ratio = selected ? .unspecified : item.ratio
                }
            }
        }
    }

    // MARK: - 5. 色调（6×5 = 30 格：首格「不限」、中间 28 个官方色、末格「黑白灰」）

    private var colorGroup: some View {
        LazyVGrid(columns: paletteColumns, spacing: 8) {
            ForEach(FilterPalette.cells) { cell in
                let selected = viewModel.query.color == cell.colorValue
                ColorSwatchCell(cell: cell, isSelected: selected) {
                    viewModel.query.color = selected ? "" : cell.colorValue   // 再点已选中项即取消（与比例组一致）
                }
            }
        }
        .frame(width: paletteGridWidth, alignment: .leading)
    }

    // MARK: - 6. 排序（最新 / 热门 / 收藏最多 / 随机，各 72pt）

    private var sortingGroup: some View {
        FilterSegmented(options: [(value: Sorting.dateAdded, label: LocalizedStringKey("最新")),
                                  (value: .toplist, label: LocalizedStringKey("热门")),
                                  (value: .favorites, label: LocalizedStringKey("收藏最多")),
                                  (value: .random, label: LocalizedStringKey("随机"))],
                        selection: viewModel.query.sorting) { viewModel.query.sorting = $0 }
    }
}
