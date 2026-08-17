import Foundation
@testable import RechnungenKit

actor MockSeaTableAPIClient: SeaTableAPIClientProtocol {
    var rowsByTable: [String: [SeaTableRow]] = [:]
    var createdRows: [(table: String, fields: [String: SeaTableValue])] = []
    var updatedRows: [(table: String, rowID: String, fields: [String: SeaTableValue])] = []
    var nextCreatedRowID = "generated-id"
    var uploadResult = SeaTableUploadedFile(name: "file.pdf", size: 1, url: "/asset/file.pdf")
    var errorToThrow: Error?

    func listRows(table: String) async throws -> [SeaTableRow] {
        if let errorToThrow { throw errorToThrow }
        return rowsByTable[table] ?? []
    }

    func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        createdRows.append((table, fields))
        return nextCreatedRowID
    }

    func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws {
        if let errorToThrow { throw errorToThrow }
        updatedRows.append((table, rowID, fields))
    }

    func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile {
        if let errorToThrow { throw errorToThrow }
        return uploadResult
    }
}

extension MockSeaTableAPIClient {
    func setRows(table: String, rows: [SeaTableRow]) {
        rowsByTable[table] = rows
    }
}
