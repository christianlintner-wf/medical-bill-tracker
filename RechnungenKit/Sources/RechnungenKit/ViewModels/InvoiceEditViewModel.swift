import Observation

@Observable
public final class InvoiceEditViewModel {
    public var invoice: Invoice
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(invoice: Invoice, repository: InvoiceRepositoryProtocol) {
        self.invoice = invoice
        self.repository = repository
    }

    public func updateStatus(_ newStatus: InvoiceStatus) async {
        invoice.status = newStatus
        do {
            try await repository.updateStatus(invoiceID: invoice.id, newStatus: newStatus)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
