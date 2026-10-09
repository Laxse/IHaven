import Foundation
import SwiftUI

/// 浏览（瀑布流）视图模型。仅依赖 WallhavenAPIProtocol（不依赖具体客户端）。
@MainActor
@Observable
final class BrowseViewModel {
    enum LoadState: Sendable {
        case idle, loading, loaded, failed(String)
    }

    var loadState: LoadState = .idle
    var wallpapers: [Wallpaper] = []
    var query = BrowseQuery()
    /// Trap 18：未配置 Key 时结果为静默缩水，产品层提示，技术层不尝试探测缩水。
    var resultsIncomplete: Bool = false

    private let client: WallhavenAPIProtocol
    private let keyProvider: KeyProvider

    init(client: WallhavenAPIProtocol, keyProvider: KeyProvider) {
        self.client = client
        self.keyProvider = keyProvider
    }

    func reload() async {
        loadState = .loading
        resultsIncomplete = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            let page = try await client.search(query)
            wallpapers = page.data
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func nextPage() async {
        guard case .loaded = loadState else { return }
        query.page += 1
        do {
            let page = try await client.search(query)
            wallpapers.append(contentsOf: page.data)
        } catch {
            query.page -= 1
            loadState = .failed(error.localizedDescription)
        }
    }
}
