import AppKit
import AVFoundation
import Foundation

/// 动态壁纸播放引擎（ADR-015 §五；ADR-003 双层结构中的动态层）。
///
/// 双层结构：
/// - **静态层**：`NSWorkspace.setDesktopImageURL` 写入首帧 poster —— 锁屏、切 Space、窗口异常时
///   用户看到的仍是这一帧，不会闪回上一张壁纸。
/// - **动态层**：每屏一个桌面层 borderless 窗口 + `AVQueuePlayer` + `AVPlayerLooper` 无缝循环。
///
/// ⚠️ 进程形态取 ADR-003 里被降级为备选的「同进程」方案，XPC 逐屏隔离延后 —— 理由与下一步
/// 见 ADR-015 §五。
@MainActor
final class DynamicWallpaperEngine: DynamicWallpaperPlaying {
    /// 内存压力回调：参数为是否 critical（critical 时已全部暂停并回落静帧）。
    var onMemoryPressure: ((Bool) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var playing: ImportedWallpaper?

    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    /// ⚠️ **必须强持有**：`AVPlayerLooper` 失去引用后循环会静默停止（ADR-003:96）。
    private var loopers: [AVPlayerLooper] = []
    /// 进入前的系统壁纸（按屏记），停止时恢复。
    private var savedWallpaper: [(screen: NSScreen, url: URL)] = []

    private var memorySource: DispatchSourceMemoryPressure?
    private var observations: [NSObjectProtocol] = []

    init() {
        observeSystemNotifications()
    }

    // MARK: - 播放控制

    func play(_ item: ImportedWallpaper) throws {
        guard FileManager.default.fileExists(atPath: item.filePath) else {
            throw DynamicWallpaperError.fileMissing
        }
        guard !NSScreen.screens.isEmpty else { throw DynamicWallpaperError.noScreen }

        // 先收掉上一段（含恢复系统壁纸），否则旧窗口叠在新窗口上。
        teardown()

        let poster = URL(fileURLWithPath: item.thumbnailPath)
        if FileManager.default.fileExists(atPath: poster.path) {
            for screen in NSScreen.screens {
                savedWallpaper.append((screen, NSWorkspace.shared.desktopImageURL(for: screen) ?? poster))
            }
            // ⚠️ 必须延后一整轮 run loop。`setDesktopImageURL` 是阻塞式 API，内部自旋 run loop
            // 等 Dock 应答；在 SwiftUI 的按钮动作那一轮里同步调用会重入，实测内存污染后
            // 在 autorelease pool drain 时 SIGSEGV。静态壁纸路径没这个问题，是因为它从
            // `Task { await … }` 里调，天然不在同一轮。
            let options = Self.posterOptions
            DispatchQueue.main.async {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(poster, for: screen, options: options)
                }
            }
        }

        // ⚠️ 窗口创建同样必须延后一整轮：在 SwiftUI 的动作/布局这一轮里同步建桌面层
        // borderless 窗口，会与正在进行的布局重入，实测（2026-10-15）无 AVPlayer 的裸窗口
        // 也崩。这是「点一下动态壁纸就卡死 / 消失」的真正根因。
        DispatchQueue.main.async { [weak self] in
            self?.installWindows(for: item)
            self?.players.forEach { $0.play() }
        }
        isPlaying = true
        isPaused = false
        playing = item
        notifyStateChange()
        observeMemoryPressure()
    }

    func stop() {
        teardown()
        // 恢复进入前的系统壁纸；没有记录到（例如 poster 缺失）时保持 poster 不动 ——
        // 那也比把桌面恢复成一张来路不明的图更可预期。
        //
        // ⚠️ 与 `play()` 同理：恢复写入也必须延后到当前这一轮 run loop 之外。
        // 实测（2026-10-15）同步调用会在 autorelease pool drain 时 use-after-free 崩溃
        // （堆栈落在 objc_release / NSAutoreleasePool drain）。详见 `play()` 里的说明。
        let pending = savedWallpaper
        let options = Self.posterOptions
        DispatchQueue.main.async {
            for entry in pending {
                try? NSWorkspace.shared.setDesktopImageURL(entry.url, for: entry.screen, options: options)
            }
        }
        savedWallpaper.removeAll()
        isPlaying = false
        isPaused = false
        playing = nil
        notifyStateChange()
        stopObservingMemoryPressure()
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        players.forEach { $0.pause() }
        isPaused = true
        notifyStateChange()
    }

    func resume() {
        guard isPlaying, isPaused else { return }
        players.forEach { $0.play() }
        isPaused = false
        notifyStateChange()
    }

    // MARK: - 内部

    /// 只拆窗口与播放器，不动静态层。屏幕拓扑变化时用它 + `installWindows` 重建，避免闪回上一张壁纸。
    /// 通知持有者镜像状态。处理器是非隔离闭包，回 MainActor 只能经 `Task { @MainActor in }`。
    private func notifyStateChange() {
        let handler = onStateChange
        Task { @MainActor in handler?() }
    }

    private func teardown() {
        players.forEach { $0.pause() }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        players.removeAll()
        loopers.removeAll()
    }

    private func installWindows(for item: ImportedWallpaper) {
        let url = URL(fileURLWithPath: item.filePath)
        for screen in NSScreen.screens {
            let player = AVQueuePlayer()
            player.isMuted = true                 // 壁纸无声，同时是隐私选择（ADR-003）
            player.actionAtItemEnd = .none
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill   // 各屏按自身比例独立裁切（差异化支点）
            let window = DesktopWallpaperWindow.make(for: screen, player: layer)
            window.orderFrontRegardless()
            windows.append(window)
            players.append(player)
            loopers.append(looper)
        }
    }

    /// 静帧层的填充方式与动态层保持一致：`resizeAspectFill` 裁切 = `allowClipping = true`。
    /// 两层用同一套裁切语义，用户不会看到「暂停时构图变了」。
    ///
    /// ⚠️ **两个值都必须是显式 `NSNumber`。** 实测（2026-10-15，复刻脚本对照三种写法）：
    /// Swift 的 `Bool` 与 `NSImageScaling` 枚举放进 `[Key: Any]` 会被装箱成 `__SwiftValue`，
    /// 字典跨到 Objective-C 时**不会**桥接成 `NSNumber`；AppKit 对这两个 key 都会发
    /// `integerValue`，于是 `-[__SwiftValue integerValue]: unrecognized selector` ——
    /// 未捕获的 ObjC 异常，进程直接终止（`do/catch` 抓不到）。
    /// 这就是「点动态壁纸就卡死 / 消失、删除也没反应」的根因：播放与恢复两条路都写这张字典。
    /// 静态引擎 `SystemWallpaperEngine.options` 用的是 NSNumber，所以它一直是好的。
    private static let posterOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
        .allowClipping: NSNumber(value: true),
    ]

    // MARK: - 系统通知（ADR-007 Trap 6：宿主是 NSApplication 不是 NSWorkspace）

    private func observeSystemNotifications() {
        let center = NotificationCenter.default
        // 处理器是非隔离闭包，回 MainActor 只能经 `Task { @MainActor in }`（Swift 6：不能直接调隔离成员）。
        observations = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            },
            // 屏幕拓扑变化（外接显示器热插拔、分辨率改变）：重建窗口以匹配新的屏幕集合。
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebuildForScreenChange() }
            },
            // 退出前必须收掉桌面层窗口。实测（2026-10-15）：不回收时 AppKit 在终止流程里拆这些
            // 窗口会 over-release，SIGSEGV 正好落在 `-[NSApplication run]` 的 autorelease pool
            // drain 上 —— 退出时崩，用户看到的是「闪退」。
            // `queue: nil` + `assumeIsolated`：该通知由 `terminate:` 在主线程同步投递，
            // 必须同步收窗口，`Task { @MainActor in }` 在终止流程里来不及跑。
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.teardownForTermination() }
            },
        ]
    }

    /// 退出时的最小回收：只拆窗口与播放器，不写系统壁纸（进程要没了，写了也不会被看见）。
    private func teardownForTermination() {
        players.forEach { $0.pause() }
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        players.removeAll()
        loopers.removeAll()
    }

    private func rebuildForScreenChange() {
        guard isPlaying, let item = playing else { return }
        let wasPaused = isPaused
        teardown()
        installWindows(for: item)
        if wasPaused { players.forEach { $0.pause() } } else { players.forEach { $0.play() } }
    }

    // MARK: - 内存压力（ADR-015 §五：warning 暂停、critical 全停并回落静帧）

    private func observeMemoryPressure() {
        guard memorySource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            // 在非隔离处理器里先把 dispatch 侧的数据取出来，再跳 MainActor 做引擎操作。
            let critical = source.data.contains(.critical)
            Task { @MainActor in
                guard let self else { return }
                self.pause()
                if critical {
                    // critical：连窗口一起收掉，只留静帧 —— 这一档的目标是把内存还给系统。
                    for window in self.windows { window.orderOut(nil); window.close() }
                    self.windows.removeAll()
                    self.players.removeAll()
                    self.loopers.removeAll()
                }
                self.onMemoryPressure?(critical)
            }
        }
        source.resume()
        memorySource = source
    }

    private func stopObservingMemoryPressure() {
        memorySource?.cancel()
        memorySource = nil
    }
}

enum DynamicWallpaperError: LocalizedError {
    case fileMissing
    case noScreen

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            String(localized: "视频文件已不存在，可能已被移出导入目录")
        case .noScreen:
            String(localized: "没有可用的屏幕来播放动态壁纸")
        }
    }
}
