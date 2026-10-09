import Foundation
import SwiftUI

/// 内存 Key 提供方（占位实现）。生产环境改用 Keychain（ARCH §6.4 / Platform Security），
/// 此处仅用于骨架演示 —— Key 绝不硬编码，由产品层在运行时注入。
///
/// `@unchecked Sendable`：仅持有一个值类型 `String` 属性，且引用本身在 client 中初始化后
/// 不再变更；读取 `currentKey` 得到的是 `String`（Sendable 值），跨隔离读取安全。
/// 生产 Keychain 实现将用 actor / @MainActor 隔离做更严格的同步。
@Observable
final class InMemoryKeyProvider: KeyProvider, @unchecked Sendable {
    var currentKey: String = ""
}
