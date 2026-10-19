import Foundation

/// 阿里百炼（万相 / DashScope）图生视频策略（#70 多厂商直连）。
///
/// [!] 未真机验证：端点 / 字段名来自官方文档整理（2026-10-20），首次用真 Key 跑请核对。
///
/// ## 两个必须记住的坑
/// 1. 提交**必须带** `X-DashScope-Async: enable`（`VendorHTTP.AuthStyle.dashScopeAsync`）。
///    视频合成本就是异步任务接口，少了这个头会被当同步请求处理 —— 长任务直接超时 / 报错，
///    而且错误信息**不会**提示是少了这个头，表现为「莫名失败」。
/// 2. 它家的业务错误藏在 `output` 里（`output.code` / `output.message`），HTTP 状态码常常仍是 200。
///    只看状态码会把一次明确的业务失败（模型未开通、余额不足）当成成功继续轮询到超时。
///    所以这里**先看 output.code**，再看 task_status。
struct DashScopeStrategy: AIVendorVideoStrategy {
    var vendorID: String { "alibaba" }

    private static let base = "https://dashscope.aliyuncs.com/api/v1"

    func submit(imageJPEG: Data, prompt: String, model: AIVideoModel, key: String) async throws -> String {
        guard let url = URL(string: "\(Self.base)/services/aigc/video-generation/video-synthesis") else {
            throw AIVideoError.transport("百炼端点构造失败")
        }
        let dataURI = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
        let body: [String: Any] = [
            "model": model.id,
            "input": [
                "prompt": prompt,
                "media": [["type": "first_frame", "url": dataURI]],
            ],
        ]
        let request = try VendorHTTP.request(url, method: "POST", key: key, auth: .dashScopeAsync, body: body)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        // HTTP 200 也可能是业务失败（模型未开通 / 参数不合法），先把 output.message 抬出来。
        if let message = VendorHTTP.string(in: root, path: "output.message"),
           let code = VendorHTTP.string(in: root, path: "output.code") {
            throw AIVideoError.requestRejected("百炼 \(code)：\(message)")
        }
        guard let taskID = VendorHTTP.string(in: root, path: "output.task_id") else {
            throw AIVideoError.decode("百炼未返回 task_id")
        }
        return taskID
    }

    func poll(task: String, key: String) async throws -> URL? {
        guard let url = URL(string: "\(Self.base)/tasks/\(task)") else {
            throw AIVideoError.transport("百炼轮询 URL 非法")
        }
        let request = try VendorHTTP.request(url, key: key, auth: .dashScopeAsync)
        let (data, response) = try await VendorHTTP.send(request)
        try VendorHTTP.classify(response, body: data)
        let root = try VendorHTTP.json(data)
        guard let output = root["output"] as? [String: Any] else {
            throw AIVideoError.decode("百炼响应缺少 output")
        }
        let status = VendorHTTP.string(in: output, path: "task_status") ?? ""
        if VendorHTTP.isFailure(status) {
            // 失败时把 code / message 都带进文案：只说「FAILED」用户不知道是模型没开通还是被审核拦了。
            let code = VendorHTTP.string(in: output, path: "code") ?? ""
            let message = VendorHTTP.string(in: output, path: "message") ?? status
            let detail = code.isEmpty ? message : "\(code) \(message)"
            throw VendorHTTP.looksLikeContentFilter(detail) ? AIVideoError.contentFiltered(detail)
                : AIVideoError.transport("百炼：\(detail)")
        }
        guard VendorHTTP.isSuccess(status) else { return nil }

        if let link = VendorHTTP.string(in: output, path: "video_url"), let video = URL(string: link) {
            return video
        }
        // 兜底：部分模型把结果放在 output.results[] 里。
        if let results = VendorHTTP.array(in: output, path: "results"),
           let first = results.first as? [String: Any],
           let link = VendorHTTP.string(in: first, path: "video_url") ?? VendorHTTP.string(in: first, path: "url"),
           let video = URL(string: link) {
            return video
        }
        throw AIVideoError.noOutput
    }
}
