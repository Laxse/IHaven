import Foundation
import Security

/// Keychain 实现的 KeyStore（ADR-002 / ARCH §3.3）。
/// - kSecClassGenericPassword；service=`com.ihaven.apikey`，account=`wallhaven`
/// - kSecAttrAccessibleWhenUnlocked：锁屏时不可读，避免后台任务拿明文 Key
/// - 绝不写日志、绝不进 UserDefaults / SQLite
///
/// `@unchecked Sendable`：`@Observable` 类的 registrar 非 Sendable，但本类只有值类型 / 常量存储，
/// 且 `currentKey` 为存储 String（Sendable），跨隔离读取安全。
@Observable
final class KeychainKeyProvider: KeyStore, @unchecked Sendable {
    var currentKey: String = ""
    private let service = "com.ihaven.apikey"
    private let account = "wallhaven"

    init() {
        currentKey = (try? Self.read(service: service, account: account)) ?? ""
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.write(trimmed, service: service, account: account)
        currentKey = trimmed
    }

    func clear() throws {
        try Self.delete(service: service, account: account)
        currentKey = ""
    }

    // MARK: - Keychain 原语

    private static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let existing = (try? read(service: service, account: account)) != nil
        if existing {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }
    }

    private static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

enum KeychainError: Error, CustomStringConvertible {
    case status(OSStatus)
    var description: String {
        switch self {
        case .status(let status): "KeychainError(status: \(status))"
        }
    }
}
