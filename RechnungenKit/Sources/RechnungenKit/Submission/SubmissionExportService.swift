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

    public func destinationFolder(for invoice: Invoice, target: InsuranceTarget) throws -> URL {
        guard let date = invoice.date else { throw ExportError.missingDate }
        return try bookmarkStore.withAccess { rawFolderURL in
            let folderURL = Self.canonicalizeURL(rawFolderURL)
            let destination = Self.destinationFolder(root: folderURL, date: date, target: target)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return destination.appendingPathComponent("")
        }
    }

    @discardableResult
    public func export(invoice: Invoice, finding: Finding?, target: InsuranceTarget) throws -> URL {
        guard let date = invoice.date else { throw ExportError.missingDate }
        guard let invoiceFileName = invoice.localPDFFileName else { throw ExportError.missingInvoiceFile }
        let invoiceData = try fileStorage.read(fileName: invoiceFileName)
        let findingData: Data? = try finding?.localPDFFileName.map { try fileStorage.read(fileName: $0) }
        let baseName = Self.baseFileName(invoice: invoice, date: date)

        return try bookmarkStore.withAccess { rawFolderURL in
            let folderURL = Self.canonicalizeURL(rawFolderURL)
            let destination = Self.destinationFolder(root: folderURL, date: date, target: target)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try invoiceData.write(to: destination.appendingPathComponent("\(baseName)_Rechnung.pdf"))
            if let findingData {
                try findingData.write(to: destination.appendingPathComponent("\(baseName)_Befund.pdf"))
            }
            return destination.appendingPathComponent("")
        }
    }

    private static func destinationFolder(root: URL, date: Date, target: InsuranceTarget) -> URL {
        root.appendingPathComponent(yearComponent(for: date)).appendingPathComponent(target.displayName)
    }

    private static func baseFileName(invoice: Invoice, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let patient = sanitize(invoice.patient.rawValue)
        let provider = sanitize(invoice.providerName ?? "Arzt")
        return "\(dateString)_\(patient)_\(provider)_\(amountComponent(invoice.amount))EUR"
    }

    private static func yearComponent(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return String(calendar.component(.year, from: date))
    }

    private static func amountComponent(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        let string = formatter.string(from: amount as NSDecimalNumber) ?? "0,00"
        return string.replacingOccurrences(of: ",", with: "-")
    }

    private static func sanitize(_ raw: String) -> String {
        raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func canonicalizeURL(_ url: URL) -> URL {
        // On macOS, /var is a symlink to /private/var. When URLs are resolved from bookmarks,
        // they use the canonical /private/var representation. We normalize back to /var
        // for consistency with how URLs are constructed in tests and user-facing code.
        var path = url.path
        if path.hasPrefix("/private/var/") {
            path = "/var/" + String(path.dropFirst(13))
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
