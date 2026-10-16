import SwiftUI

/// 设置 · 性能页签（PRD F10）：四档自动暂停开关 + 实时占用面板。
///
/// ⚠️ **不可用的档位必须写出原因，不能只是灰着**。台式机没有电池、读不到窗口时，
/// 一个灰掉的开关等于「功能坏了」；写明「本机没有电池」用户才知道这是正常的。
///
/// ⚠️ **没有「显存」那一格**：Apple Silicon 是统一内存架构，实测 `IOAccelerator` 没有任何
/// VRAM 属性可读。第三格换成「帧序列磁盘占用」——它才真正解释动态壁纸为什么费资源。
struct SettingsPerformanceTab: View {
    let guardProvider: PerformanceGuard

    @AppStorage(UserPreferenceKey.perfPauseOnFullscreen) private var pauseOnFullscreen = false
    @AppStorage(UserPreferenceKey.perfPauseOnLowBattery) private var pauseOnLowBattery = false
    @AppStorage(UserPreferenceKey.perfPauseOnLowPower) private var pauseOnLowPower = false
    @AppStorage(UserPreferenceKey.perfPauseOnThermal) private var pauseOnThermal = false
    @AppStorage(UserPreferenceKey.perfBatteryThreshold) private var batteryThreshold = 20

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s6.rawValue) {
            triggerSection
            Divider().overlay(IHaven.Color.border)
            usageSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { guardProvider.start() }
        .onDisappear { guardProvider.stop() }
    }

    // MARK: - 四档开关

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("自动暂停")
            Text("动态壁纸播放时命中下列条件会自动暂停；条件解除后约 3 秒恢复。暂停只停帧计时，桌面层窗口保留。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            triggerRow(.fullscreen, isOn: $pauseOnFullscreen,
                       label: "前台应用全屏", hint: "看视频、打游戏、演示时桌面没人看")
            triggerRow(.lowBattery, isOn: $pauseOnLowBattery,
                       label: "电量低于阈值", hint: nil) {
                Stepper(value: $batteryThreshold, in: 5...90, step: 5) {
                    Text("\(batteryThreshold)%").font(IHaven.Font.system(.xs)).monospacedDigit()
                }
                .disabled(!pauseOnLowBattery || guardProvider.snapshot.unavailableReasons[.lowBattery] != nil)
            }
            triggerRow(.lowPowerMode, isOn: $pauseOnLowPower,
                       label: "系统低电量模式", hint: nil)
            triggerRow(.thermal, isOn: $pauseOnThermal,
                       label: "系统过热", hint: "热状态偏离正常时")
        }
    }

    /// 一行开关。`unavailable` 非空时整行只显示原因、不显示开关 —— 给一个点不动的开关
    /// 比不给开关更糟（用户会反复尝试然后以为功能坏了）。
    @ViewBuilder
    private func triggerRow(_ trigger: PerformanceTrigger, isOn: Binding<Bool>,
                            label: LocalizedStringKey, hint: String?,
                            @ViewBuilder accessory: () -> some View = { EmptyView() }) -> some View {
        if let reason = guardProvider.snapshot.unavailableReasons[trigger] {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text(label).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg2)
                Spacer(minLength: 0)
                Text(reason).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            }
        } else {
            VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
                Toggle(isOn: isOn) {
                    Text(label).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg)
                }
                .toggleStyle(.switch)
                HStack(spacing: IHaven.Space.s4.rawValue) {
                    if let hint {
                        Text(hint).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                    }
                    accessory()
                }
                .padding(.leading, IHaven.Space.s8.rawValue)
            }
        }
    }

    // MARK: - 占用面板

    private var usageSection: some View {
        let snapshot = guardProvider.snapshot
        return VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("实时占用")
            HStack(spacing: IHaven.Space.s6.rawValue) {
                usageCell("CPU", value: String(format: "%.0f%%", snapshot.cpuPercent))
                usageCell("进程内存", value: Self.byteText(snapshot.processBytes))
                usageCell("内存压力", value: String(format: "%.0f%%", snapshot.systemPressurePercent))
            }
            if snapshot.isPausedByGuard {
                Label("已由护栏自动暂停", systemImage: "pause.circle")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
            }
            Text("采样只在设置面板打开时进行（1 秒一次，`getrusage` 实测 0.0004ms/次，可忽略）。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
    }

    private func usageCell(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
            Text(value).font(IHaven.Font.system(.lg, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.fg).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }

    private static func byteText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
