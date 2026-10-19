import Foundation

/// Google（Gemini API / Veo）图生视频策略（#70 多厂商直连）。
///
/// [!] 未真机验证：端点 / 字段名来自官方文档整理（2026-10-20），首次用真 Key 跑请核对。
///
/// ## 这家与别人最不一样的两点
/// 1. **底图是裸 base64**，走 `instances[].image.inlineData{mimeType,data}` —— 不带 `data:` 前缀。
///    其它五家要么吃 data URI、要么只吃 URL，照别家写法直接贴 `data:image/jpeg;base64,…`
///    会被判非法 base64。
/// 2. 鉴权是 `x-goog-api-key` 头而不是 Bearer，且**下载视频时也要带**（见 `downloadHeaders`）——
///    它家的结果 URI 不是短期公开链接，去掉 key 会 403。
///
/// 另外它是标准 LRO：提交返回 `name`（`operations/…`），轮询看 `done` 而不是 `status`。
struct GoogleVeoStrategy: AIVendorVideoStrategy {
    var vendorID: String { "google" }

    private static let base = "https://generativelanguage.googleapis.com/v1beta"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        // 用字符串拼而不是 appendingPathComponent：路径里带 `:predictLongRunning`（自定义方法名），
        // 后者对含 `:` 的整串行为不保证。
        guard let url = URL(string: "\(Self.base)/models/\(model.id):predictLongRunning") else {
            throw AIVideoError.transport("Google 端点构造失败：\(model.id)")
        }
        let body: [String: Any] = [
            "instances": [[
                "prompt": prompt,
                "image": ["inlineData": ["mimeType": "image/jpeg", "data": imageJPEG.base64EncodedString()]],
            ]],
            "parameters": ["aspectRatio": "16:9", "durationSeconds": 6, "resolution": "720p"],
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .googleAPIKey, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let name = VendorHTTP.string(in: root, path: "name") else {
            throw AIVideoError.decode("Google 未返回 operation name")
        }
        return name
    }

    func poll(task: String, key: String) async throws -> URL? {
        // task 通常是 `operations/xxx`；也兼容官方某版本直接回完整 URL 的情况。
        let raw = task.hasPrefix("http") ? task : "\(Self.base)/\(task)"
        guard let url = URL(string: raw) else { throw AIVideoError.transport("Google 轮询 URL 非法") }
        let request = try VendorHTTP.request(url, key: key, auth: .googleAPIKey)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        // LRO 用 done 而不是 status；done 为 false（或缺失）就是还在跑。
        guard let done = root["done"] as? Bool, done else { return nil }

        if let error = (root["error"] as? [String: Any])?["message"] as? String {
            throw VendorHTTP.looksLikeContentFilter(error)
                ? AIVideoError.contentFiltered
                : AIVideoError.transport(error)
        }
        // 结果路径兜底：官方是 response.generateVideoResponse.generatedSamples[0].video.uri，
        // 但同一 family 的接口历史上也用过 generatedVideos / 直接在 response 下挂 video。
        let candidates = ["response.generateVideoResponse.generatedSamples",
                          "response.generatedVideos"]
        for path in candidates {
            if let samples = VendorHTTP.array(in: root, path: path),
               let first = samples.first as? [String: Any],
               let uri = VendorHTTP.string(in: first, path: "video.uri"),
               let video = URL(string: uri) {
                return video
            }
        }
        if let uri = VendorHTTP.string(in: root, path: "response.video.uri"),
           let video = URL(string: uri) {
            return video
        }
        throw AIVideoError.noOutput
    }

    /// 它家的结果 URI 下载也要带 key，否则 403（见文件头）。
    func downloadHeaders(key: String) -> [String: String] {
        ["x-goog-api-key": key]
    }
}
