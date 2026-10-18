import Foundation
import GRDB

/// 相册 CRUD（F-组织）。从 `Database.swift` 拆出：该文件已超 ADR-009 的 300 行
/// （相册整块约 80 行），拆到 extension 文件后各文件单独计行数 —— 与 `ScheduleDatabase.swift`
/// 同路子（协议要求的方法放在 extension 里照样满足 `WallpaperDatabase` 一致性）。
///
/// 仅依赖 `GRDBWallpaperDatabase` 的 `internal` 成员 `db`，不触碰其它表的实现。
extension GRDBWallpaperDatabase {
    func addAlbum(_ album: Album) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO album (id, name, createdAt) VALUES (?,?,?)",
                arguments: [album.id, album.name, album.createdAt.timeIntervalSince1970]
            )
        }
    }

    func removeAlbum(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM album WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM album_item WHERE albumId = ?", arguments: [id])
        }
    }

    func albums() throws -> [Album] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM album ORDER BY createdAt ASC")
                .map { row -> Album in
                    Album(id: (row["id"] as String?) ?? "",
                          name: (row["name"] as String?) ?? "",
                          createdAt: Date(timeIntervalSince1970: (row["createdAt"] as Double?) ?? 0))
                }
        }
    }

    func addAlbumItem(albumId: String, item: Favorite) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO album_item
                    (albumId, wallpaperId, thumbnailURL, originalURL, addedAt)
                VALUES (?,?,?,?,?)
                """,
                arguments: [
                    albumId,
                    item.id,
                    item.thumbnailURL?.absoluteString,
                    item.originalURL.absoluteString,
                    item.addedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func removeAlbumItem(albumId: String, wallpaperId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM album_item WHERE albumId = ? AND wallpaperId = ?",
                arguments: [albumId, wallpaperId]
            )
        }
    }

    func albumItems(albumId: String) throws -> [Favorite] {
        try db.read { db in
            try Row.fetchAll(db,
                             sql: "SELECT * FROM album_item WHERE albumId = ? ORDER BY addedAt DESC",
                             arguments: [albumId])
                .map { row -> Favorite in
                    Favorite(
                        id: (row["wallpaperId"] as String?) ?? "",
                        thumbnailURL: (row["thumbnailURL"] as String?).flatMap { URL(string: $0) },
                        originalURL: URL(string: (row["originalURL"] as String?) ?? "") ?? URL(fileURLWithPath: "/"),
                        addedAt: Date(timeIntervalSince1970: (row["addedAt"] as Double?) ?? 0)
                    )
                }
        }
    }

    func albumIDs(forWallpaper id: String) throws -> [String] {
        try db.read { db in
            try Row.fetchAll(db,
                             sql: "SELECT albumId FROM album_item WHERE wallpaperId = ?",
                             arguments: [id])
                .compactMap { row in row["albumId"] as String? }
        }
    }
}
