import SwiftUI

/// 侧栏导航项（对齐线稿 SF Symbols 对照）。
enum NavItem: Hashable {
    case discover, landscape, anime, people, favorites, wallpaperSet, live, `import`, settings, key
    var label: String {
        switch self {
        case .discover: "发现"; case .landscape: "风景"; case .anime: "动漫"; case .people: "人物"
        case .favorites: "收藏"; case .wallpaperSet: "已设置"; case .live: "动态壁纸"
        case .import: "导入…"; case .settings: "设置"; case .key: "密钥"
        }
    }
    var icon: String {
        switch self {
        case .discover: "square.grid.2x2"; case .landscape: "mountain.2.fill"; case .anime: "sparkles"
        case .people: "person.fill"; case .favorites: "star"; case .wallpaperSet: "display.2"
        case .live: "play.circle"; case .import: "square.and.arrow.down"
        case .settings: "gearshape"; case .key: "key"
        }
    }
}

/// 筛选 chip 摘要生成（对齐线稿 toolbar 的筛选 chip 摘要）。
func browseActiveFilterChips(query: BrowseQuery) -> [String] {
    var r: [String] = []
    if !query.atleast.isEmpty { r.append(browseResolutionLabel(query.atleast)) }
    if query.ratio != .unspecified { r.append("比例: \(query.ratio.rawValue)") }
    if !query.color.isEmpty { r.append("色: #\(query.color)") }
    if query.purity != PurityFilter(sfw: true, sketchy: false, nsfw: false) { r.append("纯度") }
    return r
}

func browseResolutionLabel(_ atleast: String) -> String {
    switch atleast {
    case "1920x1080": return "≥1080p"
    case "2560x1440": return "≥1440p"
    case "3840x2160": return "≥4K"
    case "5120x2880": return "≥5K"
    default: return "≥\(atleast)"
    }
}

/// 工具栏筛选 chip 摘要 + 「清除全部筛选」（对齐线稿 summaryBar）。
@MainActor
func browseFilterChips(query: BrowseQuery, onClear: @escaping () -> Void) -> some View {
    let chips = browseActiveFilterChips(query: query)
    return HStack(spacing: 6) {
        ForEach(chips, id: \.self) { chip in
            Text(chip)
                .font(IHaven.Font.system(.xs, IHaven.Font.weightEmphasize))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(IHaven.Color.accent)
                .background(IHaven.Color.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(IHaven.Color.accent.opacity(0.34)))
        }
        if !chips.isEmpty {
            Button(action: onClear) {
                Text("清除全部筛选").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.focus)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 未实现功能的占位态（动态壁纸 / 导入）。
@MainActor
func browsePlaceholder(item: NavItem) -> some View {
    VStack(spacing: 12) {
        Image(systemName: item.icon).font(.system(size: 40)).foregroundStyle(IHaven.Color.meta)
        Text(item.label).font(IHaven.Font.system(.lg, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
        Text("此功能将在后续版本提供。").font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// 空态 / 错误态 / Toast（对齐线稿占位与反馈）。
@MainActor
func browseEmptyState(title: String, body: String, action: String, onAction: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Text(title).font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(body).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 360)
        Button(action: onAction) { Text(action) }.buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
func browseErrorState(_ msg: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(IHaven.Color.danger)
        Text("加载失败").font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
func browseToastView(_ msg: String) -> some View {
    Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.hudFg)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(IHaven.Color.hudBg, in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue).stroke(IHaven.Color.border))
        .padding(.bottom, 16)
}
