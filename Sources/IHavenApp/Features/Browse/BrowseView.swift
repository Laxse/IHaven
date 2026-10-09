import SwiftUI

/// 主窗口（瀑布流）骨架，对应已批准线框稿 main-window.svg。
struct BrowseView: View {
    @State var viewModel: BrowseViewModel
    var keyProvider: InMemoryKeyProvider
    @State private var showFilter = false
    @State private var showKeyConfig = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onFilter: { showFilter = true }, onSettings: { showKeyConfig = true })
            content
            FooterView(viewModel: viewModel)
        }
        .task { await viewModel.reload() }
        .sheet(isPresented: $showFilter) {
            FilterView(viewModel: viewModel) {
                showFilter = false
                Task { await viewModel.reload() }
            }
        }
        .sheet(isPresented: $showKeyConfig) {
            KeyConfigView(keyProvider: keyProvider) {
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
                        WallpaperCell(wallpaper: wp)
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
    var body: some View {
        HStack {
            if viewModel.resultsIncomplete {
                Label("结果不完整（未配置 Key）", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        AsyncImage(url: wallpaper.thumbs.small) { phase in
            switch phase {
            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
            case .failure: Color.gray
            default: ProgressView()
            }
        }
        .frame(width: 180, height: 120)
        .clipped()
        .cornerRadius(6)
    }
}
