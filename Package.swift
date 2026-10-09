// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "IHavenApp",
    platforms: [.macOS("26.0")],
    dependencies: [
        // 图片加载：Nuke 13.2.0（ADR-001）。全局 ImagePipelineActor 提供 Swift 6 并发保证。
        .package(url: "https://github.com/kean/Nuke.git", from: "13.2.0"),
        // 本地存储：GRDB.swift 7.11.1（ADR-002）。DatabasePool（WAL）提供 Swift 6 严格并发。
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .executableTarget(
            name: "IHavenApp",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/IHavenApp"
        )
    ]
)
