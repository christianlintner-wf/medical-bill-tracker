import XCTest
import SwiftData
@testable import RechnungenKit

final class SeaTableInvoiceRepositoryTests: XCTestCase {
    private func makeLocalStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    func test_refresh_pullsProvidersAndInvoicesIntoLocalCache() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setRows(table: "Arzt", rows: [
            SeaTableRow(id: "provider-1", fields: ["Arztname": .string("Dr. Mona Cooper")])
        ])
        await apiClient.setRows(table: "Arztrechnungen", rows: [
            SeaTableRow(id: "row-1", fields: [
                "Rechnungsnummer": .string("2025-72"),
                "Betrag": .number(150.0),
                "Patient": .string("Christian"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ])
        ])
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: try makeLocalStore())

        try await repository.refresh()
        let invoices = try await repository.invoices()
        let providers = try await repository.providers()

        XCTAssertEqual(providers.map(\.name), ["Dr. Mona Cooper"])
        XCTAssertEqual(invoices.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(invoices.first?.providerID, providers.first?.id)
    }

    func test_refresh_removesLocalInvoiceDeletedRemotely() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setRows(table: "Arzt", rows: [
            SeaTableRow(id: "provider-1", fields: ["Arztname": .string("Dr. Mona Cooper")])
        ])
        await apiClient.setRows(table: "Arztrechnungen", rows: [
            SeaTableRow(id: "row-1", fields: [
                "Rechnungsnummer": .string("2025-72"),
                "Betrag": .number(150.0),
                "Patient": .string("Christian"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ]),
            SeaTableRow(id: "row-2", fields: [
                "Rechnungsnummer": .string("2025-90"),
                "Betrag": .number(55.0),
                "Patient": .string("Melanie"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ])
        ])
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: try makeLocalStore())
        try await repository.refresh()

        await apiClient.setRows(table: "Arztrechnungen", rows: [
            SeaTableRow(id: "row-1", fields: [
                "Rechnungsnummer": .string("2025-72"),
                "Betrag": .number(150.0),
                "Patient": .string("Christian"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ])
        ])
        try await repository.refresh()

        let invoices = try await repository.invoices()
        let providers = try await repository.providers()
        XCTAssertEqual(invoices.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(providers.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_refresh_doesNotWipeLocalCacheWhenRemoteReturnsEmptyForPreviouslySyncedTable() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setRows(table: "Arzt", rows: [
            SeaTableRow(id: "provider-1", fields: ["Arztname": .string("Dr. Mona Cooper")])
        ])
        await apiClient.setRows(table: "Arztrechnungen", rows: [
            SeaTableRow(id: "row-1", fields: [
                "Rechnungsnummer": .string("2025-72"),
                "Betrag": .number(150.0),
                "Patient": .string("Christian"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ])
        ])
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: try makeLocalStore())
        try await repository.refresh()

        await apiClient.setRows(table: "Arzt", rows: [])
        await apiClient.setRows(table: "Arztrechnungen", rows: [])
        try await repository.refresh()

        let invoices = try await repository.invoices()
        let providers = try await repository.providers()
        XCTAssertEqual(invoices.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(providers.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_createInvoice_persistsLocallyAndEnqueuesOutbox() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie, localPDFFileName: "scan.pdf")

        try await repository.createInvoice(invoice)

        let stored = try await localStore.invoice(byLocalID: invoice.id)
        XCTAssertNotNil(stored)
        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertEqual(Set(pending.map(\.operationRawValue)), [
            OutboxOperation.createInvoice.rawValue,
            OutboxOperation.uploadInvoiceFile.rawValue
        ])
    }

    func test_updateStatus_updatesLocalStoreAndEnqueuesOutbox() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)

        try await repository.updateStatus(invoiceID: invoice.id, newStatus: .submittedToPublicInsurance)

        let stored = try await localStore.invoice(byLocalID: invoice.id)
        XCTAssertEqual(stored?.status, .submittedToPublicInsurance)
        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertTrue(pending.contains { $0.operationRawValue == OutboxOperation.updateInvoiceStatus.rawValue })
    }
}
