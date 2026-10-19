import SwiftUI

/// 标签 chip 的自动换行布局：按各 chip 自身理想尺寸排布，放不下就换行。
///
/// 不用 `LazyVGrid` 固定列数 —— 标签名长短差一倍（"anime" vs "digital art"），
/// 固定列会在长标签上截断、短标签上留大片空档。
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.replacingUnspecifiedDimensions().width
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize.zero
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 分组与属性行

/// 分组标题：11pt medium / tracking +0.66 / muted，右侧可挂一个动作（TAGS 的「更多类似」）。
func detailSectionHeader<Trailing: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack(spacing: IHaven.Space.s4.rawValue) {
        Text(title)
            .font(.system(size: IHaven.Font.Size.xs.rawValue, weight: IHaven.Font.weightEmphasize))
            .tracking(0.66)
            .foregroundStyle(IHaven.Color.muted)
        Spacer(minLength: 0)
        trailing()
    }
}

/// 属性行：高 28，**标签列固定 72pt** 左对齐，值区占满剩余并对齐到同一 x。
/// 值区样式交由调用方给（多数是 12pt mono `fg`，「时间」是 muted）。
func detailPropertyRow<Value: View>(_ label: LocalizedStringKey,
                                   @ViewBuilder value: () -> Value) -> some View {
    HStack(spacing: 0) {
        Text(label)
            .font(IHaven.Font.system(.xs))
            .foregroundStyle(IHaven.Color.fg2)
            .frame(width: 72, alignment: .leading)
        value().frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 28)
}

/// 属性行的等值文本：12pt mono `fg`。
func detailMonoText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: IHaven.Font.Size.sm.rawValue, design: .monospaced))
        .foregroundStyle(IHaven.Color.fg)
}

// MARK: - 数值格式化

/// `file_type`（`image/jpeg`）→ `JPEG`：取子类型大写（DESIGN §7.1：去掉 `image/` 前缀）。
func detailFileTypeLabel(_ fileType: String) -> String {
    let sub = fileType.split(separator: "/").last.map(String.init) ?? ""
    return (sub.isEmpty ? fileType : sub).uppercased()
}

/// 字节数 → `953.4 KiB` / `4.5 MB`（`file_size` 的单位是**字节**，不是 KB）。
func detailByteString(_ bytes: Int) -> String {
    let kib = 1024.0
    return bytes < 1_048_576
        ? String(format: "%.1f KiB", Double(bytes) / kib)
        : String(format: "%.1f MB", Double(bytes) / kib / kib)
}

/// 千分位计数（浏览 / 收藏）。
func detailCountString(_ count: Int) -> String { count.formatted() }

/// `created_at` 是 `"2026-09-22 07:53:43"` 这种**空格分隔**字符串，不是 ISO8601 ——
/// 必须按固定格式解析；7 天内给相对时间，更早给日期。
func detailDateText(_ createdAt: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let date = parser.date(from: createdAt) else { return createdAt }
    if Date.now.timeIntervalSince(date) < 7 * 86_400 {
        return date.formatted(.relative(presentation: .numeric))
    }
    return date.formatted(.dateTime.year().month().day())
}

/// 本地文件的时间（导入项，来源是文件系统的创建 / 修改时间）。读不到就给 `—`，不留空行。
func detailFileDateText(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(.dateTime.year().month().day().hour().minute())
}

/// 分类值 → 展示文案（枚举外的值一律落到「一般」，不臆造新分类）。
func detailCategoryLabel(_ category: String) -> LocalizedStringKey {
    switch category {
    case "anime": "动漫"
    case "people": "人物"
    default: "一般"
    }
}

// MARK: - 色板条 / 来源行 / 短链接条

/// 色板条：268×24，`base.colors`（恒 5 个 hex）均分 5 格，无间距、首末圆角、1px `borderSoft` 描边。
func detailColorStrip(colors: [String]) -> some View {
    HStack(spacing: 0) {
        ForEach(colors.indices, id: \.self) { index in
            Color(nsColor: NSColor(hex8: colors[index]) ?? .gray)
        }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 24)
    .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
        .stroke(IHaven.Color.borderSoft, lineWidth: 1))
}

/// 来源链接行：第一行可点（focus 蓝，hover 加下划线），第二行给出 host。
/// `source` 为**空串**（wallhaven 对无来源壁纸的返回值）时整块不渲染。
struct DetailSourceRow: View {
    let url: URL
    @Environment(\.openURL) private var openURL
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { openURL(url) } label: {
                Text(verbatim: url.absoluteString)
                    .font(IHaven.Font.system(.sm))
                    .foregroundStyle(IHaven.Color.focus)
                    .underline(hovered)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            Text(verbatim: url.host ?? "")
                .font(IHaven.Font.system(.xs))
                .foregroundStyle(IHaven.Color.fg2)
        }
    }
}

/// 底部整宽短链接条：300×32（**不受 268 内容宽限制**），整行点击 = 拷贝。
/// 用 `verbatim`：短链是数据不是文案，不该进本地化表。
@MainActor
func detailShortLinkBar(url: URL, onCopy: @escaping () -> Void) -> some View {
    Button(action: onCopy) {
        Text(verbatim: url.absoluteString)
            .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
            .foregroundStyle(IHaven.Color.fg2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IHaven.Space.s6.rawValue)
            .frame(height: IHaven.Layout.statusBarHeight)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(IHaven.Color.bgChrome)
    .overlay(alignment: .top) { Rectangle().fill(IHaven.Color.border).frame(height: 1) }
}
