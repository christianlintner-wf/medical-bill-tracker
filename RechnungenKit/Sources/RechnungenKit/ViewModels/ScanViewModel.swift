import Observation
import Foundation

@Observable
public final class ScanViewModel {
    public var invoiceNumber: String = ""
    public var amountText: String = ""
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
        if let amount = fields.amount { self.amountText = NSDecimalNumber(decimal: amount).stringValue }
    }

    public func save(pdfData: Data) async {
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
                patient: patient,
                providerID: selectedProviderID,
                status: status,
                localPDFFileName: fileName
            )
            try await repository.createInvoice(invoice)
            didSave = true
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
