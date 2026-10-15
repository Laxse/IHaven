import SwiftUI

/// 设置 · 存储页签：图片缓存占用 / 清除，动态壁纸帧序列占用 / 清理孤儿（ADR-017）。
///
/// 两块都是「占用多少 + 一键释放」，但危险等级不同，写法必须区分：
/// - **图片缓存**：内容完全可再生（ADR-017 的 `DataCache` 只是避免重复下载），清掉零风险，
///   所以直接一个按钮、不弹确认，清完给一句「已清理」。
/// - **帧序列**：里面是用户的动态壁纸素材。**只删孤儿目录**（不在 `animationIDs` 里的），
///   仍在库的动一个字节都不碰，并且在按钮旁边写清「未使用 N 项 · X MB」，让范围可预判。
struct SettingsStorageTab: View {
    /// 由装配点注入（`IHavenApp` → `BrowseView` → `SettingsView`），Feature 不直接碰 Nuke / 文件系统。
    let storage: StorageUsage
    /// 仍在库中的动态壁纸 id（= 帧序列目录名）。之外的目录即孤儿。
    let animationIDs: Set<String>

    @State private var imageBytes = 0
    @State private var frames = FrameSequenceUsage()
    @State private var isMeasuring = true
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s6.rawValue) {
            imageCacheSection
            Divider().overlay(IHaven.Color.border)
            frameSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 遍历目录是磁盘活，放到后台：帧序列成千上万个文件时在主线程量会卡住设置面板。
        .task { await measure() }
    }

    // MARK: - 图片缓存

    private var imageCacheSection: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("图片缓存")
            Text("已下载的缩略图与高清图副本，用于避免重复下载。清除后再次浏览会重新下载。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Text("占用").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                Text(Self.byteText(imageBytes))
                    .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg).monospacedDigit()
                Spacer(minLength: 0)
                Button("清除") { clearImageCache() }.buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 动态壁纸帧序列

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("动态壁纸帧序列")
            Text("由静态图本地生成的 JPEG 帧。清理只删除已不在库中的序列，现有动态壁纸不受影响。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Text("共占用").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                Text(Self.byteText(frames.totalBytes))
                    .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg).monospacedDigit()
                Spacer(minLength: 0)
                Button("清理未使用的") { clearOrphanedFrames() }
                    .buttonStyle(.bordered)
                    // 没有孤儿就禁用：此时唯一能释放空间的方式是去动态壁纸页删除条目本身。
                    .disabled(frames.orphanCount == 0 || isMeasuring)
            }
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Text("未使用").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                // 带参数的本地化必须先取格式串再 `String(format:)`：直接插值进 `String(localized:)`
                // 会生成 `%lld` / `%@` 占位键，与 lproj 里手写的 key 对不上（与导入结果提示同构）。
                Text(frames.orphanCount == 0
                     ? String(localized: "没有未使用的帧序列")
                     : String(format: String(localized: "%lld 项 · %@"),
                              frames.orphanCount, Self.byteText(frames.orphanedBytes)))
                    .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.meta)
            }
            if let hint {
                Text(hint).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.success)
            }
        }
    }

    // MARK: - 行为

    private func measure() async {
        let ids = animationIDs
        let measured = await Task.detached(priority: .utility) {
            (storage.imageCacheBytes(), storage.frameUsage(inUseIDs: ids))
        }.value
        imageBytes = measured.0
        frames = measured.1
        isMeasuring = false
    }

    private func clearImageCache() {
        storage.clearImageCache()
        imageBytes = 0
        flashHint(String(localized: "已清理"))
    }

    private func clearOrphanedFrames() {
        let freed = storage.clearOrphanedFrames(inUseIDs: animationIDs)
        frames = FrameSequenceUsage(totalBytes: frames.totalBytes - freed)
        flashHint(String(localized: "已清理"))
    }

    private func flashHint(_ text: String) {
        hint = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            hint = nil
        }
    }

    // MARK: - 样式

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }

    /// `.file` 进制（1 MB = 1000 KB），与 Finder 显示一致。
    private static func byteText(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
