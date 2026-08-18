import Foundation

public actor SeaTableInvoiceRepository: InvoiceRepositoryProtocol {
    private let apiClient: SeaTableAPIClientProtocol
    private let localStore: LocalStore

    public init(apiClient: SeaTableAPIClientProtocol, localStore: LocalStore) {
        self.apiClient = apiClient
        self.localStore = localStore
    }

    public func refresh() async throws {
        let providerRows = try await apiClient.listRows(table: "Arzt")
        for row in providerRows {
            guard let name = row.fields["Arztname"].stringValue else { continue }
            try await localStore.upsertProviderByRemoteID(remoteRowID: row.id, name: name)
        }

        let invoiceRows = try await apiClient.listRows(table: "Arztrechnungen")
        for row in invoiceRows {
            try await localStore.upsertInvoiceByRemoteID(row: row)
        }

        try await localStore.pruneInvoices(keepingRemoteRowIDs: Set(invoiceRows.map(\.id)))
        try await localStore.pruneProviders(keepingRemoteRowIDs: Set(providerRows.map(\.id)))
    }

    public func invoices() async throws -> [Invoice] {
        try await localStore.allInvoices()
    }

    public func providers() async throws -> [Provider] {
        try await localStore.allProviders()
    }

    public func createProvider(name: String) async throws -> Provider {
        let provider = Provider(name: name)
        try await localStore.upsertProvider(provider)
        try await localStore.enqueueOutboxEntry(operation: .createProvider, targetLocalID: provider.id)
        return provider
    }

    public func createInvoice(_ invoice: Invoice) async throws {
        try await localStore.upsertInvoice(invoice)
        try await localStore.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        if invoice.localPDFFileName != nil {
            try await localStore.enqueueOutboxEntry(operation: .uploadInvoiceFile, targetLocalID: invoice.id)
        }
    }

    public func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws {
        try await localStore.updateInvoiceStatus(id: invoiceID, status: newStatus)
        try await localStore.enqueueOutboxEntry(operation: .updateInvoiceStatus, targetLocalID: invoiceID)
    }

    public func updateDate(invoiceID: UUID, newDate: Date) async throws {
        try await localStore.updateInvoiceDate(id: invoiceID, date: newDate)
        try await localStore.enqueueOutboxEntry(operation: .updateInvoiceDate, targetLocalID: invoiceID)
    }

    public func createFinding(_ finding: Finding) async throws {
        try await localStore.upsertFinding(finding)
        try await localStore.enqueueOutboxEntry(operation: .createFinding, targetLocalID: finding.id)
        if finding.localPDFFileName != nil {
            try await localStore.enqueueOutboxEntry(operation: .uploadFindingFile, targetLocalID: finding.id)
        }
    }

    public func finding(forInvoiceID invoiceID: UUID) async throws -> Finding? {
        try await localStore.finding(forInvoiceID: invoiceID)
    }
}
