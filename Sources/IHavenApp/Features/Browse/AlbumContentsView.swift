import SwiftUI

/// 单个相册的内容视图：瀑布流展示成员，支持「设为壁纸」与「从相册移除」。
///
/// 复用 `FavoriteCard`（成员本就是 `Favorite`）；卡上的星标动作在此语境下意为「从相册移除」，
/// 与收藏页的取消收藏区分（相册是独立的组织层，见 `Album.swift` 说明）。
///
/// 拆成独立文件：`AlbumsView` 已把列表 + 新建 + 删除写完，内容视图再塞进去会破 ADR-009 的 300 行。
struct AlbumContentsView: View {
    let album: Album
    @Bindable var viewModel: BrowseViewModel
    var onBack: () -> Void
    /// 带上 `Album`：详情页的 `←` `→` 要在这个相册的成员里翻，光给 `Favorite` 反查不到范围。
    var onOpen: (Album, Favorite) -> Void
    var onMessage: (String) -> Void
    @State private var items: [Favorite] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(IHaven.Color.border)
            if items.isEmpty {
                browseEmptyState(title: "这个相册还是空的",
                                 body: "去发现壁纸或收藏里，点开任意壁纸选「加入相册」即可。",
                                 action: "返回") { onBack() }
            } else {
                ScrollView {
                    MasonryView(items: items,
                                spacing: IHaven.Layout.masonryGap,
                                minColumnWidth: IHaven.Layout.masonryColMin,
                                aspectRatio: { _ in 1.6 }) { fav in
                        FavoriteCard(favorite: fav,
                                     onOpen: { onOpen(album, fav) },
                                     onToggleFavorite: { remove(fav) },
                                     onSetWallpaper: { setFromFavorite(fav) })
                    }
                    .padding(IHaven.Space.s6.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
        .task { reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrowseIconButton(systemName: "chevron.left", help: "返回") { onBack() }
            Text(album.name)
                .font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce))
                .foregroundStyle(IHaven.Color.fg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IHaven.Space.s6.rawValue)
        .frame(height: IHaven.Layout.detailHeaderHeight)
    }

    private func reload() {
        items = viewModel.albumItems(albumId: album.id)
    }

    private func remove(_ fav: Favorite) {
        viewModel.removeFromAlbum(albumId: album.id, wallpaperId: fav.id)
        reload()
        onMessage(String(localized: "已从相册移除"))
    }

    private func setFromFavorite(_ fav: Favorite) {
        Task { onMessage((await viewModel.setWallpaperFromFavorite(fav)) ?? String(localized: "已设为壁纸")) }
    }
}
