import SwiftUI

@main
struct IHavenApp: App {
    @State private var keyProvider = InMemoryKeyProvider()
    @State private var browseViewModel: BrowseViewModel?

    var body: some Scene {
        WindowGroup {
            if let vm = browseViewModel {
                BrowseView(viewModel: vm, keyProvider: keyProvider)
            } else {
                ProgressView("初始化…").task { await bootstrap() }
            }
        }
    }

    private func bootstrap() async {
        let client = WallhavenClient(keyProvider: keyProvider)
        browseViewModel = BrowseViewModel(client: client, keyProvider: keyProvider)
    }
}
