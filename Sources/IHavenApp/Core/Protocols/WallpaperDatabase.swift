import Foundation

/// 本地库协议（Domain 层）：收藏集 + 已设壁纸记录。具体实现见 Infrastructure/Database：
/// 生产用 GRDB（ADR-002），测试 / 降级用 InMemory（ARCH §4 依赖方向，便于离线兜底替换）。
///
/// 注意：返回 `[Favorite]` / `[AppliedWallpaper]` 而非 `Wallpaper`，保持 Core 模型纯净
/// （二者只带 UI 需要的字段，不含 API 响应冗余字段）。
public protocol WallpaperDatabase: Sendable {
    func addFavorite(_ fav: Favorite) throws
    func removeFavorite(id: String) throws
    /// 同步读取是否收藏（供 UI 即时反查）。
    func isFavorite(id: String) -> Bool
    func favorites() throws -> [Favorite]

    /// 已设壁纸：新增一条（同 id 覆盖，含新的 appliedAt —— 同一张再次设置要把时间刷新到最新）。
    func addApplied(_ item: AppliedWallpaper) throws
    func removeApplied(id: String) throws
    /// 按设置时间倒序返回（最近设置的在最前）。
    func applied() throws -> [AppliedWallpaper]

    // MARK: - 本地导入（F8 / F9，ADR-015）

    /// 新增一条导入记录（同 id 覆盖）。
    func addImported(_ item: ImportedWallpaper) throws
    func removeImported(id: String) throws
    /// 按导入时间倒序返回（最近导入的在最前）。
    func imported() throws -> [ImportedWallpaper]
}
