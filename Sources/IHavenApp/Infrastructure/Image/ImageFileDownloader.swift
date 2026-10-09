import Foundation

/// 把远程图片下载到本地缓存文件（实现 `ImageDownloading`）。
/// 壁纸设置需要本地文件 URL，`NSWorkspace` 不接受远程 URL，故先落盘再设置。
/// 落盘目录：`temporaryDirectory/I HavenOriginals/`（系统可回收，不写系统目录）。
struct ImageFileDownloader: ImageDownloading {
    let session: URLSession = .shared

    func download(_ remote: URL) async throws -> URL {
        let (data, _) = try await session.data(from: remote)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHavenOriginals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = remote.lastPathComponent.isEmpty ? UUID().uuidString : remote.lastPathComponent
        let file = dir.appendingPathComponent(fileName)
        try data.write(to: file, options: .atomic)
        return file
    }
}
