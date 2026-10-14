import Foundation

/// 本地导入项（ADR-015 §一）：静态图片与本地视频共用一个模型，靠 `kind` 区分。
///
/// **为什么不复用 `Wallpaper`**：它的 20 个字段全由 wallhaven 响应形状决定（`purity` /
/// `category` / `views` / `favorites` / `colors` / `short_url` …）。本地文件没有这些概念，
/// 硬塞进去每个字段都是恒定的假值 —— 而假值比缺失更危险：它会让「按 purity 过滤」
/// 「按上传者分组」这类逻辑在本地项上静默出错。
public struct ImportedWallpaper: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    /// 原始文件名（展示用，保留用户认知）。
    public let fileName: String
    /// 导入后本机容器内的原文件绝对路径（自包含，不依赖访达里的原文件）。
    public let filePath: String
    /// ≤640px 缩略图（图片）或首帧 poster（视频）的绝对路径。
    public let thumbnailPath: String
    public let kind: ImportedKind
    public let width: Int
    public let height: Int
    /// 仅视频：时长（秒）。图片恒 nil。
    public let duration: Double?
    public let fileSize: Int
    /// 仅视频：首尾帧是否连续（SPEC §7.4.6）。图片恒 nil。
    public let seamless: Bool?
    public let addedAt: Date

    public var isVideo: Bool { kind == .video }

    public var resolutionText: String { "\(width) × \(height)" }

    public init(id: String, fileName: String, filePath: String, thumbnailPath: String,
                kind: ImportedKind, width: Int, height: Int, duration: Double?,
                fileSize: Int, seamless: Bool?, addedAt: Date) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.kind = kind
        self.width = width
        self.height = height
        self.duration = duration
        self.fileSize = fileSize
        self.seamless = seamless
        self.addedAt = addedAt
    }
}

public enum ImportedKind: String, Codable, Sendable, Hashable {
    case image
    case video
}

/// 瀑布流统一网格项（ADR-015 §四）：网络项与本地项在同一列表里混排，
/// 本地项带「本地」标识（PRD:697 的可区分标识）。
/// ⚠️ 不能叫 `GridItem`：SwiftUI 自带同名类型（`.gridItem` 布局用的那个），在同一个 module 里
/// 引入 SwiftUI 的文件会撞名（`FilterView.swift` 已实测撞上）。
public enum WallpaperGridItem: Identifiable, Sendable, Hashable {
    case network(Wallpaper)
    case local(ImportedWallpaper)

    public var id: String {
        switch self {
        case .network(let wp): wp.id
        case .local(let item): item.id
        }
    }

    /// 瀑布流列高按真实宽高比算：两种来源都有可信的 width/height。
    public var aspectRatio: CGFloat {
        switch self {
        case .network(let wp): CGFloat(wp.width) / CGFloat(wp.height)
        case .local(let item): CGFloat(item.width) / CGFloat(item.height)
        }
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}
