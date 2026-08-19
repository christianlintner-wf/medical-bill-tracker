import Foundation
@testable import RechnungenKit

actor MockSeaTableAPIClient: SeaTableAPIClientProtocol {
    var rowsByTable: [String: [SeaTableRow]] = [:]
    var createdRows: [(table: String, fields: [String: SeaTableValue])] = []
    var updatedRows: [(table: String, rowID: String, fields: [String: SeaTableValue])] = []
    var deletedRows: [(table: String, rowID: String)] = []
    var addedLinks: [(table: String, column: String, rowID: String, otherRowID: String)] = []
    var nextCreatedRowID = "generated-id"
    var nextCreatedRowIDByTable: [String: String] = [:]
    var uploadResult = SeaTableUploadedFile(name: "file.pdf", size: 1, url: "/asset/file.pdf")
    var errorToThrow: Error?

    func listRows(table: String) async throws -> [SeaTableRow] {
        if let errorToThrow { throw errorToThrow }
        return rowsByTable[table] ?? []
    }

    func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        createdRows.append((table, fields))
        return nextCreatedRowIDByTable[table] ?? nextCreatedRowID
    }

    func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws {
        if let errorToThrow { throw errorToThrow }
        updatedRows.append((table, rowID, fields))
    }

    func deleteRow(table: String, rowID: String) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedRows.append((table, rowID))
    }

    func addLink(table: String, column: String, rowID: String, otherRowID: String) async throws {
        if let errorToThrow { throw errorToThrow }
        addedLinks.append((table, column, rowID, otherRowID))
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

    func setNextCreatedRowID(_ id: String) {
        nextCreatedRowID = id
    }

    func setNextCreatedRowID(_ id: String, forTable table: String) {
        nextCreatedRowIDByTable[table] = id
    }

    func setErrorToThrow(_ error: Error?) {
        errorToThrow = error
    }
}
