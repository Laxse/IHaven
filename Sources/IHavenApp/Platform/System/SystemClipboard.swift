import AppKit

/// `NSPasteboard` 的 Platform 实现（ARCH §4：Feature 层只见 `ClipboardWriting` 协议）。
struct SystemClipboard: ClipboardWriting {
    @MainActor func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}
