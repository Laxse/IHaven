import SwiftUI

/// 右侧信息栏（300px，可滚动）：分辨率 → 来源 → 色板 → 操作区 → PROPERTIES → TAGS → 短链接条。
///
/// **降级**：`tags` 为空时整个 TAGS 区块不渲染（不显示空态占位）；`uploader` 为 nil 时上传者行
/// 不渲染（PROPERTIES 变 6 行）；详情请求失败时信息栏仍用列表项带过来的 `Wallpaper` 渲染。
struct DetailInspector: View {
    let wallpaper: Wallpaper
    let detail: WallpaperDetail?
    @Bindable var state: DetailViewState
    var onSearch: (String) -> Void
    var onMessage: (String) -> Void
    /// 裁剪入口，一路透传给 `DetailActions`（sheet 本身挂在 `BrowseView` 上）。
    var onCrop: () -> Void
    /// 「加入相册」入口，透传给 `DetailActions`（sheet 挂在 `BrowseView` 上）。
    var onAddToAlbum: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: IHaven.Space.s6.rawValue) {
                    resolutionBlock
                    sourceBlock
                    detailColorStrip(colors: source.colors)
                    // 404（壁纸已下架）才隐藏操作区：其余失败都是瞬时的，两个动作走的是列表项
                    // `wallpaper.path`、不依赖详情请求，禁掉它们是纯自伤。
                    if !isGone { DetailActions(state: state, onMessage: onMessage, onCrop: onCrop, onAddToAlbum: onAddToAlbum) }
                    propertiesSection
                    tagsSection
                }
                // 左右各 16pt：300 - 32 = 268 内容宽（底部短链接条不受此限制，整宽 300）。
                .padding(IHaven.Space.s6.rawValue)
            }
            if !isGone {
                detailShortLinkBar(url: wallpaper.shortURL) {
                    state.copyShortURL()
                    onMessage(String(localized: "已复制链接"))
                }
            }
        }
        .frame(width: IHaven.Layout.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(IHaven.Color.bg)
    }

    // MARK: - 区块

    /// 壁纸已下架（404）：没有内容可操作，动作与短链一并隐藏。
    private var isGone: Bool { state.detailFailure == .gone }

    /// 摘要字段的数据源：详情请求成功（`detail` 非 nil）时以服务端下发的 `detail.base` 为准
    /// （真实分辨率 / 文件大小 / 浏览 / 收藏 / 分类 / 纯度 / 时间 / 色板）；请求未完成或失败
    /// （含本地导入项无 wallhaven 数据）时回退列表项 `wallpaper`。列表项对收藏 / 已设置 里重建
    /// 出来的预览 Wallpaper 这些字段是 0 / 空，必须用详情数据覆盖，否则「收藏 / 浏览」恒显 0。
    private var source: Wallpaper { detail?.base ?? wallpaper }

    /// 分辨率大字（22pt mono semibold，字距 -0.33）+ 副行（`PNG · 4.5 MB`）。
    private var resolutionBlock: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s1.rawValue) {
            Text("\(source.width) × \(source.height)")
                .font(.system(size: IHaven.Font.Size.xxl.rawValue,
                              weight: IHaven.Font.weightAnnounce,
                              design: .monospaced))
                .tracking(-0.33)
                .foregroundStyle(IHaven.Color.fg)
            Text("\(detailFileTypeLabel(source.fileType)) · \(detailByteString(source.fileSize))")
                .font(IHaven.Font.system(.sm))
                .foregroundStyle(IHaven.Color.fg2)
        }
    }

    /// `source` 是空串（wallhaven 对无来源壁纸的返回值）或非法 URL 时整块不渲染。
    @ViewBuilder
    private var sourceBlock: some View {
        if let src = source.source, !src.isEmpty, let url = URL(string: src) {
            DetailSourceRow(url: url)
        }
    }

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailSectionHeader("属性") { EmptyView() }
            detailPropertyRow("分类") { DetailAccentChip(title: detailCategoryLabel(source.category)) }
            detailPropertyRow("纯度") { DetailPurityChip(purity: source.purity) }
            detailPropertyRow("大小") { detailMonoText(detailByteString(source.fileSize)) }
            detailPropertyRow("浏览") { detailMonoText(detailCountString(source.views)) }
            detailPropertyRow("收藏") { detailMonoText(detailCountString(source.favorites)) }
            if let uploader = detail?.uploader {
                detailPropertyRow("上传者") { uploaderValue(uploader) }
            }
            detailPropertyRow("时间") {
                Text(detailDateText(source.createdAt))
                    .font(.system(size: IHaven.Font.Size.sm.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.muted)
            }
        }
    }

    /// 32px 圆形头像 + 用户名（12pt mono）。
    private func uploaderValue(_ uploader: WallpaperDetail.Uploader) -> some View {
        HStack(spacing: IHaven.Space.s3.rawValue) {
            ThumbnailImage(url: uploader.avatar.px32)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            Text(verbatim: uploader.username)
                .font(.system(size: IHaven.Font.Size.sm.rawValue, design: .monospaced))
                .foregroundStyle(IHaven.Color.fg)
                .lineLimit(1)
        }
    }

    /// TAGS：无标签时整块不渲染（含「更多类似」，没有标签就无从找相似）。
    @ViewBuilder
    private var tagsSection: some View {
        if let detail, !detail.tags.isEmpty {
            VStack(alignment: .leading, spacing: IHaven.Space.s4.rawValue) {
                detailSectionHeader("标签") {
                    // 「更多类似」：`similarSearchQuery`（前 3 个标签拼 `+a +b +c`，空格原样保留）。
                    Button { onSearch(detail.similarSearchQuery) } label: {
                        DetailAccentChip(title: "更多类似")
                    }
                    .buttonStyle(.plain)
                }
                ChipFlowLayout(spacing: IHaven.Space.s3.rawValue) {
                    ForEach(detail.tags, id: \.id) { tag in
                        DetailTagChip(name: tag.name) { onSearch("+\(tag.name)") }
                    }
                }
            }
        }
    }
}
