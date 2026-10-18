import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 视频 → JPEG 帧序列（#70，Plan B）：把 AI 图生视频得到的 MP4 按目标帧率抽成
/// `frame-%04d.jpg`，喂给现有帧动画引擎（`DynamicWallpaperEngine` 按文件名字典序播放）。
///
/// ## 为什么用 AVFoundation 而不是 FFmpeg
/// 本 App 不捆任何二进制 blob（Non-goals：FFmpeg / 私有 API）。AVFoundation 原生解码
/// H.264 / HEVC 的 MP4 / MOV —— AI 视频服务商输出的正是这两种封装，无需第三方解码器。
/// （WEBM / MKV 仍不支持，与导入页同一约束。）
///
/// ## 实测固化的三个要点（/tmp 原型验证，勿凭印象改）
/// 1. 精确取帧必须 `requestedTimeToleranceBefore = .zero` + `requestedTimeToleranceAfter = .zero`
///    （没有单一的 `requestedTimeTolerance` 属性 —— 编译期会报 no member）。
/// 2. `appliesPreferredTrackTransform = true`：带上视频显示方向，否则带 rotation 的视频会转 90°。
/// 3. `generateCGImagesAsynchronously` 回调**乱序**、且视频末尾那一帧常返回 nil。
///    故按「请求时刻反推 index」归位，缺失帧用「上一张有效帧」前向填充，保证 `frame-%04d.jpg` 连续。
struct AVFoundationFrameExtractor: VideoFrameExtracting {
    func extractFrames(from video: URL, fps: Double, maxLongEdge: Int, pingPong: Bool, into outputDir: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: video)
        // `.load(.duration)`：直接读 `asset.duration` 在 macOS 13 起已废弃。
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard seconds.isFinite, seconds > 0.1 else { throw AIVideoError.noOutput }

        let count = max(2, Int((seconds * fps).rounded()))
        let times = (0..<count).map {
            NSValue(time: CMTime(value: CMTimeValue($0), timescale: CMTimeScale(fps)))
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        // 等比缩到长边 ≤ maxLongEdge（控磁盘 / 内存；AI 视频常见 768p~1080p，够当壁纸）。
        gen.maximumSize = CGSize(width: maxLongEdge, height: maxLongEdge)

        let sink = FrameSink(count: count)
        // 把回调式 API 桥接成 async：收齐全部帧才继续。**不能用 DispatchSemaphore.wait** ——
        // 异步上下文里阻塞等待会报 unavailable。用 continuation + 计数器归位。
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cg, _, result, _ in
                // 回调乱序：按「请求时刻 × fps」反推该帧序号。
                let idx = Int((CMTimeGetSeconds(requestedTime) * fps).rounded())
                if sink.store(idx, result == .succeeded ? cg : nil) { cont.resume() }
            }
        }

        // 写盘是 CPU / IO 重活，放后台；这里只碰 Sendable 的 sink / count / outputDir。
        return try await Task.detached(priority: .userInitiated) { [sink, count, outputDir, pingPong] in
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            var forward: [URL] = []
            var lastGood: CGImage?
            for idx in 0..<count {
                // 前向填充：某帧解码失败（末尾尤多）时沿用上一张有效帧，保证序号连续、播放不跳空。
                if let img = sink.image(at: idx) { lastGood = img }
                guard let img = lastGood else { continue }
                let url = outputDir.appendingPathComponent(String(format: "frame-%04d.jpg", idx))
                if writeJPEG(img, to: url) { forward.append(url) }
            }
            guard forward.count >= 2 else { throw AIVideoError.noOutput }

            var all = forward
            if pingPong {
                // 正放 + 倒放无缝循环：把 forward[count-2]、forward[count-3]…forward[1] 依序复制到
                // 末尾（frame 编号续下去），末帧平滑折返起点。复制既有 JPEG 比重新编码省 CPU。
                // 不含首帧 forward[0]：避免折返点上同一帧连播两次造成的凝滞。
                let base = forward.count
                for offset in 0..<(base - 2) {
                    let src = forward[base - 2 - offset]
                    let dst = outputDir.appendingPathComponent(String(format: "frame-%04d.jpg", base + offset))
                    do { try FileManager.default.copyItem(at: src, to: dst); all.append(dst) } catch {}
                }
            }
            return all
        }.value
    }

    /// 私有 JPEG 写出（quality 0.85：AI 帧是最终壁纸画面，比动态帧序列的 0.72 略高）。
    /// 不 `throws`：失败即返回 false，由调用方按「少一帧」处理，不值得为单帧写出抛错中断整轮。
    private func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.85) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }
}

/// 抽帧回调的归位容器。回调在 AVFoundation 队列上乱序到达，用锁保护的字典按 index 存，
/// 收齐后按序号写出。`@unchecked Sendable`：所有访问都经 `lock` 串行化，实际线程安全
/// （要跨 `@Sendable` 的回调 / detached 边界捕获它）。
private final class FrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [Int: CGImage] = [:]
    private var received = 0
    private let expected: Int

    init(count: Int) { expected = count }

    /// 存一帧；返回是否已收齐全部回调（恰好最后一次返回 true → 调用方 resume 一次）。
    func store(_ idx: Int, _ image: CGImage?) -> Bool {
        lock.withLock {
            if let image { collected[idx] = image }
            received += 1
            return received >= expected
        }
    }

    func image(at idx: Int) -> CGImage? {
        lock.withLock { collected[idx] }
    }
}
