import AppKit
import Foundation
import IOKit.ps

/// 电源 / 热状态监测（PRD F10 第二、三、四档）。
///
/// ⚠️ **不要用 `IOPSGetProvisioningPowerSourceType`**：该符号在 macOS 26 SDK 里**不存在**
/// （对整个 `IOKit.framework/Headers` 全量 grep 零匹配），照旧文档写会编译不过。判「是否接电源」
/// 只能读 `Power Source State` 字典键。
///
/// ⚠️ **台式机 / Mac mini / Mac Studio 上 `IOPSCopyPowerSourcesList` 返回 0 条**（实测本机就是）。
/// 那不是故障，是「本机没有电池」——电量档必须永久关闭并在 UI 上写明，而不是灰着一个开关。
final class PowerStateMonitor {
    /// 电量百分比 0~100；`nil` = 本机无电池或读不到。
    private(set) var batteryPercent: Int?
    private(set) var isLowPowerMode = false
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    var hasBattery: Bool { batteryPercent != nil }

    private var observations: [NSObjectProtocol] = []

    /// 采样一次。三个读取都便宜（实测 `isLowPowerModeEnabled` 约 0.02µs/次），可随通知直接调。
    func sample() {
        batteryPercent = Self.readBatteryPercent()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }

    /// 注册系统通知。回调都在 `queue: .main` 上（`NSProcessInfoPowerStateDidChange` 例外：
    /// 它投递在全局队列，由调用方自行 `Task { @MainActor in }`）。
    func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        observations.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onChange() }
            })
        observations.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onChange() }
            })
        // 低电量模式与热状态：Foundation 头文件明确要求用 default center。
        observations.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
                Task { @MainActor in onChange() }
            })
        observations.append(NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
                Task { @MainActor in onChange() }
            })
    }

    func stop() {
        observations.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
    }

    // MARK: - 电池

    /// ⚠️ 调用写法有个坑：`IOPSCopyPowerSourcesInfo()` 的 Swift 返回是 `Unmanaged<CFTypeRef>?`，
    /// 必须先 `takeUnretainedValue()` 再传给 `IOPSCopyPowerSourcesList` —— 直接把 `Unmanaged`
    /// 当参数传会报「expected to be an instance of a class or class-constrained type」。
    private static func readBatteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeUnretainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject],
              !sources.isEmpty
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            else { continue }
            let dict = description as? [String: Any] ?? [:]
            // 只算内置电池：UPS / 外接电源的容量与本机续航无关。
            guard (dict["Type"] as? String) == "InternalBattery" else { continue }
            // ⚠️ 变量名不能叫 `max`：会遮蔽 Swift 的全局 `max(_:_:)`，下一行的 `max(0, …)`
            // 直接报「cannot call value of non-function type 'Int'」。
            guard let current = dict["Current Capacity"] as? Int,
                  let capacity = dict["Max Capacity"] as? Int, capacity > 0
            else { continue }
            return min(100, max(0, Int((Double(current) / Double(capacity) * 100).rounded())))
        }
        return nil
    }
}
