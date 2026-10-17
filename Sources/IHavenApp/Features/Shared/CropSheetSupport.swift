import CoreGraphics
import SwiftUI

/// 裁剪选框 sheet 的零件库（顶层函数 + private struct，与 `BrowseSupport.swift` 同一组织方式）。
///
/// 拆出来的唯一理由：`WallpaperCropSheet.swift` 有 300 行硬上限（ADR-009），而遮罩 Shape、
/// 三分线、句柄、底栏按钮加起来又是这么多行 —— 零件留在这里，sheet 本体只留装配与手势。

// MARK: - 坐标换算

/// 源图等比 `.fit` 铺进 `container` 后的实际显示矩形（含居中偏移）。
///
/// 选框在**显示坐标**里拖动，而模型是**归一化**的，两者之间全靠这个矩形换算：
/// `归一化位移 = 显示位移 ÷ display.width / display.height`。
func cropDisplayRect(image: CGSize, in container: CGSize) -> CGRect {
    guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else { return .zero }
    let scale = min(container.width / image.width, container.height / image.height)
    let w = image.width * scale
    let h = image.height * scale
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

/// 归一化选框 → 显示坐标（容器坐标系，与 `GeometryReader` 的 `geo.size` 同域）。
func cropBoxRect(_ rect: WallpaperCropRect, in display: CGRect) -> CGRect {
    CGRect(x: display.minX + rect.x * display.width,
           y: display.minY + rect.y * display.height,
           width: rect.width * display.width,
           height: rect.height * display.height)
}

/// 某个角句柄在显示坐标里的中心点。
func cropHandlePoint(_ handle: CropHandle, in box: CGRect) -> CGPoint {
    switch handle {
    case .topLeft: CGPoint(x: box.minX, y: box.minY)
    case .topRight: CGPoint(x: box.maxX, y: box.minY)
    case .bottomLeft: CGPoint(x: box.minX, y: box.maxY)
    case .bottomRight: CGPoint(x: box.maxX, y: box.maxY)
    }
}

// MARK: - 遮罩 / 三分线

/// 框外压暗、框内留亮的遮罩：`even-odd` 填充规则下「外框路径 + 选框路径」自然挖出洞。
///
/// 用 Shape + `Path` 而不是两个 `Rectangle` 叠加：后者在选框贴边时会在洞外留下 1px 亮线，
/// 而 even-odd 是同一条路径自相减，不会有接缝。
struct CropHoleMask: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(Path(hole))
        return path
    }
}

/// 选框描边 + 三分线（2 横 2 竖）。纯装饰，**不吃命中**。
///
/// ⚠️ 命中测试（见 `BrowseGrid.swift:31-59` 的记录）：装饰层铺满整片预览区，一旦参与命中
/// 就会吞掉框内拖动与四角句柄，表现为「框拖不动」。调用方必须给它 `allowsHitTesting(false)`。
func cropRulesView(hole: CGRect) -> some View {
    ZStack {
        Rectangle()
            .stroke(SwiftUI.Color.white, lineWidth: 1)
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
        Path { path in
            for i in 1...2 {
                let x = hole.minX + hole.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: hole.minY))
                path.addLine(to: CGPoint(x: x, y: hole.maxY))
                let y = hole.minY + hole.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: hole.minX, y: y))
                path.addLine(to: CGPoint(x: hole.maxX, y: y))
            }
        }
        .stroke(SwiftUI.Color.white.opacity(0.25), lineWidth: 1)
    }
}

/// 四角句柄的视觉部分（12×12 白圆点描边）。命中区域由调用方显式给到 28×28。
func cropHandleKnob() -> some View {
    Circle()
        .stroke(SwiftUI.Color.white, lineWidth: 1.5)
        .frame(width: 12, height: 12)
        .shadow(radius: 1)
}

// MARK: - 标题栏 / 底栏零件

func cropSheetHeader(screenLabel: String) -> some View {
    VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
        Text("裁剪选框")
            .font(IHaven.Font.system(.lg, IHaven.Font.weightAnnounce))
            .foregroundStyle(IHaven.Color.fg)
        Text("\(screenLabel) · 已锁定屏幕比例")
            .font(IHaven.Font.system(.xs))
            .foregroundStyle(IHaven.Color.meta)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// 底栏按钮：主按钮铺 accent，次按钮铺 surface + 1px 描边（对齐 `DetailActions` 的主次关系）。
///
/// 提成类型而不是函数：hover 态要 `@State`，函数返回值里挂不住（同 `BrowseIconButton` 的理由）。
struct CropSheetButton: View {
    let label: LocalizedStringKey
    var isPrimary = false
    var isEnabled = true
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(IHaven.Font.system(.md, isPrimary ? IHaven.Font.weightEmphasize : IHaven.Font.weightRead))
                .foregroundStyle(isPrimary ? IHaven.Color.accentOn : IHaven.Color.fg)
                .padding(.horizontal, IHaven.Space.s5.rawValue)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue,
                                                             style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                    .stroke(isPrimary ? SwiftUI.Color.clear : IHaven.Color.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovered = $0 }
        .animation(IHaven.Motion.fast, value: hovered)
    }

    private var background: SwiftUI.Color {
        if !isEnabled { return IHaven.Color.surface.opacity(0.5) }
        if isPrimary { return hovered ? IHaven.Color.accentHover : IHaven.Color.accent }
        return hovered ? IHaven.Color.void : IHaven.Color.surface
    }
}
