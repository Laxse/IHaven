import Foundation

/// 本地相册（纯值类型，无 DB / UI 依赖）。把收藏按主题 / 心情 / 项目分组组织。
///
/// 与 `Favorite` 正交：一张壁纸可以同时在多个相册里，也可以只在某些相册、不是收藏。
/// 相册成员（`album_item`）自带缩略图 / 原图 URL，因此即使原壁纸已取消收藏，相册里的条目
/// 仍能正常渲染（ADR-F-相册：相册是独立的组织层，不依赖收藏存在）。
public struct Album: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public let createdAt: Date

    public init(id: String, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
