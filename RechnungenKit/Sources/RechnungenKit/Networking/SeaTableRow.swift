public struct SeaTableRow: Sendable, Equatable {
    public let id: String
    public let fields: [String: SeaTableValue]

    public init(id: String, fields: [String: SeaTableValue]) {
        self.id = id
        self.fields = fields
    }
}

public struct SeaTableUploadedFile: Sendable, Equatable {
    public let name: String
    public let size: Int
    public let url: String
}

public enum SeaTableAPIError: Error, Equatable {
    case invalidResponse
    case serverError(statusCode: Int, body: String)
}
