import SwiftUI

/// 设置 · 关于页签：版本 / 作者 / 仓库 / 联系方式 / 技术栈 / 数据位置 / 数据来源。
///
/// 拆成独立文件：`SettingsView` 已有四个页签，再加这几行会逼近单文件 300 行的门禁上限（ADR-009），
/// 且关于页自带一套「链接行 / 可复制行」的行样式，与设置面板其余页签互不复用。
struct SettingsAboutTab: View {
    /// 复制微信号用。Feature 层只见 `ClipboardWriting` 协议，具体实现由 `IHavenApp.bootstrap()`
    /// 装配注入（ARCH §4；「装配点唯一」见 `IHavenApp.bootstrap()` 的注释）。
    let clipboard: ClipboardWriting

    @State private var copyHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("关于 IHaven")
            Text("macOS 原生壁纸工具：从 Wallhaven 发现壁纸，一键设为桌面壁纸。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
            infoRow("版本", AppInfo.version)
            linkRow("作者", text: AppInfo.authorName, link: AppInfo.authorLabel, destination: AppInfo.authorURL)
            linkRow("仓库", text: nil, link: AppInfo.repositoryLabel, destination: AppInfo.repositoryURL)
            contactRow
            infoRow("技术栈", "Swift 6 · SwiftUI · Nuke · GRDB")
            infoRow("数据位置", "~/.ihaven/apikey")
            // value 是 String 通道（要参与拼接/判断），用 String(localized:) 而非裸字面量。
            infoRow("数据来源", isMock ? String(localized: "Mock（免 VPN）")
                                      : String(localized: "Wallhaven 在线服务"))
        }
    }

    // MARK: - 行样式

    private func rowLabel(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
            .frame(width: 72, alignment: .leading)
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s5.rawValue) {
            rowLabel(label)
            Text(value).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// 链接行：`text` 是链接前的普通文本（作者名），`link` 是可点击的地址文案。
    private func linkRow(_ label: LocalizedStringKey, text: String?,
                        link: String, destination: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s5.rawValue) {
            rowLabel(label)
            if let text {
                Text(text).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg)
                    .textSelection(.enabled)
            }
            Link(link, destination: destination).font(IHaven.Font.system(.sm))
            Spacer(minLength: 0)
        }
    }

    /// 联系方式：微信没有可点开的 URL scheme，拿到手也只能复制 —— 所以给一个显式复制按钮，
    /// 而不是让用户自己在设置面板里拖选（72pt 标签列旁边的短文本极难拖准）。
    private var contactRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: IHaven.Space.s5.rawValue) {
            rowLabel("联系方式")
            Text("微信").font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.meta)
            Text(AppInfo.wechatID).font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg)
                .textSelection(.enabled)
            Button("复制") { copyWechat() }
                .buttonStyle(.borderless)
                .font(IHaven.Font.system(.xs))
            if copyHint {
                Text("已复制").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.success)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }

    // MARK: - 行为

    private func copyWechat() {
        clipboard.copy(AppInfo.wechatID)
        copyHint = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copyHint = false
        }
    }

    private var isMock: Bool { ProcessInfo.processInfo.environment["IHAVEN_MOCK"] == "1" }
}
