import AppKit
import Foundation

/// 本地文件导入选择面板（`NSOpenPanel` 的 Platform 实现）。
///
/// Feature 层只见 `FileImportPresenting` 协议（ARCH §4，与 `FileSavePresenting` 同法）。
///
/// ⚠️ **故意不设 `allowedContentTypes`**：WEBM / MKV / GIF 必须能被选中，才能在导入时给出
/// 「不支持 + 具体原因 + 转换建议」（PRD §5.6 验收标准）。在这里过滤掉，用户就永远看不到
/// 那条引导，只会以为应用打不开这类文件。非媒体文件的拒绝同样由导入管线的探测负责。
struct SystemFileImportPanel: FileImportPresenting {
    @MainActor func chooseImportFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        // 文件夹也要能选：导入管线对文件夹递归扫描（PRD:695）。
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.title = String(localized: "选择要导入的图片或视频")
        panel.prompt = String(localized: "导入")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
