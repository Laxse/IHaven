import SwiftUI

/// 侧栏「导入…」页签：本地图片库（F8，ADR-015 §三）。
///
/// 与网络壁纸的关系：本地项同时出现在「发现」瀑布流的末尾并带「本地」标识（PRD:697），
/// 本页是本地项的完整管理界面（导入 / 设为壁纸 / 删除）。
struct ImportView: View {
    @Bindable var library: LocalLibraryViewModel
    var onMessage: (String) -> Void

    /// 删除需确认（DESIGN §4.6.0）：本地库的删除不可撤销，误触成本高。
    @State private var pendingDelete: ImportedWallpaper?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
                    ImportDropZone(
                        title: "从访达拖入你自己的图片文件",
                        onChoose: { library.chooseFiles() },
                        onFiles: { library.importURLs($0) })
                    FormatNotice(
                        supported: "支持：JPEG / PNG / HEIC / WebP",
                        unsupported: "不支持：WEBM / MKV（macOS 没有原生解码器）、GIF（逐帧解码功耗与效果不达标）")
                    if library.isImporting {
                        ImportProgressView(done: library.importDone, total: library.importTotal,
                                           current: library.importCurrent,
                                           onCancel: { library.cancelImport() })
                    }
                    if !library.lastRejected.isEmpty {
                        RejectedSummaryView(rejected: library.lastRejected)
                    }
                    if library.images.isEmpty {
                        LocalEmptyStateView(
                            title: "还没有导入图片",
                            message: "导入的图片不参与网络壁纸的筛选与翻页，点「选择文件…」或直接从访达拖入。",
                            action: "选择文件…",
                            onAction: { library.chooseFiles() })
                    } else {
                        MasonryView(items: library.images,
                                    spacing: IHaven.Layout.masonryGap,
                                    minColumnWidth: IHaven.Layout.masonryColMin,
                                    aspectRatio: { CGFloat($0.width) / CGFloat($0.height) }) { item in
                            LocalWallpaperCard(
                                item: item,
                                primarySystemName: "display",
                                primaryHelp: "设为壁纸",
                                onPrimary: { setWallpaper(item) },
                                onDelete: { pendingDelete = item })
                        }
                    }
                }
                .padding(IHaven.Space.s6.rawValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
        .task { library.load() }
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("确定删除这个导入项？"),
                message: Text(item.fileName),
                primaryButton: .destructive(Text("删除")) { library.remove(item) },
                secondaryButton: .cancel(Text("取消")))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s4.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text("本地图片").font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
                Text("导入的图片不参与网络壁纸的筛选与翻页")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
            Spacer(minLength: 0)
            Text("\(library.images.count) 张")
                .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                .foregroundStyle(IHaven.Color.meta)
        }
        .padding(.horizontal, IHaven.Space.s6.rawValue)
        .padding(.vertical, IHaven.Space.s4.rawValue)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
        }
    }

    private func setWallpaper(_ item: ImportedWallpaper) {
        Task {
            if let message = await library.setAsWallpaper(item) {
                onMessage(message)
            } else {
                onMessage(String(localized: "已设为壁纸"))
            }
        }
    }
}
