import SwiftUI
import RechnungenKit

struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let onSaved: () -> Void
    var syncErrorMessage: String? = nil

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let syncErrorMessage {
                    Section("Letzter Sync-Fehler") {
                        Text(syncErrorMessage).foregroundStyle(.red)
                    }
                }
                Section("SeaTable API-Token") {
                    SecureField("Token", text: $tokenInput)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Button("Speichern") { save() }
                        .disabled(tokenInput.isEmpty)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }

    private func save() {
        do {
            try keychainService.saveAPIToken(tokenInput)
            onSaved()
        } catch {
            errorMessage = "Token konnte nicht gespeichert werden."
        }
    }
}
