import Foundation

/// 裁剪产物清理（ADR-018 §Decision 4：独立目录 `AppPaths.crops` + 确定性文件名）。
///
/// 裁剪文件 `<base>-crop-<W>x<H>@<x>-<y>.jpg` **不含时间戳、不含 wallhaven id**，确定性命名
/// 便于同选框去重复用，代价是**没有任何时间/数量淘汰**——不同原图产生的裁剪件会一直堆积。
///
/// 安全优先的清理策略：以 `applied.localPath` 为白名单，只保留「当前仍被某条已设置记录引用」的
/// 裁剪件；其余（重新裁剪后被覆盖前的旧件、取消设置后失效的件）一律视为孤儿删除。
/// 这样「已设置 → 重新设置」永远能拿到本地文件（ADR-018 §Consequences 风险点），不会误删在用的。
struct CropCleaner {
    /// 统计 `Crops/` 占用：总字节、孤儿文件数、孤儿字节。
    static func usage(referencedPaths: Set<String>) -> CropUsage {
        var total = 0, orphanCount = 0, orphaned = 0
        for url in cropFileURLs() {
            let bytes = fileBytes(url)
            total += bytes
            if !referencedPaths.contains(url.path) {
                orphanCount += 1
                orphaned += bytes
            }
        }
        return CropUsage(totalBytes: total, orphanCount: orphanCount, orphanedBytes: orphaned)
    }

    /// 删除未被 `referencedPaths` 引用的裁剪件，返回释放字节数。
    @discardableResult
    static func clearOrphans(referencedPaths: Set<String>) -> Int {
        var freed = 0
        for url in cropFileURLs() where !referencedPaths.contains(url.path) {
            freed += fileBytes(url)
            try? FileManager.default.removeItem(at: url)
        }
        return freed
    }

    // MARK: - 私有

    private static func cropFileURLs() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.crops.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { AppPaths.crops.appendingPathComponent($0) }
    }

    /// 单文件实际磁盘占用（`totalFileAllocatedSize` 优先，取不到退回 `fileSize`）。
    private static func fileBytes(_ url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true else { return 0 }
        return values.totalFileAllocatedSize ?? values.fileSize ?? 0
    }
}

/// `Crops/` 目录的占用快照（与 `FrameSequenceUsage` 同构）。
struct CropUsage {
    var totalBytes: Int
    var orphanCount: Int
    var orphanedBytes: Int
}
