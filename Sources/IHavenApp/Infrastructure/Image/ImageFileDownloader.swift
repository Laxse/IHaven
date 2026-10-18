import Foundation

/// 把远程图片下载到本地缓存文件（实现 `ImageDownloading`）。
/// 壁纸设置需要本地文件 URL，`NSWorkspace` 不接受远程 URL，故先落盘再设置。
///
/// ⚠️ **落盘目录从 `$TMPDIR` 改到 `AppPaths.sub("Originals")`**（2026-10-17）。
/// 原来写在 `temporaryDirectory/IHavenOriginals/`，而 **macOS 会回收 `$TMPDIR`**
/// （重启 / 磁盘压力 / 定期清理）—— 于是「已设置」记录里的 `localPath` 随时可能失效，
/// 「重新设置」会静默走成重新下载。`Application Support` 不会被系统回收，这才是原图该待的地方。
///
/// 文件名仍用 `remote.lastPathComponent`：同一张图重复下载覆盖同一文件，不会堆积
/// （对离线复用反而是好事）。
struct ImageFileDownloader: ImageDownloading {
    let session: URLSession = .shared

    func download(_ remote: URL) async throws -> URL {
        // 本地优先（`OfflineImageStore` 三级查找：Originals 落盘 → applied 记录 → Nuke DataCache 物化）。
        // 详情页已展示过的高清原图、或之前设壁纸落过的原图都已在本地，直接复用：省带宽、
        // 也不白白消耗 wallhaven 45 次/分钟的共享配额。「下载原图」（`DetailViewState.downloadOriginal`）
        // 走的就是这条——大图在详情页已由 Nuke 载入进 DataCache，命中后直接拿本地文件弹保存面板，不联网。
        if remote.isFileURL { return remote }
        if let cached = OfflineImageStore.localFile(for: remote) { return cached }
        let (data, _) = try await session.data(from: remote)
        let dir = AppPaths.sub("Originals")
        let fileName = remote.lastPathComponent.isEmpty ? UUID().uuidString : remote.lastPathComponent
        let file = dir.appendingPathComponent(fileName)
        try data.write(to: file, options: .atomic)
        return file
    }
}
