import Foundation
import GRDB

/// GRDB 装配（ADR-002，WAL 模式 `DatabasePool`）。
/// 读写多、写少，WAL 读者池让并发读不排在写者后面（ARCH §3.2）。
///
/// 存储归属（ARCH §3.2）：收藏集存 `favorite` 表；图片二进制不入 SQLite，
/// 仅存路径，二进制落 `Application Support/Wallpapers/`。
final class GRDBWallpaperDatabase: WallpaperDatabase {
    private let db: DatabasePool

    init() throws {
        // 路径统一走 `AppPaths.root`（ADR-015 §二）：在出现第三处硬编码之前先收敛。
        let dir = AppPaths.root
        let dbURL = dir.appendingPathComponent("ihaven.sqlite")

        let pool = try DatabasePool(path: dbURL.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "favorite") { t in
                t.column("id", .text).primaryKey()
                t.column("thumbnailURL", .text)
                t.column("originalURL", .text).notNull()
                t.column("addedAt", .double).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "applied") { t in
                t.column("id", .text).primaryKey()
                t.column("thumbnailURL", .text)
                t.column("originalURL", .text).notNull()
                t.column("localPath", .text).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("appliedAt", .double).notNull()
            }
        }
        // v3：本地导入项（ADR-015 §一）。静态图片与本地视频共用一张表，靠 kind 区分 ——
        // 两者的导入管线 90% 相同，拆表等于把同一条管线写两遍（PRD 附录 A-6b 已警告）。
        migrator.registerMigration("v3") { db in
            try db.create(table: "imported") { t in
                t.column("id", .text).primaryKey()
                t.column("fileName", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("thumbnailPath", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("duration", .double)          // 仅视频
                t.column("fileSize", .integer).notNull()
                t.column("seamless", .boolean)         // 仅视频：首尾帧是否连续
                t.column("addedAt", .double).notNull()
            }
        }
        try migrator.migrate(pool)
        self.db = pool
    }

    func addFavorite(_ fav: Favorite) throws {
        try db.write { db in
            // StatementArguments 的 [Element] 构造器是 failable（返回可选），
            // 直接用数组字面量交给 `arguments:`（ExpressibleByArrayLiteral），绕开可选类型。
            try db.execute(
                sql: "INSERT OR REPLACE INTO favorite (id, thumbnailURL, originalURL, addedAt) VALUES (?,?,?,?)",
                arguments: [
                    fav.id,
                    fav.thumbnailURL?.absoluteString,
                    fav.originalURL.absoluteString,
                    fav.addedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func removeFavorite(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM favorite WHERE id = ?", arguments: [id])
        }
    }

    func isFavorite(id: String) -> Bool {
        (try? db.read { db in
            try Row.fetchOne(db, sql: "SELECT id FROM favorite WHERE id = ?", arguments: [id]) != nil
        }) ?? false
    }

    func addApplied(_ item: AppliedWallpaper) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO applied
                    (id, thumbnailURL, originalURL, localPath, width, height, appliedAt)
                VALUES (?,?,?,?,?,?,?)
                """,
                arguments: [
                    item.id,
                    item.thumbnailURL?.absoluteString,
                    item.originalURL.absoluteString,
                    item.localPath,
                    item.width,
                    item.height,
                    item.appliedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func removeApplied(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM applied WHERE id = ?", arguments: [id])
        }
    }

    func applied() throws -> [AppliedWallpaper] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM applied ORDER BY appliedAt DESC")
                .map { row -> AppliedWallpaper in
                    AppliedWallpaper(
                        id: (row["id"] as String?) ?? "",
                        thumbnailURL: (row["thumbnailURL"] as String?).flatMap { URL(string: $0) },
                        originalURL: URL(string: (row["originalURL"] as String?) ?? "") ?? URL(fileURLWithPath: "/"),
                        localPath: (row["localPath"] as String?) ?? "",
                        width: (row["width"] as Int?) ?? 0,
                        height: (row["height"] as Int?) ?? 0,
                        appliedAt: Date(timeIntervalSince1970: (row["appliedAt"] as Double?) ?? 0)
                    )
                }
        }
    }

    func favorites() throws -> [Favorite] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM favorite ORDER BY addedAt DESC")
                .map { row -> Favorite in
                    Favorite(
                        id: (row["id"] as String?) ?? "",
                        thumbnailURL: (row["thumbnailURL"] as String?).flatMap { URL(string: $0) },
                        originalURL: URL(string: (row["originalURL"] as String?) ?? "") ?? URL(fileURLWithPath: "/"),
                        addedAt: Date(timeIntervalSince1970: (row["addedAt"] as Double?) ?? 0)
                    )
                }
        }
    }

    // MARK: - 本地导入（ADR-015）

    func addImported(_ item: ImportedWallpaper) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO imported
                    (id, fileName, filePath, thumbnailPath, kind, width, height,
                     duration, fileSize, seamless, addedAt)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
                arguments: [
                    item.id,
                    item.fileName,
                    item.filePath,
                    item.thumbnailPath,
                    item.kind.rawValue,
                    item.width,
                    item.height,
                    item.duration,
                    item.fileSize,
                    item.seamless,
                    item.addedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func removeImported(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM imported WHERE id = ?", arguments: [id])
        }
    }

    func imported() throws -> [ImportedWallpaper] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM imported ORDER BY addedAt DESC")
                .map { row -> ImportedWallpaper in
                    ImportedWallpaper(
                        id: (row["id"] as String?) ?? "",
                        fileName: (row["fileName"] as String?) ?? "",
                        filePath: (row["filePath"] as String?) ?? "",
                        thumbnailPath: (row["thumbnailPath"] as String?) ?? "",
                        kind: ImportedKind(rawValue: (row["kind"] as String?) ?? "") ?? .image,
                        width: (row["width"] as Int?) ?? 0,
                        height: (row["height"] as Int?) ?? 0,
                        duration: row["duration"] as Double?,
                        fileSize: (row["fileSize"] as Int?) ?? 0,
                        seamless: row["seamless"] as Bool?,
                        addedAt: Date(timeIntervalSince1970: (row["addedAt"] as Double?) ?? 0)
                    )
                }
        }
    }
}
