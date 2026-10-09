import SwiftUI

/// 筛选面板（工具栏下 popover，320 × maxHeight 560，对齐 filter-panel.svg）。
/// 6 分组：分类 / 纯度 / 分辨率 / 比例 / 色调 / 排序，组间距 16。
/// 线稿是「11pt muted 组标题 + 裸控件」，不用 GroupBox；改动即时生效，面板内不放「应用」按钮。
struct FilterView: View {
    @Bindable var viewModel: BrowseViewModel
    /// 保留接线：BrowseView:28 仍传入闭包。即时生效模式下由外部负责收起 popover，
    /// 面板内不调用它 —— 签名不动是为了不破坏既有调用方。
    var onApply: () -> Void

    /// 最低分辨率 6 档（绑定 `atleast`，值为下发给 API 的 "WxH" 串）。
    private let atleastOptions: [(label: String, value: String)] = [
        ("不限", ""), ("≥1080p", "1920x1080"), ("≥1440p", "2560x1440"),
        ("≥4K", "3840x2160"), ("≥5K", "5120x2880"), ("超宽", "3440x1440")
    ]

    /// 6 列 × 24px + 5 × 8px = 184px，小于内容宽 288px；线稿里色格左对齐占 184px，
    /// 固定宽度可避免 LazyVGrid 把剩余空间均摊到列上。
    private let paletteColumns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6)
    private let paletteGridWidth: CGFloat = 184

    var body: some View {
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
        }
        .frame(width: 320)
        .frame(maxHeight: 560)
        .background(IHaven.Color.bg)
    }

    /// 统一组容器：11pt medium muted 标题 + 6pt 间距的无边框控件。
    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IHaven.Color.muted)
            content()
        }
    }

    // MARK: - 1. 分类

    /// 原生 macOS segmented：全部 / 风景 / 动漫 / 人物（线稿 h24 / r6，保持系统控件不自绘）。
    private var categoryGroup: some View {
        Picker("", selection: $viewModel.query.categories) {
            Text("全部").tag(CategoryFilter.all)
            Text("风景").tag(CategoryFilter.general)
            Text("动漫").tag(CategoryFilter.anime)
            Text("人物").tag(CategoryFilter.people)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - 2. 纯度

    /// 三档一律可点（NSFW 不再做门禁灰置）。默认档为全年龄 ON + 轻微暗示 ON + NSFW OFF。
    private var purityGroup: some View {
        HStack(spacing: 8) {
            PurityTextChip(title: "全年龄", isOn: $viewModel.query.purity.sfw)
            PurityTextChip(title: "轻微暗示", isOn: $viewModel.query.purity.sketchy)
            PurityTextChip(title: "NSFW", isOn: $viewModel.query.purity.nsfw)
        }
    }

    // MARK: - 3. 分辨率

    /// 上排 6 档 segmented 预设，下排「精确分辨率」下拉（封闭枚举 7 值）。
    private var resolutionGroup: some View {
        VStack(spacing: 8) {
            Picker("", selection: $viewModel.query.atleast) {
                ForEach(atleastOptions, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ExactResolutionRow(selection: $viewModel.query.resolution)
        }
    }

    // MARK: - 4. 比例

    /// 5 组归并后的可视化方块；再点已选中项即取消（置 .unspecified）。
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

    // MARK: - 5. 色调

    /// 5×6 = 30 格：首格「不限」、中间 28 个官方色、末格「黑白灰」。
    private var colorGroup: some View {
        LazyVGrid(columns: paletteColumns, spacing: 8) {
            ForEach(FilterPalette.cells) { cell in
                let selected = viewModel.query.color == cell.colorValue
                ColorSwatchCell(cell: cell, isSelected: selected) {
                    viewModel.query.color = cell.colorValue
                }
            }
        }
        .frame(width: paletteGridWidth, alignment: .leading)
    }

    // MARK: - 6. 排序

    /// 原生 macOS segmented：最新 / 热门 / 收藏最多 / 随机。
    private var sortingGroup: some View {
        Picker("", selection: $viewModel.query.sorting) {
            Text("最新").tag(Sorting.dateAdded)
            Text("热门").tag(Sorting.toplist)
            Text("收藏最多").tag(Sorting.favorites)
            Text("随机").tag(Sorting.random)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
