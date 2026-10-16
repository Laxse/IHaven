import Foundation

/// UserDefaults 的 key 常量（`@AppStorage` 用）。集中定义，避免同一个字符串散落在多处被写歪 ——
/// 尤其 `nsfwAllowed`：筛选面板（判定是否可点）与设置面板（开关）读的是同一个开关，
/// 拼写不一致会导致「设置里开了、面板里还是灰的」这类 silent bug。
enum UserPreferenceKey {
    static let appearance = "ihaven.appearance"
    static let language = "ihaven.language"
    /// 是否允许成人内容（NSFW）。默认关闭（false）—— 见 ADR-012。
    static let nsfwAllowed = "ihaven.nsfwAllowed"

    // MARK: - 壁纸铺法（PRD F2 剩余部分）

    /// 填充模式：`WallpaperFillMode.rawValue`（0 适应 / 1 填充）。
    static let wallpaperFillMode = "ihaven.wallpaperFillMode"
    /// 目标显示器：`CGDirectDisplayID`，`0` = 主屏。
    static let wallpaperTargetDisplay = "ihaven.wallpaperTargetDisplay"
    /// 目标显示器的展示名（仅用于「上次选的屏已不在」时的回退提示，不参与匹配）。
    static let wallpaperTargetName = "ihaven.wallpaperTargetName"
}
