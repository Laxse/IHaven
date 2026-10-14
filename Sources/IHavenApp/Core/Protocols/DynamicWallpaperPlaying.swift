import Foundation

/// 动态壁纸播放能力（Core 层协议，实现在 `Platform/Wallpaper/DynamicWallpaperEngine`）。
///
/// 与 `WallpaperEngine`（静态，`NSWorkspace.setDesktopImageURL`）分开而不是合并：
/// 两者的生命周期完全不同 —— 静态是一次性写入后即结束，动态是**长期持有窗口与播放器**，
/// 需要显式停止；且动态的输入是本地视频、输出是每屏一个窗口。合成一个协议会让
/// 「设置静态壁纸」的实现被迫持有播放器状态。
@MainActor
public protocol DynamicWallpaperPlaying: AnyObject {
    /// 当前是否正在播放动态壁纸。
    var isPlaying: Bool { get }
    /// 播放中但被暂停（锁屏 / 休眠 / 内存压力）。
    var isPaused: Bool { get }
    /// 正在播放的项（nil 表示未播放）。
    var playing: ImportedWallpaper? { get }
    /// 内存压力回调：参数为是否 critical（critical 时窗口已全部销毁，只剩静帧）。
    var onMemoryPressure: ((Bool) -> Void)? { get set }
    /// 播放态变化回调（播放 / 暂停 / 恢复 / 停止都由它通知）。
    /// 引擎不是 `@Observable`，SwiftUI 无法直接观察它 —— 由持有者把状态镜像到自己的可观察属性上。
    var onStateChange: (() -> Void)? { get set }

    /// 开始播放：先写静态层（首帧 poster，静帧兜底），再在每屏建桌面层窗口循环播放。
    func play(_ item: ImportedWallpaper) throws
    /// 停止播放：销毁全部窗口，恢复进入前的系统壁纸。
    func stop()
    /// 暂停 / 恢复播放（窗口保留，用于锁屏、休眠、内存压力）。
    func pause()
    func resume()
}
