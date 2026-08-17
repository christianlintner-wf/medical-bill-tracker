import SwiftUI
import RechnungenKit

@main
struct RechnungenScannerApp: App {
    @State private var root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            if let services = root.services {
                Text("Board kommt in Task 15")
                    .task { await services.syncEngine.processOutbox() }
            } else {
                SettingsView(keychainService: KeychainService(), onSaved: { root.reload() })
            }
        }
    }
}
