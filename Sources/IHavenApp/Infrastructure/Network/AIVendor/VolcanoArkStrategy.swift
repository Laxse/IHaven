import Foundation

/// 火山方舟 Ark（Seedance）图生视频策略（#70 多厂商直连）。
///
/// ## 已真机端到端验证（2026-10-19，用户真 Key）
/// `doubao-seedance-1-0-pro-fast-251015` 完整走通：
/// 提交 `POST /api/v3/contents/generations/tasks` → HTTP 200 `{"id":"cgt-…"}`；
/// 轮询 `GET .../tasks/{id}` → 约 30s 后 `status=succeeded`；
/// 结果就在 `content.video_url`（带 TOS 签名，有效期 24h），1080p / 5s / 24fps，246,840 tokens。
/// **底图用 `data:image/jpeg;base64,…` 传是被接受的** —— 不需要图床，这是本次最值钱的结论。
///
/// 两个仍要注意的点：
/// 1. 底图**短边不得低于 300px**：实测过小会 `400 InvalidParameter — expected the height to be
///    at least 300px`。本 App 的 `jpegForAPI` 只缩不放（≤1024 长边），故源图若本身很小会被拒。
/// 2. model id 必须带版本日期后缀，且**充值 ≠ 开通**（未开通报 404 `ModelNotOpen`）。
///    详见 `AIVideoVendor` 里 volcano 条目的注释。
///
/// ## 与 MiniMax 的「形似而神不似」
/// 两家都用 `content[]`，元素都是 `{type:"image_url",image_url:{url:…},role:"first_frame"}`，
/// 但**顺序相反**：火山是「文本在前、图在后」，MiniMax 是「图在前、文本在后」；
/// 而且火山没有「文本即 prompt」之外的包装。照抄另一家的顺序不会报错，
/// 但可能影响首帧的权重 —— 这类「不报错但结果不对」的差异最费排查时间，故单独留一个策略。
///
/// ## [!] `model` 字段的两种取值
/// 方舟既接受模型名（`doubao-seedance-2-0`），也接受**接入点 ID**（`ep-` 开头）。
/// 若控制台只创建了接入点而未直接开通模型，填模型名会报 model not found。
/// 这里按 `AIVideoModel.id` 原样发送；如实跑报此错，是该改 `AIVideoVendorCatalog` 里的模型条目，
/// 而不是改本策略。
struct VolcanoArkStrategy: AIVendorVideoStrategy {
    var vendorID: String { "volcano" }

    private static let base = "https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        guard let url = URL(string: Self.base) else {
            throw AIVideoError.transport("方舟端点构造失败")
        }
        let dataURI = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
        let body: [String: Any] = [
            "model": model.id,
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": dataURI], "role": "first_frame"],
            ],
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .bearer, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let id = VendorHTTP.string(in: root, path: "id") else {
            throw AIVideoError.decode("方舟未返回任务 id")
        }
        return id
    }

    func poll(task: String, key: String) async throws -> URL? {
        guard let url = URL(string: "\(Self.base)/\(task)") else {
            throw AIVideoError.transport("方舟轮询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .bearer)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        let status = VendorHTTP.string(in: root, path: "status") ?? ""
        if VendorHTTP.isFailure(status) {
            let msg = VendorHTTP.string(in: root, path: "error.message")
                ?? VendorHTTP.string(in: root, path: "error") ?? status
            throw VendorHTTP.looksLikeContentFilter(msg) ? AIVideoError.contentFiltered
                : AIVideoError.transport("方舟：\(msg)")
        }
        guard VendorHTTP.isSuccess(status) else { return nil }

        if let link = VendorHTTP.string(in: root, path: "content.video_url"), let video = URL(string: link) {
            return video
        }
        throw AIVideoError.noOutput
    }
}
