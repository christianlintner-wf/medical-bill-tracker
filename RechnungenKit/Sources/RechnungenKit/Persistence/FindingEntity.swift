import SwiftData
import Foundation

@Model
public final class FindingEntity {
    @Attribute(.unique) public var id: UUID
    public var remoteRowID: String?
    public var invoiceID: UUID
    public var invoiceRemoteRowID: String?
    public var localPDFFileName: String?
    public var remoteFileURL: String?

    public init(
        id: UUID = UUID(),
        remoteRowID: String? = nil,
        invoiceID: UUID,
        invoiceRemoteRowID: String? = nil,
        localPDFFileName: String? = nil,
        remoteFileURL: String? = nil
    ) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.invoiceID = invoiceID
        self.invoiceRemoteRowID = invoiceRemoteRowID
        self.localPDFFileName = localPDFFileName
        self.remoteFileURL = remoteFileURL
    }
}
