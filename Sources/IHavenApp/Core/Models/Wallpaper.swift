import Foundation

/// 壁纸实体（纯值类型，无 UI / 网络依赖）。仅建模 wallhaven 响应的关键字段。
///
/// ⚠️ `source` 必须为 `String?` 而非 `URL?`：wallhaven 对“无来源”壁纸返回空串 `""`，
/// 而 `URL` 的解码遇 `""` 会抛 `DecodingError.dataCorrupted: Invalid URL string`（空串非合法 URL，
/// `decodeIfPresent` 只容忍 `null`/缺键，不容忍“存在但非法”）。这是 2026-10-09 加载失败的真实根因。
public struct Wallpaper: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let url: URL
    public let shortURL: URL
    public let createdAt: String
    public let purity: String
    public let category: String
    public let width: Int
    public let height: Int
    public let resolution: String
    public let ratio: String
    public let fileSize: Int
    public let fileType: String
    public let views: Int
    public let favorites: Int
    public let source: String?
    public let colors: [String]
    public let path: URL
    public let thumbs: Thumbs

    public struct Thumbs: Codable, Sendable, Hashable {
        public let original: URL?
        public let large: URL?
        public let small: URL?
    }

    private enum CodingKeys: String, CodingKey {
        case id, url
        case shortURL = "short_url"
        case createdAt = "created_at"
        case purity, category
        case width = "dimension_x"
        case height = "dimension_y"
        case resolution, ratio
        case fileSize = "file_size"
        case fileType = "file_type"
        case views, favorites, source, colors, path, thumbs
    }
}

/// 一页搜索结果。
public struct WallhavenPage: Codable, Sendable {
    public let data: [Wallpaper]
    public let meta: Meta

    public struct Meta: Codable, Sendable {
        public let currentPage: Int
        public let lastPage: Int
        public let perPage: String
        public let total: Int
        public let query: Query?
        public let seed: String?

        private enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case lastPage = "last_page"
            case perPage = "per_page"
            case total, query, seed
        }
    }

    public struct Query: Codable, Sendable {
        public let q: String?
        public let purity: String?
    }
}
