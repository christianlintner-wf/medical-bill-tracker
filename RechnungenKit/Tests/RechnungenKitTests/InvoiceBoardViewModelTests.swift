import XCTest
@testable import RechnungenKit

final class InvoiceBoardViewModelTests: XCTestCase {
    func test_load_groupsInvoicesByStatus() async {
        let repository = MockInvoiceRepository()
        await repository.setInvoices([
            Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open),
            Invoice(invoiceNumber: "B", amount: 20, patient: .melanie, status: .submittedToPublicInsurance),
            Invoice(invoiceNumber: "C", amount: 30, patient: .christian, status: .open)
        ])
        let viewModel = InvoiceBoardViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.invoicesByStatus[.open]?.count, 2)
        XCTAssertEqual(viewModel.invoicesByStatus[.submittedToPublicInsurance]?.count, 1)
    }

    func test_moveInvoice_updatesLocalGroupingOptimisticallyAndCallsRepository() async {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        await repository.setInvoices([invoice])
        let viewModel = InvoiceBoardViewModel(repository: repository)
        await viewModel.load()

        await viewModel.moveInvoice(invoice, to: .submittedToPublicInsurance)

        XCTAssertEqual(viewModel.invoicesByStatus[.open]?.count, 0)
        XCTAssertEqual(viewModel.invoicesByStatus[.submittedToPublicInsurance]?.count, 1)
        let updates = await repository.statusUpdates
        XCTAssertEqual(updates.first?.invoiceID, invoice.id)
        XCTAssertEqual(updates.first?.status, .submittedToPublicInsurance)
    }

    func test_moveInvoice_toSameStatus_isNoOp() async {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        await repository.setInvoices([invoice])
        let viewModel = InvoiceBoardViewModel(repository: repository)
        await viewModel.load()

        await viewModel.moveInvoice(invoice, to: .open)

        let updates = await repository.statusUpdates
        XCTAssertTrue(updates.isEmpty)
    }

    func test_invoiceEditViewModel_updateStatus_updatesInvoiceAndCallsRepository() async throws {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        let submissionRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: submissionRoot, withIntermediateDirectories: true)
        let fileStorageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fileStorageDirectory, withIntermediateDirectories: true)
        let bookmarkStore = SubmissionFolderBookmarkStore(userDefaults: UserDefaults(suiteName: "InvoiceBoardViewModelTests-\(UUID().uuidString)")!)
        try bookmarkStore.save(folderURL: submissionRoot)
        let exportService = SubmissionExportService(fileStorage: LocalFileStorage(directory: fileStorageDirectory), bookmarkStore: bookmarkStore)
        let patientLinksStore = PatientLinksStore(userDefaults: UserDefaults(suiteName: "InvoiceBoardViewModelTests-links-\(UUID().uuidString)")!)
        let viewModel = InvoiceEditViewModel(invoice: invoice, repository: repository, exportService: exportService, patientLinksStore: patientLinksStore)

        await viewModel.updateStatus(.done)

        XCTAssertEqual(viewModel.invoice.status, .done)
        let updates = await repository.statusUpdates
        XCTAssertEqual(updates.first?.status, .done)
    }
}
