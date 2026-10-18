import SwiftUI

/// 设置 · 轮换页签（PRD F13）：规则列表 + 新建 / 删除 / 开关。
///
/// ⚠️ **执行期绝不发 `/search`**（45/min 与详情共享同一个桶），所以来源只有三类：
/// 本地导入（`Application Support`，不被系统回收，最稳）、已设置（`$TMPDIR` 可能被回收，
/// 用前校验）、收藏（只有远程 URL，只轮换其中已下载过的）。UI 上把这点写明，
/// 否则用户会以为「我的收藏怎么不全」。
///
/// ⚠️ **App 退出期间不轮换**：自启要走 `SMAppService` / LaunchAgent，实测开发态注册
/// 不落地（裸可执行文件 `register()` 返回成功但 `launchctl` 查无残留），必须打成 .app
/// 放进 `/Applications` 才生效。所以这里明示边界，不做一个骗人的开关。
///
/// CRUD 走 `WallpaperScheduler`（它已持有数据库），这样 `BrowseView`（已顶到 300 行上限）
/// 一行都不用改。
struct SettingsScheduleTab: View {
    let scheduler: WallpaperScheduler

    @State private var schedules: [WallpaperSchedule] = []
    @State private var editing: WallpaperSchedule?
    /// 相册来源下拉用（#67）。列表态汇总行也要用它把 albumID 还原成相册名。
    @State private var albums: [Album] = []

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s6.rawValue) {
            if let editing {
                ScheduleEditorView(draft: editing, albums: albums) { saved in
                    scheduler.save(saved)
                    self.editing = nil
                    reload()
                } onCancel: {
                    self.editing = nil
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { reload() }
    }

    // MARK: - 列表

    @ViewBuilder
    private var list: some View {
        if schedules.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: IHaven.Space.s4.rawValue) {
                ForEach(schedules) { schedule in row(schedule) }
                Button { editing = WallpaperSchedule(name: defaultName(), source: .imported) } label: {
                    Label("新建轮换规则", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, IHaven.Space.s2.rawValue)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            Text("还没有轮换规则。新建后，壁纸会按时间或间隔自动更换。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Text("App 退出期间不会轮换；来源不含网络搜索（避免消耗 wallhaven 的每分钟 45 次调用上限）。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
            Button { editing = WallpaperSchedule(name: defaultName(), source: .imported) } label: {
                Label("新建轮换规则", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func row(_ schedule: WallpaperSchedule) -> some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Toggle(isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { enabled in
                        var updated = schedule
                        updated.isEnabled = enabled
                        scheduler.save(updated)
                        reload()
                    })) {
                    Text(schedule.name).font(IHaven.Font.system(.md)).foregroundStyle(IHaven.Color.fg)
                }
                .toggleStyle(.switch)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    scheduler.remove(id: schedule.id)
                    reload()
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("删除这条规则")
            }
            Text(summary(schedule))
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
    }

    // MARK: - 辅助

    private func reload() {
        schedules = scheduler.allSchedules()
        albums = scheduler.allAlbums()
    }

    private func defaultName() -> String {
        String(localized: "轮换规则 \(schedules.count + 1)")
    }

    private func summary(_ schedule: WallpaperSchedule) -> String {
        let trigger: String
        switch schedule.mode {
        case .interval:
            trigger = String(format: String(localized: "每 %lld 分钟"), schedule.intervalMinutes)
        case .timeWindow:
            trigger = String(format: String(localized: "%02lld:%02lld – %02lld:%02lld"),
                             schedule.startMinute / 60, schedule.startMinute % 60,
                             schedule.endMinute / 60, schedule.endMinute % 60)
        }
        let source: String
        switch schedule.source {
        case .imported: source = String(localized: "本地导入")
        case .applied: source = String(localized: "已设置")
        case .favorites: source = String(localized: "收藏")
        case .album:
            source = albums.first { $0.id == schedule.albumID }?.name ?? String(localized: "相册")
        }
        let screen = WallpaperTarget.screenOptions().first { $0.id == schedule.targetDisplay }?.title
            ?? String(localized: "主屏")
        return "\(trigger) · 来源：\(source) · \(screen)"
    }
}

/// 新建 / 编辑表单。**独立成 struct**：`@Bindable` 只能用于 `@Observable` 类，
/// 而 `WallpaperSchedule` 是值类型，必须靠 `@State` + `Binding` 驱动。
private struct ScheduleEditorView: View {
    @State var draft: WallpaperSchedule
    let albums: [Album]
    let onSave: (WallpaperSchedule) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("新建轮换规则")
            TextField("规则名称", text: $draft.name)
                .textFieldStyle(.plain).font(IHaven.Font.system(.md))
                .padding(.horizontal, IHaven.Space.s5.rawValue).frame(height: 32)
                .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))

            Picker("触发方式", selection: $draft.mode) {
                Text("按间隔").tag(WallpaperSchedule.Mode.interval)
                Text("按时段").tag(WallpaperSchedule.Mode.timeWindow)
            }
            .pickerStyle(.segmented)

            if draft.mode == .interval {
                Stepper(value: $draft.intervalMinutes, in: 5...720, step: 5) {
                    Text("每 \(draft.intervalMinutes) 分钟换一张")
                        .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg)
                }
            } else {
                minuteField("开始", minute: $draft.startMinute)
                minuteField("结束", minute: $draft.endMinute)
                weekdayPicker(weekdays: $draft.weekdays)
            }

            Picker("来源", selection: $draft.source) {
                Text("本地导入").tag(WallpaperSchedule.Source.imported)
                Text("已设置（含已下载的）").tag(WallpaperSchedule.Source.applied)
                Text("收藏（仅已下载的）").tag(WallpaperSchedule.Source.favorites)
                Text("相册（仅本地文件仍在的）").tag(WallpaperSchedule.Source.album)
            }
            .pickerStyle(.menu)
            // 切到相册来源却还没选具体相册时，默认落到第一个相册（否则存下来是一条空转的规则）。
            .onChange(of: draft.source) { _, newValue in
                if newValue == .album, draft.albumID == nil { draft.albumID = albums.first?.id }
            }

            if draft.source == .album {
                if albums.isEmpty {
                    Text("还没有相册，先到侧栏「相册」创建。")
                        .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                } else {
                    Picker("选择相册", selection: $draft.albumID) {
                        ForEach(albums) { album in
                            Text(album.name).tag(album.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // 目标屏（#67 按屏分类）：每条规则各自指定写到哪块屏，0 = 主屏。
            Picker("目标屏", selection: $draft.targetDisplay) {
                ForEach(WallpaperTarget.screenOptions()) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            // 多屏写入的著名静默失败：没开「显示器具有单独 Spaces」时只生效一块屏（要注销重登）。
            // 选非主屏时提前提示，避免用户以为规则坏了。
            if draft.targetDisplay != 0, WallpaperTarget.needsSeparateSpacesWarning() {
                Text("未开启「显示器具有单独 Spaces」，多屏壁纸可能只在一块屏生效。请在系统设置 ▸ 桌面与程序坞中开启（修改后需注销重新登录）。")
                    .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("顺序", selection: $draft.order) {
                Text("随机").tag(WallpaperSchedule.Order.random)
                Text("按顺序").tag(WallpaperSchedule.Order.sequential)
            }
            .pickerStyle(.segmented)

            HStack(spacing: IHaven.Space.s4.rawValue) {
                Button("保存") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("取消", action: onCancel).buttonStyle(.bordered)
            }
        }
    }

    /// 时刻输入：自零点起的分钟数 ↔ HH:MM。存分钟数而不是 `Date` 是有意的
    /// （时段是每日重复的壁钟语义，存 Date 会引入时区与夏时制歧义）。
    private func minuteField(_ label: LocalizedStringKey, minute: Binding<Int>) -> some View {
        HStack(spacing: IHaven.Space.s3.rawValue) {
            Text(label).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            Text(String(format: "%02d:%02d", minute.wrappedValue / 60, minute.wrappedValue % 60))
                .font(IHaven.Font.system(.sm)).monospacedDigit().foregroundStyle(IHaven.Color.fg)
            Stepper("", value: minute, in: 0...1439, step: 15).labelsHidden()
        }
    }

    private func weekdayPicker(weekdays: Binding<[Int]>) -> some View {
        // Calendar weekday：1 = 周日 … 7 = 周六。
        let symbols = Calendar.current.shortWeekdaySymbols
        return HStack(spacing: IHaven.Space.s2.rawValue) {
            ForEach(1...7, id: \.self) { day in
                let isOn = weekdays.wrappedValue.contains(day)
                Button {
                    if isOn { weekdays.wrappedValue.removeAll { $0 == day } }
                    else { weekdays.wrappedValue.append(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(IHaven.Font.system(.xs, isOn ? IHaven.Font.weightEmphasize : .regular))
                        .foregroundStyle(isOn ? IHaven.Color.accentOn : IHaven.Color.meta)
                        .frame(width: 26, height: 24)
                        .background(isOn ? IHaven.Color.accent : IHaven.Color.surface,
                                    in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
                }
                .buttonStyle(.plain)
            }
            Text("不选 = 每天").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }
}
