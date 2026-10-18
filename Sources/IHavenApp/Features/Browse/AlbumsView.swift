import SwiftUI

/// 相册列表（侧栏「相册」视图）：新建 / 删除相册，点开查看某个相册的内容。
///
/// 内部自己管理「列表 ↔ 内容」二级切换，外部（`BrowseView.mainArea`）只渲染本视图即可。
/// 拆成独立文件是因为 `BrowseView` 已逼近 ADR-009 的 300 行上限，相册整块没有落脚之处。
struct AlbumsView: View {
    @Bindable var viewModel: BrowseViewModel
    var onDiscover: () -> Void
    var onOpen: (Favorite) -> Void
    var onMessage: (String) -> Void

    /// 当前打开查看内容的相册（nil = 停留在列表）。
    @State private var selected: Album?
    @State private var showCreate = false
    @State private var createName = ""
    @State private var pendingDelete: Album?

    var body: some View {
        if let album = selected {
            AlbumContentsView(album: album, viewModel: viewModel, onBack: { selected = nil },
                             onOpen: onOpen, onMessage: onMessage)
                .id(album.id)
        } else {
            list
        }
    }

    // MARK: - 列表

    private var list: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(IHaven.Color.border)
            if viewModel.albums.isEmpty {
                browseEmptyState(title: "还没有相册",
                                 body: "把任意壁纸加入相册，按主题整理你的收藏。",
                                 action: "新建相册") { showCreate = true }
            } else {
                ScrollView {
                    LazyVStack(spacing: IHaven.Space.s3.rawValue) {
                        ForEach(viewModel.albums) { album in
                            row(album)
                        }
                        .padding(IHaven.Space.s6.rawValue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IHaven.Color.bg)
        .alert("新建相册", isPresented: $showCreate) {
            TextField("相册名称", text: $createName)
            Button("取消", role: .cancel) { createName = "" }
            Button("创建") { create() }
        }
        .alert(item: $pendingDelete) { album in
            Alert(title: Text("确定删除这个相册？"),
                  message: Text(album.name),
                  primaryButton: .destructive(Text("删除")) { delete(album) },
                  secondaryButton: .cancel(Text("取消")))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("相册")
                .font(IHaven.Font.system(.xl, IHaven.Font.weightAnnounce))
                .foregroundStyle(IHaven.Color.fg)
            Spacer(minLength: 0)
            Button(action: { showCreate = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("新建相册")
                }
                .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.accentOn)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(IHaven.Color.accent, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, IHaven.Space.s6.rawValue)
        .frame(height: IHaven.Layout.detailHeaderHeight)
    }

    private func row(_ album: Album) -> some View {
        let count = viewModel.albumItems(albumId: album.id).count
        return Button {
            selected = album
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: IHaven.Icon.md))
                    .foregroundStyle(IHaven.Color.accent)
                    .frame(width: 32, height: 32)
                    .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
                        .foregroundStyle(IHaven.Color.fg)
                    Text("\(count) 张")
                        .font(IHaven.Font.system(.sm))
                        .foregroundStyle(IHaven.Color.muted)
                }
                Spacer(minLength: 0)
                Button {
                    pendingDelete = album
                } label: {
                    Image(systemName: "trash").font(.system(size: IHaven.Icon.sm))
                        .foregroundStyle(IHaven.Color.muted)
                }
                .buttonStyle(.plain)
                .help("删除相册")
            }
            .padding(.horizontal, IHaven.Space.s4.rawValue)
            .frame(height: 56)
            .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
            .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 行为

    private func create() {
        let name = createName.trimmingCharacters(in: .whitespaces)
        createName = ""
        guard !name.isEmpty else { return }
        let album = viewModel.createAlbum(name: name)
        selected = album
    }

    private func delete(_ album: Album) {
        viewModel.removeAlbum(id: album.id)
        if selected?.id == album.id { selected = nil }
    }
}
