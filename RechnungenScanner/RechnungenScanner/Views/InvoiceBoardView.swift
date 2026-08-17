import SwiftUI
import RechnungenKit

struct InvoiceBoardView: View {
    let viewModel: InvoiceBoardViewModel
    let onSelectInvoice: (Invoice) -> Void
    let onAddInvoice: () -> Void
    let onShowSettings: () -> Void

    @State private var selectedStatus: InvoiceStatus = .open
    @State private var draggingInvoice: Invoice?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                TabView(selection: $selectedStatus) {
                    ForEach(InvoiceStatus.allCases, id: \.self) { status in
                        columnView(for: status)
                            .tag(status)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .navigationTitle("Arztrechnungen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Scannen", systemImage: "plus", action: onAddInvoice)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Einstellungen", systemImage: "gearshape", action: onShowSettings)
                }
            }
            .refreshable { await viewModel.load() }
        }
    }

    private func columnView(for status: InvoiceStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(status.rawValue)
                    .font(.title3.bold())
                    .padding(.horizontal)
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.invoicesByStatus[status] ?? []) { invoice in
                        InvoiceCardView(invoice: invoice)
                            .onTapGesture { onSelectInvoice(invoice) }
                            .onDrag {
                                draggingInvoice = invoice
                                return NSItemProvider(object: invoice.id.uuidString as NSString)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let invoice = draggingInvoice else { return false }
            Task { await viewModel.moveInvoice(invoice, to: status) }
            draggingInvoice = nil
            return true
        }
    }
}
