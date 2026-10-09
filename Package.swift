// swift-tools-version:6.0
import PackageDescription

// IHaven 重写骨架（Swift 6 / macOS 26）。
// 独立于旧版 IHaven.xcodeproj，按 ARCH §4 分层：App / Core / Features / Infrastructure。
// 旧版 IHaven/（2020，含硬编码明文 Key + Alamofire）保留作参考，不接入本包。
let package = Package(
    name: "IHavenApp",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "IHavenApp",
            path: "Sources/IHavenApp"
        )
    ]
)
