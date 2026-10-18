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
    /// 选中的模型（聚合层：一套 Key 跑多个模型）。持久化 —— 下一次打开仍是这个。
    @AppStorage(UserPreferenceKey.aiVideoModel) private var modelID = AIVideoModelCatalog.fallback.id

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            header
            if !library.isAIAvailable {
                banner("当前构建未启用 AI 生成。", symbol: "exclamationmark.triangle", tint: IHaven.Color.warn)
            } else if !library.isAIKeyConfigured {
                banner("尚未配置 AI Key，请在设置 ▸ AI 中填写后再生成。", symbol: "key", tint: IHaven.Color.warn)
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
        // 约 600pt（标题 46 + 选图 108 + 预览 150 + 模型 42 + 描述 92 + 底栏 32 + 间距 80 + 内边距 48）。
        // 620 多出的 20pt 由 Spacer 吃掉：底栏被顶到下沿，错误文案折行也不会溢出。
        .frame(width: 540, height: 620)
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

    /// 模型选择。聚合层的价值就在这：一套 Replicate Key 跑多个厂商的模型，换模型不换 Key。
    /// 规格 / 单价写在下拉下面的那一行 —— 计费功能必须让用户点之前就知道花多少。
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text("模型").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg2)
                Picker("", selection: $modelID) {
                    ForEach(AIVideoModelCatalog.all) { model in
                        Text(LocalizedStringKey(model.nameKey)).tag(model.id)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 240)
            }
            Text(LocalizedStringKey(AIVideoModelCatalog.model(id: modelID).noteKey))
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
