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
                try? NSWorkspace.shared.setDesktopImageURL(poster, for: screen, options: Self.posterOptions)
            }
        }

        installWindows(for: item)
        players.forEach { $0.play() }
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
        for entry in savedWallpaper {
            try? NSWorkspace.shared.setDesktopImageURL(entry.url, for: entry.screen, options: Self.posterOptions)
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
    private static let posterOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown,
        .allowClipping: true,
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
        ]
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
