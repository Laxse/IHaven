import SwiftUI

/// 侧栏导航 / 搜索提交 / 设为壁纸的行为（#70 后续修的两个真实缺陷）。
///
/// 拆成 extension 文件：`BrowseView.swift` 顶到 ADR-009 的 300 行上限。Swift 的 extension
/// 不允许放存储属性，所以 `@State` 全部留在主类，这里只放方法 —— 与既有的
/// `BrowseView+Crop.swift` 同一套路。
extension BrowseView {
    // MARK: - 行为

    func select(_ item: NavItem) {
        // [!] **切分类必须先收起详情页**：详情页是盖在 `mainArea` 上的 overlay（见 `mainArea`
        // 的注释），不是 if/else 二选一。只改 `nav` 的话底层换了、overlay 还在 ——
        // 表现就是「点了左边分类，界面没变，还停在详情页」（用户实测，2026-10-19）。
        // 所有导航分支都要走，包括 return 的那些（收藏 / 已设置 / 相册里也能进详情）。
        detail = nil
        detailSource = .wallpapers
        switch item {
        case .settings: openSettings(.apiKey); return
        // 「已设置」读本地记录，不发网络请求；落入 default 会走 reload 白打一次搜索。
        case .favorites: nav = .favorites; viewModel.loadFavorites(); return
        case .wallpaperSet, .timeline: nav = item; viewModel.loadApplied(); return
        case .albums: nav = item; viewModel.loadAlbums(); return
        case .live, .import: nav = item; return
        default: break
        }
        nav = item
        applyCategory(item)
        // 换分类是**新的一次搜索**：page 必须回到 1。留着旧页码会以「第 5 页」去查新分类，
        // 结果要么为空要么对不上。
        viewModel.query.page = 1
        Task { await viewModel.reload() }
    }

    /// 侧栏分类 → `categories` 维度。
    ///
    /// [!] **只改分类，不塞关键词**。早先 `.landscape` 会顺手把 `q` 写成 `"nature"`，两个问题：
    /// ① 搜索框里凭空冒出一个词，用户以为自己搜了它；② wallhaven 的分类本来就只有
    /// general / anime / people 三类，「风景」对应的就是 general，再叠一个英文关键词等于
    /// 把「非动漫非人物」窄化成「被打了 nature 标签的」，结果既不对也无从解释（用户实测反馈）。
    ///
    /// 想要具体题材应该用搜索框自己输入 —— 那才是用户主动表达，而不是我们替他猜。
    func applyCategory(_ item: NavItem) {
        switch item {
        case .discover: viewModel.query.categories = .all
        case .landscape: viewModel.query.categories = .general
        case .anime: viewModel.query.categories = .anime
        case .people: viewModel.query.categories = .people
        default: return
        }
        viewModel.query.q = ""
    }

    func clearFilters() { viewModel.clearFilters(); Task { await reloadForNav() } }

    /// 打开设置面板并落在指定页签；须先收起筛选 popover（它会盖住 sheet，并存还会抢焦点）。
    func openSettings(_ tab: SettingsTab) {
        showFilter = false
        settingsTab = tab
        showSettings = true
    }

    func reloadForNav() async {
        switch nav {
        case .favorites: viewModel.loadFavorites()
        case .wallpaperSet, .timeline: viewModel.loadApplied()
        case .albums: viewModel.loadAlbums()
        case .live, .import: break
        default: await viewModel.reload()
        }
    }

    func setWallpaper(_ wp: Wallpaper) { Task { showToast((await viewModel.setAsWallpaper(wp)) ?? String(localized: "已设为壁纸")) } }
    func setWallpaperFromFavorite(_ fav: Favorite) { Task { showToast((await viewModel.setWallpaperFromFavorite(fav)) ?? String(localized: "已设为壁纸")) } }
}
