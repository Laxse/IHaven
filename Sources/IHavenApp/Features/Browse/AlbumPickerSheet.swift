import SwiftUI

/// 详情页「加入相册」的相册选择器（sheet）。列出全部相册并勾选当前壁纸已归属的，
/// 支持当场新建相册并直接加入。所有写库走 `BrowseViewModel` 的相册 extension。
///
/// sheet 本身挂在 `BrowseView` 上（子视图挂模态会被父级 `.sheet` 抑制，见 `BrowseView.swift`），
/// 本视图只负责呈现与把信号/结果用 `onMessage` 回传给 `BrowseView` 弹 toast。
struct AlbumPickerSheet: View {
    @Bindable var viewModel: BrowseViewModel
    let wallpaper: Wallpaper
    var onMessage: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// 当前壁纸归属的相册集合（用于勾选态）。
    @State private var containing: Set<String> = []
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(IHaven.Color.border)
            list
        }
        .frame(width: 360, height: 440)
        .task { reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("加入相册")
                .font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce))
                .foregroundStyle(IHaven.Color.fg)
            Spacer(minLength: 0)
            Button(action: { dismiss() }) { Text("完成") }
                .buttonStyle(.borderedProminent)
        }
        .padding(IHaven.Space.s5.rawValue)
    }

    @ViewBuilder
    private var list: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("新建相册…", text: $newName)
                        .textFieldStyle(.plain)
                    Button(action: createAndAdd) {
                        Text("添加")
                    }
                    .buttonStyle(.bordered)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                if viewModel.albums.isEmpty {
                    Text("还没有相册，先在上方创建一个。")
                        .font(IHaven.Font.system(.sm))
                        .foregroundStyle(IHaven.Color.muted)
                }
                ForEach(viewModel.albums) { album in
                    HStack(spacing: 10) {
                        Image(systemName: containing.contains(album.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(containing.contains(album.id) ? IHaven.Color.accent : IHaven.Color.fg2)
                        Text(album.name)
                            .font(IHaven.Font.system(.md))
                            .foregroundStyle(IHaven.Color.fg)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(album) }
                }
            }
        }
        .listStyle(.plain)
    }

    private func reload() {
        viewModel.loadAlbums()
        containing = viewModel.albumIDsContaining(wallpaperId: wallpaper.id)
    }

    private func toggle(_ album: Album) {
        if containing.contains(album.id) {
            viewModel.removeFromAlbum(albumId: album.id, wallpaperId: wallpaper.id)
            containing.remove(album.id)
            onMessage(String(localized: "已从相册移除"))
        } else {
            viewModel.addToAlbum(albumId: album.id, wallpaper: wallpaper)
            containing.insert(album.id)
            onMessage(String(localized: "已加入相册"))
        }
        viewModel.loadAlbums()
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let album = viewModel.createAlbum(name: name)
        viewModel.addToAlbum(albumId: album.id, wallpaper: wallpaper)
        newName = ""
        reload()
        onMessage(String(localized: "已加入相册"))
    }
}
