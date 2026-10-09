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

/// 空态 / 错误态 / Toast（对齐线稿占位与反馈）。
func browseEmptyState(title: String, body: String, action: String, onAction: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Text(title).font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(body).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 360)
        Button(action: onAction) { Text(action) }.buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

func browseErrorState(_ msg: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(IHaven.Color.danger)
        Text("加载失败").font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
        Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            .multilineTextAlignment(.center).frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

func browseToastView(_ msg: String) -> some View {
    Text(msg).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.hudFg)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(IHaven.Color.hudBg, in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue).stroke(IHaven.Color.border))
        .padding(.bottom, 16)
}
