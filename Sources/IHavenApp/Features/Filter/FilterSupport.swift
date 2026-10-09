import SwiftUI

// MARK: - 纯度 chip

/// 纯度三档纯文字胶囊（filter-panel.svg §2）。
/// 线稿是纯文字、无图标的胶囊：90×28 / r6 / 11pt medium 居中，选中走 accent 淡底 + 淡描边。
struct PurityTextChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
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
                Text(group.label)
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
        .help(group.label)
    }

    /// 把 `drawWidth:drawHeight` 等比塞进 38×26，长边贴框。
    private var drawSize: CGSize {
        let scale = min(Self.boxMaxWidth / group.drawWidth, Self.boxMaxHeight / group.drawHeight)
        return CGSize(width: group.drawWidth * scale, height: group.drawHeight * scale)
    }
}

// MARK: - 精确分辨率行

/// 精确分辨率下拉（filter-panel.svg §3 第 2 行）：整行 h28 / r6 / surface 底 + border 描边。
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
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(IHaven.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(IHaven.Color.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }

    /// 折叠态/菜单项统一文案：unspecified 显示「不限」，其余把 `1920x1080` 排成「1920 × 1080」。
    private func title(for resolution: Resolution) -> String {
        resolution == .unspecified ? "不限" : resolution.rawValue.replacingOccurrences(of: "x", with: " × ")
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

    var help: String {
        switch self {
        case .none: return "不限"
        case .hex(let hex): return "#" + hex
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
