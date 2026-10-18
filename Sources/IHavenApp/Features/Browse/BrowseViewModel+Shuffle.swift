import Foundation

/// 「换一张」的候选挑选。抽成扩展文件：`BrowseViewModel.swift` 已到 296 行（逼近 ADR-009 上限），
/// 再往里加几行就会破门禁；extension 分文件后各文件单独计行数。
extension BrowseViewModel {
    /// 「换一张」的候选：当前结果集优先，回退收藏。本地导入项由调用方补第三级
    /// （菜单栏面板与全局热键各自持有 `library`）。
    ///
    /// 面板与全局热键共用这一个方法，避免两处各写一遍优先级后悄然漂移
    /// （曾经只在面板里写过一次，热键接进来时很容易漏掉「收藏兜底」那一级）。
    func randomShuffleCandidate() -> Wallpaper? {
        if let wp = wallpapers.randomElement() { return wp }
        if let fav = favorites.randomElement() { return Wallpaper(previewFrom: fav) }
        return nil
    }
}
