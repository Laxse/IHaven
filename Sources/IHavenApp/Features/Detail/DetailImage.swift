import NukeUI
import SwiftUI

/// 大图区（`surfaceImageGap` 底，padding 16 / r10 / 1px `borderSoft`，零 glassEffect）。
///
/// **只做一件事：把整张图完整塞进可视区。** 缩放系数 = `min(容器宽/图宽, 容器高/图高)`，再封顶 1
/// （小图不放大到糊）—— 宽、高哪个方向更紧就自适应哪个，另一个方向居中留空。
/// 这是「完整显示」的唯一解。
///
/// ⚠️ **为什么不提供「1:1」和「铺满」**（曾经的缩放两档，已删除）：
/// - 「1:1」是物理像素。一张 3840×2160 的壁纸在约 1000pt 宽的可视区里，**数学上就看不全**，
///   必然只能看到四分之一。用户反馈「适合窗口和 1:1 都不能完整显示整个图片」正是这个原因。
/// - 「铺满」= 裁边，与「完整显示」直接冲突。
/// 另外「适合窗口」原先还兜了一个 0.35 的缩放下限（本意是让超宽图别缩得太小），结果下限一兜
/// 图就溢出可视区、变成裁切 —— 与 1:1 犯的是同一个错。**任何兜底倍率都会破坏「完整显示」。**
///
/// 预览用 `thumbs.large`（秒开，缓存已预热）；原图 `path` 5–20MB，预览不需要，
/// 要看全尺寸走「下载原图」。
struct DetailImageView: View {
    let wallpaper: Wallpaper
    /// 详情请求失败的分类：`gone`（404）→ 整块失败态；`transient` → 图照常渲染 + 顶部提示条。
    let failure: DetailViewState.DetailLoadFailure?
    let message: String
    let retryable: Bool
    var onRetry: () -> Void
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            // 提示条压在大图区**顶部**、把图往下推，不遮图。
            if failure == .transient { noticeBar }
            imageArea
                .padding(IHaven.Space.s6.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IHaven.Color.surfaceImageGap)
    }

    /// 瞬时失败的提示条：`meta` 文字色 + 1px 下边框。「重试」只在 `detailRetryable`（网络层错误）时出现
    /// —— 429 立刻重试必再撞限流，且每次重试再扣 1 次配额。
    private var noticeBar: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            Text(message)
                .font(IHaven.Font.system(.xs))
                .foregroundStyle(IHaven.Color.meta)
                .lineLimit(2)
            Spacer(minLength: 0)
            if retryable {
                Button("重试") { onRetry() }
                    .buttonStyle(.borderless)
                    .font(IHaven.Font.system(.xs))
            }
        }
        .padding(.horizontal, IHaven.Space.s6.rawValue)
        .frame(height: 28)
        .background(IHaven.Color.bgChrome)
        .overlay(alignment: .bottom) { Rectangle().fill(IHaven.Color.border).frame(height: 1) }
    }

    /// 图片框：外层 `.frame` 取满容器，内层 `displayFrame` 给出等比缩小后的尺寸，
    /// 小于外框时 SwiftUI 自动居中 —— 于是永远完整、永远不裁、也不需要滚动。
    private var imageArea: some View {
        GeometryReader { geo in
            let frame = displayFrame(in: geo.size)
            layer(frame: frame)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        .background(IHaven.Color.surfaceSunken)
    }

    @ViewBuilder
    private func layer(frame: CGSize) -> some View {
        if failure == .gone {
            // 壁纸已下架：没有内容可渲染，整块失败态（文案来自 `APIError.notFound`）。
            failureView(message: message, retryable: retryable) { onRetry() }
        } else {
            LazyImage(url: wallpaper.thumbs.large) { state in
                if let image = state.image {
                    // ⚠️ 必须是 `.fit` 而不是 `.fill`：框的尺寸是按 `wallpaper.width/height`
                    // （**声明的**原图尺寸）算的，实际像素来自 `thumbs.large`。两者只要比例不一致
                    // （例如 mock 给错尺寸的字节、或某个缩略图比例与原图不符），`.fill` 会直接
                    // 裁掉超出部分 —— 而本视图的硬要求是「完整显示、绝不裁切」。
                    // 比例一致时两者画出来完全一样，所以 `.fit` 是无代价的保险。
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: frame.width, height: frame.height)
                } else if state.error != nil {
                    // 图片自身取不回来：重试只重发图片请求（id 变化即重建 LazyImage）。
                    failureView(message: String(localized: "这张图暂时取不回来"), retryable: true) {
                        reloadToken += 1
                    }
                } else {
                    skeleton(frame: frame)
                }
            }
            .id(reloadToken)
        }
    }

    private func skeleton(frame: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
                .fill(IHaven.Color.surfaceSunken)
            ProgressView().controlSize(.small)
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// 整块失败态：图标与文案一律 `meta` 色，不是 `danger` —— 单张图取不到不代表筛选失败。
    private func failureView(message: String, retryable: Bool, retry: @escaping () -> Void) -> some View {
        VStack(spacing: IHaven.Space.s4.rawValue) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IHaven.Icon.lg))
                .foregroundStyle(IHaven.Color.meta)
            Text(message)
                .font(IHaven.Font.system(.sm))
                .foregroundStyle(IHaven.Color.meta)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if retryable {
                Button("重试", action: retry).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 目标尺寸：`min(宽比, 高比)` 等比缩放，封顶 1（小图不放大到糊）。
    ///
    /// 宽高哪个方向更紧就自适应哪个 —— 这就是「完整显示」的全部实现。注意 `wallpaper.width/height`
    /// 是**原图**尺寸，而这里渲染的是 `thumbs.large`：原图 4K 而容器 ~1000pt 时缩放系数 < 1，
    /// 缩略图被进一步缩小，依然清晰；只有「原图比容器还小」才会出现轻微放大。
    private func displayFrame(in size: CGSize) -> CGSize {
        let width = CGFloat(wallpaper.width)
        let height = CGFloat(wallpaper.height)
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return size }
        let scale = min(size.width / width, size.height / height, 1)
        return CGSize(width: width * scale, height: height * scale)
    }
}
