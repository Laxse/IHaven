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
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("IHaven", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
}
