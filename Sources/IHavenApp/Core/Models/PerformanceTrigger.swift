import Foundation

/// 护栏的四个暂停触发档（PRD F10）。
///
/// 前三档是行业标配（Lively 的 Smart Pause 就是这三个），第四档「系统过热」是差异点：
/// `thermalState` 读取几乎免费，而竞品没有一个拿它当暂停理由。
public enum PerformanceTrigger: String, CaseIterable, Sendable {
    /// 前台应用占满整块屏（看视频 / 打游戏 / 演示）—— 此刻没人看桌面。
    case fullscreen
    /// 电池电量低于用户设定阈值。
    case lowBattery
    /// 系统低电量模式。
    case lowPowerMode
    /// 系统热状态偏离 nominal。
    case thermal
}
