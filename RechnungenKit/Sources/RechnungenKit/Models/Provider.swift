import Foundation

public struct Provider: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var remoteRowID: String?
    public var name: String

    public init(id: UUID = UUID(), remoteRowID: String? = nil, name: String) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.name = name
    }
}
