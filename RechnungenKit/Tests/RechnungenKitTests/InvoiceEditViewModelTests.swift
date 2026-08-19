import XCTest
@testable import RechnungenKit

final class InvoiceEditViewModelTests: XCTestCase {
    private func makeExportService(submissionRoot: URL, fileStorage: LocalFileStorage) throws -> SubmissionExportService {
        let bookmarkStore = SubmissionFolderBookmarkStore(userDefaults: UserDefaults(suiteName: "InvoiceEditViewModelTests-\(UUID().uuidString)")!)
        try bookmarkStore.save(folderURL: submissionRoot)
        return SubmissionExportService(fileStorage: fileStorage, bookmarkStore: bookmarkStore)
    }

    private func makeProviderLinksStore() -> InsuranceProviderLinksStore {
        InsuranceProviderLinksStore(userDefaults: UserDefaults(suiteName: "InvoiceEditViewModelTests-links-\(UUID().uuidString)")!)
    }

    private func makePatientInsuranceStore() -> PatientInsuranceAssignmentStore {
        PatientInsuranceAssignmentStore(userDefaults: UserDefaults(suiteName: "InvoiceEditViewModelTests-patients-\(UUID().uuidString)")!)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_submissionTarget_forPublicPhase_resolvesToPatientsAssignedPublicProvider() throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .kathi, status: .open)
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        XCTAssertEqual(viewModel.submissionTarget, .bva)
    }

    func test_submissionTarget_forPrivatePhase_isAlwaysMerkurRegardlessOfPatient() throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, status: .publicInsuranceCompleted)
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        XCTAssertEqual(viewModel.submissionTarget, .merkur)
    }

    func test_loadFinding_populatesFindingFromRepository() async throws {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian)
        let finding = Finding(invoiceID: invoice.id, localPDFFileName: "befund.pdf")
        await repository.setInvoices([invoice])
        await repository.setFindings([finding])
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        await viewModel.loadFinding()

        XCTAssertEqual(viewModel.finding?.localPDFFileName, "befund.pdf")
    }

    func test_exportForSubmission_withMissingDate_setsErrorMessage() throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, localPDFFileName: "invoice.pdf")
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        viewModel.exportForSubmission()

        XCTAssertEqual(viewModel.errorMessage, "Bitte zuerst ein Rechnungsdatum ergänzen.")
        XCTAssertNil(viewModel.exportMessage)
    }

    func test_exportForSubmission_success_setsExportMessage() throws {
        let repository = MockInvoiceRepository()
        let fileStorageDirectory = try makeTempDirectory()
        let fileStorage = LocalFileStorage(directory: fileStorageDirectory)
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "invoice.pdf")
        let exportService = try makeExportService(submissionRoot: try makeTempDirectory(), fileStorage: fileStorage)
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, localPDFFileName: "invoice.pdf")
        invoice.date = Date()
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        viewModel.exportForSubmission()

        XCTAssertEqual(viewModel.exportMessage, "Dateien für ÖGK vorbereitet.")
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_exportForSubmission_withoutConfiguredFolder_setsNotConfiguredErrorMessage() throws {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: try makeTempDirectory())
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "invoice.pdf")
        let bookmarkStore = SubmissionFolderBookmarkStore(userDefaults: UserDefaults(suiteName: "InvoiceEditViewModelTests-unconfigured-\(UUID().uuidString)")!)
        let exportService = SubmissionExportService(fileStorage: fileStorage, bookmarkStore: bookmarkStore)
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, localPDFFileName: "invoice.pdf")
        invoice.date = Date()
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        viewModel.exportForSubmission()

        XCTAssertEqual(viewModel.errorMessage, "Bitte zuerst einen Einreichungs-Ordner in den Einstellungen wählen.")
    }

    func test_delete_withOpenStatus_callsRepositoryAndSetsDidDelete() async throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, status: .open)
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        await viewModel.delete()

        XCTAssertTrue(viewModel.didDelete)
        let deletedIDs = await repository.deletedInvoiceIDs
        XCTAssertEqual(deletedIDs, [invoice.id])
    }

    func test_delete_withNonOpenStatus_isRejectedAndSetsErrorMessage() async throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, status: .done)
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        await viewModel.delete()

        XCTAssertFalse(viewModel.didDelete)
        XCTAssertNotNil(viewModel.errorMessage)
        let deletedIDs = await repository.deletedInvoiceIDs
        XCTAssertTrue(deletedIDs.isEmpty)
    }

    func test_portalURL_returnsConfiguredLinkForResolvedProvider() throws {
        let repository = MockInvoiceRepository()
        let exportService = try makeExportService(
            submissionRoot: try makeTempDirectory(),
            fileStorage: LocalFileStorage(directory: try makeTempDirectory())
        )
        let providerLinksStore = makeProviderLinksStore()
        providerLinksStore.setURL(URL(string: "https://gesundheitskasse.at"), for: .oegk)
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, status: .open)
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: providerLinksStore,
            patientInsuranceStore: makePatientInsuranceStore()
        )

        XCTAssertEqual(viewModel.portalURL()?.absoluteString, "https://gesundheitskasse.at")
    }

    func test_openSubmissionFolder_returnsFilesAppURLForResolvedDestination() throws {
        let repository = MockInvoiceRepository()
        let submissionRoot = try makeTempDirectory()
        let exportService = try makeExportService(submissionRoot: submissionRoot, fileStorage: LocalFileStorage(directory: try makeTempDirectory()))
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, status: .open)
        invoice.date = Date()
        let viewModel = InvoiceEditViewModel(
            invoice: invoice,
            repository: repository,
            exportService: exportService,
            providerLinksStore: makeProviderLinksStore(),
            patientInsuranceStore: makePatientInsuranceStore()
        )

        let url = viewModel.openSubmissionFolder()

        XCTAssertEqual(url?.scheme, "shareddocuments")
    }
}
