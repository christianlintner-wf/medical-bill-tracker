import SwiftUI
import RechnungenKit

struct InvoiceDetailView: View {
    @Bindable var viewModel: InvoiceEditViewModel
    let onDeleted: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Rechnung") {
                LabeledContent("Rechnungsnummer", value: viewModel.invoice.invoiceNumber)
                LabeledContent("Betrag") {
                    Text(viewModel.invoice.amount, format: .currency(code: "EUR"))
                }
                DatePicker(
                    "Datum",
                    selection: Binding(
                        get: { viewModel.invoice.date ?? Date() },
                        set: { newValue in Task { await viewModel.updateDate(newValue) } }
                    ),
                    displayedComponents: .date
                )
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
                .pickerStyle(.menu)
            }
            if let target = viewModel.submissionTarget {
                Section("Einreichung") {
                    Button("Für \(target.displayName) vorbereiten") {
                        viewModel.exportForSubmission()
                    }
                    Button("Ordner öffnen") {
                        if let url = viewModel.openSubmissionFolder() {
                            openURL(url)
                        }
                    }
                    if let portalURL = viewModel.portalURL() {
                        Button("Bei \(target.displayName) öffnen") {
                            openURL(portalURL)
                        }
                    }
                    if let exportMessage = viewModel.exportMessage {
                        Text(exportMessage).foregroundStyle(.green)
                    }
                }
            }
            if viewModel.invoice.status == .open {
                Section {
                    Button("Rechnung löschen", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Rechnungsdetail")
        .task { await viewModel.loadFinding() }
        .confirmationDialog(
            "Rechnung wirklich löschen?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                Task {
                    await viewModel.delete()
                    if viewModel.didDelete { onDeleted() }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
