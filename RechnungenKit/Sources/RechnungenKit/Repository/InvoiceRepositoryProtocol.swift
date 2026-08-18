import Foundation

public protocol InvoiceRepositoryProtocol: Sendable {
    func refresh() async throws
    func invoices() async throws -> [Invoice]
    func providers() async throws -> [Provider]
    func createProvider(name: String) async throws -> Provider
    func createInvoice(_ invoice: Invoice) async throws
    func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws
    func updateDate(invoiceID: UUID, newDate: Date) async throws
    func createFinding(_ finding: Finding) async throws
    func finding(forInvoiceID invoiceID: UUID) async throws -> Finding?
}
