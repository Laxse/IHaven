import Foundation

/// 壁纸详情实体：`GET /api/v1/w/<id>` 响应 `{"data":{...}}` 中 `data` 的建模。
///
/// **为什么不把 `uploader` / `tags` 加进 `Wallpaper`**：详情响应是搜索项字段的严格超集
/// （只多这两个顶层字段，其余 18 个同名同型 —— `docs/VERIFIED-WALLHAVEN-DETAIL.md` §1/§3）。
/// 若把二者作为 Optional 塞进 `Wallpaper`，`/search` 响应照样解码成功，于是「详情页一定有
/// uploader/tags」这条已实测的不变量在类型层面消失，UI 侧每次都要解一次空值。
/// 因此采用**嵌套复用**：`base` 复用 `Wallpaper` 的 20 个字段定义（字段定义只有一处），
/// 详情专属字段另放本类型。JSON 是**扁平**的，`Wallpaper.init(from:)` 会自动忽略
/// `uploader` / `tags` 这两个它 CodingKeys 里没有的键，故可直接从同一 container 解码。
public struct WallpaperDetail: Codable, Sendable, Identifiable, Hashable {
    /// 与 `/search` 结果项完全同构的 18 个共有字段。
    public let base: Wallpaper
    /// 上传者。**上传者账号注销时的响应形状未实测**（8 份样本全为非 null）→ 按 Optional 解码。
    public let uploader: Uploader?
    /// 标签列表，元素个数实测 3~26 可变；**未取到空数组样本**，故缺失键时按 `[]` 兜底。
    public let tags: [Tag]

    init(base: Wallpaper, uploader: Uploader?, tags: [Tag]) {
        self.base = base
        self.uploader = uploader
        self.tags = tags
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try Wallpaper(from: decoder)
        uploader = try c.decodeIfPresent(Uploader.self, forKey: .uploader)
        // 兜底而非 `decode`：`tags` 键缺失时不应让整个详情请求失败（UI 侧另有无标签降级）。
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
    }

    /// 必须与 `init(from:)` 对称：**先**让 `base` 把它的 20 个字段写进 encoder，再从同一
    /// encoder 追加 `uploader` / `tags` —— 实测 `JSONEncoder` 会把两次取到的 keyed container
    /// 合并成一层（生成 `{"id":…,"uploader":…,"tags":…}`），详情 JSON 本就是扁平的。
    /// 若省略此方法，编译器合成的 `encode(to:)` 会产出 `{"base":{…},…}` 的**嵌套**结构，
    /// 与本类型自己的 `init(from:)` 不对称 —— 目前 mock 正是靠编码生响应，会当场对不上。
    public func encode(to encoder: any Encoder) throws {
        try base.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(uploader, forKey: .uploader)
        try c.encode(tags, forKey: .tags)
    }

    private enum CodingKeys: String, CodingKey {
        case uploader, tags
    }

    public var id: String { base.id }

    /// 详情页的「收藏 / 设为壁纸」走的是 `Wallpaper` 路径（与搜索列表同一套接口）。
    public func toWallpaper() -> Wallpaper { base }

    /// 「找相似」搜索词：取前 3 个标签名拼 wallhaven 的 `+tag` 表达式。
    ///
    /// 官方 `like:<id>` 参数实测被 Cloudflare 拦截（403 HTML），唯一可用替代是 `+tag`
    /// （VERIFIED-WALLHAVEN-DETAIL.md §4）。两条硬约束来自实测：
    /// 1. **多词标签的空格必须原样保留** —— `+digital art` 有效，`+digital_art` 返回 0 条。
    /// 2. 标签数取 3 个：1~2 个过宽，4 个以上有收敛到空结果的风险。
    public var similarSearchQuery: String {
        tags.prefix(3).map { "+\($0.name)" }.joined(separator: " ")
    }

    public struct Uploader: Codable, Sendable, Hashable {
        public let username: String
        /// 实测仅见 `"User"`；完整取值域文档未写明，**不得枚举硬编码**。
        public let group: String
        public let avatar: Avatar

        public struct Avatar: Codable, Sendable, Hashable {
            /// JSON 键以数字开头（`200px` / `128px` / `32px` / `20px`），必须给显式 rawValue。
            public let px200: URL
            public let px128: URL
            public let px32: URL
            public let px20: URL

            private enum CodingKeys: String, CodingKey {
                case px200 = "200px"
                case px128 = "128px"
                case px32 = "32px"
                case px20 = "20px"
            }
        }
    }

    public struct Tag: Codable, Sendable, Hashable {
        public let id: Int
        /// 可含空格（如 `digital art`），比较与拼接时**不得**做下划线替换。
        public let name: String
        public let alias: String
        public let categoryID: Int
        public let category: String
        public let purity: String
        public let createdAt: String

        private enum CodingKeys: String, CodingKey {
            case id, name, alias
            case categoryID = "category_id"
            case category, purity
            case createdAt = "created_at"
        }
    }
}

/// `/api/v1/w/<id>` 的响应包装。
///
/// 顶层恒为 `{"data": {…}}` 且**没有 `meta`** —— 与 `/search` 的 `{"data":[...],"meta":{…}}`
/// 不同（VERIFIED-WALLHAVEN-DETAIL.md §1）。`WallpaperDetail` 建模的是**里层那个对象**，
/// 所以客户端必须经由本 envelope 解码；直接 `decode(WallpaperDetail.self, from:)` 会拿到
/// 只有 `data` 一个键的顶层容器，报 `keyNotFound(id)` 这种与真实原因无关的错误。
public struct WallpaperDetailEnvelope: Codable, Sendable {
    public let data: WallpaperDetail
}
