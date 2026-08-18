import Foundation

public struct Invoice: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var remoteRowID: String?
    public var invoiceNumber: String
    public var amount: Decimal
    public var date: Date?
    public var patient: Patient
    public var providerID: UUID?
    public var providerRemoteRowID: String?
    public var providerName: String?
    public var status: InvoiceStatus
    public var localPDFFileName: String?
    public var remoteFileURL: String?
    public var hasPendingSync: Bool

    public init(
        id: UUID = UUID(),
        remoteRowID: String? = nil,
        invoiceNumber: String,
        amount: Decimal,
        date: Date? = nil,
        patient: Patient,
        providerID: UUID? = nil,
        providerRemoteRowID: String? = nil,
        providerName: String? = nil,
        status: InvoiceStatus = .open,
        localPDFFileName: String? = nil,
        remoteFileURL: String? = nil,
        hasPendingSync: Bool = false
    ) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.date = date
        self.patient = patient
        self.providerID = providerID
        self.providerRemoteRowID = providerRemoteRowID
        self.providerName = providerName
        self.status = status
        self.localPDFFileName = localPDFFileName
        self.remoteFileURL = remoteFileURL
        self.hasPendingSync = hasPendingSync
    }
}
