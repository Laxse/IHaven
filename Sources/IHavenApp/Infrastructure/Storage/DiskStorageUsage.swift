import Foundation
import Nuke

/// `StorageUsage` 的磁盘实现：图片缓存读 Nuke 的 `DataCache`，帧序列直接量 `AppPaths.animations`。
///
/// ⚠️ **缓存占用走目录实测而不是 `DataCache.totalSize`**：后者读的是内存里的索引，
/// 进程刚起来、索引还没建完时是 0，设置页会显示「占用 0 字节」——明明磁盘上有几百 MB。
/// 直接量 `DataCache.path` 指向的目录，值永远和磁盘一致。
struct DiskStorageUsage: StorageUsage {
    func imageCacheBytes() -> Int {
        guard let cache = imageDataCache else { return 0 }
        return directoryBytes(cache.path)
    }

    func clearImageCache() {
        imageDataCache?.removeAll()
        // 内存缓存也要清：否则清完磁盘后当前窗口里显示的还是旧位图，
        // 用户点了「清除缓存」却看不到任何变化，会以为没生效。
        NukeImagePipeline.pipeline.configuration.imageCache?.removeAll()
    }

    func frameUsage(inUseIDs: Set<String>) -> FrameSequenceUsage {
        var usage = FrameSequenceUsage()
        for name in frameDirectoryNames() {
            let bytes = directoryBytes(AppPaths.animations.appendingPathComponent(name, isDirectory: true))
            usage.totalBytes += bytes
            guard !inUseIDs.contains(name) else { continue }
            usage.orphanedBytes += bytes
            usage.orphanCount += 1
        }
        return usage
    }

    func clearOrphanedFrames(inUseIDs: Set<String>) -> Int {
        var freed = 0
        for name in frameDirectoryNames() where !inUseIDs.contains(name) {
            let url = AppPaths.animations.appendingPathComponent(name, isDirectory: true)
            freed += directoryBytes(url)
            try? FileManager.default.removeItem(at: url)
        }
        return freed
    }

    // MARK: - 私有

    private var imageDataCache: DataCache? {
        NukeImagePipeline.pipeline.configuration.dataCache as? DataCache
    }

    /// 帧序列目录下的顶层子目录名（每项一个 `<uuid>/`）。
    private func frameDirectoryNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.animations.path)) ?? []
        // `.DS_Store` 之类的隐藏文件不是帧序列目录，跳过。
        return names.filter { !$0.hasPrefix(".") }
    }

    /// 递归统计目录占用。`totalFileAllocatedSize` 优先（磁盘实际占用），取不到退回 `fileSize`。
    private func directoryBytes(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == false { continue }
            total += values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
        }
        return total
    }
}
