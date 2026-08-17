import Foundation

public struct ExtractedInvoiceFields: Equatable, Sendable {
    public var invoiceNumber: String?
    public var amount: Decimal?
    public var date: Date?

    public init(invoiceNumber: String? = nil, amount: Decimal? = nil, date: Date? = nil) {
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.date = date
    }
}
