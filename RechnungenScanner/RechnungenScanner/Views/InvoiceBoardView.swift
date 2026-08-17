import SwiftUI
import RechnungenKit

struct InvoiceBoardView: View {
    let viewModel: InvoiceBoardViewModel
    let onSelectInvoice: (Invoice) -> Void
    let onAddInvoice: () -> Void

    @State private var selectedStatus: InvoiceStatus = .open
    @State private var draggingInvoice: Invoice?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedStatus) {
                ForEach(InvoiceStatus.allCases, id: \.self) { status in
                    columnView(for: status)
                        .tag(status)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .navigationTitle("Arztrechnungen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Scannen", systemImage: "plus", action: onAddInvoice)
                }
            }
            .task { await viewModel.load() }
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
