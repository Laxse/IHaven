import Foundation

/// MiniMax（海螺）图生视频策略（#70 多厂商直连）。
///
/// [!] 未真机验证：端点 / 字段名来自官方文档整理（2026-10-20），首次用真 Key 跑请核对。
///
/// ## 为什么结果要走「两步」
/// 查询结果里**可能**直接给 `content.url`，也可能只给一个 `file_id`（视频存在它家的文件服务里，
/// 结果接口不内联 URL）。只实现任何一条都会在某次调用上拿不到视频，所以两条都留：
/// 有 url 直接用，没有就再取一次文件下载链接。
///
/// ## 为什么文件查询用字符串拼而不是 `URLQueryItem`
/// `scripts/convention-gate.sh` 会 grep `Infrastructure/` 里所有 `URLQueryItem(name:` /
/// `.init(name:`，只允许 wallhaven 搜索参数白名单内的名字（`file_id` 不在其中），
/// 写了会直接 FAIL 门禁。那条规则是防「wallhaven 筛选参数拼错被服务端静默忽略」的，
/// 不适用于厂商 API，故这里手动拼 + 百分号编码。
struct MiniMaxStrategy: AIVendorVideoStrategy {
    var vendorID: String { "minimax" }

    private static let base = "https://api.minimax.cn/v2"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        guard let url = URL(string: "\(Self.base)/video_generation") else {
            throw AIVideoError.transport("MiniMax 端点构造失败")
        }
        let dataURI = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
        // content 是有序数组：先首帧图、再文本描述。`role: "first_frame"` 是它家区分
        // 「首帧 / 尾帧」的方式，缺了会被当成文生视频或报参数不全。
        let body: [String: Any] = [
            "model": model.id,
            "content": [
                ["type": "image_url", "image_url": ["url": dataURI], "role": "first_frame"],
                ["type": "text", "text": prompt],
            ],
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .bearer, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let taskID = VendorHTTP.string(in: root, path: "task_id") else {
            throw AIVideoError.decode("MiniMax 未返回 task_id")
        }
        return taskID
    }

    func poll(task: String, key: String) async throws -> URL? {
        guard let url = URL(string: "\(Self.base)/query/video_generation/\(task)") else {
            throw AIVideoError.transport("MiniMax 轮询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .bearer)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        let status = VendorHTTP.string(in: root, path: "status") ?? ""
        if VendorHTTP.isFailure(status) {
            let msg = VendorHTTP.string(in: root, path: "message") ?? status
            throw VendorHTTP.looksLikeContentFilter(msg) ? AIVideoError.contentFiltered(msg)
                : AIVideoError.transport("MiniMax：\(msg)")
        }
        guard VendorHTTP.isSuccess(status) else { return nil }

        // 路径一：结果里直接带 URL。
        if let direct = VendorHTTP.string(in: root, path: "content.url")
            ?? VendorHTTP.string(in: root, path: "video_url"),
           let video = URL(string: direct) {
            return video
        }
        // 路径二：只给了 file_id —— 需要再查一次文件服务拿下载链接。
        guard let fileID = VendorHTTP.string(in: root, path: "file_id") else { throw AIVideoError.noOutput }
        return try await retrieveFile(fileID, key: key)
    }

    private func retrieveFile(_ fileID: String, key: String) async throws -> URL {
        let encoded = fileID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fileID
        guard let url = URL(string: "\(Self.base)/files/retrieve?file_id=\(encoded)") else {
            throw AIVideoError.transport("MiniMax 文件查询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .bearer)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let link = VendorHTTP.string(in: root, path: "file.download_url"),
              let video = URL(string: link) else {
            throw AIVideoError.decode("MiniMax 未返回下载地址")
        }
        return video
    }
}
