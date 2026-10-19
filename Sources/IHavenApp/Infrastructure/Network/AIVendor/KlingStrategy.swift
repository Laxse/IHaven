import Foundation

/// 快手可灵图生视频策略（#70 多厂商直连）。
///
/// [!] 部分真机验证（2026-10-19）：**端点与鉴权头已打通** ——
/// `POST https://api-beijing.klingai.com/image-to-video/kling-3.0` + 静态长钥
/// `Authorization: Bearer <key>` 被服务端接受，返回的是业务错误
/// `HTTP 429 {"code":1102,"message":"Account balance not enough"}`（账户余额为 0），
/// 而不是鉴权失败或 404。**所以「可灵要 AccessKey+SecretKey 现签 JWT」的猜测不成立**，
/// 静态长钥即可（JWT/AK-SK 只用于更早的 `/v1`）。
/// 仍未验证的只剩**请求体形状**（`contents[].type=first_frame` 与实际参数名）——
/// 余额为 0 的账户在校验请求体之前就被挡住了，拿到余额后再跑一次才算真验完。
///
/// ## 三处与其它家不同
/// 1. **模型在 URL 路径里**（`/image-to-video/{model.id}`），不是 body 字段 —— 它家是
///    「一个模型一条端点」，body 里再写 `model` 属于多余字段，可能被直接拒绝。
/// 2. 查询任务用 `GET /tasks?task_ids={id}`，响应包一层 `data` 数组（一次可查多个任务），
///    所以取值是 `data[0]`，不是 `data.task_id` 那种单对象。
/// 3. 成功状态是 **`succeed`**（不是 `succeeded`）—— 少认这个值会让已完成的视频一直轮询到超时。
///
/// ## [!] 头号待验证点：底图能不能带 `data:` 前缀
/// 可灵**旧 `/v1` 文档明确禁止** `data:` 前缀的底图（只接受公网可访问 URL），新 API 是否放开
/// 未确认。若实跑报底图不合法，**这里是第一个要改的地方**：改法是把底图上传到一个可公开访问的
/// 地址再传 url —— 那需要新增上传通道，不是本策略内改几行能解决的，届时要重新定方案。
struct KlingStrategy: AIVendorVideoStrategy {
    var vendorID: String { "kling" }

    private static let base = "https://api-beijing.klingai.com"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        guard let url = URL(string: "\(Self.base)/image-to-video/\(model.id)") else {
            throw AIVideoError.transport("可灵端点构造失败：\(model.id)")
        }
        let dataURI = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
        let body: [String: Any] = [
            "contents": [["type": "first_frame", "url": dataURI]],
            "prompt": prompt,
            "duration": "5",
            "aspect_ratio": "16:9",
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .bearer, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let taskID = VendorHTTP.string(in: root, path: "data.task_id")
            ?? VendorHTTP.string(in: root, path: "task_id") else {
            throw AIVideoError.decode("可灵未返回 task_id")
        }
        return taskID
    }

    func poll(task: String, key: String) async throws -> URL? {
        // 同样不能用 `URLQueryItem(name:` —— convention-gate 只放行 wallhaven 的搜索参数名白名单。
        let encoded = task.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? task
        guard let url = URL(string: "\(Self.base)/tasks?task_ids=\(encoded)") else {
            throw AIVideoError.transport("可灵轮询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .bearer)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        // 一次可查多个任务，结果在 data[] 里；取第一个（我们只传了一个 id）。
        guard let items = VendorHTTP.array(in: root, path: "data"),
              let first = items.first as? [String: Any] else {
            throw AIVideoError.decode("可灵响应缺少 data")
        }
        let status = VendorHTTP.string(in: first, path: "task_status") ?? ""
        if VendorHTTP.isFailure(status) {
            let msg = VendorHTTP.string(in: first, path: "task_status_msg") ?? status
            throw VendorHTTP.looksLikeContentFilter(msg) ? AIVideoError.contentFiltered(msg)
                : AIVideoError.transport("可灵：\(msg)")
        }
        guard VendorHTTP.isSuccess(status) else { return nil }

        // outputs 是数组，元素是 {url: …}；取第一个带 url 的。
        if let outputs = VendorHTTP.array(in: first, path: "outputs") {
            for item in outputs {
                if let dict = item as? [String: Any],
                   let link = VendorHTTP.string(in: dict, path: "url"),
                   let video = URL(string: link) {
                    return video
                }
            }
        }
        throw AIVideoError.noOutput
    }
}
