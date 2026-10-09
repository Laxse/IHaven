import Foundation

/// Key 来源（产品层注入，绝不硬编码）。详见 ARCH §6.4.0 第四条禁令：
/// 空 / 纯空白 Key 与「未配置」在服务端不可区分，故此处只暴露「当前 Key」，合法性由客户端 trim 后判定。
public protocol KeyProvider: Sendable {
    /// 当前 API Key（已 trim）。空串表示未配置。
    var currentKey: String { get }
}

/// wallhaven API 契约（Infrastructure 实现，Feature 只依赖此协议，不依赖具体类型）。
/// 所有实测固化的行为见 ADR-007（18 个 Trap）与 SPEC §9.2 / §9.8。
public protocol WallhavenAPIProtocol: Sendable {
    /// 搜索（带用户筛选的常规请求）。
    func search(_ query: BrowseQuery) async throws -> WallhavenPage
    /// NSFW 权限探测：固定宽 `purity=001`，不带任何用户筛选（SPEC §9.2）。
    func probeNSFWPermission() async -> NSFWProbeResult
    /// 当前 Key 状态（空 / 已配置）。
    var keyStatus: KeyStatus { get }
}

/// NSFW 探测结论（SPEC §9.2）。
public enum NSFWProbeResult {
    case authorized(total: Int)   // total>0：有权限
    case unauthorized            // total=0：权限不足
    case keyInvalid              // 401：Key 失效（Trap 16，唯一含义）
    case error(Error)
}

public enum KeyStatus {
    case absent                  // 未配置（空 / 纯空白）
    case configured              // 已配置（是否真有效需 probe 确认）
}
