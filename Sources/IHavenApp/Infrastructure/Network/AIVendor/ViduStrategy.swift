import Foundation

/// 生数 Vidu 图生视频策略（#70 多厂商直连）。
///
/// [!] 未真机验证：端点 / 字段名来自官方文档整理（2026-10-20），首次用真 Key 跑请核对。
///
/// ## 这家最特别的一处：鉴权头是 `Token` 而不是 `Bearer`
/// 非标准鉴权（见 `VendorHTTP.AuthStyle.viduToken`）。照其它家写 `Authorization: Bearer {key}`
/// 会直接 401，而且错误信息不会提示是前缀错了 —— 排查时第一眼只会以为 Key 无效。
///
/// ## 底图是「裸数组」
/// `images: ["data:image/jpeg;base64,…"]`，不是对象数组、也没有 `image_url` 包装层。
/// 与 MiniMax / 火山那种 `content[]` 结构只差一层，但正是这层决定了照抄必 400。
struct ViduStrategy: AIVendorVideoStrategy {
    var vendorID: String { "vidu" }

    private static let base = "https://api.vidu.cn/ent/v2"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        guard let url = URL(string: "\(Self.base)/img2video") else {
            throw AIVideoError.transport("Vidu 端点构造失败")
        }
        let dataURI = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
        let body: [String: Any] = [
            "model": model.id,
            "images": [dataURI],
            "prompt": prompt,
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .viduToken, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        // task_id 是主字段；`id` 作为兼容（它家部分接口 / 版本回的是 id）。
        guard let taskID = VendorHTTP.string(in: root, path: "task_id")
            ?? VendorHTTP.string(in: root, path: "id") else {
            throw AIVideoError.decode("Vidu 未返回 task_id")
        }
        return taskID
    }

    func poll(task: String, key: String) async throws -> URL? {
        guard let url = URL(string: "\(Self.base)/tasks/\(task)/creations") else {
            throw AIVideoError.transport("Vidu 轮询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .viduToken)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        // 状态字段名它家用 `state`，但同一 family 的接口也有回 `status` 的 —— 两个都看，
        // 取不到就当「还在跑」（轮询中字段缺失是正常的，不该直接判失败）。
        let state = VendorHTTP.string(in: root, path: "state")
            ?? VendorHTTP.string(in: root, path: "status") ?? ""
        if VendorHTTP.isFailure(state) {
            let msg = VendorHTTP.string(in: root, path: "err_msg")
                ?? VendorHTTP.string(in: root, path: "message") ?? state
            throw VendorHTTP.looksLikeContentFilter(msg) ? AIVideoError.contentFiltered
                : AIVideoError.transport("Vidu：\(msg)")
        }
        guard VendorHTTP.isSuccess(state) else { return nil }

        guard let creations = VendorHTTP.array(in: root, path: "creations"),
              let first = creations.first as? [String: Any],
              let link = VendorHTTP.string(in: first, path: "url"),
              let video = URL(string: link) else {
            throw AIVideoError.noOutput
        }
        return video
    }
}
