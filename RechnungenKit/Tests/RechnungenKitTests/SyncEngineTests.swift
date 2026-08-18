import XCTest
import SwiftData
@testable import RechnungenKit

final class SyncEngineTests: XCTestCase {
    private func makeLocalStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    private func makeFileStorage() -> LocalFileStorage {
        LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func test_processOutbox_createsProviderThenInvoiceThenUploadsFile() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setNextCreatedRowID("remote-provider-1", forTable: "Arzt")
        await apiClient.setNextCreatedRowID("remote-invoice-1", forTable: "Arztrechnungen")
        let localStore = try makeLocalStore()
        let fileStorage = makeFileStorage()
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "scan.pdf")

        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let provider = try await repository.createProvider(name: "Dr. Mona Cooper")
        let invoice = Invoice(
            invoiceNumber: "2025-90",
            amount: 55,
            patient: .melanie,
            providerID: provider.id,
            localPDFFileName: "scan.pdf"
        )
        try await repository.createInvoice(invoice)

        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: fileStorage)
        await engine.processOutbox()
        await engine.processOutbox()
        await engine.processOutbox()

        let syncedProvider = try await localStore.provider(byLocalID: provider.id)
        let syncedInvoice = try await localStore.invoice(byLocalID: invoice.id)
        let pending = try await localStore.pendingOutboxEntries()

        XCTAssertEqual(syncedProvider?.remoteRowID, "remote-provider-1")
        XCTAssertEqual(syncedInvoice?.remoteRowID, "remote-invoice-1")
        XCTAssertNotNil(syncedInvoice?.remoteFileURL)
        XCTAssertTrue(pending.isEmpty)

        let addedLinks = await apiClient.addedLinks
        XCTAssertEqual(addedLinks.count, 1)
        XCTAssertEqual(addedLinks.first?.table, "Arztrechnungen")
        XCTAssertEqual(addedLinks.first?.column, "Arzt")
        XCTAssertEqual(addedLinks.first?.rowID, "remote-invoice-1")
        XCTAssertEqual(addedLinks.first?.otherRowID, "remote-provider-1")

        let createdInvoiceFields = await apiClient.createdRows.first { $0.table == "Arztrechnungen" }?.fields
        XCTAssertNil(createdInvoiceFields?["Arzt"], "Arzt must be set via addLink, not the row create payload - SeaTable silently drops link values written that way")
    }

    func test_processOutbox_leavesEntryPendingOnFailureAndRecordsError() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setErrorToThrow(SeaTableAPIError.serverError(statusCode: 500, body: "boom"))
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)

        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: makeFileStorage())
        await engine.processOutbox()

        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].attemptCount, 1)
        XCTAssertNotNil(pending[0].lastErrorDescription)
    }

    func test_processOutbox_updatesStatusOnRemote() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)
        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: makeFileStorage())
        await engine.processOutbox() // syncs the create first

        try await repository.updateStatus(invoiceID: invoice.id, newStatus: .done)
        await engine.processOutbox()

        let updates = await apiClient.updatedRows
        XCTAssertTrue(updates.contains { $0.fields["Status"] == .string("Erledigt") })
    }
}
