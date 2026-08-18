import SwiftUI
import RechnungenKit

struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let bookmarkStore: SubmissionFolderBookmarkStore
    let providerLinksStore: InsuranceProviderLinksStore
    let patientInsuranceStore: PatientInsuranceAssignmentStore
    let onSaved: () -> Void
    var syncErrorMessage: String? = nil

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?
    @State private var hasStoredToken = false
    @State private var folderName: String?
    @State private var isPickingFolder = false
    @State private var providerLinksDraft: [InsuranceProvider: String] = [:]
    @State private var patientProviderDraft: [Patient: InsuranceProvider] = [:]

    private var publicProviders: [InsuranceProvider] {
        InsuranceProvider.allCases.filter { $0.category == .publicInsurance }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let syncErrorMessage {
                    Section("Letzter Sync-Fehler") {
                        Text(syncErrorMessage).foregroundStyle(.red)
                    }
                }
                Section("SeaTable API-Token") {
                    if hasStoredToken {
                        Text("Token gespeichert").foregroundStyle(.secondary)
                    }
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
                Section("Versicherungs-Links") {
                    ForEach(InsuranceProvider.allCases, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(provider.displayName) (\(categoryLabel(provider.category)))").font(.headline)
                            TextField("Link", text: providerLinkBinding(for: provider))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
                Section("Patienten") {
                    ForEach(Patient.allCases, id: \.self) { patient in
                        Picker(patient.rawValue, selection: patientProviderBinding(for: patient)) {
                            ForEach(publicProviders, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
        }
        .onAppear {
            hasStoredToken = ((try? keychainService.readAPIToken()) ?? nil) != nil
            folderName = (try? bookmarkStore.resolvedFolderURL())?.lastPathComponent
            providerLinksDraft = Dictionary(uniqueKeysWithValues: InsuranceProvider.allCases.map {
                ($0, providerLinksStore.url(for: $0)?.absoluteString ?? "")
            })
            patientProviderDraft = Dictionary(uniqueKeysWithValues: Patient.allCases.map {
                ($0, patientInsuranceStore.publicProvider(for: $0))
            })
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

    private func categoryLabel(_ category: InsuranceCategory) -> String {
        switch category {
        case .publicInsurance: return "Gesundheitskasse"
        case .privateInsurance: return "Privatversicherung"
        }
    }

    private func providerLinkBinding(for provider: InsuranceProvider) -> Binding<String> {
        Binding(
            get: { providerLinksDraft[provider] ?? "" },
            set: { newValue in
                providerLinksDraft[provider] = newValue
                providerLinksStore.setURL(Self.normalizedPortalURL(from: newValue), for: provider)
            }
        )
    }

    private func patientProviderBinding(for patient: Patient) -> Binding<InsuranceProvider> {
        Binding(
            get: { patientProviderDraft[patient] ?? patientInsuranceStore.publicProvider(for: patient) },
            set: { newValue in
                patientProviderDraft[patient] = newValue
                patientInsuranceStore.setPublicProvider(newValue, for: patient)
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
            hasStoredToken = true
            onSaved()
        } catch {
            errorMessage = "Token konnte nicht gespeichert werden."
        }
    }
}
