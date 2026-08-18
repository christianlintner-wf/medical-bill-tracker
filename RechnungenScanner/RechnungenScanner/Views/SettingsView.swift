import SwiftUI
import RechnungenKit

struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let bookmarkStore: SubmissionFolderBookmarkStore
    let patientLinksStore: PatientLinksStore
    let onSaved: () -> Void
    var syncErrorMessage: String? = nil

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?
    @State private var folderName: String?
    @State private var isPickingFolder = false
    @State private var patientLinksDraft: [Patient: PatientLinks] = [:]

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
                Section("Einreichungs-Ordner") {
                    Text(folderName ?? "Nicht konfiguriert")
                        .foregroundStyle(folderName == nil ? .secondary : .primary)
                    Button("Ordner wählen") { isPickingFolder = true }
                }
                Section("Patienten-Links") {
                    ForEach(Patient.allCases, id: \.self) { patient in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(patient.rawValue).font(.headline)
                            TextField("ÖGK-Link", text: linkBinding(for: patient, target: .oegk))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                            TextField("Merkur-Link", text: linkBinding(for: patient, target: .merkur))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
        }
        .onAppear {
            folderName = (try? bookmarkStore.resolvedFolderURL())?.lastPathComponent
            patientLinksDraft = Dictionary(uniqueKeysWithValues: Patient.allCases.map { ($0, patientLinksStore.links(for: $0)) })
        }
        .sheet(isPresented: $isPickingFolder) {
            FolderPicker(
                onPicked: { url in
                    try? bookmarkStore.save(folderURL: url)
                    folderName = url.lastPathComponent
                    isPickingFolder = false
                },
                onCancelled: {
                    isPickingFolder = false
                }
            )
        }
    }

    private func linkBinding(for patient: Patient, target: InsuranceTarget) -> Binding<String> {
        Binding(
            get: {
                let links = patientLinksDraft[patient] ?? PatientLinks()
                return links.url(for: target)?.absoluteString ?? ""
            },
            set: { newValue in
                var links = patientLinksDraft[patient] ?? PatientLinks()
                let normalizedURL = Self.normalizedPortalURL(from: newValue)
                switch target {
                case .oegk: links.oegkURL = normalizedURL
                case .merkur: links.merkurURL = normalizedURL
                }
                patientLinksDraft[patient] = links
                patientLinksStore.setLinks(links, for: patient)
            }
        )
    }

    private static func normalizedPortalURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
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
