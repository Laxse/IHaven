import SwiftUI

/// 侧栏「已设置」：已设为桌面壁纸的历史记录（按设置时间倒序），可「重新设置」/「移除记录」。
///
/// 数据源是本地 `applied` 表（`WallpaperDatabase.applied()`），与「收藏」同构：只存 URL 与本地路径，
/// 重新设置优先复用已下载的本地文件（见 `BrowseViewModel.reapply`）。
struct AppliedWallpapersView: View {
    @Bindable var viewModel: BrowseViewModel
    /// 「去发现壁纸」：回到发现页（由 BrowseView 提供，本视图不反向持有导航状态）。
    var onDiscover: () -> Void
    /// 单击卡片 → 进入详情页（二级页面）。
    var onOpen: (AppliedWallpaper) -> Void
    /// 操作结果提示（成功 / 失败文案），由 BrowseView 弹 toast。
    var onMessage: (String) -> Void

    var body: some View {
        Group {
            if viewModel.applied.isEmpty {
                browseEmptyState(title: "还没有设置过壁纸",
                                 body: "把任意壁纸设为桌面后，这里会留下记录，可随时一键重新设置。",
                                 action: "去发现壁纸", onAction: onDiscover)
            } else {
                ScrollView {
                    MasonryView(items: viewModel.applied,
                                spacing: IHaven.Layout.masonryGap,
                                minColumnWidth: IHaven.Layout.masonryColMin,
                                aspectRatio: { item in
                                    // 从收藏设置的记录不持有尺寸（0）→ 退回 16:10，避免 0 除。
                                    item.width > 0 && item.height > 0
                                        ? CGFloat(item.width) / CGFloat(item.height) : 1.6
                                }) { item in
                        AppliedWallpaperCard(item: item,
                                             onOpen: { onOpen(item) },
                                             onReapply: { reapply(item) },
                                             onRemove: { viewModel.removeApplied(id: item.id) })
                    }
                    .padding(IHaven.Space.s6.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
    }

    private func reapply(_ item: AppliedWallpaper) {
        Task { onMessage((await viewModel.reapply(item)) ?? String(localized: "已重新设为壁纸")) }
    }
}

/// 已设置卡：复用瀑布流布局；hover 浮层为「重新设置」+「移除记录」，左下角常驻分辨率与设置时间。
/// 单击整卡 → 进入详情页（二级页面），与发现页 `WallpaperCard` 同款交互。
struct AppliedWallpaperCard: View {
    let item: AppliedWallpaper
    /// 单击整卡 → 进入详情页（二级页面）。
    var onOpen: () -> Void
    var onReapply: () -> Void
    var onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // 手势挂在缩略图层：hover 浮层里的快捷按钮在它上层，会先吃到点击，两者不打架。
                ThumbnailImage(url: item.thumbnailURL)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onTapGesture(perform: onOpen)
                if hovered { hoverDecoration.transition(.opacity) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        // 快捷按钮必须是独立的最外层 overlay（见 `WallpaperCard` 的命中注释），不能放进禁用层。
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 6) {
                    Button(action: onReapply) {
                        Image(systemName: "desktopcomputer").foregroundStyle(.white)
                    }
                    .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                    .buttonStyle(.borderless)
                    .help("重新设为壁纸")
                    Button(action: onRemove) {
                        Image(systemName: "trash").foregroundStyle(.white)
                    }
                    .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                    .buttonStyle(.borderless)
                    .help("从已设置中移除")
                }
                .padding(8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                if let res = item.resolutionText {
                    Text(res)
                    Text("·")
                }
                Text(item.appliedAt.formatted(.dateTime.month().day().hour().minute()))
            }
            .font(IHaven.Font.system(.xs))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
            .padding(8)
            // 信息条不拦截点击，穿透到下面的缩略图（整卡单击进详情）。
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(IHaven.Motion.fast, value: hovered)
    }

    /// 纯装饰层：渐变。**整体不吃命中**，点击穿透到下面的缩略图。
    private var hoverDecoration: some View {
        LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.6)],
                      startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }
}
