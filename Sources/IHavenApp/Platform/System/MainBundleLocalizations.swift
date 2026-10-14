import Foundation

/// 把 `*.lproj` 补进 `Bundle.main`，让「设置 · 外观 · 语言」在开发态也能切换。
///
/// 为什么必须有这一步：SwiftUI 的 `Text("中文")`、`Button("保存") { }`、`.help("…")` 只接受
/// `LocalizedStringKey`，而 `LocalizedStringKey` **只在 `Bundle.main` 里查表** —— 这些初始化器
/// 都没有 `bundle:` 参数，改不了。两种运行形态下 `Bundle.main` 里有没有东西却不一样：
///
/// - 打包成 `.app`（`scripts/build-and-package.sh` 已把 `*.lproj` 复制进 `Contents/Resources`）：
///   查得到，切换语言立刻生效。
/// - 直接跑裸二进制（`swift build` / Xcode Run）：`Bundle.main` 就是可执行文件所在目录，SwiftPM
///   的资源被收进旁边的 `IHavenApp_IHavenApp.bundle`，主 bundle 里一个 `.lproj` 都没有 ——
///   查表恒失败，回退显示 key 本身。而 key 就是中文原文，于是**看起来完全像是「切换没生效」**。
///
/// 因此在启动早期把 `Bundle.module` 里的 `.lproj` 复制到 `Bundle.main.resourcePath`。
/// 只在缺失时补、幂等；打包态文件已存在，直接跳过，不做任何写操作。
///
/// 实测依据（2026-10-14）：`Bundle.localizations` 确实会被缓存（补完仍读到空数组），但
/// `localizedString(forKey:)` 每次都落盘查，补完后立刻能取到英文 —— 缓存不影响本方案。
enum MainBundleLocalizations {
    /// 与 `Sources/IHavenApp/Resources` 下的目录名一一对应；增删语言时两处一起改。
    private static let folders = ["zh-Hans.lproj", "en.lproj"]

    static func materializeIfNeeded() {
        // ⚠️ 顺序不能反：打包态必须在碰 `Bundle.module` **之前**就返回。
        // `Bundle.module` 是 SwiftPM 生成的懒加载静态量，找不到 `IHavenApp_IHavenApp.bundle`
        // 就 `fatalError`（实测：打包的 .app 启动即崩，报 "unable to find bundle named
        // IHavenApp_IHavenApp"）。而打包态本来就不需要它 —— `Contents/Resources` 下已齐全。
        guard !Bundle.main.localizations.contains("en") else { return }
        guard let from = Bundle.module.resourcePath, let to = Bundle.main.resourcePath else { return }
        let fm = FileManager.default
        for folder in folders {
            let src = (from as NSString).appendingPathComponent(folder)
            let dst = (to as NSString).appendingPathComponent(folder)
            guard fm.fileExists(atPath: src), !fm.fileExists(atPath: dst) else { continue }
            try? fm.copyItem(atPath: src, toPath: dst)
        }
    }
}
