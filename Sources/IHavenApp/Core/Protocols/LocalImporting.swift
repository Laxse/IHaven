import Foundation

/// 本地导入能力（Core 层协议，实现落在 `Infrastructure/LocalLibrary`）。
///
/// **取消语义**：实现内部在每个文件之间检查 `Task.isCancelled`。调用方在自己的 `Task`
/// 上调 `cancel()` 即可让整批导入停在下一个文件边界 —— 已导入的文件保留，不提供单文件取消。
public protocol LocalImporting: Sendable {
    /// 导入一批文件 / 文件夹（文件夹递归扫描）。
    /// - Parameters:
    ///   - urls: 用户选择的文件或文件夹 URL。
    ///   - onEvent: 进度事件，保证在 `@MainActor` 上回调（实现内部自己切线程做 IO）。
    /// - Returns: 批量摘要（成功数 / 拒绝清单 / 视频数）。
    func importFiles(_ urls: [URL],
                     onEvent: @escaping @MainActor (ImportEvent) -> Void) async -> ImportSummary
}

public enum ImportEvent: Sendable {
    /// 扫描完成，得知总数。
    case started(total: Int)
    /// 每完成一个文件（成功或拒绝）发一次。
    case progress(done: Int, total: Int, current: String)
    case imported(ImportedWallpaper)
    /// 文件被拒绝：带**具体原因**（ADR-008:71 错误信息必须具体，禁止静默失败）。
    case rejected(fileName: String, reason: String)
    case finished(ImportSummary)
}

public struct ImportSummary: Sendable {
    public var importedCount: Int
    /// `(文件名, 原因)`，顺序即用户选择顺序，便于对照。
    public var rejected: [(fileName: String, reason: String)]
    public var videoCount: Int
    /// 用户中途取消：已导入的保留，摘要照常返回。
    public var cancelled: Bool

    public init(importedCount: Int, rejected: [(fileName: String, reason: String)],
                videoCount: Int, cancelled: Bool) {
        self.importedCount = importedCount
        self.rejected = rejected
        self.videoCount = videoCount
        self.cancelled = cancelled
    }
}
