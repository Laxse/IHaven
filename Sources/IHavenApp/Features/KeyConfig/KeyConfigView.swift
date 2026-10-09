import SwiftUI

/// API Key 配置（产品层）。Key 经 KeyProvider 注入，绝不硬编码（ARCH §6.4.0）。
struct KeyConfigView: View {
    @Bindable var keyProvider: InMemoryKeyProvider
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key 配置").font(.title3.bold())
            Text("Key 经 X-API-Key 头下发；空 / 纯空白视为未配置（Trap 14）。")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("X-API-Key", text: $keyProvider.currentKey)
            Button("保存", action: onSave).buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 320)
    }
}
