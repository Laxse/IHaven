import SwiftUI

/// 本地项卡片：导入页签、动态壁纸页签、瀑布流三处复用。
///
/// 与 `WallpaperCard` 的差异：缩略图来自**本机文件**（`thumbnailPath`，导入时已生成 ≤640px），
/// 不需要 Nuke 走网络；信息条常驻显示分辨率 / 时长；左上角带「本地」标识（PRD:697 的
/// 可区分标识 —— 瀑布流里本地项与网络项混排时必须能一眼分开）。
struct LocalWallpaperCard: View {
    let item: ImportedWallpaper
    /// 卡片上的主操作（导入页 = 设为壁纸，动态页 = 播放）。
    var primarySystemName: String
    var primaryHelp: LocalizedStringKey
    var onPrimary: () -> Void
    var onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ThumbnailImage(url: URL(fileURLWithPath: item.thumbnailPath))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onTapGesture(perform: onPrimary)
                if hovered { overlay }
                // 常驻信息条：分辨率（视频再加时长）。本地文件没有网络壁纸那套上传者 / 收藏数。
                infoBar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        .overlay(alignment: .topLeading) { localBadge }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(IHaven.Motion.fast, value: hovered)
    }

    // MARK: - 浮层

    /// 装饰层整体 `.allowsHitTesting(false)`：命中区域 = View 边框，铺满的渐变会吃掉点击
    /// （BrowseGrid 的 hoverOverlay 犯过同一个错，见 2026-10-15 记录）。
    private var overlay: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(IHaven.Font.system(.xs))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(sizeText)
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(IHaven.Space.s4.rawValue)
        }
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                BrowseIconButton(systemName: primarySystemName, help: primaryHelp, action: onPrimary)
                BrowseIconButton(systemName: "trash", help: "删除", action: onDelete)
            }
            .padding(IHaven.Space.s3.rawValue)
        }
        .transition(.opacity)
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            Text(sizeText)
                .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IHaven.Space.s3.rawValue)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45))
    }

    /// 「本地」标识：本地项与网络项在同一瀑布流里混排时的可区分标识（PRD:697）。
    private var localBadge: some View {
        Text("本地")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(IHaven.Color.accent, in: Capsule())
            .padding(IHaven.Space.s3.rawValue)
    }

    private var sizeText: String {
        if let duration = item.duration {
            return "\(item.resolutionText) · \(Self.durationText(duration))"
        }
        return item.resolutionText
    }

    /// `m:ss`；超过一小时才带小时位。视频壁纸普遍在 30 秒到几分钟之间。
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
