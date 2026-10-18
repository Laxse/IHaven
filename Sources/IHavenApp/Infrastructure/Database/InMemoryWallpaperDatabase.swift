import Foundation

/// 内存库（GRDB 的等价实现，用于 Preview / 测试 / DB 初始化失败时的降级）：收藏集 + 已设壁纸记录。
/// 满足 ARCH §4「测试可用内存实现替换数据库」的离线兜底设计。
///
/// `@unchecked Sendable`：类持有可变 `store`，但所有访问都经由 `lock.withLock` 串行化，
/// 实际是线程安全的；与 `WallhavenClient` / `InMemoryKeyProvider` 一致采用显式 unchecked 标注。
final class InMemoryWallpaperDatabase: WallpaperDatabase, @unchecked Sendable {
    private var store: [String: Favorite] = [:]
    private var appliedStore: [String: AppliedWallpaper] = [:]
    private var importedStore: [String: ImportedWallpaper] = [:]
    private let lock = NSLock()

    func addFavorite(_ fav: Favorite) throws { lock.withLock { store[fav.id] = fav } }
    func removeFavorite(id: String) throws { lock.withLock { _ = store.removeValue(forKey: id) } }
    func isFavorite(id: String) -> Bool { lock.withLock { store[id] != nil } }
    func favorites() throws -> [Favorite] {
        lock.withLock { Array(store.values).sorted { $0.addedAt > $1.addedAt } }
    }

    func addApplied(_ item: AppliedWallpaper) throws { lock.withLock { appliedStore[item.id] = item } }
    func removeApplied(id: String) throws { lock.withLock { _ = appliedStore.removeValue(forKey: id) } }
    func applied() throws -> [AppliedWallpaper] {
        lock.withLock { Array(appliedStore.values).sorted { $0.appliedAt > $1.appliedAt } }
    }

    func addImported(_ item: ImportedWallpaper) throws { lock.withLock { importedStore[item.id] = item } }
    func removeImported(id: String) throws { lock.withLock { _ = importedStore.removeValue(forKey: id) } }
    func imported() throws -> [ImportedWallpaper] {
        lock.withLock { Array(importedStore.values).sorted { $0.addedAt > $1.addedAt } }
    }

    // MARK: - 相册（F-组织）

    private var albumStore: [String: Album] = [:]
    private var albumItemStore: [String: [String: Favorite]] = [:]   // albumId -> (wallpaperId -> Favorite)

    func addAlbum(_ album: Album) throws { lock.withLock { albumStore[album.id] = album } }
    func removeAlbum(id: String) throws {
        lock.withLock { _ = albumStore.removeValue(forKey: id); _ = albumItemStore.removeValue(forKey: id) }
    }
    func albums() throws -> [Album] {
        lock.withLock { Array(albumStore.values).sorted { $0.createdAt < $1.createdAt } }
    }
    func addAlbumItem(albumId: String, item: Favorite) throws {
        lock.withLock { albumItemStore[albumId, default: [:]][item.id] = item }
    }
    func removeAlbumItem(albumId: String, wallpaperId: String) throws {
        lock.withLock { _ = albumItemStore[albumId]?.removeValue(forKey: wallpaperId) }
    }
    func albumItems(albumId: String) throws -> [Favorite] {
        lock.withLock {
            let dict = albumItemStore[albumId] ?? [:]
            return Array(dict.values).sorted { $0.addedAt > $1.addedAt }
        }
    }
    func albumIDs(forWallpaper id: String) throws -> [String] {
        lock.withLock {
            albumItemStore.filter { $0.value[id] != nil }.map { $0.key }
        }
    }

    // MARK: - 轮换日程（F13）

    private var scheduleStore: [String: WallpaperSchedule] = [:]

    func addSchedule(_ schedule: WallpaperSchedule) throws { lock.withLock { scheduleStore[schedule.id] = schedule } }
    func removeSchedule(id: String) throws { lock.withLock { _ = scheduleStore.removeValue(forKey: id) } }
    func schedules() throws -> [WallpaperSchedule] {
        lock.withLock { Array(scheduleStore.values).sorted { $0.createdAt < $1.createdAt } }
    }
    func updateSchedule(_ schedule: WallpaperSchedule) throws { lock.withLock { scheduleStore[schedule.id] = schedule } }
}
