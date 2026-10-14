import AppKit

/// `NSSavePanel` 的 Platform 实现：Feature 层只见 `FileSavePresenting` 协议（ARCH §4 单向依赖）。
///
/// [!] 不设置 `directoryURL`：写死 `~/Pictures` 之类的路径会触发 TCC 授权弹窗，
///     交由系统记忆用户上次选择的目录即可。
struct SystemSavePanel: FileSavePresenting {
    @MainActor func chooseSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        // runModal 是同步模态：调用点已在主 actor，会阻塞到用户选完为止（无回调、无 run loop 重入）。
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
