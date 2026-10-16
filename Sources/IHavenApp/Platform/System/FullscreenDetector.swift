import AppKit
import CoreGraphics

/// 前台应用是否占满整块屏（PRD F10 第一档）。
///
/// **为什么不用辅助功能权限**：读 `kAXFullScreenAttribute` 要先弹 `AXIsProcessTrustedWithOptions`
/// 授权。一个壁纸 App 为「检测全屏」去要辅助功能权限，代价远大于收益 —— 用户会怀疑它在读别的窗口。
/// 所以走 `CGWindowListCopyWindowInfo` 的几何判定：**实测窗口元数据不受 TCC 限制**
/// （17/17 个 on-screen 窗口都有 owner 与 bounds，而同一进程 `AXIsProcessTrusted() == false`）；
/// 受限制的是 `CGWindowListCreateImage` 取图，那才需要屏幕录制权限。
///
/// **判据为什么可靠（实测证伪过）**：普通窗口被 AppKit 夹在 `visibleFrame` 内
/// （本机 `screen.frame` 高 1080、`visibleFrame` 高 1050），实测 8 个普通窗口没有一个能等于
/// `screen.frame`；手动 `setFrame(screen.frame)` 也会被立刻夹成 1050 高。所以
/// 「layer == 0 且 bounds 覆盖整屏」只在原生全屏时成立。
///
/// **多屏坐标必须换算**：`kCGWindowBounds` 是 CG 全局坐标（原点主屏左上、y 向下），
/// `NSScreen.frame` 是 Cocoa 坐标（原点主屏左下、y 向上）。只对主屏二者数值巧合相同，
/// 副屏直接比会永远判不上 —— 这是本文件最容易写错又最不易发现的一处。
enum FullscreenDetector {
    /// 容差（pt）：全屏窗口仍有窗口装饰内缩，实测见过 38pt；但 `visibleFrame` 与 `frame`
    /// 的差是 30pt（1080−1050），8pt 容差在 1080 高屏上仍能把普通窗口排除掉。
    private static let tolerance: CGFloat = 8

    /// 前台应用是否占满某一块屏。**读不到 / 判不准一律返回 false** ——
    /// 误暂停比误播更惹恼用户（后者只是费一点电，前者是「我的壁纸怎么不动了」）。
    static func frontmostAppCoversScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        // 自己占满屏（比如全屏预览）不算：那时壁纸本来就被自己盖住，暂停没有意义。
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }

        for screen in NSScreen.screens {
            let target = cgRect(of: screen)
            let ownerPID = Int(front.processIdentifier)
            for window in list where (window[kCGWindowOwnerPID as String] as? Int) == ownerPID
                                  && (window[kCGWindowLayer as String] as? Int) == 0 {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                      let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double
                else { continue }
                if abs(x - target.minX) < tolerance, abs(y - target.minY) < tolerance,
                   width >= target.width - tolerance, height >= target.height - tolerance {
                    return true
                }
            }
        }
        return false
    }

    /// Cocoa 坐标 → CG 全局坐标。主屏高 `H` 是两套坐标系的桥梁。
    private static func cgRect(of screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens
            .first { $0.frame.origin == .zero }?.frame.height ?? screen.frame.height
        let frame = screen.frame
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY,
                      width: frame.width, height: frame.height)
    }
}
