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
        // 设置就是主区的一个页签，与「导入…」「动态壁纸」同级：不再弹 sheet，
        // 也不重置页签（记住上次看的是哪一页）。
        case .settings: nav = item; return
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
    /// [!] **只改分类，不塞关键词**。早先 `.general` 会顺手把 `q` 写成 `"nature"`，两个问题：
    /// ① 搜索框里凭空冒出一个词，用户以为自己搜了它；② wallhaven 的分类本来就只有
    /// general / anime / people 三类，「综合」对应的就是 general，再叠一个英文关键词等于
    /// 把「非动漫非人物」窄化成「被打了 nature 标签的」，结果既不对也无从解释（用户实测反馈）。
    ///
    /// 想要具体题材应该用搜索框自己输入 —— 那才是用户主动表达，而不是我们替他猜。
    func applyCategory(_ item: NavItem) {
        switch item {
        case .discover: viewModel.query.categories = .all
        case .general: viewModel.query.categories = .general
        case .anime: viewModel.query.categories = .anime
        case .people: viewModel.query.categories = .people
        default: return
        }
        viewModel.query.q = ""
    }

    /// 详情页点标签 / 「更多类似」：这是一次**全局检索**，必须落到能渲染搜索结果的页签上。
    ///
    /// [!] **收藏 / 已设置 / 时间线 / 相册 是本地集合页签，本身没有搜索能力**。早先只调
    /// `viewModel.search(text)` 不动 `nav`：`viewModel.wallpapers` 确实查出来了，但
    /// `mainArea` 的 switch 仍走本地分支（渲染 `favorites` / `applied` / `albums`），
    /// 搜索结果**无处渲染** —— 表现是「点了标签，详情页关了，然后什么都没发生」，侧栏还
    /// 停在「收藏」，看上去像点了没反应（用户反馈，2026-10-20）。
    ///
    /// 这四个页签下统一跳「发现」（`applyCategory(.discover)` 顺带把分类放开成全部，
    /// 否则会带着上一次的分类约束去搜一个标签）；本来就在检索类页签（发现 / 综合 / 动漫 /
    /// 人物）则原地搜，保留用户当前的分类与筛选 —— 那是他显式选的，不该被一次点标签改掉。
    ///
    /// 不走 `select(.discover)`：那个方法内部自己会 `reload()` 一次（且此刻 `q` 还是旧值），
    /// 与随后的 `search(text)` 形成两个并发请求，谁后返回谁覆盖，结果不可预期。
    func searchFromDetail(_ text: String) {
        detail = nil
        detailSource = .wallpapers
        switch nav {
        case .favorites, .wallpaperSet, .timeline, .albums:
            nav = .discover
            applyCategory(.discover)
        default:
            break
        }
        // 内部 page=1 + reload，只发一次请求。
        viewModel.search(text)
    }

    func clearFilters() { viewModel.clearFilters(); Task { await reloadForNav() } }

    /// 跳到设置页签的指定页（筛选面板里点了被锁的 NSFW 档 → 直达「内容」）。
    ///
    /// 设置已不再是 sheet：这是**一次导航**，不是弹窗。仍需先收起筛选 popover（它会抢焦点），
    /// 并收起详情页 —— 详情页是盖在主区上的 overlay，不收就会变成「下面换了页、上面停在详情」。
    func openSettings(_ tab: SettingsTab) {
        showFilter = false
        settingsTab = tab
        detail = nil
        detailSource = .wallpapers
        nav = .settings
    }

    func reloadForNav() async {
        switch nav {
        case .favorites: viewModel.loadFavorites()
        case .wallpaperSet, .timeline: viewModel.loadApplied()
        case .albums: viewModel.loadAlbums()
        // 设置 / 动态壁纸 / 导入 都是本地页签，没有要重查的搜索结果。
        // [!] 设置曾落进 `default` 走了 `viewModel.reload()`：在里面保存一次 Key 就白打一次
        // wallhaven 搜索（45 次/分钟的共享配额），而用户此时根本不在看结果。
        case .live, .import, .settings: break
        default: await viewModel.reload()
        }
    }

    func setWallpaper(_ wp: Wallpaper) { Task { showToast((await viewModel.setAsWallpaper(wp)) ?? String(localized: "已设为壁纸")) } }
    func setWallpaperFromFavorite(_ fav: Favorite) { Task { showToast((await viewModel.setWallpaperFromFavorite(fav)) ?? String(localized: "已设为壁纸")) } }
}
