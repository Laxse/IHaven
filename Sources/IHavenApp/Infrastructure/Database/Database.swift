import Foundation
import GRDB

/// GRDB 装配（ADR-002，WAL 模式 `DatabasePool`）。
/// 读写多、写少，WAL 读者池让并发读不排在写者后面（ARCH §3.2）。
///
/// 存储归属（ARCH §3.2）：收藏集存 `favorite` 表；图片二进制不入 SQLite，
/// 仅存路径，二进制落 `Application Support/Wallpapers/`。
final class GRDBWallpaperDatabase: WallpaperDatabase {
    /// 跨文件可见（`ScheduleDatabase.swift` 的 extension 要用），但仍是实现细节：
    /// 同模块外不该直接碰它，一律走 `WallpaperDatabase` 协议。
    let db: DatabasePool

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
                t.column("duration", .double)          // 仅动态壁纸：循环秒数
                t.column("fileSize", .integer).notNull()
                t.column("seamless", .boolean)         // 已废弃：视频功能移除后不再写入（保留列以兼容旧库）
                t.column("addedAt", .double).notNull()
            }
        }
        // v4：清理 ADR-016 之前的 `kind='video'` 历史记录。
        //
        // ADR-016 起 `ImportedKind` 只剩 image / animation，旧库里的 video 记录会被
        // `ImportedKind(rawValue:)` 判为 nil 而**静默回退 `.image`** —— 于是那条 mp4 以
        // 「图片」身份混进导入页与瀑布流，点「设为壁纸」还会拿 mp4 去调系统接口。
        // 这里是唯一能兜住老库的地方；记录与文件一起清掉，不留指向已废弃
        // `DynamicWallpapers/` 目录的孤儿行。
        migrator.registerMigration("v4") { db in
            let stale = try Row.fetchAll(
                db, sql: "SELECT filePath, thumbnailPath FROM imported WHERE kind NOT IN ('image','animation')")
            try db.execute(sql: "DELETE FROM imported WHERE kind NOT IN ('image','animation')")
            // 文件清理放到迁移之外：删文件不可回滚，失败也不该让整次迁移失败。
            for row in stale {
                for column in ["filePath", "thumbnailPath"] {
                    if let path = row[column] as String?, !path.isEmpty {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            }
        }
        // v5：轮换日程（PRD F13）。一张表 + `mode` 字段，不拆「间隔表 / 时段表」——
        // 两类规则 90% 字段重合，拆表等于把同一套 CRUD 写两遍（PRD 附录 A-6b 同款先例）。
        // `startMinute` / `endMinute` 存自零点起的分钟数而不是 Date：时段是每日重复的壁钟语义，
        // 存 Date 会引入时区与夏时制歧义。`weekdays` 存 CSV 而不是位掩码。
        migrator.registerMigration("v5") { db in
            try db.create(table: "schedule") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("isEnabled", .boolean).notNull()
                t.column("mode", .text).notNull()
                t.column("intervalMinutes", .integer).notNull()
                t.column("startMinute", .integer).notNull()
                t.column("endMinute", .integer).notNull()
                t.column("weekdays", .text)
                t.column("sourceKind", .text).notNull()
                t.column("orderMode", .text).notNull()
                t.column("cursor", .integer).notNull()
                t.column("lastRunAt", .double)
                t.column("lastWallpaperID", .text)
                t.column("createdAt", .double).notNull()
            }
        }
        // v6：本地相册（F-组织）。两张表——`album` 头上，`album_item` 关联系数（member 自带
        // 缩略图 / 原图 URL，因此即便原壁纸取消收藏，相册条目仍能独立渲染）。
        // 主键 (albumId, wallpaperId) 让重复加入同一张只覆写、不堆积。
        migrator.registerMigration("v6") { db in
            try db.create(table: "album") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .double).notNull()
            }
            try db.create(table: "album_item") { t in
                t.column("albumId", .text).notNull().indexed()
                t.column("wallpaperId", .text).notNull().indexed()
                t.column("thumbnailURL", .text)
                t.column("originalURL", .text).notNull()
                t.column("addedAt", .double).notNull()
                t.primaryKey(["albumId", "wallpaperId"])
            }
        }
        // v7：轮换规则支持「按屏分类」（#67）——每条规则各自指定目标屏，并可指定相册来源。
        // targetDisplay 存 CGDirectDisplayID（0 = 主屏）；albumId 仅 source='album' 时有效。
        // ALTER ADD COLUMN 带默认值，老库的行自动补 0 / NULL，无需回填。
        migrator.registerMigration("v7") { db in
            try db.alter(table: "schedule") { t in
                t.add(column: "targetDisplay", .integer).notNull().defaults(to: 0)
                t.add(column: "albumId", .text)
            }
        }
        try migrator.migrate(pool)
        self.db = pool
        // 裁剪产物清理（ADR-018 清理策略）：删掉不被「已设置」记录引用的孤儿裁剪件，防止磁盘堆积。
        // 以 applied.localPath 为白名单，绝不动用在用的裁剪件。放在 DB 层而非装配点——
        // 这里已经拿到 pool 与 applied() 查询，且入口（IHavenApp）只做装配、不写业务。
        pruneOrphanCrops()
    }

    /// 删除不被「已设置」记录引用的裁剪件（孤儿）。引用集 = 所有 applied.localPath；
    /// 不在其中的 Crops/ 文件即不会再被「重新设置」用到，可安全删除。
    private func pruneOrphanCrops() {
        let referenced = Set((try? applied())?.map(\.localPath) ?? [])
        CropCleaner.clearOrphans(referencedPaths: referenced)
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
                     duration, fileSize, addedAt)
                VALUES (?,?,?,?,?,?,?,?,?,?)
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
                        addedAt: Date(timeIntervalSince1970: (row["addedAt"] as Double?) ?? 0)
                    )
                }
        }
    }

}
