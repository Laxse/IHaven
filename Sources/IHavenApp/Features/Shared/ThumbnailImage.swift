import NukeUI
import SwiftUI

/// 缩略图视图：封装 NukeUI.LazyImage，将 Nuke 类型隔离在 Infrastructure 渲染边界之外。
///
/// 放在 `Features/Shared` 而不是某个 Feature 目录内：瀑布流卡（`BrowseGrid`）、已设置卡
/// （`AppliedWallpapersView`）与详情页上传者头像（`DetailInspector`）三处都要用。
/// 若留在 `Features/Browse` 里让 `Features/Detail` 反向借用，就形成目录级依赖环 ——
/// 同一 module 编得过、门禁也查不出，但环是真的。
struct ThumbnailImage: View {
    let url: URL?
    var body: some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    Color(IHaven.Color.surfaceSunken)
                } else {
                    ProgressView()
                }
            }
        } else {
            Color(IHaven.Color.surfaceSunken)
        }
    }
}
