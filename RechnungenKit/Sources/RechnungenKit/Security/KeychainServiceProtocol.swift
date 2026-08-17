public protocol KeychainServiceProtocol: Sendable {
    func saveAPIToken(_ token: String) throws
    func readAPIToken() throws -> String?
    func deleteAPIToken() throws
}

public enum KeychainError: Error, Equatable {
    case unhandled(status: Int32)
}
