import SwiftUI
import RechnungenKit

struct InvoiceFormView: View {
    @Bindable var viewModel: ScanViewModel
    @Bindable var providerPickerViewModel: ProviderPickerViewModel
    let pdfData: Data
    let onSaved: () -> Void

    @State private var isScanningFinding = false
    @State private var findingPDFData: Data?

    var body: some View {
        Form {
            Section("Rechnung") {
                TextField("Rechnungsnummer", text: $viewModel.invoiceNumber)
                TextField("Betrag", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                DatePicker(
                    "Datum",
                    selection: Binding(
                        get: { viewModel.date ?? Date() },
                        set: { viewModel.date = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Section("Befund") {
                if findingPDFData != nil {
                    HStack {
                        Text("Befund gescannt")
                        Spacer()
                        Button("Entfernen", role: .destructive) { findingPDFData = nil }
                    }
                } else {
                    Button("Befund scannen") { isScanningFinding = true }
                }
            }
            Section("Zuordnung") {
                Picker("Patient", selection: $viewModel.patient) {
                    ForEach(Patient.allCases, id: \.self) { patient in
                        Text(patient.rawValue).tag(patient)
                    }
                }
                NavigationLink {
                    ProviderPickerView(viewModel: providerPickerViewModel, selectedProviderID: $viewModel.selectedProviderID)
                } label: {
                    HStack {
                        Text("Arzt")
                        Spacer()
                        Text(selectedProviderName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button("Speichern") {
                Task {
                    await viewModel.save(pdfData: pdfData, findingPDFData: findingPDFData)
                    if viewModel.didSave { onSaved() }
                }
            }
        }
        .navigationTitle("Neue Rechnung")
        .sheet(isPresented: $isScanningFinding) {
            ScanFlowView(
                onScanned: { data in
                    findingPDFData = data
                    isScanningFinding = false
                },
                onCancelled: { isScanningFinding = false }
            )
        }
    }

    private var selectedProviderName: String {
        guard let id = viewModel.selectedProviderID else { return "Kein Arzt" }
        return providerPickerViewModel.providers.first(where: { $0.id == id })?.name ?? "Kein Arzt"
    }
}
