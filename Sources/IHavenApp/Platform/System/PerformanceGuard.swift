import AppKit
import Foundation

/// 动态壁纸的性能护栏（PRD F10）：命中触发档时自动暂停，条件解除后自动恢复。
///
/// ## 三条硬约束（每条都对应一个真实失效模式）
///
/// 1. **一律只调 `pause()` / `resume()`，绝不 `stop()`、绝不重建桌面层窗口。**
///    `pause()` 只是 `timer?.invalidate()`，窗口与最后一帧的图**留在屏幕上**；`resume()`
///    只重建 Timer，`frameIndex` 不重置，从原帧继续，代价约 0。而重建窗口要遍历
///    `NSScreen.screens` 建 `NSWindow` 并从盘读一张 JPEG，且该路径有已验证的
///    「同步建桌面层窗口 → autorelease pool drain 时 SIGSEGV」约束。
///
/// 2. **必须区分「护栏暂停」与「用户手动暂停」** —— 引擎的 `isPaused` 区分不了这两者，
///    不分开就会在用户主动暂停后又被护栏「恢复」，把用户的意图覆盖掉。
///    状态机见 `userPaused` / `didAutoPause`。
///
/// 3. **不确定就不暂停。** 读不到窗口、读不到电量、判不准全屏时一律放过 ——
///    误暂停是「我的壁纸怎么不动了」（用户以为功能坏了），误播只是多费一点电。
///
/// ## 为什么是 App 级单例而不是协议注入
/// 全 App 只有一个电源监控、一个采样器、一个调度决策点；`ImagePipeline.shared` /
/// `NukeImagePipeline.pipeline` 已是同一性质的存在。用 `@Observable`（ADR-004 禁的是旧的那套
/// 引用式状态管理，不禁止 Observation 宏）让设置面板能直接读 `snapshot` 自动重绘，
/// 省掉一条 onChange 手抄链路。
@MainActor
@Observable
final class PerformanceGuard {
    static let shared = PerformanceGuard()

    private(set) var snapshot = GuardSnapshot()

    private weak var engine: DynamicWallpaperPlaying?
    private let power = PowerStateMonitor()
    private var sampler = ProcessUsageSampler()
    private var observations: [NSObjectProtocol] = []
    private var usageTimer: Timer?

    /// 护栏自己按下的暂停（区别于用户手动暂停）。
    private var didAutoPause = false
    /// 用户手动暂停过；为真时护栏即使条件解除也不恢复，直到用户自己恢复。
    private var userPaused = false
    /// 条件解除后的恢复延迟，避免全屏切来切去抖个不停。
    private var resumeTask: Task<Void, Never>?

    private init() {}

    // MARK: - 装配

    func attach(_ engine: DynamicWallpaperPlaying) {
        self.engine = engine
    }

    // MARK: - 生命周期

    func start() {
        guard observations.isEmpty else { return }
        power.start { [weak self] in Task { @MainActor in self?.evaluate() } }
        // 前台应用切换与 Space 切换：全屏判定的两个入口。
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            observations.append(workspace.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.evaluate() }
                })
        }
        // 引擎状态回执：用户手动暂停 / 恢复要靠它识别（约束 2）。
        engine?.onStateChange = { [weak self] in Task { @MainActor in self?.engineStateChanged() } }
        startUsageTimer()
        evaluate()
    }

    func stop() {
        observations.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observations.removeAll()
        power.stop()
        usageTimer?.invalidate()
        usageTimer = nil
        resumeTask?.cancel()
        resumeTask = nil
    }

    // MARK: - 判定

    private func evaluate() {
        power.sample()
        let prefs = preferences()
        var triggers = Set<PerformanceTrigger>()
        var unavailable: [PerformanceTrigger: String] = [:]

        // ① 前台全屏
        if prefs.isEnabled(.fullscreen) {
            if FullscreenDetector.frontmostAppCoversScreen() {
                triggers.insert(.fullscreen)
            }
        } else {
            unavailable[.fullscreen] = String(localized: "已在设置中关闭")
        }

        // ② 电池电量。无电池（台式机）= 永久不可用，必须说明而不是灰着。
        if prefs.isEnabled(.lowBattery) {
            if let percent = power.batteryPercent {
                if percent <= prefs.batteryThreshold { triggers.insert(.lowBattery) }
            } else {
                unavailable[.lowBattery] = String(localized: "本机没有电池")
            }
        } else {
            unavailable[.lowBattery] = String(localized: "已在设置中关闭")
        }

        // ③ 低电量模式。台式机恒 false，同样要说明。
        if prefs.isEnabled(.lowPowerMode) {
            if power.isLowPowerMode { triggers.insert(.lowPowerMode) }
            else if !ProcessInfo.processInfo.isLowPowerModeEnabled { /* 支持但未开启，无需说明 */ }
        } else {
            unavailable[.lowPowerMode] = String(localized: "已在设置中关闭")
        }

        // ④ 系统过热。
        if prefs.isEnabled(.thermal) {
            if power.thermalState != .nominal { triggers.insert(.thermal) }
        } else {
            unavailable[.thermal] = String(localized: "已在设置中关闭")
        }

        snapshot.activeTriggers = triggers
        snapshot.unavailableReasons = unavailable
        applyPauseDecision(triggers: triggers)
    }

    private func applyPauseDecision(triggers: Set<PerformanceTrigger>) {
        guard let engine, engine.isPlaying else {
            // 没在播放：清理「我按下的暂停」标记，下次播放重新开始判定。
            didAutoPause = false
            snapshot.isPausedByGuard = false
            return
        }
        if !triggers.isEmpty {
            resumeTask?.cancel()
            resumeTask = nil
            guard !engine.isPaused, !userPaused else { return }
            engine.pause()
            didAutoPause = true
            snapshot.isPausedByGuard = true
        } else if didAutoPause, engine.isPaused, !userPaused {
            // 延迟恢复：全屏切来切去时不要立刻跟着动。
            resumeTask?.cancel()
            resumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, self.didAutoPause, let engine = self.engine,
                      engine.isPlaying, engine.isPaused, !self.userPaused,
                      self.snapshot.activeTriggers.isEmpty else { return }
                engine.resume()
                self.didAutoPause = false
                self.snapshot.isPausedByGuard = false
            }
        }
    }

    /// 引擎状态变了：识别「用户手动暂停 / 恢复」（约束 2）。
    private func engineStateChanged() {
        guard let engine else { return }
        if engine.isPaused, !didAutoPause {
            userPaused = true
        } else if engine.isPlaying, !engine.isPaused {
            userPaused = false
        }
        snapshot.isPausedByGuard = didAutoPause
    }

    // MARK: - 占用采样

    private func startUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleUsage() }
        }
        // `.common` mode：面板展开 / 菜单滚动时也要继续采。
        if let usageTimer { RunLoop.main.add(usageTimer, forMode: .common) }
    }

    private func sampleUsage() {
        let usage = sampler.sample(elapsed: Date().timeIntervalSince(lastSampleDate))
        lastSampleDate = Date()
        snapshot.cpuPercent = usage.cpuPercent
        snapshot.processBytes = usage.processBytes
        snapshot.systemPressurePercent = usage.systemPressurePercent
    }

    private var lastSampleDate = Date()

    // MARK: - 偏好

    private struct Preferences {
        var enabled: Set<PerformanceTrigger> = []
        var batteryThreshold = 20

        func isEnabled(_ trigger: PerformanceTrigger) -> Bool { enabled.contains(trigger) }
    }

    private func preferences() -> Preferences {
        var prefs = Preferences()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UserPreferenceKey.perfPauseOnFullscreen) { prefs.enabled.insert(.fullscreen) }
        if defaults.bool(forKey: UserPreferenceKey.perfPauseOnLowBattery) { prefs.enabled.insert(.lowBattery) }
        if defaults.bool(forKey: UserPreferenceKey.perfPauseOnLowPower) { prefs.enabled.insert(.lowPowerMode) }
        if defaults.bool(forKey: UserPreferenceKey.perfPauseOnThermal) { prefs.enabled.insert(.thermal) }
        let stored = defaults.integer(forKey: UserPreferenceKey.perfBatteryThreshold)
        prefs.batteryThreshold = stored == 0 ? 20 : stored
        return prefs
    }
}
