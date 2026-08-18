import XCTest
@testable import RechnungenKit

final class SeaTableAPIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        session = URLProtocolStub.makeSession()
    }

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private func makeClient() -> SeaTableAPIClient {
        SeaTableAPIClient(configuration: .init(apiToken: "test-token"), session: session)
    }

    private static let accessTokenJSON = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#

    /// `listRows` resolves internal column keys (and select-option ids) via the metadata
    /// endpoint before it can decode a row response - every listRows-exercising test needs
    /// this stubbed too, with column keys matching whatever the row JSON uses.
    private static func metadataJSON(table: String, columns: String) -> String {
        #"{"metadata":{"tables":[{"name":"\#(table)","columns":[\#(columns)]}]}}"#
    }

    func test_listRows_returnsDecodedRows() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("metadata") {
                let columns = #"""
                {"key":"8TrB","name":"Rechnungsnummer"},
                {"key":"9Tgq","name":"Betrag"},
                {"key":"5szi","name":"Arzt"}
                """#
                return .init(statusCode: 200, data: Data(Self.metadataJSON(table: "Arztrechnungen", columns: columns).utf8))
            }
            if request.url!.absoluteString.contains("/rows") {
                // Row data is keyed by internal column key, not display name. Link-column
                // values come back as [{"display_value": ..., "row_id": ...}], not a bare
                // array of strings - exercise both real shapes here.
                let json = #"{"rows":[{"_id":"row-1","8TrB":"2025-72","9Tgq":150.0,"5szi":[{"display_value":"Dr. Mona Cooper","row_id":"provider-1"}]}]}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let rows = try await makeClient().listRows(table: "Arztrechnungen")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "row-1")
        XCTAssertEqual(rows[0].fields["Rechnungsnummer"], .string("2025-72"))
        XCTAssertEqual(rows[0].fields["Betrag"], .number(150.0))
        XCTAssertEqual(rows[0].fields["Arzt"], .stringArray(["provider-1"]))
    }

    func test_listRows_resolvesSingleSelectOptionIDsToDisplayText() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("metadata") {
                let columns = #"""
                {"key":"NL1F","name":"Status","data":{"options":[{"id":"950504","name":"Erledigt"},{"id":"850886","name":"Offen"}]}},
                {"key":"bxQU","name":"Patient","data":{"options":[{"id":"309073","name":"Christian"}]}}
                """#
                return .init(statusCode: 200, data: Data(Self.metadataJSON(table: "Arztrechnungen", columns: columns).utf8))
            }
            if request.url!.absoluteString.contains("/rows") {
                let json = #"{"rows":[{"_id":"row-1","NL1F":"950504","bxQU":"309073"}]}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let rows = try await makeClient().listRows(table: "Arztrechnungen")

        XCTAssertEqual(rows[0].fields["Status"], .string("Erledigt"))
        XCTAssertEqual(rows[0].fields["Patient"], .string("Christian"))
    }

    func test_listRows_usesV2RowsEndpoint() async throws {
        var requestedPath: String?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("metadata") {
                return .init(statusCode: 200, data: Data(Self.metadataJSON(table: "Arztrechnungen", columns: "").utf8))
            }
            requestedPath = request.url!.path
            return .init(statusCode: 200, data: Data(#"{"rows":[]}"#.utf8))
        }

        _ = try await makeClient().listRows(table: "Arztrechnungen")

        // URL.path strips the trailing slash even though the wire request keeps it (see absoluteString elsewhere).
        XCTAssertEqual(requestedPath, "/api/v2/dtables/uuid-1/rows")
    }

    func test_createRow_returnsNewRowID() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.absoluteString.contains("/rows") && request.httpMethod == "POST" {
                if let bodyData = request.httpBodyStreamData() {
                    capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                }
                let json = #"{"inserted_row_count":1,"row_ids":[{"_id":"row-2"}],"first_row":{"_id":"row-2"}}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let rowID = try await makeClient().createRow(
            table: "Arztrechnungen",
            fields: ["Rechnungsnummer": .string("2025-90")]
        )

        XCTAssertEqual(rowID, "row-2")
        let sentRows = capturedBody?["rows"] as? [[String: Any]]
        XCTAssertEqual(sentRows?.count, 1)
        XCTAssertEqual(sentRows?.first?["Rechnungsnummer"] as? String, "2025-90")
    }

    func test_updateRow_sendsPUTWithRowIDAndFields() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.httpMethod == "PUT" {
                if let bodyData = request.httpBodyStreamData() {
                    capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                }
                return .init(statusCode: 200, data: Data("{}".utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        try await makeClient().updateRow(
            table: "Arztrechnungen",
            rowID: "row-1",
            fields: ["Status": .string("Erledigt")]
        )

        let updates = capturedBody?["updates"] as? [[String: Any]]
        XCTAssertEqual(updates?.count, 1)
        XCTAssertEqual(updates?.first?["row_id"] as? String, "row-1")
        let updatedRow = updates?.first?["row"] as? [String: Any]
        XCTAssertEqual(updatedRow?["Status"] as? String, "Erledigt")
    }

    func test_addLink_sendsRequestToLinksEndpointWithResolvedIDs() async throws {
        var capturedBody: [String: Any]?
        var capturedPath: String?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("metadata") {
                let columns = #"""
                {
                  "key": "5szi",
                  "name": "Arzt",
                  "type": "link",
                  "data": {"table_id": "Qpy6", "other_table_id": "9WYy", "link_id": "Q5o9"}
                }
                """#
                return .init(statusCode: 200, data: Data(Self.metadataJSON(table: "Arztrechnungen", columns: columns).utf8))
            }
            if request.url!.path.contains("links") {
                capturedPath = request.url!.path
                if let bodyData = request.httpBodyStreamData() {
                    capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                }
                return .init(statusCode: 200, data: Data(#"{"success":true}"#.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        try await makeClient().addLink(table: "Arztrechnungen", column: "Arzt", rowID: "invoice-1", otherRowID: "provider-1")

        XCTAssertEqual(capturedPath, "/api/v2/dtables/uuid-1/links")
        XCTAssertEqual(capturedBody?["link_id"] as? String, "Q5o9")
        XCTAssertEqual(capturedBody?["table_id"] as? String, "Qpy6")
        XCTAssertEqual(capturedBody?["other_table_id"] as? String, "9WYy")
        let map = capturedBody?["other_rows_ids_map"] as? [String: [String]]
        XCTAssertEqual(map?["invoice-1"], ["provider-1"])
    }

    func test_serverError_throwsSeaTableAPIError() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            return .init(statusCode: 500, data: Data("boom".utf8))
        }

        do {
            _ = try await makeClient().listRows(table: "Arztrechnungen")
            XCTFail("expected error")
        } catch let error as SeaTableAPIError {
            guard case .serverError(let statusCode, _) = error else {
                return XCTFail("wrong error case: \(error)")
            }
            XCTAssertEqual(statusCode, 500)
        }
    }

    func test_uploadFile_returnsUploadedFileDescriptor() async throws {
        var capturedUploadBody: Data?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("app-upload-link") {
                let json = #"{"upload_link":"https://upload.seatable.io/upload-api/abc","parent_path":"/asset/uuid-1","file_relative_path":"files/2026-08","workspace_id":42}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.url!.absoluteString.contains("upload-api") {
                capturedUploadBody = request.httpBodyStreamData()
                let json = #"[{"name":"invoice.pdf","id":"abc123","size":1234}]"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let uploaded = try await makeClient().uploadFile(data: Data("pdf-bytes".utf8), fileName: "invoice.pdf")

        XCTAssertEqual(uploaded.name, "invoice.pdf")
        XCTAssertEqual(uploaded.size, 1234)
        XCTAssertEqual(uploaded.url, "/workspace/42/asset/uuid-1/files/2026-08/invoice.pdf")

        let bodyString = String(data: try XCTUnwrap(capturedUploadBody), encoding: .utf8)
        XCTAssertNotNil(bodyString)
        XCTAssertTrue(bodyString!.contains("name=\"parent_dir\""))
        XCTAssertTrue(bodyString!.contains("/asset/uuid-1"))
        XCTAssertTrue(bodyString!.contains("name=\"relative_path\""))
        XCTAssertTrue(bodyString!.contains("files/2026-08"))
        XCTAssertTrue(bodyString!.contains("name=\"file\"; filename=\"invoice.pdf\""))
        XCTAssertTrue(bodyString!.contains("pdf-bytes"))
    }

    func test_arztTable_createAndListUseArztnameField() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                return .init(statusCode: 200, data: Data(Self.accessTokenJSON.utf8))
            }
            if request.url!.path.contains("metadata") {
                let columns = #"{"key":"HC7m","name":"Arztname"}"#
                return .init(statusCode: 200, data: Data(Self.metadataJSON(table: "Arzt", columns: columns).utf8))
            }
            if request.httpMethod == "POST" {
                return .init(statusCode: 200, data: Data(#"{"row_ids":[{"_id":"provider-1"}]}"#.utf8))
            }
            if request.url!.absoluteString.contains("/rows") {
                let json = #"{"rows":[{"_id":"provider-1","HC7m":"Dr. Mona Cooper"}]}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let client = makeClient()
        let rowID = try await client.createRow(table: "Arzt", fields: ["Arztname": .string("Dr. Mona Cooper")])
        let rows = try await client.listRows(table: "Arzt")

        XCTAssertEqual(rowID, "provider-1")
        XCTAssertEqual(rows.first?.fields["Arztname"], .string("Dr. Mona Cooper"))
    }
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
