import Foundation

/// 动态壁纸帧序列的磁盘占用统计。
///
/// `orphaned` / `orphanCount` 是**已不在库中**的那部分（目录名不在 `inUseIDs` 里）：
/// 生成中途失败、或删库记录时文件没删干净都会留下这种孤儿目录。
/// 清理只针对这部分 —— 仍在库里的动态壁纸删了就等于删用户的素材，绝不能碰。
struct FrameSequenceUsage: Sendable, Equatable {
    var totalBytes = 0
    var orphanedBytes = 0
    var orphanCount = 0
}

/// 设置 · 存储页签的数据源（ADR-017）。
///
/// Feature 层不直接碰 `DataCache`（Nuke）也不直接遍历 `AppPaths` 删文件，全部经此协议注入，
/// 与 `ClipboardWriting` / `KeyStore` 同一套路（ARCH §4：Feature 只认 Core 协议）。
protocol StorageUsage: Sendable {
    /// 图片缓存占用（字节）：缩略图 + 高清图原始字节。
    func imageCacheBytes() -> Int

    /// 清除图片缓存。内容全部可再生，清掉没有副作用，只是下次浏览要重新下载。
    func clearImageCache()

    /// 帧序列占用统计。`inUseIDs` = 仍在库中的动态壁纸 id（同时也是帧目录名）。
    func frameUsage(inUseIDs: Set<String>) -> FrameSequenceUsage

    /// 删除未入库的帧序列目录，返回释放的字节数。
    func clearOrphanedFrames(inUseIDs: Set<String>) -> Int
}
