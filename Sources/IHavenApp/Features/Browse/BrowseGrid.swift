import SwiftUI

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
                // 等比缩略图：`thumbs.small` 恒 300×200 硬裁件，配按声明比例算出的卡片框
                // 会把竖图裁成一条（瀑布流里每张竖图都中招）。
                ThumbnailImage(url: wallpaper.aspectThumb)
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

