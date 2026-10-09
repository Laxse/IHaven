import Foundation

/// 文件实现的 KeyStore（ADR-010）。
///
/// 取代 Keychain 作为 API Key 的持久化位置，动机见 ADR-010：开发期构建是 **ad-hoc 签名**，
/// 每次重建二进制身份（CDHash）都变，macOS 无法把钥匙串 ACL 的「始终允许」绑定到稳定身份上 ——
/// 于是每次启动都弹「IHavenApp 想要使用你储存在钥匙串的 com.ihaven.apikey…请输入登录钥匙串密码」。
///
/// 存储位置 `~/.ihaven/apikey`：
/// - 在**仓库之外** → 不会进 git，切断 2026-10-08 P0（Key 硬编码进公开仓库）的泄露路径
/// - 不走 URL query → 不会进代理日志 / HTTP Referer
/// - 权限：目录 `0700` / 文件 `0600`，仅当前用户可读写
///
/// 已接受的代价：明文落盘，同机任意以本用户运行的进程可读。危害面（见 OPEN-DECISIONS P0 记录）
/// 为「访问 NSFW、消耗 45 次/分钟配额、读取账号设置」，无资金与敏感 PII，故判定可接受。
///
/// `@unchecked Sendable`：`@Observable` 类的 registrar 非 Sendable，但本类只有值类型 / 常量存储，
/// 且 `currentKey` 为 String（Sendable），跨隔离读取安全。
@Observable
final class FileKeyProvider: KeyStore, @unchecked Sendable {
    var currentKey: String = ""

    private let fileURL: URL

    /// - Parameter fileURL: 注入自定义路径用于测试；缺省用 `defaultFileURL`。
    ///   注意：默认参数里不能写 `Self.xxx`（covariant 'Self' 限制），故用 `nil` 兜底。
    init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL
        self.fileURL = resolved
        currentKey = (try? Self.read(resolved)) ?? ""
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ihaven", isDirectory: true)
            .appendingPathComponent("apikey", isDirectory: false)
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // 协议约定：空串视为清除，恢复未配置态
        if trimmed.isEmpty {
            try Self.delete(fileURL)
            currentKey = ""
            return
        }
        try Self.write(trimmed, to: fileURL)
        currentKey = trimmed
    }

    func clear() throws {
        try Self.delete(fileURL)
        currentKey = ""
    }

    // MARK: - 文件原语

    private static func read(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let dirAttrs: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: dirAttrs)
        }
        // 目录已存在时同样收紧权限（防止旧目录权限过宽）
        try? fm.setAttributes(dirAttrs, ofItemAtPath: dir.path)
        try Data(value.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func delete(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }
}
