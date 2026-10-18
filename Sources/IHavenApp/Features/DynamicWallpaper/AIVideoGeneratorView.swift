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
                promptField
                if library.isGeneratingAI {
                    progressRow
                } else {
                    generateButton
                }
                if let error = library.aiErrorMessage { errorLine(error) }
            }
        }
        .padding(IHaven.Space.s6.rawValue)
        // 贴合内容的高度：AI 面板没有本地生成器的实时预览 + 参数滑块，内容约 375pt。
        // 曾照抄本地器的 600 高，结果底部一大片空白、头轻脚轻（用户实测）。
        .frame(width: 540, height: 440)
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
        }
    }

    private var progressRow: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            ProgressView().controlSize(.small)
            Text("AI 生成中…可能需要数十秒").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
        }
    }

    private var generateButton: some View {
        Button(action: { confirmGenerate = true }) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Image(systemName: "sparkles")
                Text("生成动态壁纸")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selected == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func errorLine(_ msg: String) -> some View {
        Text(msg).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
            .fixedSize(horizontal: false, vertical: true)
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
            // 失败原因已写进 library.aiErrorMessage，由上面的 errorLine 显示。
        }
    }
}
