import SwiftUI

/// 真 masonry 瀑布流：按各卡真实宽高比分配列，列宽 240–340 / 沟槽 8（design-tokens grid）。
/// 宽度反馈环的规避：主体是「零内在尺寸占位」（Color.clear，最小宽=0），永远贴合父容器提议宽，
/// 不会被上次分栏内容“撑住”而无法收缩；`onGeometryChange` 测到的即“可用宽”，分栏用 `overlay`
/// 呈现且不参与尺寸、`clipped` 防溢出。旧写法把分栏放进 `VStack.frame(maxWidth:.infinity)`，
/// 其最小宽=分栏宽，窗口调小时缩不动→width 状态自锁→根布局被撑超窗口→侧栏被裁（回归根因）。
/// 高度按列宽确定性计算（不用 overlay 反推），保证 ScrollView 滚动高度判定稳定。
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

    /// 列宽 + 分桶（body 高度与 columnsView 共用同一来源，确保高度与渲染一致）。
    private var columns: (colWidth: CGFloat, buckets: [[Item]]) {
        let cols = columnCount
        let colWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        return (colWidth, distribute(into: cols, colWidth: colWidth))
    }

    /// 最高列高度 = 滚动内容高：Σ(卡高) + (n-1)×沟槽。确定性计算，随 width / items 变化。
    private var contentHeight: CGFloat {
        guard width > 0 else { return 1 }
        let (colWidth, buckets) = columns
        var maxH: CGFloat = 0
        for bucket in buckets {
            let h = bucket.reduce(CGFloat(0)) { $0 + cardHeight($1, colWidth) }
                + spacing * CGFloat(max(0, bucket.count - 1))
            if h > maxH { maxH = h }
        }
        return maxH
    }

    var body: some View {
        // 占位主体：最小宽=0 → 永远贴合父容器提议宽（断反馈环）；高度=内容高（供 ScrollView 判定）。
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: contentHeight)
            // 测“可用宽”（= 父容器提议宽），非内容宽；>0.5 才更新，避免抖动。
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if abs(newWidth - width) > 0.5 { width = newWidth }
            }
            // 分栏以 overlay 呈现：不参与主体尺寸 → 绝不上抬主体最小宽；越界由 clipped 裁掉。
            .overlay(alignment: .topLeading) {
                if width > 0 { columnsView }
            }
            .clipped()
    }

    @ViewBuilder
    private var columnsView: some View {
        let (colWidth, buckets) = columns
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<buckets.count, id: \.self) { c in
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
    /// 单击整卡 → 进入详情页（二级页面）。
    var onOpen: () -> Void
    var onToggleFavorite: () -> Void
    var onSetWallpaper: () -> Void
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ThumbnailImage(url: wallpaper.thumbs.small)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // 手势挂在**缩略图层**而不是整卡：hover 浮层里的「收藏 / 设为壁纸」在它上层，
                    // 会先吃到点击，两者不打架（整卡挂手势会把浮层按钮吞掉）。
                    .onTapGesture(perform: onOpen)
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

    /// ⚠️ 命中测试（这是「单击卡片进不了详情页」的根因）：
    /// 浮层整片盖在缩略图之上，而 SwiftUI 的命中区域就是 View 的边框 —— 渐变层铺满整卡、
    /// 按钮容器原先还写了 `maxWidth/maxHeight:.infinity`（视觉上是右上角两个小按钮，命中区域
    /// 却是整张卡）。鼠标一进卡片就 hover，浮层立刻出现，于是**每一次点击都被浮层吃掉**，
    /// 挂在缩略图上的 `onTapGesture` 永远收不到。
    /// 修法：整层 `allowsHitTesting(false)` 让点击穿透到下面的缩略图，只有两个按钮单独挂一层
    /// overlay —— 它的命中区域就是按钮本身那么大。
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
        }
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
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

