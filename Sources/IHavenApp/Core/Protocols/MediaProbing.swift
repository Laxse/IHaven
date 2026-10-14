import CoreGraphics
import Foundation

/// 媒体探测能力（Core 层协议，实现落在 `Infrastructure/Media`）。
///
/// **为什么探测必须是独立的一步**（ADR-008:70）：探测有 IO 与解码开销，放在播放时才做，
/// 用户会先看到卡顿或黑屏、再看到错误。导入时探测一次，不兼容格式立刻拒绝并给出具体原因。
public protocol MediaProbing: Sendable {
    func probe(_ url: URL) async throws -> MediaProbe
    /// 采样首帧与尾帧，各自降到 8×8 求平均色，判断首尾是否连续（SPEC §7.4.6）。
    /// 启发式判定：宁可多提示一次，不可漏提示。
    func isSeamless(video: URL) async -> Bool
}

public struct MediaProbe: Sendable, Equatable {
    public var kind: ImportedKind
    public var width: Int
    public var height: Int
    /// 视频时长（秒）；图片为 nil。
    public var duration: Double?
    /// 是否在本项目支持范围内（MP4/MOV 的 H.264/HEVC、常见静态图格式）。
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

/// 导入时一并产出的缩略图 / 首帧 poster（≤640px 长边）。
///
/// 为什么导入时生成而不是渲染时缩放：本地库一屏可能同时存在几十张卡，直接喂原图 file URL
/// 会让 Nuke 对每张卡解码整张 4K 图（单张约 30MB 位图）。导入时用
/// `CGImageSourceCreateThumbnailAtIndex`（不整图解码，ARCH §6.2.2）一次产出，
/// 滚动成本降到几十 KB。视频首帧则一物二用：卡片缩略图 + 静帧兜底层。
public protocol ThumbnailProducing: Sendable {
    /// 为本地文件生成 ≤`maxPixel` 长边的 JPEG，写到 `destination`（由调用方决定落点）。
    func makeThumbnail(source: URL, maxPixel: Int, destination: URL) throws
    /// 抽取视频首帧并生成 ≤`maxPixel` 长边的 JPEG，写到 `destination`。
    func makePoster(video: URL, maxPixel: Int, destination: URL) async throws
}
