import Foundation

/// `BrowseView` 派生给设置页的存储相关集合（ADR-009：主文件已顶到 300 行上限，
/// 这类私有 computed 抽到 extension 文件腾行数，与 `BrowseSupport` 同路子）。
///
/// 两者都只依赖 `BrowseView` 的存储属性 `library` / `viewModel`，extension 内可直接访问。
extension BrowseView {
    /// 仍在库中的动态壁纸 id（= 帧序列目录名）：存储页签据此判定哪些帧目录是孤儿。
    var animationIDs: Set<String> {
        Set(library.imported.filter(\.isAnimation).map(\.id))
    }

    /// 仍被「已设置」记录引用的裁剪件路径：存储页签据此判定哪些裁剪文件是孤儿（ADR-018 清理策略）。
    var cropReferencedPaths: Set<String> {
        Set(viewModel.applied.map(\.localPath))
    }
}
