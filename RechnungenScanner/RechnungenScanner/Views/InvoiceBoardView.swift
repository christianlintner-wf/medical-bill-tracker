import SwiftUI
import RechnungenKit

struct InvoiceBoardView: View {
    let viewModel: InvoiceBoardViewModel
    let onSelectInvoice: (Invoice) -> Void
    let onAddInvoice: () -> Void
    let onShowSettings: () -> Void

    @State private var selectedStatus: InvoiceStatus = .open
    @State private var selectedPatient: Patient?
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
                patientFilterBar
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

    private var patientFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                patientFilterChip(title: "Alle", isSelected: selectedPatient == nil) {
                    selectedPatient = nil
                }
                ForEach(Patient.allCases, id: \.self) { patient in
                    patientFilterChip(title: patient.rawValue, isSelected: selectedPatient == patient) {
                        selectedPatient = patient
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func patientFilterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
    }

    private func invoices(for status: InvoiceStatus) -> [Invoice] {
        let invoices = viewModel.invoicesByStatus[status] ?? []
        guard let selectedPatient else { return invoices }
        return invoices.filter { $0.patient == selectedPatient }
    }

    private func columnView(for status: InvoiceStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(status.rawValue)
                    .font(.title3.bold())
                    .padding(.horizontal)
                LazyVStack(spacing: 12) {
                    ForEach(invoices(for: status)) { invoice in
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
