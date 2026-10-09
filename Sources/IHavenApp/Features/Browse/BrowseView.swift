import NukeUI
import SwiftUI

/// 主窗口（瀑布流）骨架，对应已批准线框稿 main-window.svg。
struct BrowseView: View {
    @State var viewModel: BrowseViewModel
    let keyStore: KeyStore
    @State private var showFilter = false
    @State private var showKeyConfig = false
    @State private var lastSetMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onFilter: { showFilter = true }, onSettings: { showKeyConfig = true })
            content
            FooterView(viewModel: viewModel, lastSetMessage: lastSetMessage)
        }
        .task { await viewModel.reload() }
        .sheet(isPresented: $showFilter) {
            FilterView(viewModel: viewModel) {
                showFilter = false
                Task { await viewModel.reload() }
            }
        }
        .sheet(isPresented: $showKeyConfig) {
            KeyConfigView(store: keyStore) {
                showKeyConfig = false
                Task { await viewModel.reload() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("加载中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 8) {
                    ForEach(viewModel.wallpapers) { wp in
                        WallpaperCell(
                            wallpaper: wp,
                            isFavorite: viewModel.favoriteIDs.contains(wp.id),
                            onToggleFavorite: { viewModel.toggleFavorite(wp) },
                            onSetWallpaper: {
                                Task {
                                    let err = await viewModel.setAsWallpaper(wp)
                                    lastSetMessage = err ?? "已设为壁纸"
                                }
                            }
                        )
                    }
                }
                .padding(8)
            }
        case .failed(let msg):
            ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle",
                                   description: Text(msg))
        }
    }
}

private struct HeaderView: View {
    var onFilter: () -> Void
    var onSettings: () -> Void
    var body: some View {
        HStack {
            Text("IHaven").font(.headline)
            Spacer()
            Button("筛选", systemImage: "line.3.horizontal.decrease.circle", action: onFilter)
            Button("设置", systemImage: "gearshape", action: onSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

private struct FooterView: View {
    var viewModel: BrowseViewModel
    var lastSetMessage: String?
    var body: some View {
        HStack {
            if viewModel.resultsIncomplete {
                Label("结果不完整（未配置 Key）", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let msg = lastSetMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("下一页") { Task { await viewModel.nextPage() } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

private struct WallpaperCell: View {
    let wallpaper: Wallpaper
    let isFavorite: Bool
    var onToggleFavorite: () -> Void
    var onSetWallpaper: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThumbnailImage(url: wallpaper.thumbs.small)
                .frame(width: 180, height: 120)
                .clipped()
                .cornerRadius(6)
            HStack(spacing: 4) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }
                .foregroundStyle(isFavorite ? .pink : .white)
                Button(action: onSetWallpaper) {
                    Image(systemName: "desktopcomputer")
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
        }
    }
}

/// 缩略图视图：封装 NukeUI.LazyImage，将 Nuke 类型隔离在 Infrastructure 渲染边界之外。
private struct ThumbnailImage: View {
    let url: URL?
    var body: some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    Color.gray
                } else {
                    ProgressView()
                }
            }
        } else {
            Color.gray
        }
    }
}
