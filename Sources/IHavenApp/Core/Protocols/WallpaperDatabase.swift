import Foundation

/// 本地收藏库协议（Domain 层）。具体实现见 Infrastructure/Database：
/// 生产用 GRDB（ADR-002），测试 / 降级用 InMemory（ARCH §4 依赖方向，便于离线兜底替换）。
///
/// 注意：返回 `[Favorite]` 而非 `Wallpaper`，保持 Core 模型纯净（Favorite 不含 API 响应冗余字段）。
public protocol WallpaperDatabase: Sendable {
    func addFavorite(_ fav: Favorite) throws
    func removeFavorite(id: String) throws
    /// 同步读取是否收藏（供 UI 即时反查）。
    func isFavorite(id: String) -> Bool
    func favorites() throws -> [Favorite]
}
