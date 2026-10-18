import SwiftUI

/// 侧栏「动态壁纸」页签：本地生成的动态壁纸库 + 播放控制（ADR-016）。
///
/// **文案纪律**（PRD 附录 A-6b）：不得使用暗示内容池的措辞。
/// 动态壁纸一律由静态图**本地生成**（零成本、离线），不再是「导入视频」。
/// 单击卡片 = 播放 / 停止切换。
struct DynamicWallpaperView: View {
    @Bindable var library: LocalLibraryViewModel
    var onMessage: (String) -> Void
    /// 删除请求**上交给主窗口统一弹确认**（见 `BrowseView.pendingDelete`）。
    /// 本视图已挂 `.sheet`（生成面板），再挂 `.alert` 会与之竞争，导致点了删除没反应。
    var onDeleteRequest: (ImportedWallpaper) -> Void

    @State private var showGenerator = false
    @State private var showAIGenerator = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
                    if let playing = library.dynamicPlaying { playbackBar(playing) }
                    if library.isGenerating {
                        HStack(spacing: IHaven.Space.s4.rawValue) {
                            ProgressView().controlSize(.small)
                            Text("正在生成动态壁纸…")
                                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                        }
                        .padding(IHaven.Space.s5.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.borderSoft, lineWidth: 1))
                    }
                    if library.animations.isEmpty {
                        LocalEmptyStateView(
                            title: "还没有动态壁纸",
                            message: "动态壁纸由一张静态图本地生成：套用动画预设，立刻得到可循环播放的动态桌面，零成本、离线可用。",
                            action: "生成动态壁纸",
                            onAction: { showGenerator = true })
                    } else {
                        MasonryView(items: library.animations,
                                    spacing: IHaven.Layout.masonryGap,
                                    minColumnWidth: IHaven.Layout.masonryColMin,
                                    aspectRatio: { CGFloat($0.width) / CGFloat($0.height) }) { item in
                            LocalWallpaperCard(
                                item: item,
                                primarySystemName: library.dynamicPlaying?.id == item.id ? "stop.fill" : "play.fill",
                                primaryHelp: library.dynamicPlaying?.id == item.id ? "停止动态壁纸" : "设为动态壁纸",
                                onPrimary: { toggle(item) },
                                onDelete: { onDeleteRequest(item) })
                        }
                    }
                }
                .padding(IHaven.Space.s6.rawValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
        .task { library.load() }
        .sheet(isPresented: $showGenerator) {
            AnimationGeneratorView(library: library) { item in
                showGenerator = false
                if let message = library.playDynamic(item) {
                    onMessage(message)
                } else {
                    onMessage(String(localized: "已生成并开始播放"))
                }
            }
        }
        // AI 图生视频（#70，Plan B）：计费、需自备 Key；产物与本地生成同库、同引擎。
        .sheet(isPresented: $showAIGenerator) {
            AIVideoGeneratorView(library: library, onGenerated: { item in
                showAIGenerator = false
                if let message = library.playDynamic(item) {
                    onMessage(message)
                } else {
                    onMessage(String(localized: "已生成并开始播放"))
                }
            }, onClose: { showAIGenerator = false })
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
                Text("由静态图本地生成 · 离线零成本")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
            Spacer(minLength: 0)
            Button {
                showGenerator = true
            } label: {
                Image(systemName: "plus")
                Text("生成动态壁纸")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            // AI 生成入口（#70）：次级样式，不抢本地生成的主按钮地位；计费，面板内再确认。
            Button {
                showAIGenerator = true
            } label: {
                Image(systemName: "sparkles")
                Text("AI 生成")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("\(library.animations.count) 个")
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
