import Foundation

/// 已设为壁纸的记录（纯值类型，无 DB / UI 依赖）。每次设壁纸成功后落一条，供侧栏「已设置」回溯。
/// 与 `Favorite` 同构：DB 只存 URL 与本地路径，图片二进制不入 SQLite（ARCH §3.2）。
public struct AppliedWallpaper: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let thumbnailURL: URL?
    public let originalURL: URL
    /// 已下载到本地的原图路径（`Application Support/Wallpapers/`）。
    /// 「重新设置」优先复用这个文件，省掉一次下载；文件被清理时才回退到重新下载原图。
    public let localPath: String
    public let width: Int
    public let height: Int
    public let appliedAt: Date

    public init(id: String,
                thumbnailURL: URL?,
                originalURL: URL,
                localPath: String,
                width: Int,
                height: Int,
                appliedAt: Date) {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.originalURL = originalURL
        self.localPath = localPath
        self.width = width
        self.height = height
        self.appliedAt = appliedAt
    }

    /// 「3840 × 2160」；尺寸缺失（0）时不显示。
    public var resolutionText: String? {
        width > 0 && height > 0 ? "\(width) × \(height)" : nil
    }
}
