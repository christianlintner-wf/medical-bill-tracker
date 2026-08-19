import Observation

@Observable
public final class InvoiceBoardViewModel {
    public private(set) var invoicesByStatus: [InvoiceStatus: [Invoice]] = [:]
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(repository: InvoiceRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        do {
            try await repository.refresh()
            let invoices = try await repository.invoices()
            invoicesByStatus = Dictionary(grouping: invoices, by: \.status)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func moveInvoice(_ invoice: Invoice, to newStatus: InvoiceStatus) async {
        guard invoice.status != newStatus else { return }
        var updated = invoice
        updated.status = newStatus
        updated.hasPendingSync = true
        invoicesByStatus[invoice.status]?.removeAll { $0.id == invoice.id }
        invoicesByStatus[newStatus, default: []].append(updated)
        do {
            try await repository.updateStatus(invoiceID: invoice.id, newStatus: newStatus)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func deleteInvoice(_ invoice: Invoice) async {
        guard invoice.status == .open else {
            errorMessage = "Nur offene Rechnungen können gelöscht werden."
            return
        }
        invoicesByStatus[invoice.status]?.removeAll { $0.id == invoice.id }
        do {
            try await repository.deleteInvoice(invoiceID: invoice.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
