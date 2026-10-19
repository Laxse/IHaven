import Foundation
import ImageIO
import SwiftUI

/// AI 图生视频生成（#70，Plan B）。拆成 extension 文件：`LocalLibraryViewModel.swift` 已逼近
/// ADR-009 的 300 行上限，extension 分文件后各文件单独计行数。
///
/// 与主类的 `generateAnimation` 并列：那条「本地渲静图」，这条「AI 生视频抽帧」，落库口径一致
/// （都是 `kind: .animation` + `Animations/<uuid>/frame-*.jpg`），播放都走同一个引擎。
extension LocalLibraryViewModel {
    /// AI 生成是否可用（三个依赖都装配了；Preview / 降级装配下为 false）。
    var isAIAvailable: Bool { aiVideo != nil && videoFrames != nil && aiKeys != nil }

    /// 当前**选中厂商**的 Key 是否已配置（驱动入口的「去设置」引导）。
    ///
    /// 必须按厂商现查：每家的 Key 是独立文件，若读一个固定实例，会把 A 厂的 Key 当成
    /// B 厂「已配置」—— 用户切了厂商却还能点生成，然后收到一个 401。
    var isAIKeyConfigured: Bool {
        guard let aiKeys else { return false }
        let key = aiKeys.keyProvider(for: AIVideoVendorCatalog.selected().id).currentKey
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 静态图 + 运动描述 → AI 图生视频 MP4 → AVFoundation 抽帧 → 落库为动态壁纸项。
    /// - Returns: 新项；任何一步失败返回 nil 并把原因写进 `aiErrorMessage`。
    func generateAIVideo(source: ImportedWallpaper, prompt: String) async -> ImportedWallpaper? {
        guard let aiVideo, let videoFrames else {
            aiErrorMessage = String(localized: "当前构建未启用 AI 生成。")
            return nil
        }
        guard isAIKeyConfigured else {
            aiErrorMessage = AIVideoError.missingKey.errorDescription
            return nil
        }
        let uuid = UUID().uuidString
        let dir = AppPaths.animations.appendingPathComponent(uuid, isDirectory: true)

        isGeneratingAI = true
        aiErrorMessage = nil
        defer { isGeneratingAI = false }
        do {
            let sourceURL = URL(fileURLWithPath: source.filePath)
            // 1) AI 生成 MP4（异步，可能数十秒；Key 无效 / 额度 / 内容拦截在这里分类抛出）。
            let videoURL = try await aiVideo.generateVideo(sourceImage: sourceURL, prompt: prompt)
            // 临时 MP4 抽完即删，不在磁盘留垃圾。
            defer { try? FileManager.default.removeItem(at: videoURL) }
            // 2) 抽成 12fps 帧序列（与本地生成同一帧率，引擎按 duration/count 推播放间隔）；
            //    pingPong=true：AI 片段不为无缝设计，正放+倒放折返成无缝循环。
            let frames = try await videoFrames.extractFrames(from: videoURL, fps: 12,
                                                            maxLongEdge: 1920, pingPong: true, into: dir)
            guard let first = frames.first else {
                aiErrorMessage = AIVideoError.noOutput.errorDescription
                return nil
            }
            // 3) 与 generateAnimation 同一落库口径。
            let dims = framePixelSize(first)
            let item = ImportedWallpaper(
                id: uuid,
                fileName: "AI动态-\(source.fileName)",
                filePath: dir.path,
                thumbnailPath: first.path,
                kind: .animation,
                width: dims.0, height: dims.1,
                duration: Double(frames.count) / 12.0,
                fileSize: 0,
                addedAt: Date()
            )
            try database.addImported(item)
            imported.insert(item, at: 0)
            return item
        } catch let error as AIVideoError {
            aiErrorMessage = error.errorDescription
            return nil
        } catch {
            aiErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// 读一帧的像素尺寸（只取属性、不解码全图）—— 用于卡片宽高比 / 分辨率展示。
    private func framePixelSize(_ url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0 else {
            return (0, 0)
        }
        return (w, h)
    }
}
