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
        } else {
            // /thumb/<id> 缩略图 与 /wallpaper/<id> 原图 都走图片通道。
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
    static let shapes: [(w: Int, h: Int, ratio: String, resolution: String)] = [
        (1080, 1920, "9x16", "1080x1920"),
        (1440, 1440, "1x1", "1440x1440"),
        (1920, 1080, "16x9", "1920x1080"),
        (2560, 1080, "21x9", "2560x1080"),
        (3440, 1440, "21x9", "3440x1440"),
    ]
    static let palettes: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (232, 163, 61), (79, 168, 92), (127, 184, 232),
        (216, 164, 65), (216, 87, 75), (123, 135, 201),
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
        let items = (0..<perPage).map { i -> Wallpaper in
            let idx = start + i
            let shape = shapes[idx % shapes.count]
            let color = palettes[idx % palettes.count]
            let id = "mock-\(idx)"
            let hex = String(format: "#%02X%02X%02X", color.r, color.g, color.b)
            let thumb = URL(string: "https://\(MockWallhaven.host)/thumb/\(id).jpg")!
            let full = URL(string: "https://\(MockWallhaven.host)/wallpaper/\(id).jpg")!
            return Wallpaper(
                id: id,
                url: full,
                shortURL: URL(string: "https://wallhaven.cc/w/\(id)")!,
                createdAt: "2024-01-\(String(format: "%02d", (idx % 28) + 1))T10:00:00.000Z",
                purity: "100",
                category: ["general", "anime", "people"][idx % 3],
                width: shape.w,
                height: shape.h,
                resolution: shape.resolution,
                ratio: shape.ratio,
                fileSize: 1_000_000 + idx * 13_337,
                fileType: "image/jpeg",
                views: 1_000 + idx * 7,
                favorites: 50 + idx * 3,
                source: idx % 5 == 0 ? nil : "https://example.com/\(id)",
                colors: [hex],
                path: full,
                thumbs: .init(original: thumb, large: thumb, small: thumb)
            )
        }

        let page = WallhavenPage(
            data: items,
            meta: .init(currentPage: page, lastPage: lastPage,
                       perPage: "\(perPage)", total: total,
                       query: query.value("q"), seed: query.value("seed"))
        )
        return (try? encoder.encode(page)) ?? Data()
    }

    static func image(path: String) -> Data {
        let isFull = path.hasPrefix("/wallpaper/")
        let w = isFull ? 1920 : 480
        let h = isFull ? 1080 : 270
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
