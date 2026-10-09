import Foundation

/// 可持久化 Key 的协议（Domain 层）。在只读 `KeyProvider` 之上扩展写入能力，
/// 供配置页（KeyConfigView）写入；具体实现见 Infrastructure/Security 的 Keychain 实现，
/// 或 App 内的 InMemory 实现（Preview / 测试）。
public protocol KeyStore: KeyProvider {
    /// 保存 Key（trim 后；空串视为清除未配置态）。
    func save(_ key: String) throws
    /// 清除已保存的 Key（恢复为未配置）。
    func clear() throws
}
