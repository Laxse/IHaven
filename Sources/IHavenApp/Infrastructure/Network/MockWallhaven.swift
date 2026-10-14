import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Mock Wallhaven 服务
//
// 开发期免 VPN 的「模拟 wallhaven 服务」：在进程内用一个 `URLProtocol` 拦截对 mock 主机的请求，
// 直接返回合成的搜索 JSON 与缩略图/原图字节。这样整条真实链路（请求 → JSON 解码 → Nuke 预取 →
// 缩略图渲染 → 设为壁纸的原图下载）都能跑通，无需启用 VPN。
//
// 启用方式（Xcode）：Edit Scheme → Run → Arguments → Environment Variables 添加
//   IHAVEN_MOCK = 1
// 不需要时删除该环境变量即可切回真实服务。仅当环境变量为 "1" 时才接管，真实环境零影响。

enum MockWallhaven {
    static let host = "mock.wallhaven.local"
    private static let envKey = "IHAVEN_MOCK"

    /// 是否启用 mock：`IHAVEN_MOCK=1`。`WallhavenEndpoint.search` 也据此切换 base URL。
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    /// 在 `IHavenApp.bootstrap()` 最开头调用。若 `IHAVEN_MOCK=1`，注册拦截协议接管对 mock 主机的请求。
    static func configureIfNeeded() {
        guard isEnabled else { return }
        URLProtocol.registerClass(MockWallhavenProtocol.self)
    }
}

/// 拦截对 `mock.wallhaven.local` 的全部请求：搜索接口返回 JSON，图片路径返回合成 JPEG。
final class MockWallhavenProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockWallhaven.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { fail(URLError(.badURL)); return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = (items.first { $0.name == "page" }?.value).flatMap(Int.init) ?? 1

        let (data, contentType): (Data, String)
        if url.path.hasPrefix("/api/v1/search") {
            data = MockData.searchPage(page: page, query: items)
            contentType = "application/json"
        } else if url.path.hasPrefix("/api/v1/w/") {
            // 详情端点必须单独分支：否则会落进下面的图片通道，把 JPEG 字节喂给
            // JSONDecoder，报出「解析失败」这种与真实原因毫无关系的错误（昨为 §7 缺口 2）。
            data = MockData.detail(id: (url.path as NSString).lastPathComponent)
            contentType = "application/json"
        } else {
            // /thumb/<size>/<id> 缩略图、/avatar/<size>/<id> 头像 与 /wallpaper/<id> 原图
            // 都走图片通道。
            data = MockData.image(path: url.path)
            contentType = "image/jpeg"
        }
        respond(data: data, contentType: contentType)
    }

    override func stopLoading() {}

    private func respond(data: Data, contentType: String) {
        let fields = ["Content-Type": contentType]
        guard let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields
        ) else { fail(URLError(.cannotParseResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail(_ error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }
}

// MARK: - 合成数据
private enum MockData {
    static let perPage = 24
    static let total = 240
    static let lastPage = total / perPage

    // 5 种比例组循环分配：保证瀑布流有竖图 / 方图 / 横图 / 宽屏 / 超宽多种形态。
    static let shapes: [(w: Int, h: Int)] = [
        (1080, 1920), (1440, 1440), (1920, 1080), (2560, 1080), (3440, 1440),
    ]
    static let palettes: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (232, 163, 61), (79, 168, 92), (127, 184, 232),
        (216, 164, 65), (216, 87, 75), (123, 135, 201),
    ]

    // 详情专属标签种子。前 3 个固定为 artwork / illustration / digital art —— 与
    // VERIFIED-WALLHAVEN-DETAIL.md §4 实测过的 `+tag` 组合一致，便于把
    // `similarSearchQuery` 的输出直接与文档对照。
    static let tagSeeds: [(name: String, alias: String, categoryID: Int, category: String)] = [
        ("artwork", "art, artwork", 1, "Art & Design"),
        ("illustration", "illustration", 1, "Art & Design"),
        // 多词标签：空格必须原样保留 —— 换成 `digital_art` 实测返回 0 条（文档 §4）。
        ("digital art", "digital art, digital_art", 1, "Art & Design"),
        ("anime", "anime", 2, "Anime"),
        ("background", "background, wallpaper", 3, "General"),
        ("fantasy", "fantasy", 3, "General"),
    ]

    static func searchPage(page: Int, query: [URLQueryItem]) -> Data {
        let encoder = JSONEncoder()
        if page > lastPage {
            let empty = WallhavenPage(
                data: [],
                meta: .init(currentPage: page, lastPage: lastPage,
                           perPage: "\(perPage)", total: total,
                           query: query.value("q"), seed: query.value("seed"))
            )
            return (try? encoder.encode(empty)) ?? Data()
        }

        let start = (page - 1) * perPage
        let items = (0..<perPage).map { wallpaper(at: start + $0) }
        let page = WallhavenPage(
            data: items,
            meta: .init(currentPage: page, lastPage: lastPage,
                       perPage: "\(perPage)", total: total,
                       query: query.value("q"), seed: query.value("seed"))
        )
        return (try? encoder.encode(page)) ?? Data()
    }

    /// 详情响应 `{"data":{...}}`（**顶层无 `meta`**，与 `/search` 的数组 + meta 不同）。
    static func detail(id: String) -> Data {
        let idx = index(of: id)
        let payload = WallpaperDetail(base: wallpaper(at: idx),
                                      uploader: uploader(for: id),
                                      tags: tags(at: idx))
        return (try? JSONEncoder().encode(WallpaperDetailEnvelope(data: payload))) ?? Data()
    }

    /// 搜索项与详情的**共有 18 个字段**走同一个工厂：两边形状本就完全一致
    /// （VERIFIED-WALLHAVEN-DETAIL.md §1），拆成两份必然漂移。
    ///
    /// 字段形状一律照真实 API：`ratio` 是十进制字符串（**不是** "16x9"）、`purity` 是
    /// "sfw"/"sketchy"（**不是** "100"）、`created_at` 是 "YYYY-MM-DD HH:mm:ss"（**不是**
    /// ISO8601）、`colors` **恒 5 个**小写 hex。
    static func wallpaper(at idx: Int) -> Wallpaper {
        let shape = shapes[idx % shapes.count]
        let id = "mock-\(idx)"
        let host = "https://\(MockWallhaven.host)"
        let full = URL(string: "\(host)/wallpaper/\(id).jpg")!
        return Wallpaper(
            id: id,
            // `url` 是**网页详情页**地址，`path` 才是原图直链 —— 二者在真实响应里不是同一个 URL。
            url: URL(string: "https://wallhaven.cc/w/\(id)")!,
            shortURL: URL(string: "https://whvn.cc/\(id)")!,
            createdAt: String(format: "2026-%02d-%02d %02d:53:43",
                              (idx % 12) + 1, (idx % 28) + 1, idx % 24),
            purity: idx % 7 == 0 ? "sketchy" : "sfw",
            category: ["general", "anime", "people"][idx % 3],
            width: shape.w,
            height: shape.h,
            resolution: "\(shape.w)x\(shape.h)",
            ratio: String(format: "%.2f", Double(shape.w) / Double(shape.h)),
            fileSize: 1_000_000 + idx * 13_337,     // 单位：字节
            fileType: "image/jpeg",
            views: 1_000 + idx * 7,
            favorites: 50 + idx * 3,
            // 无来源时真实 API 给的是**空串 "" 而非 null**（2026-10-09 加载失败的真实根因），
            // 这里特意造出空串样本，保证 mock 覆盖到那条路径。
            source: idx % 5 == 0 ? "" : "https://example.com/\(id)",
            colors: palette(at: idx),
            path: full,
            // 三个 key 指向**三个不同尺寸**：若三者同 URL，取错 key 在 mock 下看不出来。
            thumbs: .init(
                original: URL(string: "\(host)/thumb/orig/\(id).jpg")!,
                large: URL(string: "\(host)/thumb/large/\(id).jpg")!,
                small: URL(string: "\(host)/thumb/small/\(id).jpg")!
            )
        )
    }

    /// 恒 5 个（真实 API 不变式），由基础色逐级压暗生成。
    static func palette(at idx: Int) -> [String] {
        let base = palettes[idx % palettes.count]
        return (0..<5).map { k in
            let f = 1.0 - Double(k) * 0.17
            return String(format: "#%02x%02x%02x",
                          UInt8(Double(base.r) * f),
                          UInt8(Double(base.g) * f),
                          UInt8(Double(base.b) * f))
        }
    }

    static func uploader(for id: String) -> WallpaperDetail.Uploader {
        let host = "https://\(MockWallhaven.host)"
        // 单独持有用户名：`username:` 标签里含有 `name: "` 子串，会被
        // `scripts/convention-gate.sh` 的搜索参数名白名单误判成一个下发参数。
        let user = "uploader_" + id
        return .init(username: user,
                     group: "User",
                     avatar: .init(
                        px200: URL(string: "\(host)/avatar/200px/\(id).jpg")!,
                        px128: URL(string: "\(host)/avatar/128px/\(id).jpg")!,
                        px32: URL(string: "\(host)/avatar/32px/\(id).jpg")!,
                        px20: URL(string: "\(host)/avatar/20px/\(id).jpg")!))
    }

    /// 元素个数可变（真实实测 3~26），这里给 3~6 个；`similarSearchQuery` 只取前 3 个。
    static func tags(at idx: Int) -> [WallpaperDetail.Tag] {
        (0..<(3 + idx % 4)).map { k in
            let s = tagSeeds[k % tagSeeds.count]
            return .init(id: 300 + k, name: s.name, alias: s.alias,
                         categoryID: s.categoryID, category: s.category,
                         purity: "sfw", createdAt: "2026-09-22 07:53:43")
        }
    }

    /// 搜索项 id 形如 `mock-3`；其余（如手输 id）按稳定求和哈希落到合法下标。
    private static func index(of id: String) -> Int {
        if id.hasPrefix("mock-"), let i = Int(id.dropFirst(5)) { return i }
        return id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % total
    }

    static func image(path: String) -> Data {
        let (w, h): (Int, Int)
        if path.hasPrefix("/wallpaper/") { (w, h) = (1920, 1080) }
        else if path.contains("/orig/") { (w, h) = (960, 540) }
        else if path.contains("/large/") { (w, h) = (640, 360) }
        else { (w, h) = (480, 270) }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let n = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let c = palettes[n % palettes.count]
        return jpegGradient(width: w, height: h, r: c.r, g: c.g, b: c.b)
    }

    /// 生成一张上深下浅的渐变 JPEG（纯进程内，无网络），用于缩略图 / 原图占位。
    static func jpegGradient(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data()
        }
        let top = CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        let bottom = CGColor(red: CGFloat(r) / 255 * 0.4, green: CGFloat(g) / 255 * 0.4,
                             blue: CGFloat(b) / 255 * 0.4, alpha: 1)
        var loc: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: &loc) {
            ctx.drawLinearGradient(gradient, start: .zero,
                                  end: CGPoint(x: 0, y: CGFloat(height)), options: [])
        }
        guard let cg = ctx.makeImage() else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return Data() }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}

private extension Array where Element == URLQueryItem {
    func value(_ name: String) -> String? {
        first { $0.name == name }?.value
    }
}
