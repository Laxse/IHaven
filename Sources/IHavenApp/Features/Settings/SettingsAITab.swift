import SwiftUI

/// 设置 · AI 页签（#70，Plan B）：AI 图生视频的 Key 输入 + 服务商 / 获取方式 / 成本边界。
///
/// 与「密钥」页签同构（SecureField + 已配置/未配置 + 保存/清除），但服务商不同、Key 独立存储
/// （`~/.ihaven/ai-key`，ADR-010 同机制）。核心差异是**成本**：每一次生成花的是用户 Key 的真金
/// 白银，且要自备 Key，所以服务商是谁、Token 去哪拿、怎么计费，必须写在输入框旁边一眼可见。
struct SettingsAITab: View {
    let store: KeyStore

    @State private var draft = ""
    @State private var savedHint = false
    private let tokenURL = URL(string: "https://replicate.com/account/api-tokens")!

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("AI 图生视频 Key")
            Text("选一张本地静态图、写一句运动描述，AI 生成一段短视频，IHaven 再把它逐帧本地化成无缝循环的动态壁纸。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            // 多模型（#70 聚合层）：说清「一套 Key 就够」—— 否则用户会以为每个模型都要再申请一个。
            Text("一套 Key 可调用多家的模型（MiniMax / 阿里万相 / 快手可灵 / 字节 Seedance / Google Veo / 生数 Vidu），在生成面板里选，不必逐个申请。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            // 服务商 + 如何拿 Key：用户最容易卡在这一步，故放在输入框正上方。
            VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
                HStack(spacing: 0) {
                    Text("服务商：").foregroundStyle(IHaven.Color.fg2)
                    Text("Replicate（replicate.com）· 一套 Key 跑多个模型")
                        .foregroundStyle(IHaven.Color.fg)
                }
                HStack(spacing: 4) {
                    Text("获取 Token：").foregroundStyle(IHaven.Color.fg2)
                    Link(destination: tokenURL) {
                        Text(verbatim: "replicate.com/account/api-tokens")
                            .font(IHaven.Font.system(.sm))
                            .foregroundStyle(IHaven.Color.accent)
                    }
                    Text("（r8_ 开头，注册即有一个默认 token）").foregroundStyle(IHaven.Color.meta)
                }
            }
            .font(IHaven.Font.system(.sm))

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
            Label("API 调用需在 Replicate 绑卡计费；每一次生成都会扣你的额度。",
                  systemImage: "creditcard")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                .fixedSize(horizontal: false, vertical: true)
            Text("需能访问 replicate.com（部分地区需 VPN）；生成内容受服务商安全策略约束，合规责任由你自负。存储于 ~/.ihaven/ai-key（仅本机，不进日志）。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
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
