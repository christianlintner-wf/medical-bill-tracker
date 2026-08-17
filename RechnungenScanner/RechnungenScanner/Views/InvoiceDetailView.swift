import SwiftUI
import RechnungenKit

struct InvoiceDetailView: View {
    @Bindable var viewModel: InvoiceEditViewModel

    var body: some View {
        Form {
            Section("Rechnung") {
                LabeledContent("Rechnungsnummer", value: viewModel.invoice.invoiceNumber)
                LabeledContent("Betrag") {
                    Text(viewModel.invoice.amount, format: .currency(code: "EUR"))
                }
                if let providerName = viewModel.invoice.providerName {
                    LabeledContent("Arzt", value: providerName)
                }
            }
            Section("Status") {
                Picker("Status", selection: Binding(
                    get: { viewModel.invoice.status },
                    set: { newValue in Task { await viewModel.updateStatus(newValue) } }
                )) {
                    ForEach(InvoiceStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.inline)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Rechnungsdetail")
    }
}
