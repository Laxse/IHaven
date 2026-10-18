import Foundation
import SwiftUI

/// 本地库（导入图片 + 生成的动态壁纸）的共享状态机（ADR-015 / ADR-016）。
///
/// 一个 ViewModel 同时服务两个页签：`Features/Import`（静态图）与 `Features/DynamicWallpaper`（动态壁纸）。
/// 两者读同一份 `imported`、共用同一条导入管线（PRD 附录 A-6b：不得为动态壁纸另建一套导入逻辑），
/// 只是按 `kind` 过滤出不同子集。动态壁纸由静态图本地生成，生成也走本 ViewModel。
@MainActor @Observable
final class LocalLibraryViewModel {
    /// 全部导入项（按导入时间倒序）。静态图与动态壁纸都在这里，由视图层按 `kind` 过滤。
    /// setter `internal`：AI 生成的落库在 `LocalLibraryViewModel+AIVideo` extension 里做，够不到 private。
    var imported: [ImportedWallpaper] = []
    var images: [ImportedWallpaper] { imported.filter { !$0.isAnimation } }
    var animations: [ImportedWallpaper] { imported.filter { $0.isAnimation } }

    // MARK: 导入中状态

    private(set) var isImporting = false
    private(set) var importDone = 0
    private(set) var importTotal = 0
    private(set) var importCurrent = ""
    /// 上一次导入被拒绝的文件与原因（PRD:696 要求的结果摘要）。
    private(set) var lastRejected: [(fileName: String, reason: String)] = []
    private(set) var lastSummaryMessage: String?

    // MARK: 动态壁纸播放态

    /// 正在播放的项（引擎状态的镜像；引擎不是 `@Observable`，必须镜像才能被 SwiftUI 观察）。
    private(set) var dynamicPlaying: ImportedWallpaper?
    private(set) var dynamicPaused = false

    private let importer: LocalImporting
    private let panel: FileImportPresenting
    let database: WallpaperDatabase   // internal：AIVideo extension 要写库
    private let engine: WallpaperEngine
    private let dynamicEngine: DynamicWallpaperPlaying
    private let renderer: AnimationRendering
    // MARK: - AI 图生视频（#70，Plan B）
    /// 可选依赖，未装配（Preview / 降级）时 AI 不可用；实现在 AppAssembly 注入，Feature 只见协议。
    let aiVideo: AIVideoGenerating?
    let videoFrames: VideoFrameExtracting?
    let aiKey: KeyProvider?
    /// AI 生成中 / 上次失败文案；AIVideo extension 要写，故 internal。
    var isGeneratingAI = false
    var aiErrorMessage: String?
    private var importTask: Task<Void, Never>?

    init(importer: LocalImporting,
         panel: FileImportPresenting,
         database: WallpaperDatabase,
         engine: WallpaperEngine,
         dynamicEngine: DynamicWallpaperPlaying,
         renderer: AnimationRendering,
         aiVideo: AIVideoGenerating? = nil,
         videoFrames: VideoFrameExtracting? = nil,
         aiKey: KeyProvider? = nil) {
        self.importer = importer
        self.panel = panel
        self.database = database
        self.engine = engine
        self.dynamicEngine = dynamicEngine
        self.renderer = renderer
        self.aiVideo = aiVideo
        self.videoFrames = videoFrames
        self.aiKey = aiKey
        dynamicEngine.onStateChange = { [weak self] in
            Task { @MainActor in self?.syncDynamicState() }
        }
    }

    func load() {
        imported = (try? database.imported()) ?? []
    }

    // MARK: 导入

    func chooseFiles() {
        let urls = panel.chooseImportFiles()
        guard !urls.isEmpty else { return }
        importURLs(urls)
    }

    func importURLs(_ urls: [URL]) {
        guard !isImporting, !urls.isEmpty else { return }
        lastRejected = []
        lastSummaryMessage = nil
        isImporting = true
        importDone = 0
        importTotal = 0
        importCurrent = ""

        // `[weak self]`：Task 持有 self 到导入结束；用户切走页面时 ViewModel 仍应被释放。
        importTask = Task { [importer, weak self] in
            let summary = await importer.importFiles(urls) { [weak self] event in
                self?.handle(event)
            }
            self?.finishImport(summary)
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
    }

    private func handle(_ event: ImportEvent) {
        switch event {
        case .started(let total):
            importTotal = total
        case .progress(let done, let total, let current):
            importDone = done
            importTotal = total
            importCurrent = current
        case .imported(let item):
            // 服务端按 addedAt 倒序返回，导入中最新的一条插到最前，与之一致。
            imported.insert(item, at: 0)
        case .rejected(let fileName, let reason):
            lastRejected.append((fileName, reason))
        case .finished:
            break   // 摘要在 importFiles 返回后统一处理
        }
    }

    private func finishImport(_ summary: ImportSummary) {
        isImporting = false
        importTask = nil
        load()   // 以库为唯一事实来源，避免导入中插入顺序与库排序不一致
        lastSummaryMessage = Self.summaryText(summary)
    }

    /// 摘要素材：导入数 / 跳过数 / 取消。空导入也要给一句话，不能让用户猜。
    ///
    /// ⚠️ **不能把数字直接插进 `String(localized:)` 的字面量**：那会先拼成 "3 个文件已导入"
    /// 再拿去查表，key 查不到 → 英文环境下静默回退成中文（与 `Text(_: String)` 同一个陷阱）。
    /// 正确做法是先用静态 key 取本地化格式串，再 `String(format:)` 填参 —— 与
    /// `browseStatusBar` 的 "已加载 %lld 张" 完全同构。
    static func summaryText(_ summary: ImportSummary) -> String {
        if summary.cancelled && summary.importedCount == 0 {
            return String(localized: "已取消导入，没有文件入库")
        }
        var text = String(format: String(localized: "%lld 个文件已导入"), summary.importedCount)
        if !summary.rejected.isEmpty {
            text += String(format: String(localized: "，%lld 个不支持已跳过"), summary.rejected.count)
        }
        if summary.cancelled { text += String(localized: "（已取消）") }
        return text
    }

    // MARK: 静态壁纸

    /// 把本地图片设为桌面壁纸。返回 nil 表示成功，否则为错误文案（调用方弹 toast）。
    func setAsWallpaper(_ item: ImportedWallpaper) async -> String? {
        let fileURL = URL(fileURLWithPath: item.filePath)
        do {
            try engine.setWallpaper(fileURL: fileURL, for: WallpaperTarget.resolveScreen(),
                                    mode: WallpaperTarget.fillMode(),
                                    // ImportedWallpaper 不存主色，用中性回退。
                                    fillColor: WallpaperTarget.neutralFillColor())
            // 与网络壁纸同路落「已设置」，让侧栏「已设置」页能一起回溯本地项。
            try? database.addApplied(AppliedWallpaper(
                id: item.id,
                thumbnailURL: URL(fileURLWithPath: item.thumbnailPath),
                originalURL: fileURL,
                localPath: item.filePath,
                width: item.width,
                height: item.height,
                appliedAt: Date()))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 用**裁剪产物**设为桌面壁纸（竖图黑边的根治入口，与 `setAsWallpaper` 同形状）。
    /// 返回 nil 表示成功，否则为错误文案（调用方弹 toast）。
    ///
    /// ⚠️ **模式写死 `.fill`**：产物宽高比已等于目标屏，取整的 ±1px 误差在 `.fit` 下会变成
    /// 一条极细留白，`.fill` 只会裁掉 1px 边缘 —— 这里有意覆盖用户的填充模式设置。
    ///
    /// ⚠️ `localPath` 写**裁剪产物**路径（下一次「重新设置」要用的就是它），`originalURL`
    /// 仍写 `item.filePath`（原始来源不能因为裁过就丢失）。
    func applyCropped(_ file: URL, pixelSize: CGSize, item: ImportedWallpaper) async -> String? {
        do {
            try engine.setWallpaper(fileURL: file, for: WallpaperTarget.resolveScreen(),
                                    mode: .fill,
                                    // ImportedWallpaper 不存主色，用中性回退。
                                    fillColor: WallpaperTarget.neutralFillColor())
            try? database.addApplied(AppliedWallpaper(
                id: item.id,
                thumbnailURL: URL(fileURLWithPath: item.thumbnailPath),
                originalURL: URL(fileURLWithPath: item.filePath),
                localPath: file.path,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                appliedAt: Date()))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: 动态壁纸

    func playDynamic(_ item: ImportedWallpaper) -> String? {
        do {
            try dynamicEngine.play(item)
            syncDynamicState()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stopDynamic() {
        dynamicEngine.stop()
        syncDynamicState()
    }

    func toggleDynamicPause() {
        if dynamicPaused { dynamicEngine.resume() } else { dynamicEngine.pause() }
        syncDynamicState()
    }

    private func syncDynamicState() {
        dynamicPlaying = dynamicEngine.playing
        dynamicPaused = dynamicEngine.isPaused
    }

    // MARK: 动态壁纸生成（ADR-016）

    /// 生成进行中（驱动生成面板的进度态）。
    private(set) var isGenerating = false

    /// 由一张静态图本地生成动态壁纸：渲染帧序列 → 落库 → 返回新项。
    /// 渲染是 CPU 重活，放到后台线程；模型装配与落库在主线程（GRDB 池本身可并发读）。
    ///
    /// - Parameters:
    ///   - source: 已导入的静态图项。
    ///   - spec: 动画参数（秒数 / 幅度）；帧数按 `秒数 × 12` 推导（12fps 足够慢速运动）。
    /// - Returns: 生成的动态壁纸项；失败返回 nil。
    func generateAnimation(source: ImportedWallpaper, spec: AnimationSpec) async -> ImportedWallpaper? {
        guard let screen = NSScreen.main else { return nil }
        let aspect = max(0.1, screen.frame.width / screen.frame.height)
        let sourceURL = URL(fileURLWithPath: source.filePath)
        let uuid = UUID().uuidString
        let dir = AppPaths.animations.appendingPathComponent(uuid, isDirectory: true)

        var genSpec = spec
        genSpec.frameCount = max(24, Int((spec.seconds * 12).rounded()))

        isGenerating = true
        defer { isGenerating = false }
        do {
            let frames = try await Task.detached(priority: .userInitiated) { [renderer = renderer] in
                try renderer.render(source: sourceURL, spec: genSpec, outputDir: dir, outputAspect: aspect)
            }.value
            guard let first = frames.first else { return nil }

            // 帧像素尺寸 ≈ 工作长边 × 输出比例，用于卡片宽高比与分辨率展示。
            let long = Double(AnimationRenderer.workMaxPixel)
            let dims: (Int, Int) = aspect >= 1
                ? (Int(long), Int((long / aspect).rounded()))
                : (Int((long * aspect).rounded()), Int(long))

            let item = ImportedWallpaper(
                id: uuid,
                fileName: "动态-\(source.fileName)",
                filePath: dir.path,
                thumbnailPath: first.path,
                kind: .animation,
                width: dims.0, height: dims.1,
                duration: spec.seconds,
                fileSize: 0,
                addedAt: Date()
            )
            try database.addImported(item)
            imported.insert(item, at: 0)
            return item
        } catch {
            return nil
        }
    }

    // MARK: 删除

    /// 删除导入项：先停掉正在播放的它，再删库记录，最后清容器里的文件。
    /// 文件清理失败不影响记录删除 —— 记录是用户可见的事实，文件只是缓存。
    func remove(_ item: ImportedWallpaper) {
        if dynamicPlaying?.id == item.id { dynamicEngine.stop(); syncDynamicState() }
        try? database.removeImported(id: item.id)
        imported.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(atPath: item.filePath)
        try? FileManager.default.removeItem(atPath: item.thumbnailPath)
    }
}
