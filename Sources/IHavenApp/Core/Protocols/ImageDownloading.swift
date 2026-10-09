import Foundation

/// 图片下载到本地文件的能力（Domain 层协议）。壁纸设置需要本地文件 URL，
/// 故先用此协议把远程原图下载到缓存目录，再交给 WallpaperEngine。
/// 具体实现见 Infrastructure/Image/ImageFileDownloader（URLSession）。
public protocol ImageDownloading: Sendable {
    /// 下载远程 URL 到本地缓存文件，返回本地文件 URL。
    func download(_ remote: URL) async throws -> URL
}
