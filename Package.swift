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
            path: "Sources/IHavenApp",
            // 本地化资源。两个约束：
            // 1. 用 .copy 而非 .process：.lproj 必须原样保留目录结构，否则 Bundle 查不到对应语言的
            //    Localizable.strings。
            // 2. 逐个声明 .lproj 而不是整个 `Resources` 目录：写 `.copy("Resources")` 时 SwiftPM 会
            //    把目录名一起保留，产物是 `…bundle/Contents/Resources/Resources/zh-Hans.lproj`，
            //    .lproj 被埋深一层，`Bundle.module` 自己都查不到（开发态补资源的来源就是它）。
            resources: [.copy("Resources/zh-Hans.lproj"), .copy("Resources/en.lproj")]
        )
    ]
)
