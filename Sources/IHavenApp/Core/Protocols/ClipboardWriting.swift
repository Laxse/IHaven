import Foundation

/// 写入系统剪贴板的能力（Core 层协议）。
///
/// SwiftUI 至今没有「写入剪贴板」的 API，`NSPasteboard` 属 AppKit，
/// 故与 `FileSavePresenting` 同法：协议留在 Core，实现落在 `Platform/System`（ARCH §4）。
public protocol ClipboardWriting: Sendable {
    /// 拷贝一段文本到系统剪贴板（会先清空剪贴板再写入）。
    @MainActor func copy(_ text: String)
}
