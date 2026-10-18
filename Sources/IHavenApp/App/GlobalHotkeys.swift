import Foundation

/// 全局热键的装配（#68）。放在 App 层：它要把 `GlobalHotkeyManager`（Platform）的
/// 「换一张」接到 `BrowseViewModel` / `LocalLibraryViewModel`（Feature）上 —— 这正是
/// 「入口只装配」的活，Feature 层不该知道热键，Platform 层不该知道 ViewModel。
///
/// 由 `IHavenApp.bootstrap()` 在 ViewModel 就绪后调用一次（见 `IHavenApp.swift`）。
enum GlobalHotkeys {
    /// 注入「换一张」动作并启动热键监听。viewModel / library 传可空是为让调用点保持一行；
    /// 两者在 bootstrap 里刚赋值，正常非空，空则热键静默不装（不影响其余功能）。
    @MainActor
    static func install(viewModel: BrowseViewModel?, library: LocalLibraryViewModel?) {
        guard let viewModel, let library else { return }
        GlobalHotkeyManager.shared.onShuffle = {
            // 与菜单栏面板同一条优先级：结果集 → 收藏 → 本地导入。
            if let wp = viewModel.randomShuffleCandidate() {
                return await viewModel.setAsWallpaper(wp)
            }
            if let item = library.images.randomElement() {
                return await library.setAsWallpaper(item)
            }
            return String(localized: "没有可换的壁纸，先在主窗口浏览或搜索。")
        }
        GlobalHotkeyManager.shared.start()
    }
}
