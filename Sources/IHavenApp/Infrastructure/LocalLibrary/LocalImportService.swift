import Foundation

/// 本地导入服务（ADR-015 §三）：文件选择 / 拖放 → 探测 → 复制进容器 → 生成缩略图 → 落库。
///
/// 这是 F8 与 F9 **共用的唯一入口**（PRD 附录 A-6b：不得为 F9 另建一套导入逻辑）。
/// 静态图片与本地视频的差异只在「用哪个框架探测」和「多两个字段」，因此共用同一条管线。
struct LocalImportService: LocalImporting {
    private let probe: MediaProbing
    private let thumbnails: ThumbnailProducing
    private let store: WallpaperDatabase

    /// 缩略图 / 首帧 poster 的长边上限。卡片列宽 240–340pt，640px 覆盖 @2x 后仍有富余。
    private static let thumbnailMaxPixel = 640

    init(probe: MediaProbing, thumbnails: ThumbnailProducing, store: WallpaperDatabase) {
        self.probe = probe
        self.thumbnails = thumbnails
        self.store = store
    }

    func importFiles(_ urls: [URL],
                     onEvent: @escaping @MainActor (ImportEvent) -> Void) async -> ImportSummary {
        let files = expand(urls).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        await onEvent(.started(total: files.count))

        var importedCount = 0
        var videoCount = 0
        var rejected: [(fileName: String, reason: String)] = []
        var cancelled = false

        for (index, file) in files.enumerated() {
            // 取消只能停在文件边界：已导入的保留，不提供单文件取消（ADR-015 负面清单）。
            if Task.isCancelled { cancelled = true; break }

            let name = file.lastPathComponent
            do {
                let result = try await probe.probe(file)
                guard result.isSupported else {
                    let reason = result.rejectReason ?? String(localized: "不支持的格式")
                    rejected.append((name, reason))
                    await onEvent(.rejected(fileName: name, reason: reason))
                    continue
                }
                let item = try await importOne(file, probe: result)
                try store.addImported(item)
                importedCount += 1
                if item.isVideo { videoCount += 1 }
                await onEvent(.imported(item))
            } catch {
                // 复制失败、探测异常等一律按「拒绝 + 具体原因」处理，绝不静默跳过。
                let reason = error.localizedDescription
                rejected.append((name, reason))
                await onEvent(.rejected(fileName: name, reason: reason))
            }
            await onEvent(.progress(done: index + 1, total: files.count, current: name))
        }

        let summary = ImportSummary(importedCount: importedCount, rejected: rejected,
                                    videoCount: videoCount, cancelled: cancelled)
        await onEvent(.finished(summary))
        return summary
    }

    // MARK: - 内部

    /// 展开用户选择：文件夹递归扫描，文件原样保留。
    ///
    /// **文件夹里不过滤扩展名**：非图片文件也要进列表，由探测给出拒绝原因并在摘要中列出
    /// （PRD:696「该文件被拒绝并在结果摘要中列出原因」）。在这里静默过滤掉，用户就看不到原因。
    private func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                out.append(contentsOf: scanDirectory(url))
            } else {
                out.append(url)
            }
        }
        return out
    }

    private func scanDirectory(_ dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            out.append(url)
        }
        return out
    }

    /// 导入单个文件：复制 → 生成缩略图 → 装配模型。**不落库**（由调用方统一落，便于失败时整体回退语义清晰）。
    private func importOne(_ source: URL, probe result: MediaProbe) async throws -> ImportedWallpaper {
        let uuid = UUID().uuidString
        let isVideo = result.kind == .video
        let dir = isVideo ? AppPaths.importedVideos : AppPaths.importedImages
        let ext = source.pathExtension.isEmpty
            ? (isVideo ? "mp4" : "jpg")
            : source.pathExtension.lowercased()
        let destination = AppPaths.media(named: uuid, ext: ext, in: dir)

        // 复制进容器：本地库自包含，不依赖访达里的原文件不被移动 / 删除（ADR-015 备选方案三）。
        try FileManager.default.copyItem(at: source, to: destination)

        let thumbnail = AppPaths.thumbnail(named: uuid, in: dir)
        var thumbnailPath = destination.path      // 兜底：缩略图生成失败就用原图，不让整次导入失败
        if isVideo {
            if let _ = try? await thumbnails.makePoster(video: destination,
                                                       maxPixel: Self.thumbnailMaxPixel,
                                                       destination: thumbnail) {
                thumbnailPath = thumbnail.path
            }
        } else {
            if let _ = try? thumbnails.makeThumbnail(source: destination,
                                                    maxPixel: Self.thumbnailMaxPixel,
                                                    destination: thumbnail) {
                thumbnailPath = thumbnail.path
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        var seamless: Bool?
        if isVideo { seamless = await probe.isSeamless(video: destination) }

        return ImportedWallpaper(
            id: uuid,
            fileName: source.lastPathComponent,
            filePath: destination.path,
            thumbnailPath: thumbnailPath,
            kind: result.kind,
            width: result.width,
            height: result.height,
            duration: result.duration,
            fileSize: fileSize,
            seamless: seamless,
            addedAt: Date()
        )
    }
}
