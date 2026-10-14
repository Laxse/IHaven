import SwiftUI

/// 分类 / 「更多类似」共用的强调色 chip：高 20、pad 8/4、r6、11pt medium。
///
/// [!] 文字色是 `accentHover` 而非 `accent`：DESIGN v4.2 实测 accent 在 accent.opacity(0.12)
///     底上对比度只有 3.20:1（浅色），不达标；accentHover 为 4.64:1。
struct DetailAccentChip: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: IHaven.Font.Size.xs.rawValue, weight: IHaven.Font.weightEmphasize))
            .foregroundStyle(IHaven.Color.accentHover)
            .padding(.horizontal, IHaven.Space.s4.rawValue)
            .padding(.vertical, IHaven.Space.s2.rawValue)
            .frame(height: 20)
            .background(IHaven.Color.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                .stroke(IHaven.Color.accent.opacity(0.34), lineWidth: 1))
    }
}

/// 纯度 chip：sfw → success / sketchy → warn / nsfw → danger，底 14% 透明度、文字同色系。
struct DetailPurityChip: View {
    let purity: String

    var body: some View {
        Text(title)
            .font(.system(size: IHaven.Font.Size.xs.rawValue, weight: IHaven.Font.weightEmphasize))
            .foregroundStyle(tint)
            .padding(.horizontal, IHaven.Space.s4.rawValue)
            .padding(.vertical, IHaven.Space.s2.rawValue)
            .frame(height: 20)
            .background(tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                .stroke(tint.opacity(0.34), lineWidth: 1))
    }

    private var tint: SwiftUI.Color {
        switch purity {
        case "sfw": IHaven.Color.success
        case "sketchy": IHaven.Color.warn
        default: IHaven.Color.danger
        }
    }

    /// NSFW 是 wallhaven 的官方档位名，不译。
    private var title: LocalizedStringKey {
        switch purity {
        case "sfw": "全年龄"
        case "sketchy": "轻微暗示"
        default: "NSFW"
        }
    }
}

/// 标签 chip：高 22、pad 8/4、**r8**、11pt，底 `surfaceSunken` 字 `fg2`，hover 底→`void` 字→`fg`。
/// 点击 = 用 `+<tag>` 发起搜索（多词标签的空格必须原样保留，换成下划线实测返回 0 条）。
struct DetailTagChip: View {
    let name: String
    var onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            Text(verbatim: name)
                .font(.system(size: IHaven.Font.Size.xs.rawValue))
                .foregroundStyle(hovered ? IHaven.Color.fg : IHaven.Color.fg2)
                .padding(.horizontal, IHaven.Space.s4.rawValue)
                .padding(.vertical, IHaven.Space.s2.rawValue)
                .frame(height: 22)
                .background(hovered ? IHaven.Color.void : IHaven.Color.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(name)
    }
}
