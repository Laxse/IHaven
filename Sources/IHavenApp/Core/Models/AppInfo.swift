import Foundation

/// 应用元信息（设置 · 关于页展示用）：版本、仓库、作者、联系方式。纯值，无 UI / 网络依赖。
///
/// ⚠️ `version` 是**唯一事实来源**：关于页直接读它，`scripts/build-and-package.sh` 在打包时
/// 校验 `Packaging/Info.plist` 的 `CFBundleShortVersionString` 与它一致，不一致直接打包失败。
///
/// 为什么不从 `Bundle.main.infoDictionary` 读（这是最初的写法）：开发态跑裸二进制
/// （`swift build` / Xcode Run）时没有 Info.plist，只能靠写死的兜底值 —— 于是「改了版本号、
/// 界面上还是旧的」，且兜底值与 plist 各写一份必然漂移。版本是**常量**不是运行时信息，
/// 就该放在代码里，由打包脚本保证两边一致。
enum AppInfo {
    static let version = "2.0"

    static let repositoryURL = URL(string: "https://github.com/Laxse/IHaven")!
    /// 展示用文案（不带 scheme，比完整 URL 短，放在 72pt 宽的标签列后面不容易换行）。
    static let repositoryLabel = "github.com/Laxse/IHaven"

    static let authorName = "梁霄"
    static let authorURL = URL(string: "https://github.com/Laxse")!
    static let authorLabel = "github.com/Laxse"

    /// 联系方式：微信 ID。微信没有可点开的 URL scheme，只能复制，故关于页给它一个复制按钮。
    static let wechatID = "Laxse5356"
}
