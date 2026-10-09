import Foundation

/// 收藏项（纯值类型，无 DB / UI 依赖）。DB 只存路径与缩略图 URL，二进制不入 SQLite（ARCH §3.2）。
public struct Favorite: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let thumbnailURL: URL?
    public let originalURL: URL
    public let addedAt: Date

    public init(id: String, thumbnailURL: URL?, originalURL: URL, addedAt: Date) {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.originalURL = originalURL
        self.addedAt = addedAt
    }
}
