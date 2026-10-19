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

    /// 等比缩略图 URL。
    ///
    /// ⚠️ `thumbs` 三档里**只有 `original` 保持原图比例**（长边 ≤300px，实测 8 份样本）。
    /// `large` 恒 **432×243**、`small` 恒 **300×200** —— 都是固定比例的**硬裁件**，与原图比例
    /// 无关：竖图 3805×5700 的 `large` 同样是一张 432×243 的横图（2026-10-15 `sips` 实测）。
    /// 所以任何「按原图比例显示」的地方都必须走 `original`，用另两档必然被裁。
    public var aspectThumb: URL? { thumbs.original }

    /// 是否为**本地导入项**（`ImportView` 落库时用 `UUID().uuidString` 作 id）。
    ///
    /// [!] 判据是 **id 形状**，不是 `path.isFileURL` —— 「已设置 / 时间线」里的网络壁纸原图
    /// 也常驻 `Application Support/Originals`，`path` 同样是 `file://`；用 path 判断会把它们
    /// 一并当成导入项，从此不再请求 wallhaven 详情，标签 / 上传者全丢。
    /// wallhaven 的 id 是 6 位 base36 短码，永远解析不成 UUID。
    public var isLocalImport: Bool { UUID(uuidString: id) != nil }

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
        /// ⚠️ `query` 必须为 `String?` 而非嵌套对象：wallhaven 的 `meta.query` 返回的是
        /// 搜索词字符串（如 `"nature"`），并非 `{q, purity}` 对象。用结构体会抛
        /// `DecodingError.typeMismatch: Expected to decode Dictionary but found a string`。
        /// 这是 2026-10-10 带 `q` 搜索时加载失败的真实根因（无 q 时该字段为 null，掩盖了问题）。
        ///
        /// 适用边界：官方 API 文档称，用 `id:##` 做**精确标签搜索**时，`meta.query` 会是
        /// `{"id": 1, "tag": "anime"}` 对象。**本项目走 `+tag` 组合而非 `id:`**，故该字段恒为
        /// 字符串（实测 `q=+artwork +illustration` → `meta.query = "+artwork +illustration"`，
        /// 2026-10-14）。若将来改用 `id:` 精确标签搜索，此类型需重新评估 —— 届时为真实可达分支。
        public let query: String?
        public let seed: String?

        private enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case lastPage = "last_page"
            case perPage = "per_page"
            case total, query, seed
        }
    }
}

// MARK: - 预览构造（收藏 / 已设置 进入详情二级页面用）

extension Wallpaper {
    /// 从收藏记录构造「预览用」`Wallpaper`，供详情页二级页面复用 `DetailView`。
    /// 收藏只持久化 id / 缩略图 / 原图 URL，没有尺寸与 wallhaven 元数据；详情页会按 id 重新拉取
    /// 标签 / 上传者等信息（wallhaven 来源才有），本地来源则信息栏为空、仅大图与操作可用。
    init(previewFrom favorite: Favorite) {
        self.init(id: favorite.id,
                  url: favorite.originalURL,
                  shortURL: favorite.originalURL,
                  createdAt: "",
                  purity: "",
                  category: "",
                  width: 0, height: 0,
                  resolution: "", ratio: "",
                  fileSize: 0, fileType: "",
                  views: 0, favorites: 0,
                  source: nil, colors: [],
                  path: favorite.originalURL,
                  thumbs: Thumbs(original: favorite.thumbnailURL, large: nil, small: nil))
    }

    /// 从「已设置」记录构造「预览用」`Wallpaper`。本地原图还在就直接以 `file://` 作为 `path`
    /// （详情页大图与「设为壁纸」免一次下载），否则回退原图 URL；尺寸取记录里的宽高。
    init(previewFrom applied: AppliedWallpaper) {
        let path: URL = FileManager.default.fileExists(atPath: applied.localPath)
            ? URL(fileURLWithPath: applied.localPath)
            : applied.originalURL
        self.init(id: applied.id,
                  url: applied.originalURL,
                  shortURL: applied.originalURL,
                  createdAt: "",
                  purity: "",
                  category: "",
                  width: applied.width, height: applied.height,
                  resolution: applied.resolutionText ?? "", ratio: "",
                  fileSize: 0, fileType: "",
                  views: 0, favorites: 0,
                  source: nil, colors: [],
                  path: path,
                  thumbs: Thumbs(original: applied.thumbnailURL, large: nil, small: nil))
    }
}
