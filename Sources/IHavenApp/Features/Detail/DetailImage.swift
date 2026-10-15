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
/// 图源：原图 `path` 到货前先出 `thumbs.original` 低清占位（长边 ≤300px，秒开且**比例正确**），
/// 到货后原地替换。最终显示的像素与 `wallpaper.width/height` 严格同源，`displayFrame` 才算得准。
///
/// ⚠️ **为什么不能拿 `thumbs.large` 当预览**（实测 2026-10-15，8 份样本 `sips` 量像素）：
/// `large` 恒为 **432×243**、`small` 恒为 **300×200** —— 二者都是固定比例的**硬裁件**，与原图
/// 比例无关（竖图 3805×5700 的 `large` 也是 432×243 横图）。只有 `original` 是等比缩略图。
/// 这是「竖向图在详情页居中但尺寸不对、像被裁掉」的根因：竖框里塞一张硬裁的横图。
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
            // 最终显示的是**原图** `path`：与 `wallpaper.width/height` 同源，所以 `displayFrame`
            // 算出来的框和真实像素比例一致 —— 竖图就是竖框配竖像素，不会被压成一条横带。
            LazyImage(url: wallpaper.path) { state in
                if let image = state.image {
                    // ⚠️ 必须是 `.fit` 而不是 `.fill`：比例一致时两者画出来一样，但一旦某个源的
                    // 比例与声明尺寸不符（历史上 `thumbs.large` 就是硬裁件），`.fill` 会直接
                    // 裁掉超出部分 —— 而本视图的硬要求是「完整显示、绝不裁切」。无代价的保险。
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: frame.width, height: frame.height)
                } else if state.error != nil {
                    // 图片自身取不回来：重试只重发图片请求（id 变化即重建 LazyImage）。
                    failureView(message: String(localized: "这张图暂时取不回来"), retryable: true) {
                        reloadToken += 1
                    }
                } else {
                    lowResPreview(frame: frame,
                                  fraction: Double(state.progress.fraction),
                                  totalBytes: state.progress.total)
                }
            }
            .id(reloadToken)
        }
    }

    /// 原图到货前的低清占位：**必须**用 `thumbs.original`（等比、长边 ≤300px），
    /// 用 `large` / `small` 会在原图到货前闪一下被硬裁的比例（竖图上最明显）。
    ///
    /// ⚠️ **占位图上必须叠出「正在加载高清图」的进度**（`fraction` / `totalBytes` 来自 Nuke 的
    /// `ImageTask.Progress`）。一张 300px 缩略图拉到上千 pt 就是糊的，没有进度条时用户无从判断
    /// 「还没下载完」还是「原图本来就这个清晰度」——只会得出后一个结论。
    private func lowResPreview(frame: CGSize, fraction: Double, totalBytes: Int64) -> some View {
        LazyImage(url: wallpaper.aspectThumb) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
            } else {
                skeleton(frame: frame)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .bottom) { hdLoadingHUD(fraction: fraction, totalBytes: totalBytes) }
    }

    /// 高清图下载进度：下沿一条贴底进度条 + 左上一枚胶囊标签，压在占位图上。
    ///
    /// `totalBytes <= 0`（响应没给 Content-Length）时退化为不确定态转圈 —— 此时 `fraction`
    /// 恒为 0，硬画一根不动的空条比转圈更像「卡住了」。
    @ViewBuilder
    private func hdLoadingHUD(fraction: Double, totalBytes: Int64) -> some View {
        let known = totalBytes > 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                if !known { ProgressView().controlSize(.small).scaleEffect(0.7) }
                Text("正在加载高清图")
                    .font(IHaven.Font.system(.xs))
                    .foregroundStyle(IHaven.Color.hudFg)
                if known {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(IHaven.Font.system(.xs, .medium))
                        .foregroundStyle(IHaven.Color.hudFg)
                        .monospacedDigit()
                    Text(byteText(fraction: fraction, totalBytes: totalBytes))
                        .font(IHaven.Font.system(.xs))
                        .foregroundStyle(IHaven.Color.muted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, IHaven.Space.s5.rawValue)
            .padding(.vertical, IHaven.Space.s2.rawValue)
            .background(Capsule().fill(IHaven.Color.hudBg))
            .overlay(Capsule().stroke(IHaven.Color.border, lineWidth: 1))
            .padding(IHaven.Space.s5.rawValue)

            if known {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    // `maxWidth: .infinity` 是必需的：线性进度条自身没有固有宽度，
                    // 不撑开就只剩 VStack 里那枚胶囊的宽度，看着像「只有一点点」。
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.2), value: fraction)
            }
        }
    }

    /// `已下载 / 总量`，都走 `ByteCountFormatter`（`.file` 进制，1 MB = 1000 KB，与系统一致）。
    private func byteText(fraction: Double, totalBytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let done = formatter.string(fromByteCount: Int64(fraction * Double(totalBytes)))
        return "\(done) / \(formatter.string(fromByteCount: totalBytes))"
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
    /// 宽高哪个方向更紧就自适应哪个 —— 这就是「完整显示」的全部实现。
    ///
    /// ⚠️ `wallpaper.width/height` 必须与**最终渲染的那张图**同源，否则框按声明值算、像素来自
    /// 另一个源，比例对不上就是裁切或压扁。这也是本视图渲染原图 `path`、而非任何缩略图的原因。
    private func displayFrame(in size: CGSize) -> CGSize {
        let width = CGFloat(wallpaper.width)
        let height = CGFloat(wallpaper.height)
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return size }
        let scale = min(size.width / width, size.height / height, 1)
        return CGSize(width: width * scale, height: height * scale)
    }
}
