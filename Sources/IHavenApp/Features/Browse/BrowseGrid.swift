import NukeUI
import SwiftUI

/// 真 masonry 瀑布流：按各卡真实宽高比分配列，列宽 240–340 / 沟槽 8（design-tokens grid）。
/// 宽度用 `onGeometryChange` 测量（作用在内容 VStack 上，不破坏 ScrollView 的滚动高度判定）；
/// 每列用普通 VStack —— LazyVStack 在非滚动的 HStack 内会塌缩为 0 高。
struct MasonryView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let minColumnWidth: CGFloat
    let aspectRatio: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content
    @State private var width: CGFloat = 0

    private var columnCount: Int {
        guard width > 0 else { return 1 }
        let raw = Int((width + spacing) / (minColumnWidth + spacing))
        return max(1, min(6, raw))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if width > 0 {
                let cols = columnCount
                let colWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
                let buckets = distribute(into: cols, colWidth: colWidth)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { c in
                        VStack(spacing: spacing) {
                            ForEach(buckets[c]) { item in
                                content(item)
                                    .frame(width: colWidth, height: cardHeight(item, colWidth), alignment: .top)
                                    .clipped()
                            }
                        }
                        .frame(width: colWidth, alignment: .top)
                    }
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if abs(newWidth - width) > 0.5 { width = newWidth }
        }
    }

    private func distribute(into cols: Int, colWidth: CGFloat) -> [[Item]] {
        var buckets: [[Item]] = Array(repeating: [], count: cols)
        var heights = Array(repeating: CGFloat(0), count: cols)
        for item in items {
            let idx = heights.enumerated().min(by: { $0.element < $1.element })!.offset
            buckets[idx].append(item)
            heights[idx] += cardHeight(item, colWidth) + spacing
        }
        return buckets
    }

    /// 卡片高度 = 列宽 / 真实宽高比；异常比例（0 / NaN / 负）回退 1.4，避免 0 高卡片。
    private func cardHeight(_ item: Item, _ colWidth: CGFloat) -> CGFloat {
        let ar = aspectRatio(item)
        return ar.isFinite && ar > 0 ? colWidth / ar : colWidth * 1.4
    }
}

/// 瀑布流图片卡：外部由 MasonryView 给定固定（列宽 × 计算高度），图片 fill 填满并裁切。
/// Liquid Glass 仅用于侧栏/工具栏，卡片为内容层，禁止玻璃（DESIGN liquidGlass F1）。
struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isFavorite: Bool
    var onToggleFavorite: () -> Void
    var onSetWallpaper: () -> Void
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ThumbnailImage(url: wallpaper.thumbs.small)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                if hovered { hoverOverlay.transition(.opacity) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(IHaven.Motion.fast, value: hovered)
    }

    private var hoverOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.78)],
                          startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(wallpaper.width) × \(wallpaper.height)")
                    .font(.system(size: IHaven.Font.Size.sm.rawValue, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 1)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(IHaven.Color.accent)
                    Text("\(wallpaper.favorites)").font(IHaven.Font.system(.sm)).foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(8)
            HStack(spacing: 6) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? IHaven.Color.accent : .white)
                }
                .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                .buttonStyle(.borderless)
                Button(action: onSetWallpaper) {
                    Image(systemName: "desktopcomputer").foregroundStyle(.white)
                }
                .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                .buttonStyle(.borderless)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

/// 收藏卡：复用瀑布流布局，缩略图按 16:10 估算（Favorite 不持有尺寸），hover 浮层仅含快捷动作。
struct FavoriteCard: View {
    let favorite: Favorite
    var onToggleFavorite: () -> Void
    var onSetWallpaper: () -> Void
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ThumbnailImage(url: favorite.thumbnailURL)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                if hovered {
                    ZStack {
                        LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.6)],
                                      startPoint: .top, endPoint: .bottom)
                        HStack(spacing: 6) {
                            Button(action: onToggleFavorite) {
                                Image(systemName: "heart.fill").foregroundStyle(IHaven.Color.accent)
                            }
                            .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                            .buttonStyle(.borderless)
                            Button(action: onSetWallpaper) {
                                Image(systemName: "desktopcomputer").foregroundStyle(.white)
                            }
                            .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                    }
                    .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(IHaven.Motion.fast, value: hovered)
    }
}

/// 缩略图视图：封装 NukeUI.LazyImage，将 Nuke 类型隔离在 Infrastructure 渲染边界之外。
struct ThumbnailImage: View {
    let url: URL?
    var body: some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    Color(IHaven.Color.surfaceSunken)
                } else {
                    ProgressView()
                }
            }
        } else {
            Color(IHaven.Color.surfaceSunken)
        }
    }
}
