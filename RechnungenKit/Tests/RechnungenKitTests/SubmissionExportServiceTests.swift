import XCTest
@testable import RechnungenKit

final class SubmissionExportServiceTests: XCTestCase {
    private func makeService() throws -> (service: SubmissionExportService, fileStorage: LocalFileStorage, submissionRoot: URL) {
        let scansDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileStorage = LocalFileStorage(directory: scansDirectory)
        let submissionRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: submissionRoot, withIntermediateDirectories: true)
        let bookmarkStore = SubmissionFolderBookmarkStore(userDefaults: UserDefaults(suiteName: "SubmissionExportServiceTests-\(UUID().uuidString)")!)
        try bookmarkStore.save(folderURL: submissionRoot)
        let service = SubmissionExportService(fileStorage: fileStorage, bookmarkStore: bookmarkStore)
        return (service, fileStorage, submissionRoot)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    func test_export_writesInvoiceFileIntoYearAndInvoiceSubfolder() throws {
        let (service, fileStorage, submissionRoot) = try makeService()
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "invoice.pdf")
        var invoice = Invoice(
            invoiceNumber: "2026-1",
            amount: Decimal(string: "120.50")!,
            patient: .christian,
            providerName: "Dr. Schmidt",
            localPDFFileName: "invoice.pdf"
        )
        invoice.date = makeDate(year: 2026, month: 8, day: 17)

        let destination = try service.export(invoice: invoice, finding: nil)

        let expectedFolder = submissionRoot
            .appendingPathComponent("2026")
            .appendingPathComponent("2026-08-17_Christian_DrSchmidt_20261")
        XCTAssertEqual(destination.standardizedFileURL, expectedFolder.standardizedFileURL)
        let expectedFile = destination.appendingPathComponent("Rechnung.pdf")
        XCTAssertEqual(try Data(contentsOf: expectedFile), Data("pdf-bytes".utf8))
    }

    func test_export_withFinding_alsoWritesBefundFile() throws {
        let (service, fileStorage, _) = try makeService()
        try fileStorage.save(Data("invoice-bytes".utf8), fileName: "invoice.pdf")
        try fileStorage.save(Data("finding-bytes".utf8), fileName: "finding.pdf")
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 50, patient: .melanie, providerName: "Dr. Huber", localPDFFileName: "invoice.pdf")
        invoice.date = makeDate(year: 2026, month: 1, day: 5)
        let finding = Finding(invoiceID: invoice.id, localPDFFileName: "finding.pdf")

        let destination = try service.export(invoice: invoice, finding: finding)

        let expectedFindingFile = destination.appendingPathComponent("Befund.pdf")
        XCTAssertEqual(try Data(contentsOf: expectedFindingFile), Data("finding-bytes".utf8))
    }

    func test_export_withoutDate_throwsMissingDate() throws {
        let (service, fileStorage, _) = try makeService()
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "invoice.pdf")
        let invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, localPDFFileName: "invoice.pdf")

        XCTAssertThrowsError(try service.export(invoice: invoice, finding: nil)) { error in
            XCTAssertEqual(error as? SubmissionExportService.ExportError, .missingDate)
        }
    }

    func test_export_withoutInvoiceFile_throwsMissingInvoiceFile() throws {
        let (service, _, _) = try makeService()
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian)
        invoice.date = makeDate(year: 2026, month: 1, day: 1)

        XCTAssertThrowsError(try service.export(invoice: invoice, finding: nil)) { error in
            XCTAssertEqual(error as? SubmissionExportService.ExportError, .missingInvoiceFile)
        }
    }

    func test_destinationFolder_createsFolderEvenBeforeExport() throws {
        let (service, _, submissionRoot) = try makeService()
        var invoice = Invoice(invoiceNumber: "2026-1", amount: 10, patient: .christian, providerName: "Dr. Schmidt")
        invoice.date = makeDate(year: 2026, month: 3, day: 1)

        let destination = try service.destinationFolder(for: invoice)

        let expectedFolder = submissionRoot
            .appendingPathComponent("2026")
            .appendingPathComponent("2026-03-01_Christian_DrSchmidt_20261")
        XCTAssertEqual(destination.standardizedFileURL, expectedFolder.standardizedFileURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
