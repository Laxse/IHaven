import SwiftUI

/// 动态壁纸生成面板（ADR-016）：选一张静态图 → 套用动画预设（缓推 / 呼吸 / 横移）→ 调幅度与
/// 时长 → 实时预览 → 本地生成帧序列。
///
/// 生成是本地、离线、零成本的：不接任何云端 API。AI 生视频作为后续可选项（设置里填 Key 后启用）。
struct AnimationGeneratorView: View {
    @Bindable var library: LocalLibraryViewModel
    /// 生成成功后回调（传出新品，便于调用方自动开始播放）。
    var onGenerated: (ImportedWallpaper) -> Void

    @State private var selected: ImportedWallpaper?
    @State private var preset: AnimationPreset = .breathe
    @State private var seconds: Double = 12
    @State private var amplitude: Double = 0.12
    @State private var generateError: String?

    private var spec: AnimationSpec {
        AnimationSpec(preset: preset, seconds: seconds, frameCount: 0, amplitude: amplitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            HStack {
                Text("生成动态壁纸").font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
                Spacer(minLength: 0)
            }

            if library.images.isEmpty {
                VStack(spacing: IHaven.Space.s4.rawValue) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: IHaven.Icon.lg)).foregroundStyle(IHaven.Color.meta)
                    Text("先在「本地图片」页签导入一些静态图片，再来生成动态壁纸。")
                        .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sourcePicker
                preview
                controls
                generateButton
            }
        }
        .padding(IHaven.Space.s6.rawValue)
        .frame(width: 540, height: 600)
        .onAppear { if selected == nil { selected = library.images.first } }
    }

    // MARK: - 源选择

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            Text("选择一张静态图").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    ForEach(library.images) { img in
                        SourceThumb(item: img, selected: selected?.id == img.id)
                            .onTapGesture { selected = img }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 88)
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private var preview: some View {
        if let src = selected {
            PreviewBox(item: src, spec: spec)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
                    .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
                .fill(IHaven.Color.surfaceSunken)
                .frame(height: 200)
                .overlay(Text("选择上方一张图即可预览").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.meta))
        }
    }

    // MARK: - 控件

    private var controls: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
                Text("动画预设").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                Picker("", selection: $preset) {
                    ForEach(AnimationPreset.allCases, id: \.self) { p in
                        Text(p.labelKey).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
                HStack {
                    Text("循环时长").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f 秒", seconds))
                        .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                        .foregroundStyle(IHaven.Color.meta)
                }
                Slider(value: $seconds, in: AnimationSpec.secondsRange)
            }

            VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
                HStack {
                    Text("运动幅度").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", amplitude * 100))
                        .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                        .foregroundStyle(IHaven.Color.meta)
                }
                Slider(value: $amplitude, in: AnimationSpec.amplitudeRange)
            }
        }
    }

    // MARK: - 生成

    private var generateButton: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            if let generateError {
                Text(generateError)
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
            }
            Button {
                generate()
            } label: {
                if library.isGenerating {
                    ProgressView().controlSize(.small)
                    Text("生成中…")
                } else {
                    Text("生成动态壁纸")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == nil || library.isGenerating)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func generate() {
        guard let src = selected else { return }
        generateError = nil
        Task {
            if let item = await library.generateAnimation(source: src, spec: spec) {
                onGenerated(item)
            } else {
                generateError = String(localized: "生成失败，请重试")
            }
        }
    }
}

/// 源图缩略图（生成面板用），带选中描边。`internal`：AI 生成面板（#70）复用同一零件。
struct SourceThumb: View {
    let item: ImportedWallpaper
    let selected: Bool

    var body: some View {
        ThumbnailImage(url: URL(fileURLWithPath: item.thumbnailPath))
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                .stroke(selected ? IHaven.Color.accent : IHaven.Color.border, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(IHaven.Color.accent).font(.system(size: 18))
                        .padding(3)
                }
            }
    }
}

/// 实时预览：用 SwiftUI 仿射变换复现当前预设的循环运动（廉价，不落盘）。
///
/// 与 `AnimationSpec.cropRect` 同套 `t ∈ [0,1]` 公式，所以预览与最终生成帧的运动一致；
/// 预览靠变换、生成靠裁切，目的不同但视觉同构。
private struct PreviewBox: View {
    let item: ImportedWallpaper
    let spec: AnimationSpec

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { ctx in
                let t = (ctx.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: max(0.1, spec.seconds))) / max(0.1, spec.seconds)
                let (scale, ox, oy) = Self.transform(spec.preset, spec.amplitude, t,
                                                     geo.size.width, geo.size.height)
                ThumbnailImage(url: URL(fileURLWithPath: item.thumbnailPath))
                    .scaleEffect(scale)
                    .offset(x: ox, y: oy)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .background(Color.black)
    }

    /// 返回 (scale, offsetX, offsetY)。t=0 与 t=1 同值 → 无缝循环。
    static func transform(_ preset: AnimationPreset, _ amp: Double, _ t: Double,
                          _ w: CGFloat, _ h: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let tri = (1 - cos(2 * Double.pi * t)) / 2.0   // 0 → 1 → 0
        switch preset {
        case .breathe:
            return (1 + amp * tri, 0, 0)
        case .pan:
            let overflow = w * amp / 2
            return (1 + amp, overflow * (2 * tri - 1), 0)
        case .zoomIn:
            let overflow = h * amp / 2
            return (1 + amp * tri, 0, overflow * (2 * tri - 1))
        }
    }
}
