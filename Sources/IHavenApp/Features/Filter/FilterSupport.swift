import SwiftUI

// MARK: - 等宽分段控件（线稿规格：容器 h24 / r6，选中项内缩 1pt 成 70×22 药丸）

/// 自绘分段控件（filter-panel.svg §1 / §3 / §6）。
/// [!] 不用原生 `.pickerStyle(.segmented)`：其最小宽度由标签字宽决定，分辨率 6 档 ≈384pt 撑破 288pt 内容宽，
///     会把整个面板内容撑到 384 并被 popover 居中裁掉左右各 32pt（组标题整条消失、每行左端少一项）。
/// 这里按线稿定格：项等宽（分类/排序 72pt、分辨率 48pt，均由 288pt 均分得到），选中项药丸、未选纯文字。
struct FilterSegmented<Value: Hashable>: View {
    /// label 必须是 `LocalizedStringKey`：声明成 `String` 会把中文在编译期固化，SwiftUI 不再查表。
    let options: [(value: Value, label: LocalizedStringKey)]
    let selection: Value
    var onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { onSelect(option.value) } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? IHaven.Color.fg : IHaven.Color.fg2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selected ? IHaven.Color.surface : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(selected ? IHaven.Color.border : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(1)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(IHaven.Color.surfaceSunken))
    }
}

// MARK: - 纯度 chip

/// 纯度三档纯文字胶囊（filter-panel.svg §2）。
/// 线稿是纯文字、无图标的胶囊：90×28 / r6 / 11pt medium 居中，选中走 accent 淡底 + 淡描边。
struct PurityTextChip: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    /// 锁定态（NSFW 档在设置开关关闭时）：不可勾选，点击走 `onLockedTap` 引导去开启 ——
    /// 「灰置且无处解锁」正是 ADR-011 否决线稿方案的理由，所以锁定态必须给出可达的出口。
    var isLocked = false
    var onLockedTap: () -> Void = {}

    var body: some View {
        Button { isLocked ? onLockedTap() : isOn.toggle() } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? IHaven.Color.accentHover : IHaven.Color.fg2)
                // 定尺 90×28：三档等宽对齐线稿，不随文案长短伸缩
                .frame(width: 90, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? IHaven.Color.accent.opacity(0.12) : IHaven.Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? IHaven.Color.accent.opacity(0.34) : IHaven.Color.borderSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.45 : 1)
        .help(chipHelp)
    }

    /// 锁定态才有提示；未锁定时给空串（空 tooltip 不显示），避免在三元里塞两个字面量。
    private var chipHelp: LocalizedStringKey {
        isLocked ? "需先在设置 · 内容中启用" : ""
    }
}

// MARK: - 比例方块

/// 比例方块（filter-panel.svg §4）：51×56 / r6，格内按 `drawWidth:drawHeight` 等比画描边示意矩形（≤38×26），下方 10pt 标签。
struct RatioTile: View {
    let group: RatioGroup
    var isSelected: Bool
    var onTap: () -> Void

    /// 线稿给格内示意矩形留的最大绘制区，等比缩放到此框内居中。
    private static let boxMaxWidth: CGFloat = 38
    private static let boxMaxHeight: CGFloat = 26

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Rectangle()
                    .stroke(isSelected ? IHaven.Color.accentHover : IHaven.Color.muted, lineWidth: 1)
                    .frame(width: drawSize.width, height: drawSize.height)
                    .frame(width: Self.boxMaxWidth, height: Self.boxMaxHeight)   // 居中于最大框
                Spacer(minLength: 0)
                Text(group.localizedLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? IHaven.Color.accentHover : IHaven.Color.muted)
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(width: 51, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? IHaven.Color.accent.opacity(0.12) : IHaven.Color.surfaceBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? IHaven.Color.accent : IHaven.Color.borderSoft,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(group.localizedLabel)
    }

    /// 把 `drawWidth:drawHeight` 等比塞进 38×26，长边贴框。
    private var drawSize: CGSize {
        let scale = min(Self.boxMaxWidth / group.drawWidth, Self.boxMaxHeight / group.drawHeight)
        return CGSize(width: group.drawWidth * scale, height: group.drawHeight * scale)
    }
}

// MARK: - 精确分辨率行

/// 精确分辨率下拉（filter-panel.svg §3 第 2 行）：288pt 整行 h28 / r6 / surface 底 + border 描边，
/// 左侧标签 + 右侧当前值 + chevron（原生 menu 指示器会多出一个左箭头，故隐藏）。
struct ExactResolutionRow: View {
    @Binding var selection: Resolution

    var body: some View {
        Menu {
            ForEach(Resolution.allCases, id: \.self) { item in
                Button(title(for: item)) { selection = item }
            }
        } label: {
            HStack(spacing: 6) {
                Text("精确分辨率").font(.system(size: 11)).foregroundStyle(IHaven.Color.fg2)
                Spacer(minLength: 0)
                Text(title(for: selection)).font(.system(size: 11)).foregroundStyle(IHaven.Color.meta)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(IHaven.Color.meta)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)          // 撑满 288pt：Menu 默认按标签内容收窄，Spacer 会塌陷
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(IHaven.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(IHaven.Color.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)                      // plain 让标签占满提议宽度（borderlessButton 会收窄成内容宽）
        .menuIndicator(.hidden)                   // 原生指示器会额外多一个左箭头
    }

    /// 折叠态/菜单项统一文案：unspecified 显示「不限」，其余把 `1920x1080` 排成「1920 × 1080」。
    /// 返回 `LocalizedStringKey` 而非 `String`，否则下拉里的文案不会查 Localizable.strings。
    private func title(for resolution: Resolution) -> LocalizedStringKey {
        resolution == .unspecified
            ? "不限"
            : LocalizedStringKey(resolution.rawValue.replacingOccurrences(of: "x", with: " × "))
    }
}

// MARK: - 色调格

/// 色调格类型（filter-panel.svg §5）：首格「不限」→ 28 个官方 hex → 末格「黑白灰」。
enum FilterPaletteCell: Hashable, Identifiable {
    case none
    case hex(String)
    case grayscale

    var id: String {
        switch self {
        case .none: return "none"
        case .hex(let hex): return hex
        case .grayscale: return "grayscale"
        }
    }

    /// 点击该格后写入 `query.color` 的值。
    var colorValue: String {
        switch self {
        case .none: return ""
        case .hex(let hex): return hex
        case .grayscale: return "999999"
        }
    }

    /// 悬停提示。用 `LocalizedStringKey`：`.help()` 收 `String` 时不会查表。
    var help: LocalizedStringKey {
        switch self {
        case .none: return "不限"
        case .hex(let hex): return LocalizedStringKey("#" + hex)
        case .grayscale: return "黑白灰"
        }
    }
}

enum FilterPalette {
    /// wallhaven 官方 28 色，顺序固定（线稿明确「hex 不臆造」，取自官方色板常量）。
    static let hexes: [String] = [
        "660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399",
        "333399", "0066cc", "0099cc", "66cccc", "77cc33", "669900", "336600",
        "666600", "999900", "cccc00", "ffff00", "ffcc33", "ffa500", "ff6600",
        "cc6633", "996633", "663300", "000000", "999999", "cccccc", "ffffff"
    ]

    /// 5×6 = 30 格，视图只遍历这一个数组，不在 body 里手写 30 个视图。
    static let cells: [FilterPaletteCell] =
        [FilterPaletteCell.none] + hexes.map { FilterPaletteCell.hex($0) } + [FilterPaletteCell.grayscale]
}

/// 单格色块：24×24 / r4，选中叠 accent 2px 描边，未选叠 borderSoft 1px。
struct ColorSwatchCell: View {
    let cell: FilterPaletteCell
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            content
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? IHaven.Color.accent : IHaven.Color.borderSoft,
                                lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(cell.help)
    }

    @ViewBuilder
    private var content: some View {
        switch cell {
        case .none:
            ZStack {
                IHaven.Color.surfaceSunken
                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(IHaven.Color.meta)
            }
        case .hex(let hex):
            Color(nsColor: NSColor(hex8: hex) ?? .gray)
        case .grayscale:
            // 三等宽竖条（白 / 中灰 / 黑），代表无彩色筛选
            HStack(spacing: 0) {
                Color.white
                Color(nsColor: NSColor(hex8: "808080") ?? .gray)
                Color.black
            }
        }
    }
}
