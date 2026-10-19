import Foundation

/// AI 图生视频的 Key 存储（#70 多厂商直连）：**每家厂商一个独立文件**。
///
/// 路径 `~/.ihaven/ai-key-<vendorID>`（如 `ai-key-google`、`ai-key-kling`）。与 wallhaven 的 Key
/// 同机制（ADR-010 文件存储，理由照抄 `Infrastructure/Security/FileKeyStore.swift` 文件头）：
/// - 在**仓库之外** → 不会进 git，切断 Key 被硬编码进公开仓库的泄露路径
/// - 不走 URL query → 不会进代理日志 / HTTP Referer
/// - 权限：目录 `0700` / 文件 `0600`，仅当前用户可读写
///
/// 已接受的代价：明文落盘，同机任意以本用户运行的进程可读。危害面为「消耗该厂商的额度」，
/// 无资金账户与敏感 PII，故判定可接受。
///
/// 六家的 Key **互不通用**（各自官网发放、各自计费），所以必须分开存：混存会让「清掉 A 厂的 Key」
/// 变成「B 厂也不能用了」，而且换厂商时无法判断新厂商到底配没配。
final class AIVendorKeyVault: AIVendorKeyProviding, @unchecked Sendable {
    /// vendorID → 该厂商的 Key 提供方。
    ///
    /// **init 时一次性建好、之后只读**（字典本身也是 `let`，没有任何插入 / 替换条目的路径），
    /// 这是本类敢标 `@unchecked Sendable` 的理由 —— 元素 `FileKeyProvider` 自身已是
    /// `@unchecked Sendable`（只有值类型存储 + 常量路径），容器又不可变，跨隔离读取安全。
    private let providers: [String: FileKeyProvider]

    init(vendorIDs: [String]) {
        var map: [String: FileKeyProvider] = [:]
        for id in vendorIDs {
            map[id] = FileKeyProvider(fileURL: Self.fileURL(forVendor: id))
        }
        providers = map
    }

    static func fileURL(forVendor vendorID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ihaven", isDirectory: true)
            .appendingPathComponent("ai-key-\(vendorID)", isDirectory: false)
    }

    func keyProvider(for vendorID: String) -> KeyProvider {
        // 未知 id（厂商已下线 / 手改过偏好）返回一份**空的内存实现**：不崩，也不会被误判成
        // 「已配置」。这里每次 new 一个新实例是故意的 —— 兜底分支没有「设置里写、客户端读」
        // 的同步需求，缓存一个空壳反而会让下一次查询拿到永不更新的值。
        guard let provider = providers[vendorID] else { return InMemoryKeyProvider() }
        return provider
    }

    /// 设置面板的写入入口：返回的是 `keyProvider(for:)` 那个**同一个实例** —— 存完即刻能被
    /// 生成客户端读到（`FileKeyProvider` 把 Key 缓存在内存 `currentKey` 里，两个实例不同步）。
    /// 未知 vendorID 返回 nil，UI 侧按「未配置」处理。
    func keyStore(for vendorID: String) -> KeyStore? { providers[vendorID] }
}

/// 全 App 唯一的 AI Key 仓库。
///
/// **必须是 `shared` 单例**：设置面板（写）与生成客户端（读）要持有同一实例，理由见
/// `AIVendorKeyProviding` 的注释。
///
/// 旧的 `~/.ihaven/ai-key`（Replicate 的 Key）**不迁移、不删除**：那是已废弃聚合层的 Key，
/// 与新的六家厂商没有任何对应关系，自动搬运只会制造误会；用户可自行清理该文件。
enum AIKeyStore {
    static let shared = AIVendorKeyVault(vendorIDs: AIVideoVendorCatalog.all.map(\.id))
}
