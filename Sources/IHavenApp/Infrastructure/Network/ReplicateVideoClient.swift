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
/// ## 端点 / 模型（已按官方文档核对，2026-10-18；真机跑到 HTTP 422 后修正一次）
/// 官方模型必须走 `POST /v1/models/{owner}/{name}/predictions`，body **只有 `input`**。
/// ⚠️ **不能走通用 `/v1/predictions`**：那条路径必填 `version`（64 位版本哈希或
/// `owner/name:hash`），body 里**根本没有 `model` 字段** —— 传 `{"model": …}` 会被判
/// 422 Unprocessable Entity（用户真机实测，错误文案就是「HTTP 422」）。
/// 仍是 `Prefer: wait` 同步等 ≤60s，超时转轮询 `GET /v1/predictions/{id}`。
/// 模型不再是写死的常量，而是**用户在生成面板里选的那个**（`AIVideoModelCatalog.selected()`，
/// 持久化在 `UserPreferenceKey.aiVideoModel`）。聚合层的价值就在这里：一套 Key 跑多个模型，
/// 换模型不换 Key。入参键名随模型变，见 `AIVideoModel.imageInputKey` 的说明。
///
/// 输出统一是**单个字符串 URI**（解析端同时兼容字符串 / 数组）。
struct ReplicateVideoClient: AIVideoGenerating {
    private let keyProvider: KeyProvider
    private let baseURL = URL(string: "https://api.replicate.com/v1")!

    init(keyProvider: KeyProvider) {
        self.keyProvider = keyProvider
    }

    /// 当前模型。现读而不是 init 时固定 —— 用户改选后下一次生成立即生效，不用重启。
    private var model: AIVideoModel { AIVideoModelCatalog.selected() }

    func generateVideo(sourceImage: URL, prompt: String) async throws -> URL {
        let key = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIVideoError.missingKey }
        // 官方模型端点由模型名推出来（见文件头说明）：模型标识必须是 owner/name。
        guard let endpoint = modelEndpoint() else {
            throw AIVideoError.requestRejected("模型标识应为 owner/name：\(model)")
        }

        // 底图转成 API 友好的 JPEG（≤1024 长边）：模型可靠吃 JPEG，且显著减小请求体
        // （原图可能是 4K / HEIC，直接 base64 会是数 MB，甚至被模型拒收）。
        let jpeg = try jpegForAPI(sourceImage)
        let dataURI = "data:image/jpeg;base64," + jpeg.base64EncodedString()

        // 这条端点只认 input —— 模型已由 URL 决定，不能再塞 model / version（否则 422）。
        // 底图键名随模型变（first_frame_image / first_frame / start_image / image），
        // 取自 AIVideoModelCatalog —— 写死成 "image" 会 422（已踩过一次）。
        let model = self.model
        let body: [String: Any] = [
            "input": [model.imageInputKey: dataURI, model.promptInputKey: prompt],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Prefer: wait = 让服务端尽量同步等完再返回（上限约 60s），省掉多数轮询。
        request.setValue("wait", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try classifyHTTP(response, body: data)
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
            try classifyHTTP(response, body: data)
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

    /// 官方模型的创建端点：`POST /v1/models/{owner}/{name}/predictions`（body 只需 `input`）。
    ///
    /// ⚠️ 不能走通用 `/v1/predictions`：那条路径必填 `version`（64 位版本哈希，或
    /// `owner/name:hash`），body 里**没有 `model` 字段** —— 传 `{"model": …}` 会直接 422。
    /// 用字符串拼接而不是 `appendingPathComponent`：后者对含 `/` 的整串行为不保证。
    private func modelEndpoint() -> URL? {
        let parts = model.id.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return URL(string: "\(baseURL.absoluteString)/models/\(parts[0])/\(parts[1])/predictions")
    }

    /// HTTP 状态码 → 错误分类。`body` 是响应正文，只为把服务端的说明带进错误文案。
    private func classifyHTTP(_ response: URLResponse, body data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 401, 403: throw AIVideoError.invalidKey
        case 402, 429: throw AIVideoError.quotaOrRate
        case 200...299: return
        // 422 = 参数 / 模型 / 输入 schema 不被接受。必须把服务端 detail 带出来 —— 只剩一句
        // 「HTTP 422」时连哪个字段错了都看不出来（本轮就是这么白跑一次的）。
        case 422: throw AIVideoError.requestRejected(serverMessage(data))
        default: throw AIVideoError.transport("HTTP \(http.statusCode) \(serverMessage(data))")
        }
    }

    /// 提取服务端错误说明。Replicate 用 `{"detail": "..."}`；FastAPI 的校验错误里 detail
    /// 是数组，退化成原文片段。截断 300 字，避免把整个 schema 塞进 UI。
    private func serverMessage(_ data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = root["detail"] as? String, !detail.isEmpty {
            return detail
        }
        let text = (String(data: data.prefix(300), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.replacingOccurrences(of: "\n", with: " ")
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
