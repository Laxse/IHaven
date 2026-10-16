import Foundation
import Nuke

/// 「设为壁纸」的本地优先取图（PRD F7 离线兜底）。
///
/// 原来三条链路都是**无条件先下载再设置**：`BrowseViewModel.setAsWallpaper` /
/// `setWallpaperFromFavorite` / `DetailViewState.setWallpaper` 全都
/// `downloader.download(url)`。结果是同一张图每设一次就重下一次，断网时直接失败 ——
/// 而它很可能**已经在本地了**。
///
/// 三级查找，从便宜到贵：
/// 1. `AppPaths.sub("Originals")/<原文件名>` —— 以前下载过（`ImageFileDownloader` 的落地位置）。
/// 2. `applied` 记录里的 `localPath`（可能是老版本写在 `$TMPDIR` 的，所以要 `fileExists` 校验）。
/// 3. Nuke `DataCache` 里的原始字节 —— 详情页打开过就一定有，把它**物化**出来用。
///
/// 都不命中才返回 nil，由调用方联网下载。
///
/// ⚠️ **第 3 级的 key 规则**：Nuke 的 data cache key = `request.imageID + thumbnail.identifier +
/// processors.identifier`，而 `imageID` 默认就是 `url.absoluteString`，本项目所有 `LazyImage(url:)`
/// 都不带 processor 与 thumbnail —— 所以 key 就是 URL 本身，文件名是该字符串的 SHA1 小写 hex。
/// 直接调 `makeDataCacheKey(for:)` 比自己拼字符串安全（Nuke 改规则时不用跟着改）。
enum OfflineImageStore {
    /// 原图在本地的位置；找不到返回 nil。
    static func localFile(for remote: URL) -> URL? {
        let direct = AppPaths.sub("Originals").appendingPathComponent(remote.lastPathComponent)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let bytes = cachedOriginalData(for: remote) {
            // 物化到 Originals：下次连第 1 级就能命中，不必每次都从缓存里翻。
            let target = direct
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? bytes.write(to: target, options: .atomic)) != nil { return target }
        }
        return nil
    }

    /// `DataCache` 里的原始字节（仅原图请求，缩略图的 key 不同，不会混）。
    static func cachedOriginalData(for remote: URL) -> Data? {
        guard let cache = ImagePipeline.shared.configuration.dataCache as? DataCache else { return nil }
        let request = ImageRequest(url: remote)
        guard cache.containsData(for: ImagePipeline.shared.cache.makeDataCacheKey(for: request)) else {
            return nil
        }
        return cache.cachedData(for: ImagePipeline.shared.cache.makeDataCacheKey(for: request))
    }

    /// `applied` 记录给出的本地路径是否仍可用（老版本写在 `$TMPDIR`，系统可能已回收）。
    static func usableLocalPath(_ path: String) -> URL? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
