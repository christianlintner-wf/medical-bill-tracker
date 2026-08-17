import Foundation

public protocol SeaTableAPIClientProtocol: Sendable {
    func listRows(table: String) async throws -> [SeaTableRow]
    func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String
    func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws
    func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile
}
