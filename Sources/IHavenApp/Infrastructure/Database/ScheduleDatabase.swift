import Foundation
import GRDB

/// `schedule` 表的 CRUD（PRD F13）。
///
/// **单独成文件而不是塞进 `Database.swift`**：那个文件已接近 300 行上限（ADR-009），
/// 而 extension 分文件后各文件单独计行数，是这里唯一不触门禁的落点。
///
/// ⚠️ 沿用 `Database.swift:80-82` 的既有硬约束：`StatementArguments` 的 `[Element]` 构造器是
/// failable，**必须把数组字面量直接交给 `arguments:`**（走 `ExpressibleByArrayLiteral`），
/// 不能先 `let args = [...]` 再传 —— 后者会得到 nil 而不是报错。
///
/// ⚠️ GRDB 的 `Row` 下标取值全是可选，每个字段都要 `as? T? ?? default`，不写默认值会在读到
/// NULL 时崩。
extension GRDBWallpaperDatabase {
    func addSchedule(_ schedule: WallpaperSchedule) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO schedule
                (id, name, isEnabled, mode, intervalMinutes, startMinute, endMinute,
                 weekdays, sourceKind, orderMode, cursor, lastRunAt, lastWallpaperID, createdAt)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                arguments: [schedule.id, schedule.name, schedule.isEnabled, schedule.mode.rawValue,
                            schedule.intervalMinutes, schedule.startMinute, schedule.endMinute,
                            schedule.weekdays.map { String($0) }.joined(separator: ","),
                            schedule.source.rawValue, schedule.order.rawValue, schedule.cursor,
                            schedule.lastRunAt?.timeIntervalSince1970, schedule.lastWallpaperID,
                            schedule.createdAt.timeIntervalSince1970])
        }
    }

    func removeSchedule(id: String) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM schedule WHERE id = ?", arguments: [id]) }
    }

    func schedules() throws -> [WallpaperSchedule] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM schedule ORDER BY createdAt ASC").map { row in
                WallpaperSchedule(
                    id: row["id"], name: row["name"], isEnabled: row["isEnabled"],
                    mode: WallpaperSchedule.Mode(rawValue: row["mode"]) ?? .interval,
                    intervalMinutes: row["intervalMinutes"],
                    startMinute: row["startMinute"], endMinute: row["endMinute"],
                    weekdays: (row["weekdays"] as String?)
                        .map { $0.split(separator: ",").compactMap { Int($0) } } ?? [],
                    source: WallpaperSchedule.Source(rawValue: row["sourceKind"]) ?? .imported,
                    order: WallpaperSchedule.Order(rawValue: row["orderMode"]) ?? .random,
                    cursor: row["cursor"],
                    lastRunAt: (row["lastRunAt"] as Double?).map { Date(timeIntervalSince1970: $0) },
                    lastWallpaperID: row["lastWallpaperID"],
                    createdAt: Date(timeIntervalSince1970: row["createdAt"]))
            }
        }
    }

    func updateSchedule(_ schedule: WallpaperSchedule) throws {
        // 只更新可变字段，不重建整条记录 —— `name` / 规则本身不在运行期变。
        try db.write { db in
            try db.execute(sql: """
                UPDATE schedule SET isEnabled = ?, cursor = ?, lastRunAt = ?, lastWallpaperID = ?
                WHERE id = ?
                """,
                arguments: [schedule.isEnabled, schedule.cursor,
                            schedule.lastRunAt?.timeIntervalSince1970,
                            schedule.lastWallpaperID, schedule.id])
        }
    }
}
