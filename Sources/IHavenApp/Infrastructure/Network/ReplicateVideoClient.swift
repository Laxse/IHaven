import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AI 图生视频客户端 —— Replicate 实现（#70，Plan B）。Feature 只见 `AIVideoGenerating` 协议。
///
/// ## 为什么选 Replicate
/// 一套 REST（提交 prediction → 轮询 → 下载）覆盖大量图生视频模型，按次计费、用户自备 Key，
/// 与「gated behind an optional key」的定位吻合。协议留了替换余地：换提供商只需再写一个
/// `AIVideoGenerating` 实现，装配点换一行。
///
/// ## ⚠️ 未真机验证的部分（首次真跑必须核对，勿直接信）
/// 这里**无法真调**（无 Key、付费）。`model` 名与 `input` 字段名以官方文档为准，不同图生视频
/// 模型的 schema 会有差异（有的收 `prompt`、有的收 `motion_prompt`，输出可能是字符串或数组）。
/// 故解析端做了防御式处理（output 兼容字符串 / 数组），但 **model 常量与 input 键名需首次
/// 用真 Key 跑通后确认**，与当初 wallhaven 端点要实测一遍同理。
struct ReplicateVideoClient: AIVideoGenerating {
    private let keyProvider: KeyProvider
    /// 默认模型：文本 + 图像条件化的图生视频。**可换** —— 换模型只改这一处 + 对应 input 键名。
    /// 选文本条件化而非 SVD：Plan B 要的是「按运动描述生成」，纯图条件的 SVD 不吃 prompt。
    private let model: String
    private let baseURL = URL(string: "https://api.replicate.com/v1")!

    init(keyProvider: KeyProvider, model: String = "minimax/video-01") {
        self.keyProvider = keyProvider
        self.model = model
    }

    func generateVideo(sourceImage: URL, prompt: String) async throws -> URL {
        let key = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIVideoError.missingKey }

        // 底图转成 API 友好的 JPEG（≤1024 长边）：模型可靠吃 JPEG，且显著减小请求体
        // （原图可能是 4K / HEIC，直接 base64 会是数 MB，甚至被模型拒收）。
        let jpeg = try jpegForAPI(sourceImage)
        let dataURI = "data:image/jpeg;base64," + jpeg.base64EncodedString()

        let body: [String: Any] = [
            "model": model,
            "input": ["image": dataURI, "prompt": prompt],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("predictions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Prefer: wait = 让服务端尽量同步等完再返回（上限约 60s），省掉多数轮询。
        request.setValue("wait", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try classifyHTTP(response)
        var prediction = try parsePrediction(data)

        // 同步等待超时 → 进入轮询（每 2s 一次，总上限约 3 分钟；图生视频常 30s~2min）。
        if prediction.status == "starting" || prediction.status == "processing" {
            prediction = try await poll(id: prediction.id, key: key)
        }
        guard prediction.status == "succeeded" else {
            if let err = prediction.error, looksLikeContentFilter(err) { throw AIVideoError.contentFiltered }
            throw AIVideoError.transport(prediction.error ?? "status=\(prediction.status)")
        }
        guard let videoURL = prediction.outputURL else { throw AIVideoError.noOutput }
        return try await download(videoURL)
    }

    // MARK: - 轮询

    private func poll(id: String, key: String) async throws -> Prediction {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var request = URLRequest(url: baseURL.appendingPathComponent("predictions/\(id)"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try classifyHTTP(response)
            let p = try parsePrediction(data)
            if p.status != "starting" && p.status != "processing" { return p }
        }
        throw AIVideoError.transport("生成超时")
    }

    // MARK: - 下载

    private func download(_ remote: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: remote)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIVideoError.transport("下载视频失败 HTTP \(http.statusCode)")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHavenAIVideo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).mp4")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 辅助

    /// HTTP 状态码 → 错误分类。
    private func classifyHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 401, 403: throw AIVideoError.invalidKey
        case 402, 429: throw AIVideoError.quotaOrRate
        case 200...299: return
        default: throw AIVideoError.transport("HTTP \(http.statusCode)")
        }
    }

    /// 防御式解析 prediction。`output` 在不同模型下可能是字符串或字符串数组，都兼容。
    private func parsePrediction(_ data: Data) throws -> Prediction {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = root["id"] as? String,
              let status = root["status"] as? String else {
            throw AIVideoError.decode(String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        var outputURL: URL?
        if let arr = root["output"] as? [String], let first = arr.first { outputURL = URL(string: first) }
        else if let s = root["output"] as? String { outputURL = URL(string: s) }
        return Prediction(id: id, status: status,
                          outputURL: outputURL,
                          error: root["error"] as? String)
    }

    /// 服务商安全策略拦截的关键词（best-effort：不同模型措辞不一，命中即归类为「被拦截」）。
    private func looksLikeContentFilter(_ error: String) -> Bool {
        let lower = error.lowercased()
        return ["safety", "nsfw", "moderat", "polic", "flagged", "sensitive"].contains { lower.contains($0) }
    }

    /// 源图 → ≤1024 长边 JPEG Data（应用 EXIF 方向；写法同 `WallpaperCropWriter.loadOriented`）。
    private func jpegForAPI(_ url: URL) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else { throw AIVideoError.decode("无法读取源图") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw AIVideoError.decode("无法解码源图")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { throw AIVideoError.decode("编码失败") }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw AIVideoError.decode("编码失败") }
        return data as Data
    }
}

private struct Prediction {
    let id: String
    let status: String
    let outputURL: URL?
    let error: String?
}
