import SwiftData
import Foundation

@Model
public final class InvoiceEntity {
    @Attribute(.unique) public var id: UUID
    public var remoteRowID: String?
    public var invoiceNumber: String
    public var amount: Decimal
    public var date: Date?
    public var patientRawValue: String
    public var providerID: UUID?
    public var providerRemoteRowID: String?
    public var providerName: String?
    public var statusRawValue: String
    public var localPDFFileName: String?
    public var remoteFileURL: String?

    public init(
        id: UUID = UUID(),
        remoteRowID: String? = nil,
        invoiceNumber: String,
        amount: Decimal,
        date: Date? = nil,
        patientRawValue: String,
        providerID: UUID? = nil,
        providerRemoteRowID: String? = nil,
        providerName: String? = nil,
        statusRawValue: String,
        localPDFFileName: String? = nil,
        remoteFileURL: String? = nil
    ) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.date = date
        self.patientRawValue = patientRawValue
        self.providerID = providerID
        self.providerRemoteRowID = providerRemoteRowID
        self.providerName = providerName
        self.statusRawValue = statusRawValue
        self.localPDFFileName = localPDFFileName
        self.remoteFileURL = remoteFileURL
    }
}
