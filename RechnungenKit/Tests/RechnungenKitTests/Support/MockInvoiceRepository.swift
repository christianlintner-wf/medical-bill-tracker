import Foundation
@testable import RechnungenKit

actor MockInvoiceRepository: InvoiceRepositoryProtocol {
    var storedInvoices: [Invoice] = []
    var storedProviders: [Provider] = []
    var storedFindings: [Finding] = []
    var statusUpdates: [(invoiceID: UUID, status: InvoiceStatus)] = []
    var dateUpdates: [(invoiceID: UUID, date: Date)] = []
    var deletedInvoiceIDs: [UUID] = []
    var errorToThrow: Error?

    func refresh() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func invoices() async throws -> [Invoice] {
        if let errorToThrow { throw errorToThrow }
        return storedInvoices
    }

    func providers() async throws -> [Provider] {
        if let errorToThrow { throw errorToThrow }
        return storedProviders
    }

    func createProvider(name: String) async throws -> Provider {
        if let errorToThrow { throw errorToThrow }
        let provider = Provider(name: name)
        storedProviders.append(provider)
        return provider
    }

    func createInvoice(_ invoice: Invoice) async throws {
        if let errorToThrow { throw errorToThrow }
        storedInvoices.append(invoice)
    }

    func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws {
        if let errorToThrow { throw errorToThrow }
        statusUpdates.append((invoiceID, newStatus))
        if let index = storedInvoices.firstIndex(where: { $0.id == invoiceID }) {
            storedInvoices[index].status = newStatus
        }
    }

    func updateDate(invoiceID: UUID, newDate: Date) async throws {
        if let errorToThrow { throw errorToThrow }
        dateUpdates.append((invoiceID, newDate))
        if let index = storedInvoices.firstIndex(where: { $0.id == invoiceID }) {
            storedInvoices[index].date = newDate
        }
    }

    func deleteInvoice(invoiceID: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedInvoiceIDs.append(invoiceID)
        storedInvoices.removeAll { $0.id == invoiceID }
    }

    func createFinding(_ finding: Finding) async throws {
        if let errorToThrow { throw errorToThrow }
        storedFindings.append(finding)
    }

    func finding(forInvoiceID invoiceID: UUID) async throws -> Finding? {
        if let errorToThrow { throw errorToThrow }
        return storedFindings.first { $0.invoiceID == invoiceID }
    }
}

extension MockInvoiceRepository {
    func setProviders(_ providers: [Provider]) {
        storedProviders = providers
    }

    func setInvoices(_ invoices: [Invoice]) {
        storedInvoices = invoices
    }

    func setFindings(_ findings: [Finding]) {
        storedFindings = findings
    }

    func setError(_ error: Error?) {
        errorToThrow = error
    }
}
