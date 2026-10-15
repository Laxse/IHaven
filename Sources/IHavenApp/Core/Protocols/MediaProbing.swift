import CoreGraphics
import Foundation

/// 媒体探测能力（Core 层协议，实现落在 `Infrastructure/Media`）。
///
/// **为什么探测必须是独立的一步**（ADR-008:70）：探测有 IO 与解码开销，放在播放时才做，
/// 用户会先看到卡顿或黑屏、再看到错误。导入时探测一次，不兼容格式立刻拒绝并给出具体原因。
public protocol MediaProbing: Sendable {
    /// 探测一个本地文件：是受支持的静态图吗？不支持时 `isSupported = false` 并给出 `rejectReason`。
    ///
    /// ADR-016 起不再支持视频（动态壁纸改为由静态图生成），所以这里只判「静态图 / 否」。
    func probe(_ url: URL) async throws -> MediaProbe
}

public struct MediaProbe: Sendable, Equatable {
    public var kind: ImportedKind
    public var width: Int
    public var height: Int
    /// 保留字段；静态图恒 nil（视频时代曾承载时长）。
    public var duration: Double?
    /// 是否在本项目支持范围内（常见静态图格式）。
    public var isSupported: Bool
    /// 不支持时的具体原因，直接展示给用户（ADR-008:71）。
    public var rejectReason: String?

    public init(kind: ImportedKind, width: Int, height: Int, duration: Double?,
                isSupported: Bool, rejectReason: String?) {
        self.kind = kind
        self.width = width
        self.height = height
        self.duration = duration
        self.isSupported = isSupported
        self.rejectReason = rejectReason
    }
}

/// 导入时一并产出的缩略图（≤640px 长边）。
///
/// 为什么导入时生成而不是渲染时缩放：本地库一屏可能同时存在几十张卡，直接喂原图 file URL
/// 会让 Nuke 对每张卡解码整张 4K 图（单张约 30MB 位图）。导入时用
/// `CGImageSourceCreateThumbnailAtIndex`（不整图解码，ARCH §6.2.2）一次产出，
/// 滚动成本降到几十 KB。
public protocol ThumbnailProducing: Sendable {
    /// 为本地文件生成 ≤`maxPixel` 长边的 JPEG，写到 `destination`（由调用方决定落点）。
    func makeThumbnail(source: URL, maxPixel: Int, destination: URL) throws
}
