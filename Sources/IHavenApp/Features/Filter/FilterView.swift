import SwiftUI

/// 筛选面板（popover 320 × maxHeight 560，对齐 design-tokens filterPanel / 线稿）。
/// 6 分组（category/purity/resolution/ratio/color/sorting），间距 16，复用 Token 与 ChipToggleStyle。
/// 保持 `@Bindable var viewModel` + `onApply` 接线不变。
struct FilterView: View {
    @Bindable var viewModel: BrowseViewModel
    var onApply: () -> Void

    private let resolutionOptions: [(label: String, value: String)] = [
        ("不限", ""), ("≥1080p", "1920x1080"), ("≥1440p", "2560x1440"),
        ("≥4K", "3840x2160"), ("≥5K", "5120x2880")
    ]
    private let ratioOptions: [(label: String, value: Ratio)] = [
        ("不限", .unspecified), ("16:9", .r16x9), ("16:10", .r16x10),
        ("21:9", .r21x9), ("32:9", .r32x9), ("9:16", .r9x16), ("1:1", .r1x1)
    ]
    private let categoryOptions: [(label: String, value: CategoryFilter)] = [
        ("综合", .general), ("动漫", .anime), ("人物", .people)
    ]
    private let sortingOptions: [(label: String, value: Sorting)] = [
        ("日期", .dateAdded), ("相关", .relevance), ("浏览", .views),
        ("收藏", .favorites), ("排行", .toplist), ("随机", .random)
    ]
    private let palette: [(label: String, hex: String)] = [
        ("红", "e23b3b"), ("橙", "ff8c1a"), ("黄", "f5d300"), ("绿", "3bae3b"),
        ("青", "1aa3a3"), ("蓝", "3b6fe2"), ("紫", "9b3be2"), ("粉", "e23b9b"),
        ("棕", "8a5a2b"), ("灰", "808080"), ("黑", "000000"), ("白", "ffffff")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IHaven.Space.s6.rawValue) {
                Text("筛选").font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
                categoryGroup
                purityGroup
                SingleSelectChips(title: "分辨率", options: resolutionOptions, selection: $viewModel.query.atleast)
                SingleSelectChips(title: "比例", options: ratioOptions, selection: $viewModel.query.ratio)
                colorGroup
                sortingGroup
                Button { onApply() } label: { Text("应用").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(IHaven.Space.s6.rawValue)
        }
        .frame(width: 320, height: 560)
        .background(IHaven.Color.bg)
    }

    private var categoryGroup: some View {
        GroupBox("分类") {
            Picker("", selection: $viewModel.query.categories) {
                ForEach(categoryOptions, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var purityGroup: some View {
        GroupBox("纯度（purity）") {
            HStack(spacing: 8) {
                PurityChip("SFW", isOn: $viewModel.query.purity.sfw)
                PurityChip("Sketchy", isOn: $viewModel.query.purity.sketchy)
                // NSFW 档位按 L3 门禁灰置（默认关，需探测授权后放开）
                PurityChip("NSFW", isOn: $viewModel.query.purity.nsfw, disabled: true)
            }
        }
    }

    private var colorGroup: some View {
        GroupBox("颜色") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                ForEach(palette, id: \.hex) { c in
                    let selected = viewModel.query.color == c.hex
                    Button {
                        viewModel.query.color = selected ? "" : c.hex
                    } label: {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex8: c.hex) ?? .gray))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(selected ? IHaven.Color.accent : SwiftUI.Color.clear, lineWidth: 2))
                            .overlay(Circle().stroke(IHaven.Color.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(c.label)
                }
            }
        }
    }

    private var sortingGroup: some View {
        GroupBox("排序") {
            Picker("", selection: $viewModel.query.sorting) {
                ForEach(sortingOptions, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - 纯度 chip（复用 ChipToggleStyle）

    private struct PurityChip: View {
        let label: String
        @Binding var isOn: Bool
        var disabled: Bool = false
        init(_ label: String, isOn: Binding<Bool>, disabled: Bool = false) {
            self.label = label
            self._isOn = isOn
            self.disabled = disabled
        }
        var body: some View {
            Toggle(label, isOn: $isOn).disabled(disabled).toggleStyle(ChipToggleStyle())
        }
    }

    /// 自定义 chip 风格 Toggle（选中高亮 + 圆角胶囊；灰置态降级视觉并禁止切换）。
    private struct ChipToggleStyle: ToggleStyle {
        @Environment(\.isEnabled) private var isEnabled
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? IHaven.Color.accent : IHaven.Color.fg2)
                configuration.label.font(IHaven.Font.system(.sm))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(IHaven.Color.fg2)
            .background(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                .fill(configuration.isOn ? IHaven.Color.accent.opacity(0.12) : IHaven.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                .stroke(configuration.isOn ? IHaven.Color.accent : SwiftUI.Color.clear, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        }
    }

    /// 单选 chip 组（分辨率/比例），选中即写入 binding。
    private struct SingleSelectChips<T: Equatable>: View {
        let title: String
        let options: [(label: String, value: T)]
        @Binding var selection: T
        var body: some View {
            GroupBox(title) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 160))], spacing: 8) {
                    ForEach(options, id: \.label) { opt in
                        let selected = selection == opt.value
                        Button { selection = opt.value } label: {
                            Text(opt.label).font(IHaven.Font.system(.sm))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .foregroundStyle(selected ? IHaven.Color.accent : IHaven.Color.fg2)
                                .background(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                                    .fill(selected ? IHaven.Color.accent.opacity(0.12) : IHaven.Color.surface))
                                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                                    .stroke(selected ? IHaven.Color.accent.opacity(0.34) : SwiftUI.Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
