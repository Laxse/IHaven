import SwiftUI

/// 信息栏操作区：主「设为壁纸」+ 次「下载原图」+ 次「裁剪…」。
///
/// 位置固定在色板条之后、PROPERTIES 之前：与 macOS 检视器顶部放动作组一致，
/// 且不会随属性行数（上传者有无 → 6/7 行）变化而上下跳动。
///
/// 不做「分配到显示器…」/「编辑为动态…」：代码里根本没有实现（`BrowseViewModel.setAsWallpaper`
/// 写死主屏），置灰占位会变成用户反复点击找原因的死按钮。屏保按钮同理（PRD Out-of-Scope）。
struct DetailActions: View {
    @Bindable var state: DetailViewState
    var onMessage: (String) -> Void
    /// 裁剪入口。⚠️ **sheet 由 `BrowseView` 那一层挂**（子视图挂模态会被父级 `.sheet` 抑制），
    /// 这里只往上抛一个「用户想裁这张」的信号。
    var onCrop: () -> Void
    /// 「加入相册」入口。同理，sheet 挂在 `BrowseView`，这里只抛信号。
    var onAddToAlbum: () -> Void
    @State private var hoverPrimary = false
    @State private var hoverSecondary = false
    @State private var hoverTertiary = false
    @State private var hoverAlbum = false

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s4.rawValue) {
            Button { Task { await applyWallpaper() } } label: {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    leadingIcon(busy: state.inFlight == .wallpaper,
                                systemName: "desktopcomputer", size: IHaven.Icon.md)
                    // 显式 LocalizedStringKey：三元里的字面量会被推断成 String，编译期固化后查不到表。
                    Text(state.inFlight == .wallpaper
                         ? LocalizedStringKey("正在设置…") : LocalizedStringKey("设为壁纸"))
                }
                .font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.accentOn)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(hoverPrimary && !state.isBusy ? IHaven.Color.accentHover : IHaven.Color.accent,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.isBusy)
            .onHover { hoverPrimary = $0 }

            Button { Task { await state.downloadOriginal() } } label: {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    leadingIcon(busy: state.inFlight == .download,
                                systemName: "arrow.down.circle", size: IHaven.Icon.sm)
                    Text(state.inFlight == .download
                         ? LocalizedStringKey("正在下载…") : LocalizedStringKey("下载原图"))
                }
                .font(IHaven.Font.system(.md))
                .foregroundStyle(IHaven.Color.fg)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(hoverSecondary && !state.isBusy ? IHaven.Color.void : IHaven.Color.surface,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                    .stroke(IHaven.Color.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .onHover { hoverSecondary = $0 }

            // 「裁剪…」：竖图设壁纸会左右黑边时，先框出与屏幕同比例的一块再设（ADR-018）。
            // 样式照「下载原图」（surface 底 + border 描边 + 高 28），主按钮仍保持第一位。
            Button(action: onCrop) {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    Image(systemName: "crop").font(.system(size: IHaven.Icon.sm))
                    // 非三元，字面量直接被推断成 LocalizedStringKey（本文件 L22-24 的注释）。
                    Text("裁剪…")
                }
                .font(IHaven.Font.system(.md))
                .foregroundStyle(IHaven.Color.fg)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(hoverTertiary && !state.isBusy ? IHaven.Color.void : IHaven.Color.surface,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                    .stroke(IHaven.Color.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .onHover { hoverTertiary = $0 }

            // 「加入相册」：把这张壁纸整理进本地主题相册（F-组织）。样式同「裁剪…」的次级按钮。
            Button(action: onAddToAlbum) {
                HStack(spacing: IHaven.Space.s3.rawValue) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: IHaven.Icon.sm))
                    Text("加入相册")
                }
                .font(IHaven.Font.system(.md))
                .foregroundStyle(IHaven.Color.fg)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(hoverAlbum && !state.isBusy ? IHaven.Color.void : IHaven.Color.surface,
                            in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous)
                    .stroke(IHaven.Color.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .onHover { hoverAlbum = $0 }

            if let error = state.actionError { inlineError(error) }
        }
    }

    private func applyWallpaper() async {
        // 成功走 toast（复用「已设为壁纸」）；失败留在内联错误区，不弹 toast。
        if let message = await state.setWallpaper() {
            _ = message
        } else {
            onMessage(String(localized: "已设为壁纸"))
        }
    }

    // MARK: - 片段

    /// 图标位：进行中换成不确定态 `ProgressView`，并锁定图标槽尺寸，按钮宽度不跳。
    @ViewBuilder
    private func leadingIcon(busy: Bool, systemName: String, size: CGFloat) -> some View {
        if busy {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: systemName).font(.system(size: size))
        }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: IHaven.Space.s3.rawValue) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IHaven.Icon.sm))
                .foregroundStyle(IHaven.Color.danger)
            Text(message)
                .font(IHaven.Font.system(.sm))
                .foregroundStyle(IHaven.Color.danger)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
