import Foundation
import Observation

/// 限流退避的广播点：`WallhavenClient`（Infrastructure）在退避等待前写入剩余秒数，
/// 视图（Feature）只读，`0` = 未在等待。
///
/// ⚠️ **为什么是一个共享状态盒，而不是回调**：写入方在 `WallhavenClient.perform` 的
/// 非 MainActor 上下文里，读取方是 SwiftUI；而客户端由 `IHavenApp.bootstrap()` 先装配、
/// 视图模型后创建 —— 回调根本没有可注入的时机。`@MainActor` + `@Observable` 让
/// SwiftUI 自动追踪，两端各只多一行。
///
/// 放在 Core 是为了守住 ARCH §4 的单向依赖：Feature 只见 Core 类型，
/// 不需要认识 `WallhavenClient`。
@MainActor
@Observable
final class ThrottleSignal {
    var waitingSeconds = 0
}
