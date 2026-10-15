import AppKit
import Foundation

/// 动态壁纸播放引擎（ADR-016 改版）：**帧序列轮播**。
///
/// 与旧版（AVPlayer + AVPlayerLooper 播 MP4）的区别：输入不再是视频文件，而是
/// 「由静态图本地生成的帧目录」。播放侧因此不需要解码器与播放器生命周期 ——
/// 每帧只是把 JPEG 赋给 `NSImageView.image`，零合成、零解码队列。
///
/// 双层结构保留 ADR-015 的形态：
/// - **静态层**：`NSWorkspace.setDesktopImageURL` 写首帧 —— 锁屏 / 切 Space / 窗口异常时
///   用户看到的仍是这一帧，不会闪回上一张壁纸。
/// - **动态层**：每屏一个桌面层 borderless 窗口 + `NSImageView`，由 Timer 逐帧替换。
///
/// ⚠️ **两条实测出来的硬约束（2026-10-15，缺一即崩）**：
/// 1. options 字典里的值必须是显式 `NSNumber`。Swift 的 `Bool` / `NSImageScaling` 枚举装进
///    `[Key: Any]` 会变成 `__SwiftValue`，跨到 Objective-C 不桥接，AppKit 一发 `integerValue`
///    就是未捕获异常、进程直接终止。
/// 2. **建窗口必须延后一整轮 run loop**。在 SwiftUI 按钮动作那一轮里同步建桌面层窗口会与
///    正在进行的布局重入，内存污染后在 autorelease pool drain 时 SIGSEGV ——
///    这正是「点一下动态壁纸就卡死 / 消失」的根因。
@MainActor
final class DynamicWallpaperEngine: DynamicWallpaperPlaying {
    var onMemoryPressure: ((Bool) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var playing: ImportedWallpaper?

    private var windows: [NSWindow] = []
    private var imageViews: [NSImageView] = []
    private var frames: [URL] = []
    private var frameIndex = 0
    private var timer: Timer?
    private var memorySource: DispatchSourceMemoryPressure?
    /// 进入前的系统壁纸（按屏记），停止时恢复。
    private var savedWallpaper: [(screen: NSScreen, url: URL)] = []
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

        let frameURLs = Self.frameURLs(in: item.filePath)
        guard !frameURLs.isEmpty else { throw DynamicWallpaperError.noFrames }

        teardown()
        frames = frameURLs
        frameIndex = 0

        // 静态层：首帧兜底。
        let poster = URL(fileURLWithPath: item.thumbnailPath)
        if FileManager.default.fileExists(atPath: poster.path) {
            for screen in NSScreen.screens {
                savedWallpaper.append((screen, NSWorkspace.shared.desktopImageURL(for: screen) ?? poster))
            }
            let options = Self.posterOptions
            DispatchQueue.main.async {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(poster, for: screen, options: options)
                }
            }
        }

        // ⚠️ 见文件头约束 2：窗口创建必须延后一整轮。
        let interval = Self.frameInterval(seconds: item.duration ?? 12, count: frames.count)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.installWindows()
            self.startTimer(interval: interval)
        }
        isPlaying = true
        isPaused = false
        playing = item
        notifyStateChange()
        observeMemoryPressure()
    }

    func stop() {
        teardown()
        // 恢复进入前的系统壁纸；没有记录到时保持首帧不动。
        let pending = savedWallpaper
        let options = Self.posterOptions
        DispatchQueue.main.async {
            for entry in pending {
                try? NSWorkspace.shared.setDesktopImageURL(entry.url, for: entry.screen, options: options)
            }
        }
        savedWallpaper.removeAll()
        frames = []
        frameIndex = 0
        isPlaying = false
        isPaused = false
        playing = nil
        notifyStateChange()
        stopObservingMemoryPressure()
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        timer?.invalidate()
        timer = nil
        isPaused = true
        notifyStateChange()
    }

    func resume() {
        guard isPlaying, isPaused else { return }
        startTimer(interval: Self.frameInterval(seconds: playing?.duration ?? 12, count: frames.count))
        isPaused = false
        notifyStateChange()
    }

    // MARK: - 内部

    private func installWindows() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.sharingType = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            // ⚠️ ARC 下必须关掉这个（缺了它「停止 / 暂停切换」会闪退）：
            // `NSWindow` 的 `isReleasedWhenClosed` 默认为 `true`，`close()` 会**再 release 一次**，
            // 与 ARC 既有的强引用叠加 → 过度释放。实测停止动态壁纸时窗口在 autorelease pool
            // drain 阶段收到 release 崩溃（Zombie 报 `-[NSWindow release]: message sent to
            // deallocated instance`；崩溃栈落在 objc_autoreleasePoolPop → objc_release）。
            window.isReleasedWhenClosed = false

            let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            // 帧是按屏幕比例裁的（生成时取了主屏比例），等比拉伸铺满屏幕、不变形——
            // 与旧版 `AVPlayerLayer.videoGravity = .resizeAspectFill` 同一套裁切语义。
            view.imageScaling = .scaleAxesIndependently
            view.animates = false     // 关掉 NSImageView 自带的交叉淡入，避免和轮播叠加
            window.contentView = view
            window.orderFrontRegardless()

            windows.append(window)
            imageViews.append(view)
        }
        showFrame(at: frameIndex)
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        // 加到 common modes：滚动 / 拖拽时 Timer 不被暂停，壁纸不会突然冻住。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        showFrame(at: frameIndex)
    }

    private func showFrame(at index: Int) {
        guard frames.indices.contains(index) else { return }
        // 逐帧从盘上读：144 帧全预载要 1GB+ 位图，绝不这么干。旧 image 在赋值时即释放。
        let image = NSImage(contentsOf: frames[index])
        for view in imageViews { view.image = image }
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        imageViews.removeAll()
    }

    /// 帧间隔（秒）。按 duration / frameCount 反推，夹在 1/30 ~ 1/6 秒之间。
    static func frameInterval(seconds: Double, count: Int) -> TimeInterval {
        guard count > 0 else { return 1.0 / 12 }
        return min(max(seconds / Double(count), 1.0 / 30), 1.0 / 6)
    }

    /// 帧目录内的文件按文件名排序（`frame-%04d.jpg` 补零，字典序即时间序）。
    static func frameURLs(in dir: String) -> [URL] {
        let url = URL(fileURLWithPath: dir)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 系统通知（ADR-007 Trap 6：宿主是 NSApplication 不是 NSWorkspace）

    private func observeSystemNotifications() {
        let center = NotificationCenter.default
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
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebuildForScreenChange() }
            },
            // 退出前必须收掉桌面层窗口，否则 AppKit 终止流程里拆窗口会 over-release（实测闪退）。
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.teardownForTermination() }
            },
        ]
    }

    private func rebuildForScreenChange() {
        guard isPlaying else { return }
        let wasPaused = isPaused
        teardown()
        installWindows()
        if !wasPaused {
            startTimer(interval: Self.frameInterval(seconds: playing?.duration ?? 12, count: frames.count))
        }
    }

    private func teardownForTermination() {
        timer?.invalidate()
        timer = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        imageViews.removeAll()
    }

    // MARK: - 内存压力

    private func observeMemoryPressure() {
        memorySource?.cancel()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let critical = source.data.contains(.critical)
            Task { @MainActor in
                guard let self else { return }
                self.pause()
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

    private func notifyStateChange() {
        let handler = onStateChange
        Task { @MainActor in handler?() }
    }

    /// 见文件头约束 1：两个值都必须是显式 `NSNumber`。
    private static let posterOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
        .allowClipping: NSNumber(value: true),
    ]
}

enum DynamicWallpaperError: LocalizedError {
    case fileMissing
    case noScreen
    case noFrames

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            String(localized: "动态壁纸的帧文件已不存在，可能已被移出导入目录")
        case .noScreen:
            String(localized: "没有可用的屏幕来播放动态壁纸")
        case .noFrames:
            String(localized: "帧目录是空的，无法播放")
        }
    }
}
