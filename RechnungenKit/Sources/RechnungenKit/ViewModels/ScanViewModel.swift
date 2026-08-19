import Observation
import Foundation

@Observable
public final class ScanViewModel {
    public var invoiceNumber: String = ""
    public var amountText: String = ""
    public var date: Date? = Date()
    public var patient: Patient = .christian
    public var selectedProviderID: UUID?
    public var status: InvoiceStatus = .open
    public var errorMessage: String?
    public private(set) var didSave = false

    private let repository: InvoiceRepositoryProtocol
    private let fileStorage: LocalFileStorage

    public init(repository: InvoiceRepositoryProtocol, fileStorage: LocalFileStorage) {
        self.repository = repository
        self.fileStorage = fileStorage
    }

    public func applyExtractedFields(_ fields: ExtractedInvoiceFields) {
        if let invoiceNumber = fields.invoiceNumber { self.invoiceNumber = invoiceNumber }
        if let amount = fields.amount {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.usesGroupingSeparator = false
            self.amountText = formatter.string(from: amount as NSDecimalNumber) ?? ""
        }
        if let date = fields.date { self.date = date }
    }

    public func save(pdfData: Data, findingPDFData: Data? = nil) async {
        var missingFields: [String] = []
        if invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missingFields.append("Rechnungsnummer") }
        if date == nil { missingFields.append("Rechnungsdatum") }
        if selectedProviderID == nil { missingFields.append("Arzt") }
        guard missingFields.isEmpty else {
            errorMessage = "Bitte folgende Pflichtfelder ausfüllen: \(missingFields.joined(separator: ", "))"
            return
        }

        let normalizedAmount = amountText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: normalizedAmount), amount > 0 else {
            errorMessage = "Ungültiger Betrag"
            return
        }
        let fileName = "\(UUID().uuidString).pdf"
        do {
            try fileStorage.save(pdfData, fileName: fileName)
            let invoice = Invoice(
                invoiceNumber: invoiceNumber,
                amount: amount,
                date: date,
                patient: patient,
                providerID: selectedProviderID,
                status: status,
                localPDFFileName: fileName
            )
            try await repository.createInvoice(invoice)
            if let findingPDFData {
                let findingFileName = "\(UUID().uuidString).pdf"
                try fileStorage.save(findingPDFData, fileName: findingFileName)
                let finding = Finding(invoiceID: invoice.id, localPDFFileName: findingFileName)
                try await repository.createFinding(finding)
            }
            didSave = true
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
