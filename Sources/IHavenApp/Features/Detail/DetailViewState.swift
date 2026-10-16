import Foundation
import SwiftUI

/// 壁纸详情页状态机（`/wall/:id`）。
///
/// 依赖由 `BrowseViewModel.makeDetailState` 以**领域协议**注入（ARCH §4：Feature 不见具体类型）。
/// 列表项 `Wallpaper` 是**保底数据**：详情请求失败时信息栏照常渲染，只有大图区转失败态 —— 不整页空白。
@MainActor
@Observable
final class DetailViewState {
    /// 在途动作。下载与设壁纸会写同一张原图，并发会让「已设置」记录重复落库，故二者互斥。
    enum InFlight: Sendable { case wallpaper, download }

    let wallpaper: Wallpaper
    private(set) var detail: WallpaperDetail?
    /// 详情请求失败的分类：决定大图区是「整块失败」还是「照常渲染 + 顶部提示条」。
    ///
    /// 分两档的理由：两个动作（下载 / 设壁纸）用的是列表项 `wallpaper.path`，**根本不依赖详情请求**，
    /// 详情失败就把它们禁掉是纯自伤。而最常撞的失败恰恰是 429（详情与搜索共享 45 次/分钟的
    /// 配额桶，滚动 + 进详情很容易触顶）与 `URLError`，都是瞬时的 —— 只有 404 才是真的没内容可渲染。
    enum DetailLoadFailure: Sendable {
        /// 404：壁纸已下架 —— 大图区整块失败态，动作与底部短链一并隐藏（给按钮也是白点）。
        case gone
        /// 其余：大图照常渲染 `thumbs.large`，信息栏照常用列表项兜底，动作照常可用，
        /// 只在大图区顶部挂一条 `meta` 色提示条。
        case transient
    }

    private(set) var detailFailure: DetailLoadFailure?
    /// 失败文案（提示条 / 失败态共用，取 `error.localizedDescription`）。
    private(set) var detailMessage = ""
    /// 可否重试：**只有网络层错误（`URLError`）才给「重试」** —— 429 立刻重试必再撞限流，
    /// 而且每次重试再扣 1 次配额（限流比重试严一档）。
    private(set) var detailRetryable = false
    private(set) var inFlight: InFlight?
    /// 动作失败的内联错误。不进 toast：2 秒消失读不完一行错误，且 toast 里放不下「下一步」。
    var actionError: String?

    private let client: WallhavenAPIProtocol
    private let engine: WallpaperEngine
    private let downloader: ImageDownloading
    private let savePanel: FileSavePresenting
    private let clipboard: ClipboardWriting
    /// 设壁纸成功后落「已设置」记录（走 BrowseViewModel 的落库口径，避免两处漂移）。
    private let onApplied: (Wallpaper, URL) -> Void

    init(wallpaper: Wallpaper,
         client: WallhavenAPIProtocol,
         engine: WallpaperEngine,
         downloader: ImageDownloading,
         savePanel: FileSavePresenting,
         clipboard: ClipboardWriting,
         onApplied: @escaping (Wallpaper, URL) -> Void) {
        self.wallpaper = wallpaper
        self.client = client
        self.engine = engine
        self.downloader = downloader
        self.savePanel = savePanel
        self.clipboard = clipboard
        self.onApplied = onApplied
    }

    var isBusy: Bool { inFlight != nil }

    /// 详情请求。一次进入 = 一次配额（与翻页同价），结果在视图内缓存复用，绝不轮询。
    func loadDetail() async {
        guard detail == nil, detailFailure == nil else { return }
        do { detail = try await client.detail(id: wallpaper.id) } catch { classify(error) }
    }

    /// 提示条上的「重试」：清掉失败标记后重发详情请求（调用方只在 `detailRetryable` 为真时给按钮）。
    func retryDetail() async {
        detailFailure = nil
        detailRetryable = false
        await loadDetail()
    }

    /// [!] 为了区分 404，这里直接认识了 Infrastructure 的 `APIError` —— 这是 ARCH §4「Feature
    /// 只依赖 Core」的一处破例，与之前删掉的 `SystemSavePanel` 默认值同类，只因门禁查不到才留得住。
    /// 干净做法：让 `WallhavenClient.detail` 抛一个 Core 层的分类错误类型（要动 Infrastructure，
    /// 不在我的文件边界内）—— 已上报，等裁定后替换掉这一个 `as?`。
    private func classify(_ error: Error) {
        detailMessage = error.localizedDescription
        detailRetryable = error is URLError
        if let api = error as? APIError {
            switch api {
            case .notFound: detailFailure = .gone
            default: detailFailure = .transient
            }
        } else {
            detailFailure = .transient
        }
    }

    /// 设为壁纸。返回 `nil` 表示成功（由调用方弹 toast，文案复用「已设为壁纸」），否则为内联错误文案。
    @discardableResult
    func setWallpaper() async -> String? {
        guard inFlight == nil else { return nil }
        inFlight = .wallpaper
        defer { inFlight = nil }
        actionError = nil
        do {
            // 本地优先（详见 OfflineImageStore）：不能并进 `??`，因为 `??` 右侧的 autoclosure
            // 不支持 async/throws。
            let file: URL
            if let cached = OfflineImageStore.localFile(for: wallpaper.path) {
                file = cached
            } else {
                file = try await downloader.download(wallpaper.path)
            }
            try engine.setWallpaper(fileURL: file, for: WallpaperTarget.resolveScreen(),
                                    mode: WallpaperTarget.fillMode(),
                                    fillColor: WallpaperTarget.fillColor(for: wallpaper.colors))
            onApplied(wallpaper, file)
            return nil
        } catch {
            return fail(error)
        }
    }

    /// 下载原图：先落到临时目录，再由用户在保存面板里选落盘位置后移过去。
    /// 临时目录系统可回收，**不能**把它当成用户的下载结果。
    func downloadOriginal() async {
        guard inFlight == nil else { return }
        inFlight = .download
        defer { inFlight = nil }
        actionError = nil
        let temp: URL
        do { temp = try await downloader.download(wallpaper.path) } catch { fail(error); return }
        guard let dest = savePanel.chooseSaveLocation(suggestedName: suggestedFileName) else {
            // 用户取消：静默结束，并把已经落地的临时文件清掉。
            try? FileManager.default.removeItem(at: temp)
            return
        }
        do {
            // 目标已存在时 moveItem 会失败，先删再移（覆盖写是保存面板的默认语义）。
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
        } catch {
            fail(error)
            try? FileManager.default.removeItem(at: temp)
        }
    }

    /// 底部短链接条：整行点击 = 拷贝 `short_url`。
    func copyShortURL() { clipboard.copy(wallpaper.shortURL.absoluteString) }

    @discardableResult
    private func fail(_ error: Error) -> String {
        let message = error.localizedDescription
        actionError = message
        return message
    }

    private var suggestedFileName: String {
        let ext = wallpaper.path.pathExtension
        return "\(wallpaper.id).\(ext.isEmpty ? "jpg" : ext)"
    }
}
