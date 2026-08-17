import SwiftUI
import RechnungenKit

struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let onSaved: () -> Void

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
