import SwiftData
import Foundation

public enum OutboxOperation: String, Codable, Sendable {
    case createProvider
    case createInvoice
    case updateInvoiceStatus
    case uploadInvoiceFile
}

@Model
public final class OutboxEntryEntity {
    @Attribute(.unique) public var id: UUID
    public var operationRawValue: String
    public var targetLocalID: UUID
    public var createdAt: Date
    public var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastErrorDescription: String?

    public init(
        id: UUID = UUID(),
        operationRawValue: String,
        targetLocalID: UUID,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        lastErrorDescription: String? = nil
    ) {
        self.id = id
        self.operationRawValue = operationRawValue
        self.targetLocalID = targetLocalID
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
        self.lastErrorDescription = lastErrorDescription
    }
}
