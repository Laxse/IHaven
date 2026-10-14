import SwiftUI

/// 侧栏「动态壁纸」页签：本地视频库 + 播放控制（F9，ADR-015 §五）。
///
/// **文案纪律**（PRD 附录 A-6b）：不得使用暗示存在内容池的措辞（「库 / 精选 / 大全」）。
/// 入口固定一行「从本地视频文件导入」——wallhaven 零视频内容，用户带着「来找动态壁纸」的
/// 预期进来，必须先看到能力边界，再看到空态。
///
/// 单击卡片 = 播放 / 停止切换。DESIGN §4.6 原规定「单击 = 打开编辑器」，但编辑器是 V3 功能
/// （PRD §5.1），V2 交付播放时该动作没有定义 —— 这里补齐为「播放 / 停止」，这是唯一
/// 不依赖尚未存在的界面、且与用户预期一致的动作。
struct DynamicWallpaperView: View {
    @Bindable var library: LocalLibraryViewModel
    var onMessage: (String) -> Void

    @State private var pendingDelete: ImportedWallpaper?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
                    if let playing = library.dynamicPlaying { playbackBar(playing) }
                    if let notice = library.seamNotice {
                        SeamNoticeView(fileName: notice.fileName) { library.seamNotice = nil }
                    }
                    ImportDropZone(
                        title: "从访达拖入你自己的视频文件",
                        onChoose: { library.chooseFiles() },
                        onFiles: { library.importURLs($0) })
                    FormatNotice(
                        supported: "支持：MP4 / MOV（H.264、HEVC）",
                        unsupported: "不支持：WEBM / MKV（macOS 没有原生解码器）、GIF（逐帧解码功耗与效果不达标）")
                    if library.isImporting {
                        ImportProgressView(done: library.importDone, total: library.importTotal,
                                           current: library.importCurrent,
                                           onCancel: { library.cancelImport() })
                    }
                    if !library.lastRejected.isEmpty {
                        RejectedSummaryView(rejected: library.lastRejected)
                    }
                    if library.videos.isEmpty {
                        LocalEmptyStateView(
                            title: "还没有动态壁纸",
                            message: "动态壁纸从本地视频文件导入。支持 MP4 / MOV，不支持 WEBM / MKV / GIF。",
                            action: "选择文件…",
                            onAction: { library.chooseFiles() })
                    } else {
                        MasonryView(items: library.videos,
                                    spacing: IHaven.Layout.masonryGap,
                                    minColumnWidth: IHaven.Layout.masonryColMin,
                                    aspectRatio: { CGFloat($0.width) / CGFloat($0.height) }) { item in
                            LocalWallpaperCard(
                                item: item,
                                primarySystemName: library.dynamicPlaying?.id == item.id ? "stop.fill" : "play.fill",
                                primaryHelp: library.dynamicPlaying?.id == item.id ? "停止动态壁纸" : "设为动态壁纸",
                                onPrimary: { toggle(item) },
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

    // MARK: - 播放状态条

    /// 常驻一条播放态：正在播什么、是否暂停、能停。没有它，用户无从知道动态壁纸是否在跑
    /// （桌面层窗口是 `ignoresMouseEvents` 的，点不到）。
    private func playbackBar(_ item: ImportedWallpaper) -> some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            Image(systemName: library.dynamicPaused ? "pause.circle" : "play.circle")
                .foregroundStyle(IHaven.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(library.dynamicPaused ? "已暂停" : "正在播放")
                    .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg)
                Text(item.fileName)
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(library.dynamicPaused ? "恢复" : "暂停") { library.toggleDynamicPause() }
                .buttonStyle(.borderless)
                .font(IHaven.Font.system(.xs))
            Button("停止动态壁纸") { library.stopDynamic() }
                .buttonStyle(.borderless)
                .font(IHaven.Font.system(.xs))
        }
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.borderSoft, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s4.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text("动态壁纸").font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
                Text("从本地视频文件导入")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
            Spacer(minLength: 0)
            Text("\(library.videos.count) 个")
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

    private func toggle(_ item: ImportedWallpaper) {
        if library.dynamicPlaying?.id == item.id {
            library.stopDynamic()
            onMessage(String(localized: "已停止动态壁纸"))
        } else if let message = library.playDynamic(item) {
            onMessage(message)
        }
    }
}
