import CoreGraphics
import SwiftUI

/// 设置壁纸前的裁剪选框（用户原话：「跟一些网站上设置头像的逻辑一样」）。
///
/// 竖图直接设壁纸会左右黑边，根因是填充模式默认读成了「完整可见」。这里让用户先框出
/// **与屏幕同宽高比**的一块，按全分辨率裁成新文件再设壁纸 —— 产物比例与屏幕一致，
/// 系统无论按 fit 还是 fill 铺都不留白。
///
/// `sourceURL` 必须是**本地文件 URL**：远程 URL 交给系统壁纸 API 会 SIGABRT
/// （见 `Platform/Wallpaper/SystemWallpaperEngine.swift` L12-22）。
struct WallpaperCropSheet: View {
    let sourceURL: URL
    /// 锁定给选框的宽高比（= 目标屏宽高比，由 `WallpaperTarget.cropAspect()` 给出）。
    let aspect: CGFloat
    let screenLabel: String
    let onCancel: () -> Void
    /// 参数1 = 裁剪产物本地 fileURL；参数2 = 产物像素尺寸。
    let onApply: (URL, CGSize) -> Void

    @State private var image: CGImage?
    @State private var rect = WallpaperCropRect.full
    @State private var isLoading = true
    @State private var isSaving = false
    /// 运行期错误文案（写盘失败等）。**留在 sheet 内联显示**，不崩、不弹系统框。
    @State private var errorText: String?
    /// 手势基准：一次拖拽内始终以「按下那一刻的 rect」为基准做增量，否则会把每帧的
    /// 位移累加成漂移（拖一圈回不到原点）。
    @State private var dragBase: WallpaperCropRect?

    var body: some View {
        VStack(spacing: 0) {
            cropSheetHeader(screenLabel: screenLabel)
                .padding(.horizontal, IHaven.Space.s6.rawValue)
                .padding(.vertical, IHaven.Space.s5.rawValue)
            preview
                .padding(.horizontal, IHaven.Space.s6.rawValue)
            footer
                .padding(.horizontal, IHaven.Space.s6.rawValue)
                .padding(.vertical, IHaven.Space.s5.rawValue)
        }
        .frame(width: 780, height: 620)
        .background(IHaven.Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.xl.rawValue, style: .continuous))
        .task { load() }
    }

    // MARK: - 预览区（选框 + 手势）

    private var preview: some View {
        GeometryReader { geo in
            if let image {
                let display = cropDisplayRect(image: CGSize(width: image.width, height: image.height),
                                              in: geo.size)
                let box = cropBoxRect(rect, in: display)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    // 框外压暗：even-odd 挖洞。装饰层整层不吃命中，否则会吞掉框内拖动。
                    CropHoleMask(hole: box)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(SwiftUI.Color.black.opacity(0.55))
                        .allowsHitTesting(false)
                    cropRulesView(hole: box)
                        .allowsHitTesting(false)
                    // 框内拖动 = 整体移动。用透明色块而不是给整块 overlay 挂手势：
                    // 只有框内可拖，框外拖动不该误移选框。
                    SwiftUI.Color.clear
                        .contentShape(Rectangle())
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .gesture(moveGesture(display: display.size))
                }
                // 四角句柄必须是**挂在最外层的独立 overlay**：`allowsHitTesting(false)` 会连带
                // 禁用它的整个子树，句柄放进那棵子树里就变成点不到的死按钮（BrowseGrid.swift:31-59）。
                // 命中框显式给到 28×28，不能用 maxWidth:.infinity（那会让整片预览区都吃命中）。
                .overlay {
                    ForEach(CropHandle.allCases, id: \.self) { handle in
                        cropHandleKnob()
                            .frame(width: IHaven.Layout.hitPointerMin, height: IHaven.Layout.hitPointerMin)
                            .contentShape(Rectangle())
                            .position(cropHandlePoint(handle, in: box))
                            .gesture(resizeGesture(handle: handle, display: display.size))
                    }
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("无法加载该图片")
                    .font(IHaven.Font.system(.sm))
                    .foregroundStyle(IHaven.Color.meta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(IHaven.Color.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous))
        .animation(IHaven.Motion.base, value: isLoading)
    }

    /// 整体移动：显示位移 ÷ 显示宽/高 = 归一化位移，交给模型去钳边界。
    private func moveGesture(display: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragBase == nil { dragBase = rect }
                guard let base = dragBase, display.width > 0, display.height > 0 else { return }
                rect = base.moved(dx: value.translation.width / display.width,
                                  dy: value.translation.height / display.height)
            }
            .onEnded { _ in dragBase = nil }
    }

    /// 拖角缩放：对角锚定、锁定屏幕比例，触底停住（模型内部保证）。
    private func resizeGesture(handle: CropHandle, display: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragBase == nil { dragBase = rect }
                guard let base = dragBase, display.width > 0, display.height > 0 else { return }
                rect = base.resized(handle: handle,
                                    dx: value.translation.width / display.width,
                                    dy: value.translation.height / display.height,
                                    aspect: aspect)
            }
            .onEnded { _ in dragBase = nil }
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            if let errorText {
                Text(verbatim: errorText)
                    .font(IHaven.Font.system(.xs))
                    .foregroundStyle(IHaven.Color.danger)
            }
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text("裁剪后 · \(Int(cropPixelSize.width)) × \(Int(cropPixelSize.height))")
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.meta)
                Spacer()
                CropSheetButton(label: "重置", isEnabled: image != nil) { reset() }
                CropSheetButton(label: "取消") { onCancel() }
                CropSheetButton(label: isSaving
                                ? LocalizedStringKey("正在裁剪…") : LocalizedStringKey("设为壁纸"),
                                isPrimary: true,
                                isEnabled: image != nil && !isSaving) { apply() }
            }
        }
    }

    private var cropPixelSize: CGSize {
        guard let image else { return .zero }
        return rect.pixelRect(in: CGSize(width: image.width, height: image.height)).size
    }

    // MARK: - 动作

    private func load() {
        guard image == nil else { return }
        // 大图解码几百 ms，同步解即可（放在 .task 里，不卡首帧）。
        do {
            let loaded = try WallpaperCropWriter.loadOriented(sourceURL)
            image = loaded
            rect = .centered(in: CGSize(width: loaded.width, height: loaded.height), aspect: aspect)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func reset() {
        guard let image else { return }
        rect = .centered(in: CGSize(width: image.width, height: image.height), aspect: aspect)
        dragBase = nil
    }

    private func apply() {
        guard image != nil, !isSaving else { return }
        isSaving = true
        errorText = nil
        do {
            let url = try WallpaperCropWriter.write(source: sourceURL, rect: rect,
                                                    to: AppPaths.sub("Crops"))
            onApply(url, cropPixelSize)
        } catch {
            // 失败就留在 sheet 里给一行红字，让用户改选框重试；不崩、不静默。
            errorText = error.localizedDescription
            isSaving = false
        }
    }
}
