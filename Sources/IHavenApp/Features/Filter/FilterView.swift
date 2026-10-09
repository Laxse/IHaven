import SwiftUI

/// 筛选面板骨架，对应已批准线框稿 filter-panel.svg。
struct FilterView: View {
    @Bindable var viewModel: BrowseViewModel
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("筛选").font(.title3.bold())
            GroupBox("纯度（purity）") {
                HStack {
                    PurityChip("SFW", isOn: $viewModel.query.purity.sfw)
                    PurityChip("Sketchy", isOn: $viewModel.query.purity.sketchy)
                    // NSFW 档位按 L3 门禁灰置（默认关，需探测授权后放开）
                    PurityChip("NSFW", isOn: $viewModel.query.purity.nsfw, disabled: true)
                }
            }
            GroupBox("比例") {
                Picker("比例", selection: $viewModel.query.ratio) {
                    ForEach(Ratio.allCases, id: \.self) { r in
                        Text(r.rawValue.isEmpty ? "不限" : r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.menu)
            }
            GroupBox("分辨率") {
                Picker("分辨率", selection: $viewModel.query.resolution) {
                    ForEach(Resolution.allCases, id: \.self) { r in
                        Text(r.rawValue.isEmpty ? "不限" : r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.menu)
            }
            Spacer()
            Button("应用", action: onApply).buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 320, height: 420)
    }

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
            Toggle(label, isOn: $isOn)
                .disabled(disabled)
                .toggleStyle(ChipToggleStyle())
        }
    }

    /// 自定义 chip 风格 Toggle（对应线框稿 filter-panel.svg 的纯度三档）。
    /// SwiftUI 无内建 `.chip` 风格，此处自绘：选中高亮 + 圆角胶囊；
    /// 灰置态（NSFW 未授权）通过 `configuration.isEnabled` 降级视觉并禁止切换。
    private struct ChipToggleStyle: ToggleStyle {
        @Environment(\.isEnabled) private var isEnabled
        func makeBody(configuration: Configuration) -> some View {
            let active = configuration.isOn
            HStack(spacing: 6) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                configuration.label
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .onTapGesture {
                if isEnabled { configuration.$isOn.wrappedValue.toggle() }
            }
        }
    }
}
