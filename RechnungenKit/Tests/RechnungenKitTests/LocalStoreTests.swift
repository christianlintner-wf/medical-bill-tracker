import XCTest
import SwiftData
@testable import RechnungenKit

final class LocalStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    func test_upsertProvider_thenAllProviders_roundTrips() async throws {
        let store = try makeStore()
        let provider = Provider(name: "Dr. Mona Cooper")

        try await store.upsertProvider(provider)
        let all = try await store.allProviders()

        XCTAssertEqual(all.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_upsertInvoice_thenAllInvoices_roundTrips() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)

        try await store.upsertInvoice(invoice)
        let all = try await store.allInvoices()

        XCTAssertEqual(all.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(all.first?.status, .open)
    }

    func test_updateInvoiceStatus_updatesStoredInvoice() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.updateInvoiceStatus(id: invoice.id, status: .submittedToPublicInsurance)
        let updated = try await store.invoice(byLocalID: invoice.id)

        XCTAssertEqual(updated?.status, .submittedToPublicInsurance)
    }

    func test_setInvoiceRemoteRowID_marksInvoiceAsSynced() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.setInvoiceRemoteRowID(localID: invoice.id, remoteRowID: "row-1")
        let updated = try await store.invoice(byLocalID: invoice.id)

        XCTAssertEqual(updated?.remoteRowID, "row-1")
    }

    func test_upsertInvoiceByRemoteID_linksExistingLocalProviderByRemoteRowID() async throws {
        let store = try makeStore()
        var provider = Provider(name: "Dr. Mona Cooper")
        provider.remoteRowID = "provider-1"
        try await store.upsertProvider(provider)

        let row = SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"),
            "Betrag": .number(150.0),
            "Patient": .string("Christian"),
            "Status": .string("Offen"),
            "Arzt": .stringArray(["provider-1"])
        ])
        try await store.upsertInvoiceByRemoteID(row: row)

        let invoices = try await store.allInvoices()
        XCTAssertEqual(invoices.count, 1)
        XCTAssertEqual(invoices[0].providerID, provider.id)
        XCTAssertEqual(invoices[0].remoteRowID, "row-1")
    }

    func test_outbox_enqueueListRemove_roundTrips() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        var pending = try await store.pendingOutboxEntries()
        XCTAssertEqual(pending.count, 1)

        try await store.removeOutboxEntry(id: pending[0].id)
        pending = try await store.pendingOutboxEntries()
        XCTAssertTrue(pending.isEmpty)
    }

    func test_upsertInvoiceByRemoteID_preservesLocalStatusWhenUpdateIsPending() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian, status: .submittedToPublicInsurance)
        try await store.upsertInvoice(invoice)
        try await store.setInvoiceRemoteRowID(localID: invoice.id, remoteRowID: "row-1")
        try await store.enqueueOutboxEntry(operation: .updateInvoiceStatus, targetLocalID: invoice.id)

        let row = SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"),
            "Betrag": .number(150.0),
            "Patient": .string("Christian"),
            "Status": .string("Offen")
        ])
        try await store.upsertInvoiceByRemoteID(row: row)

        let updated = try await store.invoice(byLocalID: invoice.id)
        XCTAssertEqual(updated?.status, .submittedToPublicInsurance)
    }

    func test_allInvoices_resolvesProviderNameFromProviderID() async throws {
        let store = try makeStore()
        let provider = Provider(name: "Dr. Mona Cooper")
        try await store.upsertProvider(provider)
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian, providerID: provider.id)
        try await store.upsertInvoice(invoice)

        let stored = try await store.invoice(byLocalID: invoice.id)
        XCTAssertEqual(stored?.providerName, "Dr. Mona Cooper")
    }

    func test_hasPendingSync_reflectsSyncAndOutboxState() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        let unsynced = try await store.invoice(byLocalID: invoice.id)
        XCTAssertEqual(unsynced?.hasPendingSync, true)

        try await store.setInvoiceRemoteRowID(localID: invoice.id, remoteRowID: "row-1")
        let synced = try await store.invoice(byLocalID: invoice.id)
        XCTAssertEqual(synced?.hasPendingSync, false)
    }

    func test_recordOutboxFailure_incrementsAttemptCount() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        try await store.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        let entryID = try await store.pendingOutboxEntries()[0].id

        try await store.recordOutboxFailure(id: entryID, error: "network down")
        let entry = try await store.pendingOutboxEntries()[0]

        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastErrorDescription, "network down")
    }
}
