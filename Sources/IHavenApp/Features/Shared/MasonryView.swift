import SwiftUI

/// 真 masonry 瀑布流：按各卡真实宽高比分配列，列宽 240–340 / 沟槽 8（design-tokens grid）。
///
/// 放在 `Features/Shared` 而不是 `Features/Browse`：导入页、动态壁纸页、瀑布流三处都要用。
/// 同 module 内不需要 import，但 `Features/DynamicWallpaper` 目录被 convention-gate 的
/// F9 依赖方向规则扫描（禁出现 `Features/Browse` / `WallhavenClient` 字样）——
/// 留在 Browse 里会逼着 DynamicWallpaper 侧写注释绕过，那是把规则当敌人。
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
