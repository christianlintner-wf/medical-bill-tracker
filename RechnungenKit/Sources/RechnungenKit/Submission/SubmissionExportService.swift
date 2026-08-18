import Foundation

public struct SubmissionExportService: Sendable {
    private let fileStorage: LocalFileStorage
    private let bookmarkStore: SubmissionFolderBookmarkStore

    public init(fileStorage: LocalFileStorage, bookmarkStore: SubmissionFolderBookmarkStore) {
        self.fileStorage = fileStorage
        self.bookmarkStore = bookmarkStore
    }

    public enum ExportError: Error, Equatable {
        case missingDate
        case missingInvoiceFile
    }

    public func destinationFolder(for invoice: Invoice) throws -> URL {
        guard let date = invoice.date else { throw ExportError.missingDate }
        return try bookmarkStore.withAccess { folderURL in
            let destination = Self.destinationFolder(root: folderURL, invoice: invoice, date: date)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return destination
        }
    }

    @discardableResult
    public func export(invoice: Invoice, finding: Finding?) throws -> URL {
        guard let date = invoice.date else { throw ExportError.missingDate }
        guard let invoiceFileName = invoice.localPDFFileName else { throw ExportError.missingInvoiceFile }
        let invoiceData = try fileStorage.read(fileName: invoiceFileName)
        let findingData: Data? = try finding?.localPDFFileName.map { try fileStorage.read(fileName: $0) }

        return try bookmarkStore.withAccess { folderURL in
            let destination = Self.destinationFolder(root: folderURL, invoice: invoice, date: date)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try invoiceData.write(to: destination.appendingPathComponent("Rechnung.pdf"))
            if let findingData {
                try findingData.write(to: destination.appendingPathComponent("Befund.pdf"))
            }
            return destination
        }
    }

    private static func destinationFolder(root: URL, invoice: Invoice, date: Date) -> URL {
        root.appendingPathComponent(yearComponent(for: date)).appendingPathComponent(invoiceFolderName(invoice: invoice, date: date))
    }

    private static func invoiceFolderName(invoice: Invoice, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let patient = sanitize(invoice.patient.rawValue)
        let provider = sanitize(invoice.providerName ?? "Arzt")
        let invoiceID = sanitize(invoice.invoiceNumber)
        return "\(dateString)_\(patient)_\(provider)_\(invoiceID)"
    }

    private static func yearComponent(for date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }

    private static func sanitize(_ raw: String) -> String {
        raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}
