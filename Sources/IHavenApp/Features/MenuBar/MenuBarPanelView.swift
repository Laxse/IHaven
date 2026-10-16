import SwiftUI

/// 菜单栏面板（PRD F3）：搜索 / 上一张 / 下一张 / 换一张 / 收藏夹入口 + 当前壁纸 + 打开主窗口。
///
/// ⚠️ 三条必须守住的约束（每条都对应一个真实失效模式）：
/// 1. **状态不自建**。`viewModel` / `library` 就是主窗口那两个实例，由 `IHavenApp` 注入。
///    菜单栏面板与主窗口是两个 SwiftUI scene（ADR-004 关键约束：单一 `@Observable`、不用通知
///    广播）—— 这里 new 一个就变成两套状态，「下一张」在主窗口里看不见。
/// 2. **必须由 `IHavenApp` 用 `.menuBarExtraStyle(.window)` 挂**：PRD F3 要搜索框，`.menu`
///    样式渲染的是 NSMenuItem 宿主，`TextField` 落不了焦。
/// 3. **自己挂 `.appLocale()` 与 `preferredColorScheme`**：被呈现的子树不跟随根视图的环境更新，
///    理由见 `Core/Theme/View+Locale.swift:15-20`。
@MainActor
struct MenuBarPanelView: View {
    /// 主窗口 ID。`IHavenApp` 的 `WindowGroup` 与这里同源：漂移的后果是「打开主窗口」
    /// 静默失效（id 对不上时 `openWindow` 什么都不做，且不报错）。
    static let mainWindowID = "main"

    /// 主窗口的浏览状态。`bootstrap()` 完成前是 nil（`IHavenApp` 的 `@State`），故有 nil 分支。
    let viewModel: BrowseViewModel?
    /// 本地库（导入的静态图），「换一张」的第三级候选源。
    let library: LocalLibraryViewModel?

    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserPreferenceKey.appearance) private var appearance: String = "system"
    @State private var queryText = ""
    /// 「上一张 / 下一张」在 `viewModel.wallpapers` 内的游标。结果集换了会被夹回范围内。
    @State private var cursor = 0
    /// 内联状态行。**面板看不到主窗口的 toast**（两个独立 scene，toast 挂在主窗口 overlay 上），
    /// 设壁纸的结果必须自己显示出来，否则点「下一张」没有任何反馈。
    @State private var status: String?
    @State private var isBusy = false

    /// 面板宽度。PRD F3 未给菜单栏线稿，取能容下 4 张收藏缩略图 + 搜索框的最小可读宽度。
    private static let width: CGFloat = 300
    /// 收藏一次显示几条：面板是高频快捷入口，不是收藏管理器，多了要滚动。
    private static let favoriteLimit = 4
    /// 搜索框与操作按钮共用的外形（design token `Radius.sm`）。
    private static let fieldShape = RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let viewModel {
                panelContent(viewModel)
            } else {
                initializing
            }
        }
        .frame(width: Self.width)
        .background(IHaven.Color.bg)
        .preferredColorScheme(colorScheme)
        // 同 `.sheet` / `.popover`：这棵子树自己挂一次语言，不依赖环境从外向内传。
        .appLocale()
    }

    // MARK: - 未装配

    private var initializing: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            ProgressView().controlSize(.small)
            Text("初始化…").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
        }
        .padding(IHaven.Space.s6.rawValue)
    }

    // MARK: - 主体

    private func panelContent(_ vm: BrowseViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            currentWallpaper(vm)
            searchField(vm)
            actions(vm)
            statusLine
            favorites(vm)
            Rectangle().fill(IHaven.Color.border).frame(height: 1)
            footer
        }
        // 面板每次展开都刷新：`favorites` / `applied` 是惰性数组，不拉就是空的。
        .task { refresh(vm) }
    }

    /// 当前壁纸（最近一条「已设置」记录）。没有历史就整块省略，不留空位。
    @ViewBuilder
    private func currentWallpaper(_ vm: BrowseViewModel) -> some View {
        if let item = vm.applied.first {
            HStack(spacing: IHaven.Space.s4.rawValue) {
                thumb(item.thumbnailURL, width: 56, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("当前壁纸").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                    Text(item.resolutionText ?? item.id)
                        .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                        .foregroundStyle(IHaven.Color.fg)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, IHaven.Space.s5.rawValue)
            .padding(.vertical, IHaven.Space.s4.rawValue)
        }
    }

    private func searchField(_ vm: BrowseViewModel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(IHaven.Color.meta)
            TextField("搜索壁纸、标签、上传者", text: $queryText)
                .textFieldStyle(.plain)
                .onSubmit { submit(vm) }
        }
        .padding(.horizontal, IHaven.Space.s4.rawValue)
        .frame(height: 28)
        .background(IHaven.Color.surface, in: Self.fieldShape)
        .overlay(Self.fieldShape.stroke(IHaven.Color.border))
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.bottom, IHaven.Space.s4.rawValue)
    }

    private func actions(_ vm: BrowseViewModel) -> some View {
        HStack(spacing: IHaven.Space.s3.rawValue) {
            panelButton("上一张", systemImage: "chevron.left",
                        disabled: vm.wallpapers.isEmpty || isBusy) { step(-1, vm) }
            panelButton("下一张", systemImage: "chevron.right",
                        disabled: vm.wallpapers.isEmpty || isBusy) { step(1, vm) }
            panelButton("换一张", systemImage: "shuffle", disabled: isBusy) { shuffle(vm) }
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.bottom, IHaven.Space.s4.rawValue)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在设置…").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.muted)
            }
            .padding(.horizontal, IHaven.Space.s5.rawValue)
            .padding(.bottom, IHaven.Space.s4.rawValue)
        } else if let status {
            Text(status)
                .font(IHaven.Font.system(.xs))
                // 成功 / 失败共用一行且都中性色：拿不到结构化错误，用警示色会把成功文案也染红。
                .foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, IHaven.Space.s5.rawValue)
                .padding(.bottom, IHaven.Space.s4.rawValue)
        }
    }

    @ViewBuilder
    private func favorites(_ vm: BrowseViewModel) -> some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            Text("收藏").font(IHaven.Font.system(.xs, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.meta)
            if vm.favorites.isEmpty {
                Text("还没有收藏").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(vm.favorites.prefix(Self.favoriteLimit))) { fav in
                        Button { applyFavorite(fav, vm) } label: {
                            thumb(fav.thumbnailURL, width: 60, height: 38).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("设为壁纸")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.bottom, IHaven.Space.s4.rawValue)
    }

    private var footer: some View {
        HStack(spacing: IHaven.Space.s5.rawValue) {
            Button(action: openMainWindow) {
                Text("打开主窗口").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.focus)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { NSApp.terminate(nil) } label: {
                Text("退出 IHaven").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, IHaven.Space.s5.rawValue)
        .padding(.vertical, IHaven.Space.s4.rawValue)
    }

    /// 缩略图小卡（当前壁纸 / 收藏格共用）：统一圆角 + hairline 描边。
    private func thumb(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
        return ThumbnailImage(url: url)
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.stroke(IHaven.Color.borderSoft, lineWidth: 1))
    }

    private func panelButton(_ title: LocalizedStringKey, systemImage: String,
                             disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(title).font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
            }
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(IHaven.Color.surface, in: Self.fieldShape)
            .overlay(Self.fieldShape.stroke(IHaven.Color.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - 行为

    private func refresh(_ vm: BrowseViewModel) {
        // ⚠️ `loadFavorites()` / `loadApplied()` 内部会把 `loadState` 置为 `.loaded`。面板是另一个
        // scene，无条件调用会把主窗口正在展示的失败态悄悄换成空态（错误文案消失）—— 主窗口在
        // failed 时一律不刷新。根治是让这两个方法不碰 `loadState`，那属 BrowseViewModel 的边界。
        if case .failed = vm.loadState { return }
        vm.loadFavorites()
        vm.loadApplied()
        if let library, library.images.isEmpty { library.load() }
    }

    private func submit(_ vm: BrowseViewModel) {
        vm.search(queryText)
        // 结果落在主窗口的瀑布流里：不 activate 的话窗口会开在菜单栏面板后面。
        openMainWindow()
    }

    private func openMainWindow() {
        openWindow(id: Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 在当前结果集内按游标移动，越界回绕。
    private func step(_ delta: Int, _ vm: BrowseViewModel) {
        guard !vm.wallpapers.isEmpty else {
            status = String(localized: "还没有搜索结果，先在主窗口浏览或搜索。")
            return
        }
        let count = vm.wallpapers.count
        cursor = ((cursor + delta) % count + count) % count
        applyWallpaper(vm.wallpapers[min(cursor, count - 1)], vm)
    }

    /// 随机一张。源按「当前结果集 → 收藏 → 本地导入」降级，全空才给明确文案。
    private func shuffle(_ vm: BrowseViewModel) {
        if !vm.wallpapers.isEmpty {
            cursor = Int.random(in: vm.wallpapers.indices)
            applyWallpaper(vm.wallpapers[cursor], vm)
        } else if let fav = vm.favorites.randomElement() {
            applyFavorite(fav, vm)
        } else if let item = library?.images.randomElement() {
            applyLocal(item)
        } else {
            status = String(localized: "没有可换的壁纸，先在主窗口浏览或搜索。")
        }
    }

    private func applyWallpaper(_ wp: Wallpaper, _ vm: BrowseViewModel) {
        guard begin() else { return }
        Task { finish(await vm.setAsWallpaper(wp)) }
    }

    private func applyFavorite(_ fav: Favorite, _ vm: BrowseViewModel) {
        guard begin() else { return }
        Task { finish(await vm.setWallpaperFromFavorite(fav)) }
    }

    private func applyLocal(_ item: ImportedWallpaper) {
        guard begin(), let library else { return }
        Task { finish(await library.setAsWallpaper(item)) }
    }

    /// 开始一次设壁纸动作；返回 false 表示已有动作在途，调用方直接放弃（避免并发重复下载同一张图）。
    private func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        status = nil
        return true
    }

    /// 约定：`nil` = 成功，非 nil = `error.localizedDescription`（与主窗口 toast 同一口径）。
    private func finish(_ result: String?) {
        isBusy = false
        status = result ?? String(localized: "已设为壁纸")
    }

    /// 与 `IHavenApp.appearanceScheme` 同逻辑：面板是独立 scene，不继承主窗口的 `preferredColorScheme`。
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
}
