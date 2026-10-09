import Foundation
import SwiftUI

/// 内存 Key 提供方（占位 / Preview / 测试实现）。生产环境改用 Keychain
/// （Infrastructure/Security/KeychainStore.swift，ARCH §6.4 / §3.3）。
/// Key 绝不硬编码，由产品层在运行时注入。
///
/// `@unchecked Sendable`：仅持有一个值类型 `String` 属性；读取 `currentKey` 得到 `String`
/// （Sendable 值），跨隔离读取安全。
@Observable
final class InMemoryKeyProvider: KeyStore, @unchecked Sendable {
    var currentKey: String = ""

    func save(_ key: String) throws { currentKey = key }
    func clear() throws { currentKey = "" }
}
