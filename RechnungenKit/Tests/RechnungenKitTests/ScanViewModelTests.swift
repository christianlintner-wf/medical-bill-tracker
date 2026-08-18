import XCTest
@testable import RechnungenKit

final class ScanViewModelTests: XCTestCase {
    func test_providerPickerViewModel_load_populatesProviders() async {
        let repository = MockInvoiceRepository()
        await repository.setProviders([Provider(name: "Dr. Mona Cooper")])
        let viewModel = ProviderPickerViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.providers.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_providerPickerViewModel_createProvider_appendsAndReturnsProvider() async {
        let repository = MockInvoiceRepository()
        let viewModel = ProviderPickerViewModel(repository: repository)

        let created = await viewModel.createProvider(name: "Dr. Reuter")

        XCTAssertEqual(created?.name, "Dr. Reuter")
        XCTAssertEqual(viewModel.providers.map(\.name), ["Dr. Reuter"])
    }

    func test_scanViewModel_applyExtractedFields_prefillsForm() {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)

        viewModel.applyExtractedFields(ExtractedInvoiceFields(invoiceNumber: "2025-72", amount: 150, date: nil))

        XCTAssertEqual(viewModel.invoiceNumber, "2025-72")
        XCTAssertEqual(viewModel.amountText, "150,00")
    }

    func test_scanViewModel_save_createsInvoiceAndSetsDidSave() async {
        let repository = MockInvoiceRepository()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileStorage = LocalFileStorage(directory: directory)
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.invoiceNumber = "2025-72"
        viewModel.amountText = "150,00"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertTrue(viewModel.didSave)
        let stored = await repository.storedInvoices
        XCTAssertEqual(stored.first?.invoiceNumber, "2025-72")
        XCTAssertEqual(stored.first?.amount, Decimal(string: "150.00"))
    }

    func test_scanViewModel_save_withInvalidAmount_setsErrorAndDoesNotSave() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.amountText = "nicht-numerisch"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertFalse(viewModel.didSave)
        XCTAssertNotNil(viewModel.errorMessage)
        let stored = await repository.storedInvoices
        XCTAssertTrue(stored.isEmpty)
    }

    func test_scanViewModel_save_withFindingPDFData_createsFindingLinkedToInvoice() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.invoiceNumber = "2025-72"
        viewModel.amountText = "150,00"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8), findingPDFData: Data("befund-bytes".utf8))

        XCTAssertTrue(viewModel.didSave)
        let storedInvoices = await repository.storedInvoices
        let storedFindings = await repository.storedFindings
        XCTAssertEqual(storedFindings.count, 1)
        XCTAssertEqual(storedFindings.first?.invoiceID, storedInvoices.first?.id)
        XCTAssertNotNil(storedFindings.first?.localPDFFileName)
    }

    func test_scanViewModel_save_withoutFindingPDFData_createsNoFinding() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.invoiceNumber = "2025-72"
        viewModel.amountText = "150,00"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertTrue(viewModel.didSave)
        let storedFindings = await repository.storedFindings
        XCTAssertTrue(storedFindings.isEmpty)
    }

    func test_scanViewModel_ocrPrefillThenSave_roundTripsFractionalAmountCorrectly() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)

        viewModel.applyExtractedFields(ExtractedInvoiceFields(invoiceNumber: "2025-72", amount: Decimal(string: "19.99"), date: nil))
        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertTrue(viewModel.didSave)
        let stored = await repository.storedInvoices
        XCTAssertEqual(stored.first?.amount, Decimal(string: "19.99"))
    }

    func test_scanViewModel_applyExtractedFields_prefillsDate() {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        viewModel.applyExtractedFields(ExtractedInvoiceFields(invoiceNumber: "2025-72", amount: 150, date: date))

        XCTAssertEqual(viewModel.date, date)
    }

    func test_scanViewModel_save_persistsDateOnCreatedInvoice() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.invoiceNumber = "2025-72"
        viewModel.amountText = "150,00"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        viewModel.date = date

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        let stored = await repository.storedInvoices
        XCTAssertEqual(stored.first?.date, date)
    }
}
