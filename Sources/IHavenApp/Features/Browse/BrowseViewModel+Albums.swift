import Foundation

/// 相册（F-组织）：把收藏 / 任意壁纸按主题分组的本地组织层。
///
/// 单独成文件：`BrowseViewModel.swift` 已逼近 ADR-009 的 300 行上限，extension 分文件后
/// 各文件单独计行数 —— 这是不触门禁的唯一落点（与 `BrowseViewModel+Favorites.swift` 同路子）。
extension BrowseViewModel {
    /// 载入相册列表（侧栏「相册」视图用）。
    /// `albums` 的存储属性定义在主类 `BrowseViewModel.swift`，此处仅做加载入口。
    func loadAlbums() {
        albums = (try? database.albums()) ?? []
        loadState = .loaded
    }

    /// 新建相册（返回创建后的相册；id 由调用方生成，便于 UI 立即选中）。
    func createAlbum(name: String) -> Album {
        let album = Album(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                          createdAt: Date())
        try? database.addAlbum(album)
        loadAlbums()
        return album
    }

    /// 删除相册（连带删除其成员）。
    func removeAlbum(id: String) {
        try? database.removeAlbum(id: id)
        loadAlbums()
    }

    /// 取相册内的成员（按加入时间倒序），供相册内容视图渲染。
    func albumItems(albumId: String) -> [Favorite] {
        (try? database.albumItems(albumId: albumId)) ?? []
    }

    /// 把一张壁纸加入相册（成员自带缩略图 / 原图 URL，独立于收藏存在）。
    func addToAlbum(albumId: String, wallpaper: Wallpaper) {
        let item = Favorite(id: wallpaper.id,
                            thumbnailURL: wallpaper.aspectThumb,
                            originalURL: wallpaper.path,
                            addedAt: Date())
        try? database.addAlbumItem(albumId: albumId, item: item)
    }

    /// 从相册移除一张壁纸。
    func removeFromAlbum(albumId: String, wallpaperId: String) {
        try? database.removeAlbumItem(albumId: albumId, wallpaperId: wallpaperId)
    }

    /// 一张壁纸被哪些相册收录（详情页「加入相册」反查勾选态）。
    func albumIDsContaining(wallpaperId: String) -> Set<String> {
        Set((try? database.albumIDs(forWallpaper: wallpaperId)) ?? [])
    }

    /// 某相册内的壁纸 id 集合（用于相册内容视图的收藏态反查等）。
    func albumItemIDs(albumId: String) -> Set<String> {
        Set(albumItems(albumId: albumId).map(\.id))
    }
}
