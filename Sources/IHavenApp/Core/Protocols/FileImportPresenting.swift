import CoreGraphics
import Foundation

/// 选择要导入的本地文件（Core 层协议，实现在 `Platform/System`）。
///
/// 与 `FileSavePresenting` 同法：`NSOpenPanel` 属 AppKit，Feature 层只见协议（ARCH §4）。
public protocol FileImportPresenting: Sendable {
    /// 弹出多选面板，返回用户选中的 URL；取消返回空数组。
    @MainActor func chooseImportFiles() -> [URL]
}
