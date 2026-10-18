import Foundation

/// AI 图生视频的 Key 存储（#70）。
///
/// 与 wallhaven Key 同机制（ADR-010 文件存储，`~/.ihaven/` 下、`0600`、不进 git / 日志），
/// 但**独立文件 `~/.ihaven/ai-key`** —— 不同服务商的 Key 不混存，清除其一不影响另一个。
///
/// ⚠️ **必须是 `shared` 单例**：设置面板（写）与生成客户端（读）要持有**同一实例**。
/// `FileKeyProvider` 把 Key 缓存在内存 `currentKey` 里，若两边各 `init` 一个，设置里刚保存的
/// Key 不会同步到客户端那个实例的内存缓存 → 表现为「存了 Key 还是说没配」。
enum AIKeyStore {
    static let shared: FileKeyProvider = FileKeyProvider(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ihaven", isDirectory: true)
            .appendingPathComponent("ai-key", isDirectory: false)
    )
}
