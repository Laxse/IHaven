import Foundation

/// 本机容器内的固定路径（`Application Support/IHaven/`）。
///
/// ⚠️ **集中在这里，不要在别处再拼一遍。** 收敛之前已有两处各自硬编码：数据库路径
/// （`Database.swift` 的 `applicationSupportDirectory + "IHaven"`）与原图临时目录
/// （`ImageFileDownloader.swift` 的 `temporaryDirectory + "IHavenOriginals"`）。
/// 出现第三处之前先收成一处 —— 目录名三处漂移是「改了名字漏改一处」这类静默 bug 的标准入口。
///
/// 目录语义（ADR-015 / ADR-016）：
/// - `Wallpapers/`：本地导入的静态图原文件 + ≤640px 缩略图
/// - `Animations/`：由静态图本地生成的动态壁纸帧序列（每项一个 `<uuid>/` 子目录，内含 `frame-*.jpg`）
/// 二进制一律不入 SQLite（ARCH §3.2：BLOB 会使 DB 膨胀，只存路径）。
enum AppPaths {
    /// `Application Support/IHaven`，不存在则创建。
    static var root: URL {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("IHaven", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var importedImages: URL { sub("Wallpapers") }
    static var animations: URL { sub("Animations") }
    /// 裁剪派生产物（ADR-018 §Decision 4）：由「裁剪后设为壁纸」生成、可重建的缓存，非资产。
    /// 此前是四处散落的 `sub("Crops")` 动态传参，收敛到一处常量（见本文件头注释）。
    static var crops: URL { sub("Crops") }

    /// 生成子目录（不存在则创建）并返回。
    static func sub(_ name: String) -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 导入产物命名：原文件 `<uuid>.<ext>`，缩略图 / poster `<uuid>-thumb.jpg`。
    /// UUID 而非原始文件名 —— 同名文件重复导入不该互相覆盖，且原始文件名可能含路径分隔符。
    static func media(named uuid: String, ext: String, in dir: URL) -> URL {
        dir.appendingPathComponent("\(uuid).\(ext)")
    }

    static func thumbnail(named uuid: String, in dir: URL) -> URL {
        dir.appendingPathComponent("\(uuid)-thumb.jpg")
    }
}
