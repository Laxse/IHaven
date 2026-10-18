import SwiftUI

/// 侧栏「时间线」：把「已设置」记录按设置日期分组、倒序呈现的时间轴视图。
///
/// 与「已设置」(`AppliedWallpapersView`) 共用同一份本地 `applied` 数据，只是换了呈现方式——
/// 按天聚合后，用户可以回看「某一天用了哪些壁纸」。数据层零新增（applied 已按 appliedAt 倒序），
/// 纯展示重组。卡片复用 `AppliedWallpaperCard`，单击进详情、hover 可重新设置 / 移除记录。
struct AppliedTimelineView: View {
    @Bindable var viewModel: BrowseViewModel
    /// 「去发现壁纸」：回到发现页（由 BrowseView 提供，本视图不反向持有导航状态）。
    var onDiscover: () -> Void
    /// 单击卡片 → 进入详情页（二级页面）。
    var onOpen: (AppliedWallpaper) -> Void
    /// 操作结果提示（成功 / 失败文案），由 BrowseView 弹 toast。
    var onMessage: (String) -> Void

    /// 按「设置日期」聚合并倒序：键是当天零点，值是当天的记录（保持 appliedAt 倒序）。
    private var sections: [(date: Date, items: [AppliedWallpaper])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: viewModel.applied) { cal.startOfDay(for: $0.appliedAt) }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, items: $0.value.sorted { $0.appliedAt > $1.appliedAt }) }
    }

    var body: some View {
        Group {
            if viewModel.applied.isEmpty {
                browseEmptyState(title: "还没有设置过壁纸",
                                body: "把任意壁纸设为桌面后，这里会留下按日期排列的记录，可随时回看或一键重新设置。",
                                action: "去发现壁纸", onAction: onDiscover)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: IHaven.Space.s7.rawValue) {
                        ForEach(sections, id: \.date) { section in
                            timelineSection(section)
                        }
                        .padding(IHaven.Space.s6.rawValue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
    }

    private func timelineSection(_ section: (date: Date, items: [AppliedWallpaper])) -> some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s4.rawValue) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text(section.date.formatted(.dateTime.year().month().day().weekday()))
                    .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg)
                Text("\(section.items.count) 张")
                    .font(IHaven.Font.system(.xs))
                    .foregroundStyle(IHaven.Color.meta)
            }
            MasonryView(items: section.items,
                        spacing: IHaven.Layout.masonryGap,
                        minColumnWidth: IHaven.Layout.masonryColMin,
                        aspectRatio: { item in
                            item.width > 0 && item.height > 0
                                ? CGFloat(item.width) / CGFloat(item.height) : 1.6
                        }) { item in
                AppliedWallpaperCard(item: item,
                                     onOpen: { onOpen(item) },
                                     onReapply: { reapply(item) },
                                     onRemove: { viewModel.removeApplied(id: item.id) })
            }
        }
    }

    private func reapply(_ item: AppliedWallpaper) {
        Task { onMessage((await viewModel.reapply(item)) ?? String(localized: "已重新设为壁纸")) }
    }
}
