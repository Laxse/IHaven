import Foundation

/// 让用户为下载结果选择落盘位置的能力（Core 层协议）。
///
/// 存在的理由：`ImageDownloading.download` 只保证产出一个**临时目录里的文件**
/// （系统可回收，且不是用户能找到的地方），不能把它当成「用户下载到的文件」。
/// 完整链路必须是：下载到临时目录 → 经本协议让用户选目标位置 → 由调用方移动过去。
///
/// 具体实现见 `Platform/System`（`NSSavePanel` 属 AppKit，不得出现在 Feature 层，ARCH §4）。
public protocol FileSavePresenting: Sendable {
    /// 弹出保存面板让用户选落盘位置。返回 `nil` 表示用户取消
    /// —— 调用方须静默结束（不报错）并清理已下载的临时文件。
    @MainActor func chooseSaveLocation(suggestedName: String) -> URL?
}
