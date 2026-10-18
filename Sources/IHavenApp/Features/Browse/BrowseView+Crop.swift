import SwiftUI

/// 裁剪相关行为（竖图黑边，ADR-018）+ 全局 toast。从 `BrowseView` 拆出：该文件已逼近
/// ADR-009 的 300 行上限（本次相册功能又加了一截），裁剪整块约 33 行没有落脚之处 ——
/// 本文件与 `BrowseView+Storage.swift` 同路子（extension 分文件后各文件单独计行数）。
///
/// 抽出的方法只依赖 `BrowseView` 的 `internal` 成员（`viewModel` / `library` / `crop` / `toast`），
/// 因此这些方法本身也保持 `internal`（主文件里的 `.sheet` 回调与 `detailPage` 仍要调用它们）。
extension BrowseView {
    /// 网络壁纸：先取本地原图（失败提示重试）再弹 sheet。闭包里用参数 `wp`，不捕获 `@State detail`。
    func cropWallpaper(_ wp: Wallpaper) {
        Task {
            guard let file = await viewModel.cropSource(for: wp) else {
                showToast(String(localized: "原图下载失败，请重试")); return
            }
            crop = CropRequest(id: wp.id, sourceURL: file, kind: .wallpaper(wp))
        }
    }

    func cropImported(_ item: ImportedWallpaper) {
        crop = CropRequest(id: item.id, sourceURL: URL(fileURLWithPath: item.filePath), kind: .imported(item))
    }

    func applyCrop(_ req: CropRequest, url: URL, size: CGSize) {
        Task {
            let error: String? = switch req.kind {
            case .wallpaper(let wp): await viewModel.applyCropped(url, pixelSize: size, wallpaper: wp)
            case .imported(let item): await library.applyCropped(url, pixelSize: size, item: item)
            }
            showToast(error ?? String(localized: "已设为壁纸"))
        }
    }

    func showToast(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == msg { toast = nil }
        }
    }
}
