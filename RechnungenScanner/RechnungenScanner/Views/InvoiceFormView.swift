import SwiftUI
import RechnungenKit

struct InvoiceFormView: View {
    @Bindable var viewModel: ScanViewModel
    @Bindable var providerPickerViewModel: ProviderPickerViewModel
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
                    await viewModel.save(pdfData: pdfData)
                    if viewModel.didSave { onSaved() }
                }
            }
        }
        .navigationTitle("Neue Rechnung")
    }

    private var selectedProviderName: String {
        guard let id = viewModel.selectedProviderID else { return "Kein Arzt" }
        return providerPickerViewModel.providers.first(where: { $0.id == id })?.name ?? "Kein Arzt"
    }
}
