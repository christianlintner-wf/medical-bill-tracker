import SwiftUI
import RechnungenKit

struct InvoiceFormView: View {
    @Bindable var viewModel: ScanViewModel
    let providers: [Provider]
    let pdfData: Data
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section("Rechnung") {
                TextField("Rechnungsnummer", text: $viewModel.invoiceNumber)
                TextField("Betrag", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
            }
            Section("Zuordnung") {
                Picker("Patient", selection: $viewModel.patient) {
                    ForEach(Patient.allCases, id: \.self) { patient in
                        Text(patient.rawValue).tag(patient)
                    }
                }
                Picker("Arzt", selection: $viewModel.selectedProviderID) {
                    Text("Kein Arzt").tag(UUID?.none)
                    ForEach(providers) { provider in
                        Text(provider.name).tag(Optional(provider.id))
                    }
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button("Speichern") {
                Task {
                    await viewModel.save(pdfData: pdfData)
                    if viewModel.didSave { onSaved() }
                }
            }
        }
        .navigationTitle("Neue Rechnung")
    }
}
