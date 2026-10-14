import Foundation
import SwiftUI

/// 比例分组（filter-panel.svg §4.3 ②「5 组归并」）。
///
/// 线稿把 12 个封闭比例值归成 5 个可视化分组，UI 呈现分组、下发时取组内**代表值**：
/// 竖构图 = 9x16 / 10x16 / 9x18 → 代表 9x16
/// 方图   = 1x1                  → 代表 1x1
/// 横构图 = 3x2 / 4x3 / 5x4 / 16x9 → 代表 4x3
/// 宽幅   = 16x10 / 21x9         → 代表 16x10
/// 超宽   = 32x9 / 48x9          → 代表 32x9
///
/// 纯值类型，仅依赖 Core（ARCH §4 单向依赖）；Browse 的筛选 chip 与 Filter 面板共用同一张表。
public struct RatioGroup: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    /// 下发给 wallhaven 的代表值（组内第一个成员）。
    public let ratio: Ratio
    /// 组内**全部**封闭枚举成员 —— 摘要 chip 要把任意具体值归回分组，
    /// 只认代表值会让 `16x9` / `3x2` / `10x16` 这些同组值漏回去显示原始串。
    public let members: [Ratio]
    /// 格内示意方块的真实宽高比（线稿要求「每格按真实宽高比绘制」）。
    public let drawWidth: CGFloat
    public let drawHeight: CGFloat

    public init(id: String, label: String, members: [Ratio], drawWidth: CGFloat, drawHeight: CGFloat) {
        self.id = id
        self.label = label
        self.members = members
        self.ratio = members[0]
        self.drawWidth = drawWidth
        self.drawHeight = drawHeight
    }

    public static let all: [RatioGroup] = [
        RatioGroup(id: "portrait", label: "竖构图", members: [.r9x16, .r10x16, .r9x18],
                   drawWidth: 9, drawHeight: 16),
        RatioGroup(id: "square", label: "方图", members: [.r1x1],
                   drawWidth: 1, drawHeight: 1),
        RatioGroup(id: "landscape", label: "横构图", members: [.r3x2, .r4x3, .r5x4, .r16x9],
                   drawWidth: 4, drawHeight: 3),
        RatioGroup(id: "wide", label: "宽幅", members: [.r16x10, .r21x9],
                   drawWidth: 16, drawHeight: 10),
        RatioGroup(id: "ultrawide", label: "超宽", members: [.r32x9, .r48x9],
                   drawWidth: 32, drawHeight: 9)
    ]

    /// 分组名的可本地化版本，供 `Text` / `.help` 使用。
    /// `label` 本身保持 `String`：工具栏摘要 chip 要拿它做「比例: 横构图」拼接，而
    /// `LocalizedStringKey` 不支持拼接；直接把 `label` 丢进 `Text` 则会在编译期固化成中文、不查表。
    public var localizedLabel: LocalizedStringKey { LocalizedStringKey(label) }

    /// 把任意具体 ratio 归回所属分组名（工具栏摘要 chip 用「比例: 横构图」而非原始值）。
    /// 未命中分组（如 `.unspecified`）返回 nil，由调用方决定展示原始值。
    public static func label(for ratio: Ratio) -> String? {
        all.first { $0.members.contains(ratio) }?.label
    }
}
