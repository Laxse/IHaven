import SwiftUI

/// 设置 · AI 页签（#70，Plan B）：AI 图生视频的 Key 输入 + 成本与边界说明。
///
/// 与「密钥」页签同构（SecureField + 已配置/未配置 + 保存/清除），但服务商不同、Key 独立存储
/// （`~/.ihaven/ai-key`，ADR-010 同机制）。核心差异是**成本**：每一次生成花的是用户 Key 的真金
/// 白银，所以必须把「会计费」「需自备 Key」「内容合规自负」讲在明处。
struct SettingsAITab: View {
    let store: KeyStore

    @State private var draft = ""
    @State private var savedHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("AI 图生视频 Key")
            Text("选一张本地静态图、写一句运动描述，AI 会生成一段短视频，IHaven 再把它逐帧本地化成动态壁纸。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: IHaven.Space.s4.rawValue) {
                Circle().fill(isConfigured ? IHaven.Color.success : IHaven.Color.meta).frame(width: 8, height: 8)
                Text(isConfigured ? LocalizedStringKey("已配置") : LocalizedStringKey("未配置"))
                    .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.fg2)
                if savedHint { Text("已保存").font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.success) }
            }
            SecureField("API Key", text: $draft)
                .textFieldStyle(.plain).font(IHaven.Font.system(.md))
                .padding(.horizontal, IHaven.Space.s5.rawValue).frame(height: 32)
                .background(IHaven.Color.surface, in: RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue))
                .overlay(RoundedRectangle(cornerRadius: IHaven.Radius.sm.rawValue).stroke(IHaven.Color.border))
            HStack(spacing: IHaven.Space.s4.rawValue) {
                Button("保存") { save() }.buttonStyle(.borderedProminent)
                Button("清除") { save(clear: true) }.buttonStyle(.bordered)
            }

            // 成本与边界：每一次生成都计费，且要自备 Key、联网、自负内容合规。
            Label("每一次生成都会通过你的 Key 计费；未配置时「AI 生成」入口不可用。",
                  systemImage: "creditcard")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                .fixedSize(horizontal: false, vertical: true)
            Text("需要能访问 AI 服务商的网络（与 wallhaven 一样，部分地区需 VPN）。生成内容受服务商安全策略约束，合规责任由你自负。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
            Text("存储位置：~/.ihaven/ai-key（ADR-010）—— 仅存本机文件，绝不进日志与崩溃报告。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
        .onAppear { draft = store.currentKey }
    }

    private var isConfigured: Bool {
        !store.currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save(clear: Bool = false) {
        try? store.save(clear ? "" : draft)
        if clear { draft = "" }
        savedHint = true
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); savedHint = false }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }
}
