import Foundation

/// 裁剪壁纸（设置壁纸前的选框裁剪）的错误。
///
/// 独立定义而非复用 `MediaError`（`Infrastructure/Media/AVMediaProbe.swift:89`）：
/// `MediaError.thumbnailFailed` 的文案是「生成缩略图失败」，套到裁剪上会误导用户去怀疑
/// 文件损坏，而真实原因往往是选框太小或目标目录不可写 —— 三类失败要能分开说清。
enum CropError: LocalizedError {
    /// 源图读不出来：文件损坏、被删、没有读权限，或压根不是图片。
    case unreadable
    /// 裁不出来：选框退化为 0 宽 / 0 高，或 `CGImage.cropping(to:)` 返回 nil。
    case cropFailed
    /// 裁出来但写不进磁盘：目录不可写、磁盘满。
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "无法读取该文件，可能已损坏或没有读取权限")
        case .cropFailed:
            String(localized: "裁剪区域无效，请调整选框后重试")
        case .writeFailed:
            String(localized: "裁剪结果写入失败，请检查磁盘空间或文件夹权限")
        }
    }
}
