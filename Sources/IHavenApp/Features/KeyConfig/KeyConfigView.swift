import SwiftUI

/// API Key 配置（产品层）。Key 经 KeyStore 持久化到 Keychain（生产）/ 内存（Preview），
/// 绝不硬编码（ARCH §6.4.0）。本地 draft 编辑，保存时调用 `store.save`（trim 后写入）。
struct KeyConfigView: View {
    let store: KeyStore
    var onSave: () -> Void
    @State private var draft: String

    init(store: KeyStore, onSave: @escaping () -> Void) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.currentKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key 配置").font(.title3.bold())
            Text("Key 经 X-API-Key 头下发；空 / 纯空白视为未配置（Trap 14）。")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("X-API-Key", text: $draft)
            Button("保存") {
                try? store.save(draft)
                onSave()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 320)
    }
}
