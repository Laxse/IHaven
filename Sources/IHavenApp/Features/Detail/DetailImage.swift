import NukeUI
import SwiftUI

/// 缩放两档：只做「适合窗口 / 1:1」，不做「铺满」（铺满即裁边，与「不裁」的版式前提冲突）。
enum DetailZoom: Hashable { case fit, actual }

/// 大图区（`surfaceImageGap` 底，`.fit` 不裁，padding 16 / r10 / 1px `borderSoft`，零 glassEffect）。
///
/// **两级加载**：先 `thumbs.large` 秒开，`path` 原图只在切到「1:1」时才拉（原图 5–20MB，预览不需要）。
/// 加载中按 `base.width/height` **预计算**骨架尺寸，避免图片到位时布局抖一下。
struct DetailImageView: View {
    let wallpaper: Wallpaper
    /// 详情请求失败 → 大图区转失败态；失败文案一律 `meta` 色，不是 `danger`
    /// （单张图取不到不代表筛选失败）。
    let failed: Bool
    var onRetry: () -> Void
    @Binding var zoom: DetailZoom
    @State private var reloadToken = 0

    /// 「适合窗口」把超长 / 超宽图缩到该比例以下就看不清了，改为兜到这个比例并允许双向拖动。
    private static let panScaleFloor: CGFloat = 0.35

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            imageArea
            zoomControl.padding(IHaven.Space.s5.rawValue)
        }
        .padding(IHaven.Space.s6.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.surfaceImageGap)
    }

    /// 图片框超出容器时切成双向 `ScrollView`：超长 / 超宽图放大后仍可拖动查看。
    private var imageArea: some View {
        GeometryReader { geo in
            let frame = displayFrame(in: geo.size)
            if frame.width > geo.size.width + 0.5 || frame.height > geo.size.height + 0.5 {
                ScrollView([.horizontal, .vertical]) {
                    layer(frame: frame).frame(width: frame.width, height: frame.height)
                }
            } else {
                layer(frame: frame).frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
            .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        .background(IHaven.Color.surfaceSunken)
    }

    @ViewBuilder
    private func layer(frame: CGSize) -> some View {
        if failed {
            failureView { onRetry() }
        } else {
            LazyImage(url: zoom == .actual ? wallpaper.path : wallpaper.thumbs.large) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: frame.width, height: frame.height)
                } else if state.error != nil {
                    // 图片自身取不回来：重试只重发图片请求（id 变化即重建 LazyImage）。
                    failureView { reloadToken += 1 }
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

    private func failureView(retry: @escaping () -> Void) -> some View {
        VStack(spacing: IHaven.Space.s4.rawValue) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IHaven.Icon.lg))
                .foregroundStyle(IHaven.Color.meta)
            Text("这张图暂时取不回来")
                .font(IHaven.Font.system(.sm))
                .foregroundStyle(IHaven.Color.meta)
            Button("重试", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 缩放控件：复用筛选面板的分段控件（2 项自动各半），浮在大图右下角。
    private var zoomControl: some View {
        FilterSegmented(options: [(value: DetailZoom.fit, label: LocalizedStringKey("适合窗口")),
                                  (value: DetailZoom.actual, label: LocalizedStringKey("1:1"))],
                        selection: zoom,
                        onSelect: { zoom = $0 })
            .frame(width: 160)
            .background(IHaven.Color.surface,
                        in: RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous)
                .stroke(IHaven.Color.border, lineWidth: 1))
    }

    /// 目标尺寸：`.fit` 只缩不放（小图不放大到糊），超长 / 超宽图兜到 `panScaleFloor`；
    /// `1:1` 直接用物理像素，超出容器的部分交给外层 `ScrollView`。
    private func displayFrame(in size: CGSize) -> CGSize {
        let width = CGFloat(wallpaper.width)
        let height = CGFloat(wallpaper.height)
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return size }
        let fit = min(size.width / width, size.height / height)
        switch zoom {
        case .fit:
            let scale = min(max(fit, Self.panScaleFloor), 1)
            return CGSize(width: width * scale, height: height * scale)
        case .actual:
            return CGSize(width: width, height: height)
        }
    }
}
