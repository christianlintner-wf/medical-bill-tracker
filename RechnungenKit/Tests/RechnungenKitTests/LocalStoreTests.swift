import XCTest
import SwiftData
@testable import RechnungenKit

final class LocalStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self, FindingEntity.self])
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

    func test_pruneInvoices_removesInvoiceMissingFromNonEmptyRemoteSet() async throws {
        let store = try makeStore()
        try await store.upsertInvoiceByRemoteID(row: SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"), "Betrag": .number(150.0),
            "Patient": .string("Christian"), "Status": .string("Offen")
        ]))
        try await store.upsertInvoiceByRemoteID(row: SeaTableRow(id: "row-2", fields: [
            "Rechnungsnummer": .string("2025-90"), "Betrag": .number(55.0),
            "Patient": .string("Melanie"), "Status": .string("Offen")
        ]))

        try await store.pruneInvoices(keepingRemoteRowIDs: ["row-1"])

        let remaining = try await store.allInvoices()
        XCTAssertEqual(remaining.map(\.remoteRowID), ["row-1"])
    }

    func test_pruneInvoices_keepsLocalOnlyInvoiceWithNoRemoteRowID() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await store.upsertInvoice(invoice)

        try await store.pruneInvoices(keepingRemoteRowIDs: [])

        let remaining = try await store.allInvoices()
        XCTAssertEqual(remaining.map(\.id), [invoice.id])
    }

    func test_pruneInvoices_removesPendingOutboxEntriesForPrunedInvoice() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        try await store.setInvoiceRemoteRowID(localID: invoice.id, remoteRowID: "row-1")
        try await store.enqueueOutboxEntry(operation: .updateInvoiceStatus, targetLocalID: invoice.id)

        try await store.pruneInvoices(keepingRemoteRowIDs: ["some-other-row"])

        let pending = try await store.pendingOutboxEntries()
        XCTAssertTrue(pending.isEmpty)
    }

    func test_pruneInvoices_skipsPruningWhenRemoteSetIsEmptyButLocalHasSyncedInvoices() async throws {
        let store = try makeStore()
        try await store.upsertInvoiceByRemoteID(row: SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"), "Betrag": .number(150.0),
            "Patient": .string("Christian"), "Status": .string("Offen")
        ]))

        try await store.pruneInvoices(keepingRemoteRowIDs: [])

        let remaining = try await store.allInvoices()
        XCTAssertEqual(remaining.map(\.remoteRowID), ["row-1"])
    }

    func test_pruneProviders_removesProviderMissingFromNonEmptyRemoteSet() async throws {
        let store = try makeStore()
        try await store.upsertProviderByRemoteID(remoteRowID: "provider-1", name: "Dr. Mona Cooper")
        try await store.upsertProviderByRemoteID(remoteRowID: "provider-2", name: "Dr. John Smith")

        try await store.pruneProviders(keepingRemoteRowIDs: ["provider-1"])

        let remaining = try await store.allProviders()
        XCTAssertEqual(remaining.map(\.remoteRowID), ["provider-1"])
    }

    func test_pruneProviders_skipsPruningWhenRemoteSetIsEmptyButLocalHasSyncedProviders() async throws {
        let store = try makeStore()
        try await store.upsertProviderByRemoteID(remoteRowID: "provider-1", name: "Dr. Mona Cooper")

        try await store.pruneProviders(keepingRemoteRowIDs: [])

        let remaining = try await store.allProviders()
        XCTAssertEqual(remaining.map(\.remoteRowID), ["provider-1"])
    }

    func test_pruneProviders_invoiceReferencingPrunedProviderDegradesGracefully() async throws {
        let store = try makeStore()
        try await store.upsertProviderByRemoteID(remoteRowID: "provider-1", name: "Dr. Mona Cooper")
        try await store.upsertProviderByRemoteID(remoteRowID: "provider-2", name: "Dr. John Smith")
        let row = SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"), "Betrag": .number(150.0),
            "Patient": .string("Christian"), "Status": .string("Offen"),
            "Arzt": .stringArray(["provider-1"])
        ])
        try await store.upsertInvoiceByRemoteID(row: row)

        try await store.pruneProviders(keepingRemoteRowIDs: ["provider-2"])

        let providers = try await store.allProviders()
        XCTAssertEqual(providers.map(\.remoteRowID), ["provider-2"])
        let invoice = try await store.allInvoices().first
        XCTAssertEqual(invoice?.invoiceNumber, "2025-72")
        XCTAssertNil(invoice?.providerName)
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

    func test_upsertFinding_thenFindingByLocalID_roundTrips() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        let finding = Finding(invoiceID: invoice.id, localPDFFileName: "befund.pdf")

        try await store.upsertFinding(finding)
        let stored = try await store.finding(byLocalID: finding.id)

        XCTAssertEqual(stored?.invoiceID, invoice.id)
        XCTAssertEqual(stored?.localPDFFileName, "befund.pdf")
        XCTAssertNil(stored?.remoteRowID)
    }

    func test_setFindingRemoteRowID_updatesStoredFinding() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        let finding = Finding(invoiceID: invoice.id)
        try await store.upsertFinding(finding)

        try await store.setFindingRemoteRowID(localID: finding.id, remoteRowID: "finding-row-1")
        let updated = try await store.finding(byLocalID: finding.id)

        XCTAssertEqual(updated?.remoteRowID, "finding-row-1")
    }

    func test_setFindingRemoteFileURL_updatesStoredFinding() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        let finding = Finding(invoiceID: invoice.id)
        try await store.upsertFinding(finding)

        try await store.setFindingRemoteFileURL(localID: finding.id, url: "/asset/befund.pdf")
        let updated = try await store.finding(byLocalID: finding.id)

        XCTAssertEqual(updated?.remoteFileURL, "/asset/befund.pdf")
    }

    func test_upsertInvoice_thenInvoiceByLocalID_roundTripsDate() async throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, date: date, patient: .christian)

        try await store.upsertInvoice(invoice)
        let stored = try await store.invoice(byLocalID: invoice.id)

        XCTAssertEqual(stored?.date, date)
    }

    func test_upsertInvoiceByRemoteID_parsesDatumField() async throws {
        let store = try makeStore()
        let row = SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"),
            "Betrag": .number(150.0),
            "Patient": .string("Christian"),
            "Status": .string("Offen"),
            "Datum": .string("2026-08-17")
        ])

        try await store.upsertInvoiceByRemoteID(row: row)

        let invoices = try await store.allInvoices()
        XCTAssertEqual(SeaTableDateFormatter.string(from: invoices[0].date!), "2026-08-17")
    }

    func test_finding_forInvoiceID_findsTheFindingLinkedToThatInvoice() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        let finding = Finding(invoiceID: invoice.id, localPDFFileName: "befund.pdf")
        try await store.upsertFinding(finding)

        let found = try await store.finding(forInvoiceID: invoice.id)

        XCTAssertEqual(found?.id, finding.id)
    }

    func test_finding_forInvoiceID_returnsNilWhenNoneExists() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        let found = try await store.finding(forInvoiceID: invoice.id)

        XCTAssertNil(found)
    }
}
