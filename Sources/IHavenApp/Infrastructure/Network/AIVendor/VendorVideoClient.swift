import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AI 图生视频客户端 —— **多厂商直连**实现（#70）。Feature 只见 `AIVideoGenerating` 协议。
///
/// ## 为什么不走聚合层
/// 原实现走 Replicate 聚合层（一把 Key 跑多家模型），用户否决了这个方向：要用各自的模型厂商、
/// 各家一把自己的 Key。于是客户端不再认识任何具体协议，只做**与厂商无关的骨架**：
/// 转 JPEG → 按厂商取策略 → 提交 → 轮询 → 下载。六家的差异全在 `AIVendorVideoStrategy` 里。
///
/// ## 为什么厂商 / 模型都现调现用
/// `AIVideoVendorCatalog.selected()` 与 `selectedModel()` 读的是 UserDefaults，
/// 设置面板会在进程运行期间改写它们。缓存成 `let` 就会出现「用户刚换了厂商，本次会话还在用
/// 老厂商的 Key 和老厂商的模型名」，要重启才生效 —— 而模型 id 不是跨厂商通用的命名空间，
/// 串厂商发请求只会得到 404 / model not found，错误信息还不会提示是串了。
///
/// ## 超时设置
/// 首等 5s（各家提交后都要排队，立刻查必然是 queued）、之后 3s 一次，总上限 6 分钟。
/// 图生视频常 1~3 分钟，可灵 / 万相在高峰期可能更久，3 分钟会误杀。
struct VendorVideoClient: AIVideoGenerating {
    private let keyResolver: AIVendorKeyProviding

    init(keyResolver: AIVendorKeyProviding) {
        self.keyResolver = keyResolver
    }

    func generateVideo(sourceImage: URL, prompt: String) async throws -> URL {
        let vendor = AIVideoVendorCatalog.selected()
        let model = AIVideoVendorCatalog.selectedModel()
        guard let strategy = VendorStrategies.strategy(for: vendor.id) else {
            throw AIVideoError.transport("未支持的厂商：\(vendor.id)")
        }
        // Key 按**厂商**解析：六家的 Key 互不通用，拿 A 厂的 Key 去打 B 厂的端点只会 401。
        let key = keyResolver.keyProvider(for: vendor.id).currentKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIVideoError.missingKey }

        let jpeg = try Self.jpegForAPI(sourceImage)
        let task = try await strategy.submit(imageJPEG: jpeg, prompt: prompt, model: model, key: key)

        let deadline = Date().addingTimeInterval(360)
        var delay: UInt64 = 5_000_000_000
        while Date() < deadline {
            try await Task.sleep(nanoseconds: delay)
            delay = 3_000_000_000
            if let url = try await strategy.poll(task: task, key: key) {
                return try await Self.download(url, headers: strategy.downloadHeaders(key: key))
            }
        }
        throw AIVideoError.transport("生成超时")
    }

    // MARK: - 底图

    /// 源图 → ≤1024 长边 JPEG Data。
    ///
    /// 两个必须做的理由：模型可靠吃 JPEG（原图可能是 4K / HEIC，直接 base64 会是数 MB，
    /// 甚至被模型拒收）；以及 `kCGImageSourceCreateThumbnailWithTransform: true` ——
    /// 少了它带 EXIF 方向的图会差 90°（本项目踩过，表现为「生成的视频里画面是躺着的」）。
    private static func jpegForAPI(_ url: URL) throws -> Data {
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

    // MARK: - 下载

    /// 下载视频到临时目录（`…/IHavenAIVideo/<uuid>.mp4`），返回本地 URL。
    ///
    /// 写临时目录而不是让用户选路径：这段视频只是**抽帧的中间产物**（ADR-016 播放的是 JPEG
    /// 帧序列），落地即被消费完。调用方用完负责清理（协议注释已声明）。
    private static func download(_ remote: URL, headers: [String: String]) async throws -> URL {
        var request = URLRequest(url: remote)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
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
}

/// 厂商 id → 策略实现。**加厂商只改这里加一行**，其余代码不感知。
///
/// 每次返回 fresh 实例而不是全局单例：策略都是无状态 struct（只有常量端点字符串），
/// 持有一份全局实例没有任何好处，反而给 Swift 6 严格并发多一个要证明 Sendable 的全局量。
enum VendorStrategies {
    static func strategy(for vendorID: String) -> (any AIVendorVideoStrategy)? {
        switch vendorID {
        case "google": return GoogleVeoStrategy()
        case "minimax": return MiniMaxStrategy()
        case "vidu": return ViduStrategy()
        case "alibaba": return DashScopeStrategy()
        case "volcano": return VolcanoArkStrategy()
        case "kling": return KlingStrategy()
        default: return nil
        }
    }
}
