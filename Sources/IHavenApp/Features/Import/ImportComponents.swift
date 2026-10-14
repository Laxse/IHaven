import SwiftUI

/// 导入页签的共用零件（ADR-015 §三、§七）：拖放区、格式说明、进度条、拒绝摘要、接缝提示。
///
/// 静态图页与动态壁纸页共用同一套零件，只有文案不同 —— 复用而不是各写一份，是为了让
/// 「格式说明必须主动列出不支持项」这条硬要求（PRD:311-313）只有一处实现。
struct ImportDropZone: View {
    let title: LocalizedStringKey
    var onChoose: () -> Void
    var onFiles: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: IHaven.Space.s4.rawValue) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: IHaven.Icon.lg))
                .foregroundStyle(IHaven.Color.meta)
            Text(title)
                .font(IHaven.Font.system(.sm))
                .foregroundStyle(IHaven.Color.fg2)
                .multilineTextAlignment(.center)
            Button("选择文件…", action: onChoose)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IHaven.Space.s7.rawValue)
        .background(IHaven.Color.surfaceSunken, in: RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IHaven.Radius.lg.rawValue, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(isTargeted ? IHaven.Color.accent : IHaven.Color.border)
        )
        // 拖放：`URL` 自带 Transferable，从访达拖文件进来即可。非沙盒态拿到的 URL 直接可读。
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            onFiles(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// 格式说明：**主动列出支持与不支持的格式**（PRD:311-313）。
///
/// 用户必须先看到能力边界、再看到空态。把不支持的三项藏起来，用户只会先失败一次才知道 ——
/// 而失败的那一次会把原因归到「这应用打不开我的文件」，而不是「这个格式不受支持」。
struct FormatNotice: View {
    let supported: LocalizedStringKey
    let unsupported: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s3.rawValue) {
                Circle().fill(IHaven.Color.success).frame(width: 6, height: 6)
                Text(supported).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.fg2)
            }
            HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s3.rawValue) {
                Circle().fill(IHaven.Color.warn).frame(width: 6, height: 6)
                Text(unsupported).font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.fg2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.borderSoft, lineWidth: 1))
    }
}

/// 导入进度：已完成 / 总数 + 当前文件名 + 取消（PRD:695）。
struct ImportProgressView: View {
    let done: Int
    let total: Int
    let current: String
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            HStack {
                Text("导入中…").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                Spacer(minLength: 0)
                Text("\(done) / \(total)")
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.meta)
                Button("取消导入", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(IHaven.Font.system(.xs))
            }
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .progressViewStyle(.linear)
            if !current.isEmpty {
                Text(current)
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.borderSoft, lineWidth: 1))
    }
}

/// 拒绝摘要：被跳过的文件 + 具体原因（PRD:696）。没有原因就不显示 —— 空摘要等于噪音。
struct RejectedSummaryView: View {
    let rejected: [(fileName: String, reason: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            Text("\(rejected.count) 个文件不支持已跳过")
                .font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                .foregroundStyle(IHaven.Color.fg)
            ForEach(Array(rejected.enumerated()), id: \.offset) { _, entry in
                Text("\(entry.fileName) — \(entry.reason)")
                    .font(IHaven.Font.system(.xs))
                    .foregroundStyle(IHaven.Color.meta)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.borderSoft, lineWidth: 1))
    }
}

/// 首尾帧不连续的一次性非阻断提示（SPEC §7.4.6）。
///
/// 只在导入完成后出现一次，播放中不重复；用户点「仍然使用」即消失 —— 不是错误，是知情提示。
struct SeamNoticeView: View {
    let fileName: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: IHaven.Space.s4.rawValue) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(IHaven.Color.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("此视频首尾帧不连续，循环时可能有明显跳变")
                    .font(IHaven.Font.system(.sm))
                    .foregroundStyle(IHaven.Color.fg)
                Text(fileName)
                    .font(.system(size: IHaven.Font.Size.xs.rawValue, design: .monospaced))
                    .foregroundStyle(IHaven.Color.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("仍然使用", action: onDismiss)
                .buttonStyle(.borderless)
                .font(IHaven.Font.system(.xs))
        }
        .padding(IHaven.Space.s5.rawValue)
        .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue, style: .continuous).stroke(IHaven.Color.warn, lineWidth: 1))
    }
}

/// 本地项空态：两个入口并列（浏览网络源 / 拖入本地文件），见 PRD:708。
struct LocalEmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: LocalizedStringKey
    var onAction: () -> Void

    var body: some View {
        VStack(spacing: IHaven.Space.s5.rawValue) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: IHaven.Icon.lg))
                .foregroundStyle(IHaven.Color.meta)
            Text(title).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
            Text(message).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action, action: onAction).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
