import Foundation
import SwiftUI

/// 搜索 / 翻页 / 筛选变更（#70 后续修的两个真实缺陷）。
///
/// 拆成 extension 文件：`BrowseViewModel.swift` 顶到 ADR-009 的 300 行上限，
/// 而「翻页要有边界」这件事本身也需要一块独立的说明空间。extension 分文件后各文件单独计行数，
/// 与既有的 `BrowseViewModel+Albums.swift` / `+Favorites.swift` 同一套路。
// 存储属性（`hasMore` / `isLoadingMore` / `filterReloadTask` / `lastFilterKey`）留在主类里 ——
// Swift 的 extension 不允许放存储属性。这里只放方法。
extension BrowseViewModel {
    func reload() async {
        loadState = .loading
        resultsIncomplete = keyProvider.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            let page = try await client.search(query)
            wallpapers = page.data
            hasMore = !page.data.isEmpty && query.page < page.meta.lastPage
            refreshFavorites()
            isOffline = false
            loadState = .loaded
        } catch {
            isOffline = (error as? APIError)?.isOffline ?? false
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 详情页点标签 / 「更多类似」：用 `+tag` 表达式回到第 1 页重查（多词标签的空格必须原样保留）。
    func search(_ text: String) {
        query.q = text
        query.page = 1
        // 同步防抖基准：否则随后一次筛选变更会因为 filterKey 与基准不一致而多打一次请求。
        lastFilterKey = query.filterKey
        Task { await reload() }
    }

    func nextPage() async {
        // 三道门缺一不可：已加载 / 未在途 / **确实还有下一页**。
        // `hasMore` 这道门是「结果不足一页时底部转圈不停 + 反复空请求」的根因修复。
        guard case .loaded = loadState, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        query.page += 1
        do {
            let page = try await client.search(query)
            wallpapers.append(contentsOf: page.data)
            hasMore = !page.data.isEmpty && query.page < page.meta.lastPage
        } catch {
            query.page -= 1
            loadState = .failed(error.localizedDescription)
        }
        isLoadingMore = false
    }

    // MARK: - 筛选变更（DESIGN §4.3：150ms debounce 再请求）

    /// 筛选面板任一维度变更 → 150ms 防抖后回到第 1 页重查。
    /// 只有 `BrowseQuery.filterKey`（不含 page/seed）变化才算筛选变更，翻页不会触发重查。
    func scheduleFilterReload() {
        guard query.filterKey != lastFilterKey else { return }
        lastFilterKey = query.filterKey
        filterReloadTask?.cancel()
        filterReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.query.page = 1
            await self.reload()
        }
    }
}
