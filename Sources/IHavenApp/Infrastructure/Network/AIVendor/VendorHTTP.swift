import Foundation

/// 六家厂商共用的 HTTP 原语（#70 多厂商直连）。
///
/// ## 为什么抽出来
/// 六家策略里「发一个带鉴权的 JSON 请求 → 看状态码 → 把服务端说明塞进错误文案」这一段是
/// **逐字相同**的。不抽的话每家都得抄一遍，而这段恰好是最容易写歪的部分（鉴权头写错、
/// 错误字段取不到只剩一句「HTTP 400」）。收口到这里后，各家文件只剩真正属于自己协议的
/// 那部分：端点、请求体、结果 JSON 路径。
///
/// ## 为什么不自动重试
/// ADR-019 的成本护栏：**每次生成都花用户的钱**。网络抖动时静默重试一次，用户侧看到的是
/// 「点了生成、等了三分钟、扣了两笔费」。宁可让它明确失败、由用户决定是否再来一次。
/// 同理也不做超时后继续轮询式的重试。
struct VendorHTTP: Sendable {

    /// 六家各自的鉴权风格。
    ///
    /// [!] 两个都不是笔误的反直觉点：
    /// - `.viduToken` 用的是 `Token` 前缀而不是 `Bearer` —— Vidu（生数）的鉴权头是非标准的
    ///   `Authorization: Token {key}`，照 Bearer 写会 401。
    /// - `.dashScopeAsync` 必须额外带 `X-DashScope-Async: enable` —— 阿里百炼的视频合成是
    ///   异步任务接口，少了这个头会被当**同步**请求处理，长任务直接超时 / 报错，
    ///   且错误信息不会提示是少了这个头。
    enum AuthStyle {
        case bearer
        case googleAPIKey
        case viduToken
        case dashScopeAsync
    }

    // MARK: - 构造请求

    /// 构造一个带鉴权与（可选）JSON body 的请求。
    /// - Parameter extraHeaders: 覆写用 —— 在鉴权头与 Content-Type 之后写入，可覆盖二者。
    static func request(_ url: URL,
                        method: String = "GET",
                        key: String,
                        auth: AuthStyle,
                        extraHeaders: [String: String] = [:],
                        body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        switch auth {
        case .bearer:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .googleAPIKey:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .viduToken:
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        case .dashScopeAsync:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw AIVideoError.requestRejected("请求体无法序列化：\(error.localizedDescription)")
            }
        }
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    // MARK: - 发送

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIVideoError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIVideoError.transport("非 HTTP 响应")
        }
        return (data, http)
    }

    // MARK: - 状态码分类

    /// HTTP 状态码 → `AIVideoError`。`body` 只为把服务端的说明带进错误文案。
    static func classify(_ response: HTTPURLResponse, body: Data) throws {
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw AIVideoError.invalidKey
        // 402 / 429 也必须带原文：实测可灵「余额为 0」返回的是 429 而不是 402，
        // 只给一句「额度不足或请求过于频繁」，用户不知道该充值还是该等（2026-10-19 真实反馈）。
        case 402, 429: throw AIVideoError.quotaOrRate(serverMessage(body))
        // 400 / 404 / 422 = 请求本身不被接受（参数 / 模型名或未开通 / 底图格式）。
        // 必须把服务端 detail 带出来 —— 只剩一句「HTTP 400」时连哪个字段错了都看不出来
        // （本项目已为此白跑过一次真机排查）。
        // 404 也归到这里而不是落到 default 的「网络错误」：实测方舟「模型未开通」返回的正是
        // 404 + `code: ModelNotOpen`，把它说成网络错误会让人去查网络，方向全错。
        //
        // 另外**内容审核也是走这一档**：方舟对含敏感信息的底图回 400
        // 「The request failed because the input image 'content[1]' may contain sensitive
        // information」。若按普通「请求被拒」显示，用户会去改参数 —— 但它其实是审核拦截，
        // 该换图。故这里先过一次关键词判定，命中转 `contentFiltered`。
        case 400, 404, 422:
            let message = serverMessage(body)
            throw looksLikeContentFilter(message)
                ? AIVideoError.contentFiltered(message)
                : AIVideoError.requestRejected(message)
        default: throw AIVideoError.transport("HTTP \(response.statusCode) \(serverMessage(body))")
        }
    }

    // MARK: - 错误文案

    /// 提取服务端错误说明。
    ///
    /// ## 为什么必须多键兜底
    /// 六家用**不同的错误字段名**：Google 是 `error.message`、多数家是 `message`、
    /// FastAPI 系的 Replicate / Vidu 是 `detail`、国内几家常用 `msg` 或 `base_resp.status_msg`、
    /// 阿里百炼把业务错误放在 `output.message`。只认一个键的结果是：真实失败被降级成
    /// 一句「HTTP 400」，用户不知道该改哪、我们也得再跑一次真机才能定位。
    /// 故依次试过全部已知键，都没有才退回原文片段。
    static func serverMessage(_ data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let candidates = [
                VendorHTTP.string(in: root, path: "error.message"),
                VendorHTTP.string(in: root, path: "message"),
                VendorHTTP.string(in: root, path: "detail"),
                VendorHTTP.string(in: root, path: "msg"),
                VendorHTTP.string(in: root, path: "error"),
                VendorHTTP.string(in: root, path: "output.message"),
                VendorHTTP.string(in: root, path: "base_resp.status_msg"),
            ]
            if let hit = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                return flatten(hit)
            }
        }
        // 兜底：截前 300 字节原文（可能是 HTML 错误页或非 JSON），换行换成空格以免把 UI 撑坏。
        return flatten(String(data: data.prefix(300), encoding: .utf8) ?? "")
    }

    /// 换行/回车换空格 + 截断 300 字 —— 错误文案要进 UI，不能带换行也不能无限长。
    private static func flatten(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(oneLine.prefix(300))
    }

    // MARK: - 解析

    static func json(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIVideoError.decode(String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return root
    }

    /// 从字典里按**多条候选路径**取字符串（如 `output.task_id`、`data.task_id`、`task_id`）。
    /// 都取不到返回 nil —— 由调用方决定是 `.decode` 还是继续跑（轮询中字段缺失是正常的）。
    static func string(in root: [String: Any], path: String) -> String? {
        var node: Any = root
        for key in path.split(separator: ".") {
            guard let dict = node as? [String: Any], let next = dict[String(key)] else { return nil }
            node = next
        }
        guard let value = node as? String, !value.isEmpty else { return nil }
        return value
    }

    /// 按路径取数组（如 `response.generatedVideos` / `creations` / `data`）；取不到或不是数组返回 nil。
    /// 与 `string(in:path:)` 同源：结果 JSON 的层级各家不同，不要用下标硬掏。
    static func array(in root: [String: Any], path: String) -> [Any]? {
        var node: Any = root
        for key in path.split(separator: ".") {
            guard let dict = node as? [String: Any], let next = dict[String(key)] else { return nil }
            node = next
        }
        return node as? [Any]
    }

    // MARK: - 终态判定

    /// 状态是否已经成功。六家用词与大小写全不一样（`SUCCEEDED` / `Success` / `succeed` /
    /// `done` / `completed`），统一小写后再比 —— 少认一个值就会让已完成的任务一直轮询到超时，
    /// 用户侧表现为「明明生成完了却报超时」。
    static func isSuccess(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["succeeded", "success", "succeed", "done", "complete", "completed"].contains(s)
    }

    /// 状态是否已经失败。与 `isSuccess` 互补但不穷尽：排队 / 运行中的状态两边都不命中。
    static func isFailure(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["failed", "failure", "fail", "error", "cancelled", "canceled", "expired"].contains(s)
    }

    /// 失败说明是否像安全策略拦截（best-effort：各家措辞不一，命中即归类为「被拦截」）。
    /// 判不出来就按普通失败处理 —— 误判成「被拦截」会让用户白改描述。
    static func looksLikeContentFilter(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["safety", "nsfw", "moderat", "polic", "flagged", "sensitive", "blocked",
                "prohibited", "not allowed", "inappropriate", "审核", "违规", "敏感"]
            .contains { lower.contains($0) }
    }
}
