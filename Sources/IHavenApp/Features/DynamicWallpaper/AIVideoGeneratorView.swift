import Foundation
import SwiftUI

/// AI 图生视频面板（#70，Plan B）：选一张本地静态图 + 写一句运动描述 → AI 生成短视频 →
/// 本地抽帧成动态壁纸。与「生成动态壁纸」面板（本地渲静图）并列，产物都进同一个动态壁纸库。
///
/// 三道前置门：构建未装配 AI / 未配 Key / 库里没有静态图 —— 各自给一句可操作提示，
/// 不把一个点不动的生成按钮留给用户。生成计费，故每次都要一次确认。
struct AIVideoGeneratorView: View {
    @Bindable var library: LocalLibraryViewModel
    var onGenerated: (ImportedWallpaper) -> Void
    var onClose: () -> Void

    @State private var selected: ImportedWallpaper?
    @State private var prompt = ""
    @State private var confirmGenerate = false
    @FocusState private var promptFocused: Bool
    /// 选中的厂商与模型（#70 多厂商直连：模型挂在厂商下，Key 也按厂商分）。持久化 ——
    /// 下一次打开仍是这个。厂商在这里只读不说：换厂商要去设置里配那家的 Key。
    @AppStorage(UserPreferenceKey.aiVideoVendor) private var vendorID = AIVideoVendorCatalog.fallback.id
    @AppStorage(UserPreferenceKey.aiVideoModel) private var modelID = AIVideoVendorCatalog.fallback.models[0].id

    private var vendor: AIVideoVendor { AIVideoVendorCatalog.vendor(id: vendorID) }
    /// 下拉的选中项：偏好里存的 id 可能属于上一家，回落当前厂商的第一个（与
    /// `AIVideoVendorCatalog.selectedModel()` 同口径）。
    private var model: AIVideoModel { vendor.models.first { $0.id == modelID } ?? vendor.models[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            header
            if !library.isAIAvailable {
                banner("当前构建未启用 AI 生成。", symbol: "exclamationmark.triangle", tint: IHaven.Color.warn)
            } else if !library.isAIKeyConfigured {
                // 点名当前厂商：每家 Key 独立，说「没配 AI Key」用户会不知道该去申请哪一家。
                banner(missingKeyText, symbol: "key", tint: IHaven.Color.warn)
            } else if library.images.isEmpty {
                banner("先在「本地图片」页签导入一张静态图，AI 才能把它变成动态壁纸。",
                       symbol: "photo.on.rectangle.angled", tint: IHaven.Color.meta)
            } else {
                sourcePicker
                previewRow
                modelRow
                promptField
                // 底部按钮钉在面板下沿：内容再长也不会把主操作顶到半空。
                Spacer(minLength: 0)
                footer
            }
        }
        .padding(IHaven.Space.s6.rawValue)
        // 高度**必须跟着内容收**：三道前置门任一未过时只显示「标题 + 一句提示」，
        // 固定 620 会在提示下面留一大片空白（用户实测截图，看着像加载失败）。
        // 620 → 660：模型区上方多了一行「厂商 + 去哪改」，原高度会把底部按钮挤出面板。
        .frame(width: 540, height: hasAllPreconditions ? 660 : 260)
        .onAppear { if selected == nil { selected = library.images.first } }
        .confirmationDialog("将消耗一次 AI 生成额度，确定生成？",
                            isPresented: $confirmGenerate,
                            titleVisibility: .visible) {
            Button("生成") { generate() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("每一次生成都会通过你的 AI Key 计费，可能需要数十秒。")
        }
    }

    // MARK: - 零件

    /// 三道前置门（构建装配 / 已配 Key / 库里有静态图）是否全过。只有全过才需要整块面板。
    private var hasAllPreconditions: Bool {
        library.isAIAvailable && library.isAIKeyConfigured && !library.images.isEmpty
    }

    /// 厂商名是运行时才拿到的 lproj key，故走 `NSLocalizedString`；拼好再查表会查不到 key、
    /// 静默回退成中文，故先取本地化格式串再 `String(format:)` 填参。
    private var missingKeyText: String {
        String(format: String(localized: "尚未配置 %@ 的 Key，请在设置 ▸ AI 中填写后再生成。"),
               NSLocalizedString(vendor.nameKey, comment: "AI 厂商名"))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 生成动态壁纸").font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce)).foregroundStyle(IHaven.Color.fg)
                Text("图生视频 · 本地逐帧化 · 计费").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
    }

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
        .disabled(library.isGeneratingAI)
    }

    // MARK: - 预览

    /// 源图预览（左）+ 关键信息（右）。
    ///
    /// **为什么不再用通栏大图**：500pt 宽 × 170pt 高的框里 fit 一张 4:3 图，左右各留 140pt 死黑边
    /// —— 看着像加载失败（用户实测原话「布局不美观」）。改成「图片按自身比例定宽 + 右侧信息列」：
    /// 既不裁切（不把预览误导成输出比例），也不留空洞，顺带把「这张图多大、会生成什么」写在旁边。
    private var previewRow: some View {
        HStack(alignment: .top, spacing: IHaven.Space.s5.rawValue) {
            previewImage
            previewMeta
        }
    }

    @ViewBuilder
    private var previewImage: some View {
        if let sel = selected, sel.width > 0, sel.height > 0 {
            let ratio = CGFloat(sel.width) / CGFloat(sel.height)
            ThumbnailImage(url: URL(fileURLWithPath: sel.thumbnailPath))
                // 宽按源图比例推、上限 300pt：竖图不会被压成细条，21:9 宽图也不会顶满整行。
                .frame(width: min(150 * ratio, 300), height: 150)
                .clipShape(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous)
                    .stroke(IHaven.Color.borderSoft, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: IHaven.Radius.md.rawValue, style: .continuous)
                .fill(IHaven.Color.surfaceSunken)
                .frame(width: 200, height: 150)
                .overlay(Text("选择上方一张图即可预览")
                    .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.meta))
        }
    }

    private var previewMeta: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            Text(selected?.fileName ?? "")
                .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.fg)
                .lineLimit(2)
            if let sel = selected {
                HStack(spacing: IHaven.Space.s2.rawValue) {
                    Text("尺寸").foregroundStyle(IHaven.Color.meta)
                    Text(verbatim: "\(sel.width) × \(sel.height)").foregroundStyle(IHaven.Color.fg2)
                }
            }
            Spacer(minLength: 0)
        }
        .font(IHaven.Font.system(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 厂商（只读展示）+ 该厂商下的模型。
    ///
    /// **厂商为什么只读**：换厂商就要换那家的 Key，而填 Key 在设置里；这里给一行「当前是谁 +
    /// 去哪改」就够了，不在生成面板上开第二个配置入口（两个入口改同一份偏好最易出分叉）。
    /// 规格 / 单价写在下拉下面的那一行 —— 计费功能必须让用户点之前就知道花多少。
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text("厂商").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                Text(LocalizedStringKey(vendor.nameKey)).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg)
                Text("换厂商和 Key 在设置 ▸ AI").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text("模型").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                // 只列当前厂商的模型：模型 id 只在厂商内有意义，跨厂商列出来会发出 404。
                Picker("", selection: $modelID) {
                    ForEach(vendor.models) { item in
                        Text(LocalizedStringKey(item.nameKey)).tag(item.id)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 240)
            }
            Text(LocalizedStringKey(model.noteKey))
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            Text("运动描述").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
            TextField("例如：云缓缓飘动，镜头缓慢推近", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain).font(IHaven.Font.system(.md))
                .focused($promptFocused)
                .padding(IHaven.Space.s4.rawValue)
                .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
                .lineLimit(2...4)
                .disabled(library.isGeneratingAI)
        }
    }

    // MARK: - 底栏

    /// 左边状态（生成中 / 失败原因），右边主操作。错误就近放在按钮旁，不再另起一行把面板撑高。
    private var footer: some View {
        HStack(alignment: .center, spacing: IHaven.Space.s4.rawValue) {
            if library.isGeneratingAI {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    ProgressView().controlSize(.small)
                    Text("AI 生成中…可能需要数十秒").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.fg2)
                }
            } else if let error = library.aiErrorMessage {
                Text(error).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            generateButton
        }
    }

    private var generateButton: some View {
        Button(action: { confirmGenerate = true }) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                if library.isGeneratingAI {
                    Text("生成中…")
                } else {
                    Image(systemName: "sparkles")
                    Text("生成动态壁纸")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(library.isGeneratingAI || selected == nil
                  || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func banner(_ text: String, symbol: String, tint: SwiftUI.Color) -> some View {
        Label(text, systemImage: symbol)
            .font(IHaven.Font.system(.sm)).foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IHaven.Space.s5.rawValue)
    }

    // MARK: - 行为

    private func generate() {
        guard let src = selected else { return }
        library.aiErrorMessage = nil
        Task {
            if let item = await library.generateAIVideo(source: src, prompt: prompt) {
                onGenerated(item)
            }
            // 失败原因已写进 library.aiErrorMessage，由 footer 显示。
        }
    }
}
