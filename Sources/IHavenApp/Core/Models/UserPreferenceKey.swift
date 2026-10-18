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

    // MARK: - 性能护栏（PRD F10）

    static let perfPauseOnFullscreen = "ihaven.perfPauseOnFullscreen"
    static let perfPauseOnLowBattery = "ihaven.perfPauseOnLowBattery"
    static let perfPauseOnLowPower = "ihaven.perfPauseOnLowPower"
    static let perfPauseOnThermal = "ihaven.perfPauseOnThermal"
    /// 电量阈值百分比；`0` = 未设置，读时按默认 20 处理。
    static let perfBatteryThreshold = "ihaven.perfBatteryThreshold"

    // MARK: - 全局热键（#68）

    /// 是否启用 ⌥⌘S 全局「换一张」。默认 false —— **启动时不索取辅助功能权限**，
    /// 由用户在设置 ▸ 快捷键里按需开启（开启时才弹一次系统授权框）。
    static let globalHotkeyEnabled = "ihaven.globalHotkeyEnabled"

    // MARK: - AI 图生视频（#70 多模型）

    /// 选中的模型：`AIVideoModel.id`（Replicate 的 owner/name）。缺省回落到目录里的默认模型。
    static let aiVideoModel = "ihaven.aiVideoModel"
}
