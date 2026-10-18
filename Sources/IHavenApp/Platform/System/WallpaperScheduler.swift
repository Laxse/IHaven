import AppKit
import Foundation

/// 壁纸轮换执行器（PRD F13）。
///
/// ## 三条硬约束
///
/// 1. **执行期绝不发 `/search`。** 45 次/分钟的硬限与详情请求共享同一个桶
///    （`Infrastructure/Network/APIError.swift` 已实测记录）。所以 `Source` 只有
///    `favorites` / `applied` / `imported` 三类本地或已缓存来源，**没有 search 型** ——
///    要支持搜索来源就得先做「保存时拉一次、缓存 id 列表」，那是另一个功能。
///    从收藏轮换即使每次重下原图也不耗配额（`ImageDownloading` 走图片 CDN，不过桶），
///    只是费流量，UI 上标注清楚即可。
/// 2. **`localPath` 必须先 `fileExists` 校验。** `ImageFileDownloader` 把原图写到
///    `$TMPDIR/IHavenOriginals/`，**系统可随时回收**（重启 / 磁盘压力 / 定期清理）。
///    失效就跳过该项取下一张，不把它当可用源。
/// 3. **只调 `WallpaperEngine`，不碰 `BrowseViewModel`。** 那层会 `downloader.download`
///    再设置，还要往 `loadState` 写状态 —— 后台轮换不该动前台的加载态。
///
/// ## 定时器为什么是 `DispatchSourceTimer` 而不是 `Timer`
/// 两者都受系统休眠影响，但 `DispatchSourceTimer` 的 `wallDeadline` 语义明确、可
/// `suspend/resume`，且不受 RunLoop mode 影响。**休眠唤醒后必须重算下一次触发时间** ——
/// 睡 3 小时醒来不会补跑，也不会连换 5 张（补做比不换更糟）。
///
/// ## App Nap 是真风险
/// 关窗后 App 没有可见窗口，macOS 会把它判为可休眠并合并定时器 —— 不做
/// `beginActivity`，「每 30 分钟换一张」会变成「每 2 小时随机换一张」。
@MainActor
final class WallpaperScheduler {
    /// App 级单例。`configure(database:engine:)` 由 `IHavenApp.bootstrap()` 调用 ——
    /// 数据库装配失败时会降级成 InMemory 实现，那时单例仍可用（规则只是不持久）。
    static let shared = WallpaperScheduler()

    private var database: WallpaperDatabase?
    private var engine: WallpaperEngine?
    private var timer: DispatchSourceTimer?
    private var napAssertion: NSObjectProtocol?
    private var observations: [NSObjectProtocol] = []
    /// 下一次计划触发时刻，供唤醒后判断「是否已错过」。
    private var nextFire: Date?
    private var isRunning = false

    private init() {}

    func configure(database: WallpaperDatabase, engine: WallpaperEngine) {
        self.database = database
        self.engine = engine
        if isRunning { start() }
    }

    // MARK: - 规则 CRUD（设置 · 轮换页签直接走这里，不必再拉一条数据库注入链）

    func allSchedules() -> [WallpaperSchedule] {
        (try? database?.schedules()) ?? []
    }

    /// 全部相册（设置 · 轮换页签的「相册来源」下拉用）。相册 CRUD 走 `WallpaperDatabase` 协议。
    func allAlbums() -> [Album] {
        (try? database?.albums()) ?? []
    }

    func save(_ schedule: WallpaperSchedule) {
        try? database?.addSchedule(schedule)
        reschedule()
    }

    func remove(id: String) {
        try? database?.removeSchedule(id: id)
        reschedule()
    }

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        suppressAppNap()
        // 前台 / 唤醒 / 屏幕参数变化都重算：这些时刻系统的定时器语义可能已经变了。
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.screensDidWakeNotification] {
            observations.append(workspace.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reschedule() }
                })
        }
        isRunning = true
        reschedule()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        nextFire = nil
        if let napAssertion {
            ProcessInfo.processInfo.endActivity(napAssertion)
            self.napAssertion = nil
        }
        observations.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observations.removeAll()
    }

    /// 规则变化（增删改 / 开关）后由设置页调用。
    func reschedule() {
        timer?.cancel()
        timer = nil
        let schedules = allSchedules()
        let enabled = schedules.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        // 间隔型取最短间隔；时段型每分钟查一次窗口（代价可忽略，每分钟一次 `isActive`）。
        let intervalMinutes = enabled
            .filter { $0.mode == .interval }
            .map(\.intervalMinutes)
            .min() ?? 1
        let seconds = max(60, intervalMinutes * 60)
        nextFire = Date().addingTimeInterval(TimeInterval(seconds))

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds))
        source.setEventHandler { [weak self] in Task { @MainActor in self?.tick() } }
        source.resume()
        timer = source
    }

    // MARK: - 执行

    private func tick() {
        nextFire = Date()
        rotateIfNeeded(at: Date())
    }

    /// 到点且规则命中时换一张。
    func rotateIfNeeded(at date: Date) {
        guard let schedules = try? database?.schedules() else { return }
        for var schedule in schedules where schedule.isEnabled {
            guard schedule.isActive(at: date) else { continue }
            // 间隔型还要看距上次执行是否够一个间隔（时段型由窗口本身约束）。
            if schedule.mode == .interval, let last = schedule.lastRunAt,
               date.timeIntervalSince(last) < TimeInterval(schedule.intervalMinutes * 60) { continue }
            guard let candidate = nextCandidate(for: &schedule) else { continue }
            apply(candidate, for: &schedule, at: date)
        }
    }

    /// 取下一张候选；顺序模式推进游标，随机模式避开上一张。
    private func nextCandidate(for schedule: inout WallpaperSchedule) -> ImportedWallpaper? {
        let pool = pool(for: schedule)
        guard !pool.isEmpty else { return nil }
        var index: Int
        switch schedule.order {
        case .sequential:
            index = schedule.cursor % pool.count
            schedule.cursor = (schedule.cursor + 1) % pool.count
        case .random:
            index = Int.random(in: pool.indices)
            if pool.count > 1, let last = schedule.lastWallpaperID,
               let lastIndex = pool.firstIndex(where: { $0.id == last }), lastIndex == index {
                index = (index + 1) % pool.count
            }
        }
        // `lastWallpaperID` 记的是 ImportedWallpaper.id；favorites / applied 的 id 与之相同
        // （都是 wallhaven 的壁纸 id），可直接比较。
        let chosen = pool[index]
        schedule.lastWallpaperID = chosen.id
        return chosen
    }

    /// 规则对应的候选池。**本地文件已不存在的项一律剔除**（约束 2）。
    private func pool(for schedule: WallpaperSchedule) -> [ImportedWallpaper] {
        guard let database else { return [] }
        switch schedule.source {
        case .imported:
            return (try? database.imported()) ?? []
        case .applied:
            guard let applied = try? database.applied() else { return [] }
            return applied.compactMap { record -> ImportedWallpaper? in
                guard FileManager.default.fileExists(atPath: record.localPath) else { return nil }
                return ImportedWallpaper(
                    id: record.id,
                    fileName: record.id,
                    filePath: record.localPath,
                    thumbnailPath: record.thumbnailURL?.path ?? record.localPath,
                    kind: .image,
                    width: record.width, height: record.height,
                    duration: nil, fileSize: 0, addedAt: record.appliedAt)
            }
        case .favorites:
            // 收藏只有远程 URL，没有本地路径：必须现下。这里只返回「已设置历史里下过的那些」，
            // 把「纯收藏」交给 UI 标注「需要联网下载原图」—— 后台静默下载多张大图不是好事。
            guard let applied = try? database.applied() else { return [] }
            let favoriteIDs = Set(((try? database.favorites()) ?? []).map(\.id))
            return applied.compactMap { record -> ImportedWallpaper? in
                guard favoriteIDs.contains(record.id),
                      FileManager.default.fileExists(atPath: record.localPath) else { return nil }
                return ImportedWallpaper(
                    id: record.id,
                    fileName: record.id,
                    filePath: record.localPath,
                    thumbnailPath: record.thumbnailURL?.path ?? record.localPath,
                    kind: .image,
                    width: record.width, height: record.height,
                    duration: nil, fileSize: 0, addedAt: record.appliedAt)
            }
        case .album:
            // 相册成员（Favorite）同样不带本地路径，与收藏同思路：只轮换其中「已设置历史里下过、
            // 本地文件仍在」的成员（约束 1/2：不联网、失效即剔除）。UI 标注清楚。
            guard let albumID = schedule.albumID,
                  let members = try? database.albumItems(albumId: albumID),
                  let applied = try? database.applied() else { return [] }
            let memberIDs = Set(members.map(\.id))
            return applied.compactMap { record -> ImportedWallpaper? in
                guard memberIDs.contains(record.id),
                      FileManager.default.fileExists(atPath: record.localPath) else { return nil }
                return ImportedWallpaper(
                    id: record.id,
                    fileName: record.id,
                    filePath: record.localPath,
                    thumbnailPath: record.thumbnailURL?.path ?? record.localPath,
                    kind: .image,
                    width: record.width, height: record.height,
                    duration: nil, fileSize: 0, addedAt: record.appliedAt)
            }
        }
    }

    private func apply(_ item: ImportedWallpaper, for schedule: inout WallpaperSchedule, at date: Date) {
        schedule.lastRunAt = date
        try? database?.updateSchedule(schedule)
        do {
            try engine?.setWallpaper(fileURL: URL(fileURLWithPath: item.filePath),
                                    for: WallpaperTarget.resolveScreen(displayID: schedule.targetDisplay),
                                    mode: WallpaperTarget.fillMode(),
                                    // ImportedWallpaper 不存主色，用中性回退。
                                    fillColor: WallpaperTarget.neutralFillColor())
        } catch {
            // 单张失败不该中断整轮轮换，也不该弹窗打断用户（后台任务）。
        }
    }

    // MARK: - App Nap

    private func suppressAppNap() {
        guard napAssertion == nil else { return }
        napAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.latencyCritical, .userInitiated],
            reason: "壁纸轮换需要按时触发")
    }
}
