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

    private func stubAccessToken() {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }
    }

    func test_listRows_returnsDecodedRows() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.url!.absoluteString.contains("/rows") {
                let json = #"{"rows":[{"_id":"row-1","Rechnungsnummer":"2025-72","Betrag":150.0,"Arzt":["provider-1"]}]}"#
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

    func test_createRow_returnsNewRowID() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.url!.absoluteString.contains("/rows") && request.httpMethod == "POST" {
                let json = #"{"_id":"row-2"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let rowID = try await makeClient().createRow(
            table: "Arztrechnungen",
            fields: ["Rechnungsnummer": .string("2025-90")]
        )

        XCTAssertEqual(rowID, "row-2")
    }

    func test_updateRow_sendsPUTWithRowIDAndFields() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
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

        XCTAssertEqual(capturedBody?["row_id"] as? String, "row-1")
    }

    func test_serverError_throwsSeaTableAPIError() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
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
