import Foundation
import SwiftUI

/// 设置 · AI 页签（#70 多厂商直连）：**选厂商 → 去该厂商官网拿 Key → 填进 IHaven → 再选模型**。
///
/// 与「密钥」页签同构（SecureField + 已配置/未配置 + 保存/清除），但关键差异是**一家厂商一把 Key**：
/// 六家的 Key 各自申请、各自计费、各自一个文件（见 `AIKeyStore`）。所以厂商一变，
/// 「去哪拿 Key / 这家配没配 / 有哪些模型」全都跟着变 —— 本页每个区块都以当前 `vendor`
/// 为输入，绝不缓存某一家的实例，否则会出现「A 厂填了 Key，切到 B 厂还显示已配置」。
struct SettingsAITab: View {
    /// 当前厂商。**现读现用**：本页自己就会改写这个偏好，缓存成常量会让切厂商后本次不生效。
    @AppStorage(UserPreferenceKey.aiVideoVendor) private var vendorID = AIVideoVendorCatalog.fallback.id
    /// 当前模型，与生成面板共用同一个 `@AppStorage`：两处改任一处都同步。
    /// **为什么设置里也要有一份**：配 AI 的第一反应是来设置找，只在生成面板里有会找不到。
    @AppStorage(UserPreferenceKey.aiVideoModel) private var modelID = AIVideoVendorCatalog.fallback.models[0].id

    @State private var draft = ""
    @State private var savedHint = false

    private var vendor: AIVideoVendor { AIVideoVendorCatalog.vendor(id: vendorID) }
    /// 下拉里选中的模型。找不到（偏好里存的是上一家的 id）时回落第一个 —— 与
    /// `AIVideoVendorCatalog.selectedModel()` 同一口径，只是这里还要给下拉一个选中项。
    private var model: AIVideoModel { vendor.models.first { $0.id == modelID } ?? vendor.models[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s5.rawValue) {
            sectionTitle("AI 图生视频 Key")
            Text("选一张本地静态图、写一句运动描述，AI 生成一段短视频，IHaven 再把它逐帧本地化成无缝循环的动态壁纸。")
                .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            vendorBlock
            keyBlock
            modelBlock
            costNote
        }
        .onAppear {
            // 老偏好里的模型 id 可能属于上一家（甚至是被删掉的聚合层目录），先归位再显示。
            if !vendor.models.contains(where: { $0.id == modelID }) { modelID = vendor.models[0].id }
            reloadDraft()
        }
        // 换厂商：模型必须回到新厂商的第一个（否则下拉选中一个不在选项里的 id，显示成空选中态），
        // Key 输入框也必须换成新厂商的 Key —— 否则会把上一家的 Key 露出来、甚至误存进新厂商的文件。
        .onChange(of: vendorID) { _, _ in
            modelID = vendor.models[0].id
            savedHint = false
            reloadDraft()
        }
    }

    // MARK: - 厂商

    /// 厂商是整个页签的开关：它决定了下面拿 Key 的链接、Key 存哪个文件、以及有哪些模型。
    private var vendorBlock: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                Text("厂商").font(IHaven.Font.system(.sm, IHaven.Font.weightEmphasize))
                    .foregroundStyle(IHaven.Color.fg2)
                Picker("", selection: $vendorID) {
                    ForEach(AIVideoVendorCatalog.all) { item in
                        Text(LocalizedStringKey(item.nameKey)).tag(item.id)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
            }
            Text(LocalizedStringKey(vendor.noteKey))
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Key

    /// 去哪拿 Key + 填 Key。链接与提示都跟着厂商变：六家的控制台入口与 Key 前缀全不一样，
    /// 写死成任何一家都会把用户带去错误的页面。
    private var keyBlock: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            HStack(spacing: 4) {
                Text("获取 Key：").foregroundStyle(IHaven.Color.fg2)
                Link(destination: vendor.keyPageURL) {
                    Text(verbatim: keyPageLabel)
                        .font(IHaven.Font.system(.sm)).foregroundStyle(IHaven.Color.accent)
                }
            }
            .font(IHaven.Font.system(.sm))
            Text(LocalizedStringKey(vendor.keyHintKey))
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: IHaven.Space.s4.rawValue) {
                Circle().fill(isConfigured ? IHaven.Color.success : IHaven.Color.meta).frame(width: 8, height: 8)
                // 三元直接写在字面量上会先固化成 String，故两侧各自构造 LocalizedStringKey。
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
        }
    }

    /// 链接只显示「主机 + 路径」：带上 query（如百炼的 `?tab=model#/api-key`）会让一行变长且难读。
    private var keyPageLabel: String {
        let host = vendor.keyPageURL.host ?? ""
        return host + vendor.keyPageURL.path
    }

    private var isConfigured: Bool {
        !AIKeyStore.shared.keyProvider(for: vendor.id).currentKey
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 模型

    /// 只列**当前厂商**的模型：模型 id 只在厂商内有意义，跨厂商列出来会发出 404 / model not found。
    /// 规格 / 单价写在下拉下面那行 —— 计费功能必须让用户点之前就知道花多少。
    private var modelBlock: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s3.rawValue) {
            HStack(spacing: IHaven.Space.s3.rawValue) {
                sectionTitle("模型")
                Picker("", selection: $modelID) {
                    ForEach(vendor.models) { item in
                        Text(LocalizedStringKey(item.nameKey)).tag(item.id)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
            }
            Text(LocalizedStringKey(model.noteKey))
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
            Text("生成面板里也能改，两处同步。")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
        }
    }

    // MARK: - 成本与存储

    /// 每一次生成花的是用户 Key 的真金白银，且由谁计费取决于厂商 —— 故这一行必须带上厂商名。
    private var costNote: some View {
        VStack(alignment: .leading, spacing: IHaven.Space.s2.rawValue) {
            Label(costText, systemImage: "creditcard")
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.warn)
                .fixedSize(horizontal: false, vertical: true)
            Text(storageText)
                .font(IHaven.Font.system(.xs)).foregroundStyle(IHaven.Color.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// [!] 厂商名是**运行时**才拿到的 lproj key，不能用 `String(localized: "字面量")` 那个重载
    /// （它要求编译期字面量），故走 `NSLocalizedString`；数字 / 名字一律用 `String(format:)`
    /// 填进已本地化的格式串，不能拼好再查表（拼好再查会查不到 key、静默回退中文）。
    private var costText: String {
        String(format: String(localized: "%@ 的调用按你的 Key 计费；每一次生成都会扣你的额度。"),
               NSLocalizedString(vendor.nameKey, comment: "AI 厂商名"))
    }

    private var storageText: String {
        String(format: String(localized: "Key 存于 ~/.ihaven/ai-key-%@（仅本机，不进日志）。"), vendor.id)
    }

    // MARK: - 行为

    private func reloadDraft() {
        draft = AIKeyStore.shared.keyProvider(for: vendor.id).currentKey
    }

    private func save(clear: Bool = false) {
        try? AIKeyStore.shared.keyStore(for: vendor.id)?.save(clear ? "" : draft)
        if clear { draft = "" }
        savedHint = true
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); savedHint = false }
    }

    private func sectionTitle(_ s: LocalizedStringKey) -> some View {
        Text(s).font(IHaven.Font.system(.md, IHaven.Font.weightEmphasize)).foregroundStyle(IHaven.Color.fg)
    }
}
