# iOS Scan App (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS app that scans Arztrechnungen (doctor invoices), extracts key fields via on-device OCR, and syncs directly with the existing SeaTable base ("Arztrechnungen") — no custom backend.

**Architecture:** Two components. `RechnungenKit` is a platform-agnostic Swift Package holding all business logic (models, SeaTable API client, SwiftData-backed local cache/outbox, sync engine, OCR field extraction, Keychain token storage, view models) — fully unit-testable via `swift test` without Xcode. `RechnungenScanner` is a thin SwiftUI app target (generated via XcodeGen) that depends on `RechnungenKit` and adds only what must run on-device: SwiftUI views, the VisionKit camera scanner, and app wiring.

**Tech Stack:** Swift 5.9+/6, SwiftUI, SwiftData (iOS 17+), Vision & VisionKit, Swift Concurrency (async/await, actors), XcodeGen for project generation, XCTest.

## Global Constraints

- Deployment target: iOS 17.0+ (required for SwiftData and `@Observable`).
- No custom backend in this phase — the app talks directly to the SeaTable REST API.
- SeaTable base: "Arztrechnungen". App reads/writes only the `Arztrechnungen` and `Arzt` tables; all other tables stay read-only in SeaTable itself.
- `InvoiceStatus` raw values must match the SeaTable Status option strings **exactly**: `Offen`, `Krankenkasse eingereicht`, `Krankenkasse abgeschlossen`, `Merkur eingereicht`, `Merkur abgeschlossen`, `Erledigt`.
- Auth: a single SeaTable Base API token, stored in the iOS Keychain. No per-user login.
- The app must work offline: writes go through a local outbox and sync when connectivity returns.
- No third-party dependencies — only Apple frameworks (avoids SPM dependency management entirely for this phase).
- SeaTable API endpoint paths used below follow the documented SeaTable v2.1/dtable-server API shape. **Verify exact field/endpoint names against https://api.seatable.io during Task 2/3 implementation** and adjust the private endpoint-path constants if they've changed — the client is written so this only touches a few lines.

---

## Repository Layout

```
RechnungenKit/                          # Swift Package — testable via `swift test`, no Xcode needed
  Package.swift
  Sources/RechnungenKit/
    Models/
    Networking/
    Persistence/
    Repository/
    Sync/
    OCR/
    Security/
    ViewModels/
  Tests/RechnungenKitTests/
    Support/

RechnungenScanner/                      # Xcode app target — generated via XcodeGen, needs full Xcode
  project.yml
  RechnungenScanner/
    Scan/
    Views/
```

---

### Task 1: RechnungenKit package scaffolding + domain models

**Files:**
- Create: `RechnungenKit/Package.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Models/Patient.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Models/InvoiceStatus.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Models/Provider.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Models/Invoice.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/ModelsTests.swift`

**Interfaces:**
- Produces: `Patient` (enum, raw `String`), `InvoiceStatus` (enum, raw `String`, `Comparable`, `CaseIterable`), `Provider` (struct, `Identifiable` via `UUID`, has `remoteRowID: String?`), `Invoice` (struct, `Identifiable` via `UUID`, has `remoteRowID: String?`, `providerID: UUID?`, `providerRemoteRowID: String?`, `status: InvoiceStatus`).

- [ ] **Step 1: Create the package manifest**

`RechnungenKit/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RechnungenKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RechnungenKit", targets: ["RechnungenKit"])
    ],
    targets: [
        .target(name: "RechnungenKit"),
        .testTarget(name: "RechnungenKitTests", dependencies: ["RechnungenKit"])
    ]
)
```

- [ ] **Step 2: Write the failing tests for the domain models**

`RechnungenKit/Tests/RechnungenKitTests/ModelsTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class ModelsTests: XCTestCase {
    func test_invoiceStatus_rawValuesMatchSeaTableOptionStrings() {
        XCTAssertEqual(InvoiceStatus.open.rawValue, "Offen")
        XCTAssertEqual(InvoiceStatus.submittedToPublicInsurance.rawValue, "Krankenkasse eingereicht")
        XCTAssertEqual(InvoiceStatus.publicInsuranceCompleted.rawValue, "Krankenkasse abgeschlossen")
        XCTAssertEqual(InvoiceStatus.submittedToPrivateInsurance.rawValue, "Merkur eingereicht")
        XCTAssertEqual(InvoiceStatus.privateInsuranceCompleted.rawValue, "Merkur abgeschlossen")
        XCTAssertEqual(InvoiceStatus.done.rawValue, "Erledigt")
    }

    func test_invoiceStatus_ordersAsWorkflowSequence() {
        let ordered = InvoiceStatus.allCases
        XCTAssertEqual(ordered, [
            .open,
            .submittedToPublicInsurance,
            .publicInsuranceCompleted,
            .submittedToPrivateInsurance,
            .privateInsuranceCompleted,
            .done
        ])
        XCTAssertTrue(InvoiceStatus.open < InvoiceStatus.done)
        XCTAssertFalse(InvoiceStatus.done < InvoiceStatus.open)
    }

    func test_invoice_defaultsToOpenStatusAndStableID() {
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        XCTAssertEqual(invoice.status, .open)
        XCTAssertNil(invoice.remoteRowID)
        XCTAssertNil(invoice.providerID)
    }

    func test_provider_defaultsToNilRemoteRowID() {
        let provider = Provider(name: "Dr. Mona Cooper")
        XCTAssertNil(provider.remoteRowID)
        XCTAssertEqual(provider.name, "Dr. Mona Cooper")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter ModelsTests`
Expected: FAIL — compiler errors, `Patient`/`InvoiceStatus`/`Provider`/`Invoice` don't exist yet.

- [ ] **Step 4: Implement `Patient`**

`RechnungenKit/Sources/RechnungenKit/Models/Patient.swift`:

```swift
public enum Patient: String, Codable, CaseIterable, Sendable, Hashable {
    case christian = "Christian"
    case melanie = "Melanie"
}
```

- [ ] **Step 5: Implement `InvoiceStatus`**

`RechnungenKit/Sources/RechnungenKit/Models/InvoiceStatus.swift`:

```swift
public enum InvoiceStatus: String, Codable, CaseIterable, Sendable, Comparable, Hashable {
    case open = "Offen"
    case submittedToPublicInsurance = "Krankenkasse eingereicht"
    case publicInsuranceCompleted = "Krankenkasse abgeschlossen"
    case submittedToPrivateInsurance = "Merkur eingereicht"
    case privateInsuranceCompleted = "Merkur abgeschlossen"
    case done = "Erledigt"

    public static func < (lhs: InvoiceStatus, rhs: InvoiceStatus) -> Bool {
        (Self.allCases.firstIndex(of: lhs) ?? 0) < (Self.allCases.firstIndex(of: rhs) ?? 0)
    }
}
```

- [ ] **Step 6: Implement `Provider`**

`RechnungenKit/Sources/RechnungenKit/Models/Provider.swift`:

```swift
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
```

- [ ] **Step 7: Implement `Invoice`**

`RechnungenKit/Sources/RechnungenKit/Models/Invoice.swift`:

```swift
import Foundation

public struct Invoice: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var remoteRowID: String?
    public var invoiceNumber: String
    public var amount: Decimal
    public var patient: Patient
    public var providerID: UUID?
    public var providerRemoteRowID: String?
    public var providerName: String?
    public var status: InvoiceStatus
    public var localPDFFileName: String?
    public var remoteFileURL: String?

    public init(
        id: UUID = UUID(),
        remoteRowID: String? = nil,
        invoiceNumber: String,
        amount: Decimal,
        patient: Patient,
        providerID: UUID? = nil,
        providerRemoteRowID: String? = nil,
        providerName: String? = nil,
        status: InvoiceStatus = .open,
        localPDFFileName: String? = nil,
        remoteFileURL: String? = nil
    ) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.patient = patient
        self.providerID = providerID
        self.providerRemoteRowID = providerRemoteRowID
        self.providerName = providerName
        self.status = status
        self.localPDFFileName = localPDFFileName
        self.remoteFileURL = remoteFileURL
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter ModelsTests`
Expected: PASS (4 tests)

- [ ] **Step 9: Commit**

```bash
git add RechnungenKit/Package.swift RechnungenKit/Sources/RechnungenKit/Models RechnungenKit/Tests/RechnungenKitTests/ModelsTests.swift
git commit -m "Add RechnungenKit package scaffolding and domain models"
```

---

### Task 2: SeaTableAPIClient — auth + Arztrechnungen row CRUD

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableValue.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableRow.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClientProtocol.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClient.swift`
- Create: `RechnungenKit/Tests/RechnungenKitTests/Support/URLProtocolStub.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 directly (networking layer is independent of the domain models).
- Produces: `SeaTableValue` (enum: `.string`, `.number`, `.stringArray`, `.null`, plus `Optional<SeaTableValue>.stringValue/.numberValue/.stringArrayValue` accessors), `SeaTableRow { let id: String; let fields: [String: SeaTableValue] }`, `SeaTableAPIClientProtocol` with `listRows(table:) async throws -> [SeaTableRow]`, `createRow(table:fields:) async throws -> String`, `updateRow(table:rowID:fields:) async throws`, `uploadFile(data:fileName:) async throws -> SeaTableUploadedFile`. `SeaTableAPIClient(configuration:session:)` is the concrete implementation. `SeaTableAPIError` enum for failures.

- [ ] **Step 1: Write the URL protocol stub test helper (no test yet, just infrastructure)**

`RechnungenKit/Tests/RechnungenKitTests/Support/URLProtocolStub.swift`:

```swift
import Foundation

final class URLProtocolStub: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
    }

    static var handler: ((URLRequest) -> Stub)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
```

- [ ] **Step 2: Write the failing test for `listRows` and `createRow`**

`RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift`:

```swift
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
            if request.url!.path.contains("/rows/") {
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
            if request.url!.path.contains("/rows/") && request.httpMethod == "POST" {
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
        httpBody
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter SeaTableAPIClientTests`
Expected: FAIL — `SeaTableAPIClient`, `SeaTableValue`, `SeaTableRow`, `SeaTableAPIError` don't exist yet.

- [ ] **Step 4: Implement `SeaTableValue`**

`RechnungenKit/Sources/RechnungenKit/Networking/SeaTableValue.swift`:

```swift
import Foundation

public enum SeaTableValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case stringArray([String])
    case null

    public var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .stringArray(let values): return values
        case .null: return NSNull()
        }
    }

    public init(jsonObject: Any) {
        switch jsonObject {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let values as [String]:
            self = .stringArray(values)
        default:
            self = .null
        }
    }
}

public extension Optional where Wrapped == SeaTableValue {
    var stringValue: String? {
        if case .string(let value)? = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value)? = self { return value }
        return nil
    }

    var stringArrayValue: [String]? {
        if case .stringArray(let value)? = self { return value }
        return nil
    }
}
```

- [ ] **Step 5: Implement `SeaTableRow`, `SeaTableAPIError`, `SeaTableUploadedFile`, and the protocol**

`RechnungenKit/Sources/RechnungenKit/Networking/SeaTableRow.swift`:

```swift
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
```

`RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClientProtocol.swift`:

```swift
public protocol SeaTableAPIClientProtocol: Sendable {
    func listRows(table: String) async throws -> [SeaTableRow]
    func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String
    func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws
    func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile
}
```

Add `import Foundation` at the top of that file (for `Data`).

- [ ] **Step 6: Implement `SeaTableAPIClient` (auth + row CRUD; file upload comes in Task 3)**

`RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClient.swift`:

```swift
import Foundation

public actor SeaTableAPIClient: SeaTableAPIClientProtocol {
    public struct Configuration: Sendable {
        public let apiToken: String
        public let serverBaseURL: URL

        public init(apiToken: String, serverBaseURL: URL = URL(string: "https://cloud.seatable.io")!) {
            self.apiToken = apiToken
            self.serverBaseURL = serverBaseURL
        }
    }

    struct BaseAccessToken: Decodable {
        let accessToken: String
        let dtableUUID: String
        let dtableServer: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case dtableUUID = "dtable_uuid"
            case dtableServer = "dtable_server"
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private var cachedToken: BaseAccessToken?
    private var cachedTokenFetchedAt: Date?
    private let tokenLifetime: TimeInterval = 3000

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    private func baseAccessToken() async throws -> BaseAccessToken {
        if let cachedToken, let cachedTokenFetchedAt, Date().timeIntervalSince(cachedTokenFetchedAt) < tokenLifetime {
            return cachedToken
        }
        var request = URLRequest(url: configuration.serverBaseURL.appendingPathComponent("api/v2.1/dtable/app-access-token/"))
        request.setValue("Token \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        let token = try JSONDecoder().decode(BaseAccessToken.self, from: data)
        cachedToken = token
        cachedTokenFetchedAt = Date()
        return token
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SeaTableAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SeaTableAPIError.serverError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    public func listRows(table: String) async throws -> [SeaTableRow] {
        let token = try await baseAccessToken()
        var components = URLComponents(
            url: URL(string: token.dtableServer)!.appendingPathComponent("api/v1/dtables/\(token.dtableUUID)/rows/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "table_name", value: table)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.parseRows(from: data)
    }

    public func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String {
        let token = try await baseAccessToken()
        let url = URL(string: token.dtableServer)!.appendingPathComponent("api/v1/dtables/\(token.dtableUUID)/rows/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "table_name": table,
            "row": fields.mapValues { $0.jsonObject }
        ])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rowID = json["_id"] as? String
        else {
            throw SeaTableAPIError.invalidResponse
        }
        return rowID
    }

    public func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws {
        let token = try await baseAccessToken()
        let url = URL(string: token.dtableServer)!.appendingPathComponent("api/v1/dtables/\(token.dtableUUID)/rows/")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "table_name": table,
            "row_id": rowID,
            "row": fields.mapValues { $0.jsonObject }
        ])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    private static func parseRows(from data: Data) throws -> [SeaTableRow] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawRows = json["rows"] as? [[String: Any]]
        else {
            throw SeaTableAPIError.invalidResponse
        }
        return rawRows.compactMap { raw in
            guard let id = raw["_id"] as? String else { return nil }
            var fields: [String: SeaTableValue] = [:]
            for (key, value) in raw where key != "_id" {
                fields[key] = SeaTableValue(jsonObject: value)
            }
            return SeaTableRow(id: id, fields: fields)
        }
    }
}
```

Note: `uploadFile` is added in Task 3 as an extension on this same type — leave the protocol conformance incomplete (it won't compile standalone) and proceed directly to Task 3 before running the full test target. For this task, run only the tests that don't touch `uploadFile`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter SeaTableAPIClientTests`
Expected: PASS (4 tests) — the compiler will complain that `SeaTableAPIClient` doesn't fully conform to `SeaTableAPIClientProtocol` yet (missing `uploadFile`). Add a temporary stub to make it compile for this task only:

```swift
public func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile {
    fatalError("implemented in Task 3")
}
```

Add this at the bottom of the `SeaTableAPIClient` actor body. It will be replaced with the real implementation in the next task.

- [ ] **Step 8: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Networking RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift RechnungenKit/Tests/RechnungenKitTests/Support/URLProtocolStub.swift
git commit -m "Add SeaTableAPIClient with auth and Arztrechnungen row CRUD"
```

---

### Task 3: SeaTableAPIClient — Arzt row CRUD + file upload

**Files:**
- Modify: `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClient.swift` (replace the `fatalError` stub with a real `uploadFile` implementation)
- Test: `RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift` (add upload test)

**Interfaces:**
- Consumes: `SeaTableAPIClient` from Task 2, `SeaTableUploadedFile` from Task 2.
- Produces: working `uploadFile(data:fileName:) async throws -> SeaTableUploadedFile`. Arzt-table CRUD uses the same `listRows`/`createRow` methods from Task 2 (table name `"Arzt"`, field `"Arztname"`) — no new methods needed, only new tests documenting that usage.

- [ ] **Step 1: Write the failing test for file upload**

Add to `RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift`:

```swift
    func test_uploadFile_returnsUploadedFileDescriptor() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.url!.path.contains("app-upload-link") {
                let json = #"{"upload_link":"https://upload.seatable.io/upload-api/abc","parent_path":"/asset/uuid-1/files"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.url!.absoluteString.contains("upload-api") {
                let json = #"[{"name":"invoice.pdf","size":1234}]"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            return .init(statusCode: 404, data: Data())
        }

        let uploaded = try await makeClient().uploadFile(data: Data("pdf-bytes".utf8), fileName: "invoice.pdf")

        XCTAssertEqual(uploaded.name, "invoice.pdf")
        XCTAssertEqual(uploaded.size, 1234)
        XCTAssertEqual(uploaded.url, "/asset/uuid-1/files/invoice.pdf")
    }

    func test_arztTable_createAndListUseArztnameField() async throws {
        URLProtocolStub.handler = { request in
            if request.url!.path.contains("app-access-token") {
                let json = #"{"access_token":"abc","dtable_uuid":"uuid-1","dtable_server":"https://cloud.seatable.io/"}"#
                return .init(statusCode: 200, data: Data(json.utf8))
            }
            if request.httpMethod == "POST" {
                return .init(statusCode: 200, data: Data(#"{"_id":"provider-1"}"#.utf8))
            }
            if request.url!.path.contains("/rows/") {
                let json = #"{"rows":[{"_id":"provider-1","Arztname":"Dr. Mona Cooper"}]}"#
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
```

- [ ] **Step 2: Run the tests to verify the upload test fails**

Run: `cd RechnungenKit && swift test --filter SeaTableAPIClientTests`
Expected: FAIL on `test_uploadFile_returnsUploadedFileDescriptor` — current implementation calls `fatalError`.

- [ ] **Step 3: Implement `uploadFile`**

In `RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClient.swift`, replace the `fatalError` stub with:

```swift
    public func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile {
        let token = try await baseAccessToken()

        var linkRequest = URLRequest(url: configuration.serverBaseURL.appendingPathComponent("api/v2.1/dtable/app-upload-link/"))
        linkRequest.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (linkData, linkResponse) = try await session.data(for: linkRequest)
        try Self.validate(response: linkResponse, data: linkData)
        guard
            let linkJSON = try JSONSerialization.jsonObject(with: linkData) as? [String: Any],
            let uploadLinkString = linkJSON["upload_link"] as? String,
            let parentPath = linkJSON["parent_path"] as? String,
            let uploadLink = URL(string: uploadLinkString)
        else {
            throw SeaTableAPIError.invalidResponse
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var uploadRequest = URLRequest(url: uploadLink)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"parent_dir\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(parentPath)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        uploadRequest.httpBody = body

        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
        try Self.validate(response: uploadResponse, data: uploadData)
        guard
            let uploadJSON = try JSONSerialization.jsonObject(with: uploadData) as? [[String: Any]],
            let uploaded = uploadJSON.first,
            let relativeName = uploaded["name"] as? String,
            let size = uploaded["size"] as? Int
        else {
            throw SeaTableAPIError.invalidResponse
        }
        return SeaTableUploadedFile(name: relativeName, size: size, url: "\(parentPath)/\(relativeName)")
    }
```

Remove the old `fatalError` stub entirely.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter SeaTableAPIClientTests`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Networking/SeaTableAPIClient.swift RechnungenKit/Tests/RechnungenKitTests/SeaTableAPIClientTests.swift
git commit -m "Implement SeaTable file upload and cover Arzt table CRUD"
```

---

### Task 4: SwiftData LocalStore + LocalFileStorage

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/Persistence/ProviderEntity.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Persistence/InvoiceEntity.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Persistence/OutboxEntryEntity.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Persistence/LocalStore.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Persistence/LocalFileStorage.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/LocalStoreTests.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/LocalFileStorageTests.swift`

**Interfaces:**
- Consumes: `Provider`, `Invoice`, `InvoiceStatus`, `Patient` (Task 1), `SeaTableRow`, `SeaTableValue` accessors (Task 2).
- Produces: `LocalStore` (a `@ModelActor`) with `upsertProvider(_:)`, `allProviders()`, `provider(byLocalID:)`, `upsertProviderByRemoteID(remoteRowID:name:)`, `setProviderRemoteRowID(localID:remoteRowID:)`, `upsertInvoice(_:)`, `allInvoices()`, `invoice(byLocalID:)`, `upsertInvoiceByRemoteID(row:)`, `updateInvoiceStatus(id:status:)`, `setInvoiceRemoteRowID(localID:remoteRowID:)`, `setInvoiceRemoteFileURL(localID:url:)`, `enqueueOutboxEntry(operation:targetLocalID:)`, `pendingOutboxEntries()`, `removeOutboxEntry(id:)`, `recordOutboxFailure(id:error:)`. `OutboxOperation` enum. `LocalFileStorage(directory:)` with `save(_:fileName:)` / `read(fileName:)`.

- [ ] **Step 1: Write the failing tests for `LocalStore`**

`RechnungenKit/Tests/RechnungenKitTests/LocalStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import RechnungenKit

final class LocalStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    func test_upsertProvider_thenAllProviders_roundTrips() async throws {
        let store = try makeStore()
        let provider = Provider(name: "Dr. Mona Cooper")

        try await store.upsertProvider(provider)
        let all = try await store.allProviders()

        XCTAssertEqual(all.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_upsertInvoice_thenAllInvoices_roundTrips() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)

        try await store.upsertInvoice(invoice)
        let all = try await store.allInvoices()

        XCTAssertEqual(all.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(all.first?.status, .open)
    }

    func test_updateInvoiceStatus_updatesStoredInvoice() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.updateInvoiceStatus(id: invoice.id, status: .submittedToPublicInsurance)
        let updated = try await store.invoice(byLocalID: invoice.id)

        XCTAssertEqual(updated?.status, .submittedToPublicInsurance)
    }

    func test_setInvoiceRemoteRowID_marksInvoiceAsSynced() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.setInvoiceRemoteRowID(localID: invoice.id, remoteRowID: "row-1")
        let updated = try await store.invoice(byLocalID: invoice.id)

        XCTAssertEqual(updated?.remoteRowID, "row-1")
    }

    func test_upsertInvoiceByRemoteID_linksExistingLocalProviderByRemoteRowID() async throws {
        let store = try makeStore()
        var provider = Provider(name: "Dr. Mona Cooper")
        provider.remoteRowID = "provider-1"
        try await store.upsertProvider(provider)

        let row = SeaTableRow(id: "row-1", fields: [
            "Rechnungsnummer": .string("2025-72"),
            "Betrag": .number(150.0),
            "Patient": .string("Christian"),
            "Status": .string("Offen"),
            "Arzt": .stringArray(["provider-1"])
        ])
        try await store.upsertInvoiceByRemoteID(row: row)

        let invoices = try await store.allInvoices()
        XCTAssertEqual(invoices.count, 1)
        XCTAssertEqual(invoices[0].providerID, provider.id)
        XCTAssertEqual(invoices[0].remoteRowID, "row-1")
    }

    func test_outbox_enqueueListRemove_roundTrips() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)

        try await store.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        var pending = try await store.pendingOutboxEntries()
        XCTAssertEqual(pending.count, 1)

        try await store.removeOutboxEntry(id: pending[0].id)
        pending = try await store.pendingOutboxEntries()
        XCTAssertTrue(pending.isEmpty)
    }

    func test_recordOutboxFailure_incrementsAttemptCount() async throws {
        let store = try makeStore()
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        try await store.upsertInvoice(invoice)
        try await store.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        let entryID = try await store.pendingOutboxEntries()[0].id

        try await store.recordOutboxFailure(id: entryID, error: "network down")
        let entry = try await store.pendingOutboxEntries()[0]

        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastErrorDescription, "network down")
    }
}
```

- [ ] **Step 2: Write the failing test for `LocalFileStorage`**

`RechnungenKit/Tests/RechnungenKitTests/LocalFileStorageTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class LocalFileStorageTests: XCTestCase {
    func test_saveThenRead_roundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalFileStorage(directory: directory)

        try storage.save(Data("pdf-bytes".utf8), fileName: "invoice.pdf")
        let read = try storage.read(fileName: "invoice.pdf")

        XCTAssertEqual(read, Data("pdf-bytes".utf8))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter LocalStoreTests` and `swift test --filter LocalFileStorageTests`
Expected: FAIL — types don't exist yet.

- [ ] **Step 4: Implement the SwiftData entities**

`RechnungenKit/Sources/RechnungenKit/Persistence/ProviderEntity.swift`:

```swift
import SwiftData
import Foundation

@Model
public final class ProviderEntity {
    @Attribute(.unique) public var id: UUID
    public var remoteRowID: String?
    public var name: String

    public init(id: UUID = UUID(), remoteRowID: String? = nil, name: String) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.name = name
    }
}
```

`RechnungenKit/Sources/RechnungenKit/Persistence/InvoiceEntity.swift`:

```swift
import SwiftData
import Foundation

@Model
public final class InvoiceEntity {
    @Attribute(.unique) public var id: UUID
    public var remoteRowID: String?
    public var invoiceNumber: String
    public var amount: Decimal
    public var patientRawValue: String
    public var providerID: UUID?
    public var providerRemoteRowID: String?
    public var providerName: String?
    public var statusRawValue: String
    public var localPDFFileName: String?
    public var remoteFileURL: String?

    public init(
        id: UUID = UUID(),
        remoteRowID: String? = nil,
        invoiceNumber: String,
        amount: Decimal,
        patientRawValue: String,
        providerID: UUID? = nil,
        providerRemoteRowID: String? = nil,
        providerName: String? = nil,
        statusRawValue: String,
        localPDFFileName: String? = nil,
        remoteFileURL: String? = nil
    ) {
        self.id = id
        self.remoteRowID = remoteRowID
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.patientRawValue = patientRawValue
        self.providerID = providerID
        self.providerRemoteRowID = providerRemoteRowID
        self.providerName = providerName
        self.statusRawValue = statusRawValue
        self.localPDFFileName = localPDFFileName
        self.remoteFileURL = remoteFileURL
    }
}
```

`RechnungenKit/Sources/RechnungenKit/Persistence/OutboxEntryEntity.swift`:

```swift
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
```

- [ ] **Step 5: Implement `LocalStore`**

`RechnungenKit/Sources/RechnungenKit/Persistence/LocalStore.swift`:

```swift
import SwiftData
import Foundation

@ModelActor
public actor LocalStore {
    public func upsertProvider(_ provider: Provider) throws {
        let targetID = provider.id
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.remoteRowID = provider.remoteRowID
            existing.name = provider.name
        } else {
            modelContext.insert(ProviderEntity(id: provider.id, remoteRowID: provider.remoteRowID, name: provider.name))
        }
        try modelContext.save()
    }

    public func allProviders() throws -> [Provider] {
        try modelContext.fetch(FetchDescriptor<ProviderEntity>()).map {
            Provider(id: $0.id, remoteRowID: $0.remoteRowID, name: $0.name)
        }
    }

    public func provider(byLocalID id: UUID) throws -> Provider? {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return Provider(id: entity.id, remoteRowID: entity.remoteRowID, name: entity.name)
    }

    public func upsertProviderByRemoteID(remoteRowID: String, name: String) throws {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.remoteRowID == remoteRowID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = name
        } else {
            modelContext.insert(ProviderEntity(remoteRowID: remoteRowID, name: name))
        }
        try modelContext.save()
    }

    public func setProviderRemoteRowID(localID: UUID, remoteRowID: String) throws {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteRowID = remoteRowID
        try modelContext.save()

        let invoiceDescriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.providerID == localID })
        for invoice in try modelContext.fetch(invoiceDescriptor) {
            invoice.providerRemoteRowID = remoteRowID
        }
        try modelContext.save()
    }

    public func upsertInvoice(_ invoice: Invoice) throws {
        let targetID = invoice.id
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            apply(invoice, to: existing)
        } else {
            modelContext.insert(makeEntity(from: invoice))
        }
        try modelContext.save()
    }

    public func allInvoices() throws -> [Invoice] {
        try modelContext.fetch(FetchDescriptor<InvoiceEntity>()).map(makeInvoice(from:))
    }

    public func invoice(byLocalID id: UUID) throws -> Invoice? {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return makeInvoice(from: entity)
    }

    public func upsertInvoiceByRemoteID(row: SeaTableRow) throws {
        let remoteID = row.id
        let invoiceNumber = row.fields["Rechnungsnummer"].stringValue ?? ""
        let amount = row.fields["Betrag"].numberValue ?? 0
        let patientRaw = row.fields["Patient"].stringValue ?? Patient.christian.rawValue
        let statusRaw = row.fields["Status"].stringValue ?? InvoiceStatus.open.rawValue
        let providerRemoteRowID = row.fields["Arzt"].stringArrayValue?.first

        var providerLocalID: UUID?
        if let providerRemoteRowID {
            let providerDescriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.remoteRowID == providerRemoteRowID })
            providerLocalID = try modelContext.fetch(providerDescriptor).first?.id
        }

        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.remoteRowID == remoteID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.invoiceNumber = invoiceNumber
            existing.amount = Decimal(amount)
            existing.patientRawValue = patientRaw
            existing.statusRawValue = statusRaw
            existing.providerID = providerLocalID
            existing.providerRemoteRowID = providerRemoteRowID
        } else {
            modelContext.insert(InvoiceEntity(
                remoteRowID: remoteID,
                invoiceNumber: invoiceNumber,
                amount: Decimal(amount),
                patientRawValue: patientRaw,
                providerID: providerLocalID,
                providerRemoteRowID: providerRemoteRowID,
                statusRawValue: statusRaw
            ))
        }
        try modelContext.save()
    }

    public func updateInvoiceStatus(id: UUID, status: InvoiceStatus) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.statusRawValue = status.rawValue
        try modelContext.save()
    }

    public func setInvoiceRemoteRowID(localID: UUID, remoteRowID: String) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteRowID = remoteRowID
        try modelContext.save()
    }

    public func setInvoiceRemoteFileURL(localID: UUID, url: String) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteFileURL = url
        try modelContext.save()
    }

    public func enqueueOutboxEntry(operation: OutboxOperation, targetLocalID: UUID) throws {
        modelContext.insert(OutboxEntryEntity(operationRawValue: operation.rawValue, targetLocalID: targetLocalID))
        try modelContext.save()
    }

    public func pendingOutboxEntries() throws -> [OutboxEntryEntity] {
        try modelContext.fetch(FetchDescriptor<OutboxEntryEntity>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    public func removeOutboxEntry(id: UUID) throws {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func recordOutboxFailure(id: UUID, error: String) throws {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.attemptCount += 1
        entity.lastAttemptAt = Date()
        entity.lastErrorDescription = error
        try modelContext.save()
    }

    private func makeEntity(from invoice: Invoice) -> InvoiceEntity {
        InvoiceEntity(
            id: invoice.id,
            remoteRowID: invoice.remoteRowID,
            invoiceNumber: invoice.invoiceNumber,
            amount: invoice.amount,
            patientRawValue: invoice.patient.rawValue,
            providerID: invoice.providerID,
            providerRemoteRowID: invoice.providerRemoteRowID,
            providerName: invoice.providerName,
            statusRawValue: invoice.status.rawValue,
            localPDFFileName: invoice.localPDFFileName,
            remoteFileURL: invoice.remoteFileURL
        )
    }

    private func apply(_ invoice: Invoice, to entity: InvoiceEntity) {
        entity.remoteRowID = invoice.remoteRowID
        entity.invoiceNumber = invoice.invoiceNumber
        entity.amount = invoice.amount
        entity.patientRawValue = invoice.patient.rawValue
        entity.providerID = invoice.providerID
        entity.providerRemoteRowID = invoice.providerRemoteRowID
        entity.providerName = invoice.providerName
        entity.statusRawValue = invoice.status.rawValue
        entity.localPDFFileName = invoice.localPDFFileName
        entity.remoteFileURL = invoice.remoteFileURL
    }

    private func makeInvoice(from entity: InvoiceEntity) -> Invoice {
        Invoice(
            id: entity.id,
            remoteRowID: entity.remoteRowID,
            invoiceNumber: entity.invoiceNumber,
            amount: entity.amount,
            patient: Patient(rawValue: entity.patientRawValue) ?? .christian,
            providerID: entity.providerID,
            providerRemoteRowID: entity.providerRemoteRowID,
            providerName: entity.providerName,
            status: InvoiceStatus(rawValue: entity.statusRawValue) ?? .open,
            localPDFFileName: entity.localPDFFileName,
            remoteFileURL: entity.remoteFileURL
        )
    }
}
```

- [ ] **Step 6: Implement `LocalFileStorage`**

`RechnungenKit/Sources/RechnungenKit/Persistence/LocalFileStorage.swift`:

```swift
import Foundation

public struct LocalFileStorage: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ data: Data, fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName))
    }

    public func read(fileName: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(fileName))
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter LocalStoreTests` and `swift test --filter LocalFileStorageTests`
Expected: PASS (7 + 1 tests)

- [ ] **Step 8: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Persistence RechnungenKit/Tests/RechnungenKitTests/LocalStoreTests.swift RechnungenKit/Tests/RechnungenKitTests/LocalFileStorageTests.swift
git commit -m "Add SwiftData LocalStore and LocalFileStorage"
```

---

### Task 5: InvoiceRepository

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/Repository/InvoiceRepositoryProtocol.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Repository/SeaTableInvoiceRepository.swift`
- Create: `RechnungenKit/Tests/RechnungenKitTests/Support/MockSeaTableAPIClient.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/SeaTableInvoiceRepositoryTests.swift`

**Interfaces:**
- Consumes: `SeaTableAPIClientProtocol` (Task 2/3), `LocalStore` (Task 4), `Provider`/`Invoice`/`InvoiceStatus` (Task 1).
- Produces: `InvoiceRepositoryProtocol` with `refresh() async throws`, `invoices() async throws -> [Invoice]`, `providers() async throws -> [Provider]`, `createProvider(name:) async throws -> Provider`, `createInvoice(_:) async throws`, `updateStatus(invoiceID:newStatus:) async throws`. `SeaTableInvoiceRepository` is the concrete implementation used by Tasks 9/10.

- [ ] **Step 1: Write the mock API client test double**

`RechnungenKit/Tests/RechnungenKitTests/Support/MockSeaTableAPIClient.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing tests for `SeaTableInvoiceRepository`**

`RechnungenKit/Tests/RechnungenKitTests/SeaTableInvoiceRepositoryTests.swift`:

```swift
import XCTest
import SwiftData
@testable import RechnungenKit

final class SeaTableInvoiceRepositoryTests: XCTestCase {
    private func makeLocalStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    func test_refresh_pullsProvidersAndInvoicesIntoLocalCache() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setRows(table: "Arzt", rows: [
            SeaTableRow(id: "provider-1", fields: ["Arztname": .string("Dr. Mona Cooper")])
        ])
        await apiClient.setRows(table: "Arztrechnungen", rows: [
            SeaTableRow(id: "row-1", fields: [
                "Rechnungsnummer": .string("2025-72"),
                "Betrag": .number(150.0),
                "Patient": .string("Christian"),
                "Status": .string("Offen"),
                "Arzt": .stringArray(["provider-1"])
            ])
        ])
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: try makeLocalStore())

        try await repository.refresh()
        let invoices = try await repository.invoices()
        let providers = try await repository.providers()

        XCTAssertEqual(providers.map(\.name), ["Dr. Mona Cooper"])
        XCTAssertEqual(invoices.map(\.invoiceNumber), ["2025-72"])
        XCTAssertEqual(invoices.first?.providerID, providers.first?.id)
    }

    func test_createInvoice_persistsLocallyAndEnqueuesOutbox() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie, localPDFFileName: "scan.pdf")

        try await repository.createInvoice(invoice)

        let stored = try await localStore.invoice(byLocalID: invoice.id)
        XCTAssertNotNil(stored)
        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertEqual(Set(pending.map(\.operationRawValue)), [
            OutboxOperation.createInvoice.rawValue,
            OutboxOperation.uploadInvoiceFile.rawValue
        ])
    }

    func test_updateStatus_updatesLocalStoreAndEnqueuesOutbox() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)

        try await repository.updateStatus(invoiceID: invoice.id, newStatus: .submittedToPublicInsurance)

        let stored = try await localStore.invoice(byLocalID: invoice.id)
        XCTAssertEqual(stored?.status, .submittedToPublicInsurance)
        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertTrue(pending.contains { $0.operationRawValue == OutboxOperation.updateInvoiceStatus.rawValue })
    }
}
```

Add a small test-only helper to the mock so tests can set canned rows without exposing mutable state races across actor isolation:

Append to `MockSeaTableAPIClient.swift`:

```swift
extension MockSeaTableAPIClient {
    func setRows(table: String, rows: [SeaTableRow]) {
        rowsByTable[table] = rows
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter SeaTableInvoiceRepositoryTests`
Expected: FAIL — `InvoiceRepositoryProtocol`/`SeaTableInvoiceRepository` don't exist yet.

- [ ] **Step 4: Implement the protocol**

`RechnungenKit/Sources/RechnungenKit/Repository/InvoiceRepositoryProtocol.swift`:

```swift
public protocol InvoiceRepositoryProtocol: Sendable {
    func refresh() async throws
    func invoices() async throws -> [Invoice]
    func providers() async throws -> [Provider]
    func createProvider(name: String) async throws -> Provider
    func createInvoice(_ invoice: Invoice) async throws
    func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws
}
```

Add `import Foundation` at the top (for `UUID`).

- [ ] **Step 5: Implement `SeaTableInvoiceRepository`**

`RechnungenKit/Sources/RechnungenKit/Repository/SeaTableInvoiceRepository.swift`:

```swift
import Foundation

public actor SeaTableInvoiceRepository: InvoiceRepositoryProtocol {
    private let apiClient: SeaTableAPIClientProtocol
    private let localStore: LocalStore

    public init(apiClient: SeaTableAPIClientProtocol, localStore: LocalStore) {
        self.apiClient = apiClient
        self.localStore = localStore
    }

    public func refresh() async throws {
        let providerRows = try await apiClient.listRows(table: "Arzt")
        for row in providerRows {
            guard let name = row.fields["Arztname"].stringValue else { continue }
            try await localStore.upsertProviderByRemoteID(remoteRowID: row.id, name: name)
        }

        let invoiceRows = try await apiClient.listRows(table: "Arztrechnungen")
        for row in invoiceRows {
            try await localStore.upsertInvoiceByRemoteID(row: row)
        }
    }

    public func invoices() async throws -> [Invoice] {
        try await localStore.allInvoices()
    }

    public func providers() async throws -> [Provider] {
        try await localStore.allProviders()
    }

    public func createProvider(name: String) async throws -> Provider {
        let provider = Provider(name: name)
        try await localStore.upsertProvider(provider)
        try await localStore.enqueueOutboxEntry(operation: .createProvider, targetLocalID: provider.id)
        return provider
    }

    public func createInvoice(_ invoice: Invoice) async throws {
        try await localStore.upsertInvoice(invoice)
        try await localStore.enqueueOutboxEntry(operation: .createInvoice, targetLocalID: invoice.id)
        if invoice.localPDFFileName != nil {
            try await localStore.enqueueOutboxEntry(operation: .uploadInvoiceFile, targetLocalID: invoice.id)
        }
    }

    public func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws {
        try await localStore.updateInvoiceStatus(id: invoiceID, status: newStatus)
        try await localStore.enqueueOutboxEntry(operation: .updateInvoiceStatus, targetLocalID: invoiceID)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter SeaTableInvoiceRepositoryTests`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Repository RechnungenKit/Tests/RechnungenKitTests/SeaTableInvoiceRepositoryTests.swift RechnungenKit/Tests/RechnungenKitTests/Support/MockSeaTableAPIClient.swift
git commit -m "Add InvoiceRepository bridging SeaTable API and local cache"
```

---

### Task 6: SyncEngine

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/Sync/SyncEngine.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: `SeaTableAPIClientProtocol`, `LocalStore`, `LocalFileStorage`, `OutboxOperation`, `OutboxEntryEntity`.
- Produces: `SyncEngine(apiClient:localStore:fileStorage:)` with `processOutbox() async`. `SyncError` enum.

- [ ] **Step 1: Write the failing tests**

`RechnungenKit/Tests/RechnungenKitTests/SyncEngineTests.swift`:

```swift
import XCTest
import SwiftData
@testable import RechnungenKit

final class SyncEngineTests: XCTestCase {
    private func makeLocalStore() throws -> LocalStore {
        let schema = Schema([ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return LocalStore(modelContainer: container)
    }

    private func makeFileStorage() -> LocalFileStorage {
        LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func test_processOutbox_createsProviderThenInvoiceThenUploadsFile() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setNextCreatedRowID("remote-provider-1")
        let localStore = try makeLocalStore()
        let fileStorage = makeFileStorage()
        try fileStorage.save(Data("pdf-bytes".utf8), fileName: "scan.pdf")

        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let provider = try await repository.createProvider(name: "Dr. Mona Cooper")
        let invoice = Invoice(
            invoiceNumber: "2025-90",
            amount: 55,
            patient: .melanie,
            providerID: provider.id,
            localPDFFileName: "scan.pdf"
        )
        try await repository.createInvoice(invoice)

        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: fileStorage)
        await engine.processOutbox()
        await apiClient.setNextCreatedRowID("remote-invoice-1")
        await engine.processOutbox()
        await engine.processOutbox()

        let syncedProvider = try await localStore.provider(byLocalID: provider.id)
        let syncedInvoice = try await localStore.invoice(byLocalID: invoice.id)
        let pending = try await localStore.pendingOutboxEntries()

        XCTAssertEqual(syncedProvider?.remoteRowID, "remote-provider-1")
        XCTAssertEqual(syncedInvoice?.remoteRowID, "remote-invoice-1")
        XCTAssertNotNil(syncedInvoice?.remoteFileURL)
        XCTAssertTrue(pending.isEmpty)
    }

    func test_processOutbox_leavesEntryPendingOnFailureAndRecordsError() async throws {
        let apiClient = MockSeaTableAPIClient()
        await apiClient.setErrorToThrow(SeaTableAPIError.serverError(statusCode: 500, body: "boom"))
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)

        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: makeFileStorage())
        await engine.processOutbox()

        let pending = try await localStore.pendingOutboxEntries()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].attemptCount, 1)
        XCTAssertNotNil(pending[0].lastErrorDescription)
    }

    func test_processOutbox_updatesStatusOnRemote() async throws {
        let apiClient = MockSeaTableAPIClient()
        let localStore = try makeLocalStore()
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let invoice = Invoice(invoiceNumber: "2025-90", amount: 55, patient: .melanie)
        try await repository.createInvoice(invoice)
        let engine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: makeFileStorage())
        await engine.processOutbox() // syncs the create first

        try await repository.updateStatus(invoiceID: invoice.id, newStatus: .done)
        await engine.processOutbox()

        let updates = await apiClient.updatedRows
        XCTAssertTrue(updates.contains { $0.fields["Status"] == .string("Erledigt") })
    }
}
```

Add the two missing test-only mutators to the mock:

Append to `RechnungenKit/Tests/RechnungenKitTests/Support/MockSeaTableAPIClient.swift`:

```swift
extension MockSeaTableAPIClient {
    func setNextCreatedRowID(_ id: String) {
        nextCreatedRowID = id
    }

    func setErrorToThrow(_ error: Error?) {
        errorToThrow = error
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter SyncEngineTests`
Expected: FAIL — `SyncEngine` doesn't exist yet.

- [ ] **Step 3: Implement `SyncEngine`**

`RechnungenKit/Sources/RechnungenKit/Sync/SyncEngine.swift`:

```swift
import Foundation

public enum SyncError: Error, Equatable {
    case dependencyNotReady
}

public actor SyncEngine {
    private let apiClient: SeaTableAPIClientProtocol
    private let localStore: LocalStore
    private let fileStorage: LocalFileStorage

    public init(apiClient: SeaTableAPIClientProtocol, localStore: LocalStore, fileStorage: LocalFileStorage) {
        self.apiClient = apiClient
        self.localStore = localStore
        self.fileStorage = fileStorage
    }

    public func processOutbox() async {
        guard let entries = try? await localStore.pendingOutboxEntries() else { return }
        for entry in entries {
            await process(entry: entry)
        }
    }

    private func process(entry: OutboxEntryEntity) async {
        do {
            switch OutboxOperation(rawValue: entry.operationRawValue) {
            case .createProvider:
                try await syncCreateProvider(localID: entry.targetLocalID)
            case .createInvoice:
                try await syncCreateInvoice(localID: entry.targetLocalID)
            case .updateInvoiceStatus:
                try await syncUpdateStatus(localID: entry.targetLocalID)
            case .uploadInvoiceFile:
                try await syncUploadFile(localID: entry.targetLocalID)
            case .none:
                break
            }
            try await localStore.removeOutboxEntry(id: entry.id)
        } catch {
            try? await localStore.recordOutboxFailure(id: entry.id, error: String(describing: error))
        }
    }

    private func syncCreateProvider(localID: UUID) async throws {
        guard let provider = try await localStore.provider(byLocalID: localID), provider.remoteRowID == nil else { return }
        let rowID = try await apiClient.createRow(table: "Arzt", fields: ["Arztname": .string(provider.name)])
        try await localStore.setProviderRemoteRowID(localID: localID, remoteRowID: rowID)
    }

    private func syncCreateInvoice(localID: UUID) async throws {
        guard let invoice = try await localStore.invoice(byLocalID: localID), invoice.remoteRowID == nil else { return }

        var providerRemoteRowID = invoice.providerRemoteRowID
        if providerRemoteRowID == nil, let providerID = invoice.providerID {
            providerRemoteRowID = try await localStore.provider(byLocalID: providerID)?.remoteRowID
            guard providerRemoteRowID != nil else {
                throw SyncError.dependencyNotReady
            }
        }

        var fields: [String: SeaTableValue] = [
            "Rechnungsnummer": .string(invoice.invoiceNumber),
            "Betrag": .number((invoice.amount as NSDecimalNumber).doubleValue),
            "Patient": .string(invoice.patient.rawValue),
            "Status": .string(invoice.status.rawValue)
        ]
        if let providerRemoteRowID {
            fields["Arzt"] = .stringArray([providerRemoteRowID])
        }
        let rowID = try await apiClient.createRow(table: "Arztrechnungen", fields: fields)
        try await localStore.setInvoiceRemoteRowID(localID: localID, remoteRowID: rowID)
    }

    private func syncUpdateStatus(localID: UUID) async throws {
        guard
            let invoice = try await localStore.invoice(byLocalID: localID),
            let remoteRowID = invoice.remoteRowID
        else {
            throw SyncError.dependencyNotReady
        }
        try await apiClient.updateRow(
            table: "Arztrechnungen",
            rowID: remoteRowID,
            fields: ["Status": .string(invoice.status.rawValue)]
        )
    }

    private func syncUploadFile(localID: UUID) async throws {
        guard
            let invoice = try await localStore.invoice(byLocalID: localID),
            let remoteRowID = invoice.remoteRowID,
            let fileName = invoice.localPDFFileName
        else {
            throw SyncError.dependencyNotReady
        }
        let data = try fileStorage.read(fileName: fileName)
        let uploaded = try await apiClient.uploadFile(data: data, fileName: fileName)
        try await apiClient.updateRow(
            table: "Arztrechnungen",
            rowID: remoteRowID,
            fields: ["Arztrechnung": .stringArray([uploaded.url])]
        )
        try await localStore.setInvoiceRemoteFileURL(localID: localID, url: uploaded.url)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter SyncEngineTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Sync RechnungenKit/Tests/RechnungenKitTests/SyncEngineTests.swift RechnungenKit/Tests/RechnungenKitTests/Support/MockSeaTableAPIClient.swift
git commit -m "Add SyncEngine to process the offline outbox against SeaTable"
```

---

### Task 7: OCR — InvoiceFieldExtractor + TextRecognizer

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/OCR/ExtractedInvoiceFields.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/OCR/InvoiceFieldExtractor.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/OCR/TextRecognizer.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/InvoiceFieldExtractorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ExtractedInvoiceFields { var invoiceNumber: String?; var amount: Decimal?; var date: Date? }`, `InvoiceFieldExtractor().extract(from: [String]) -> ExtractedInvoiceFields`, `TextRecognizer().recognizeLines(in: CGImage) async throws -> [String]` (used by Task 14, not unit tested here — see note in Step 5).

- [ ] **Step 1: Write the failing tests for `InvoiceFieldExtractor`**

`RechnungenKit/Tests/RechnungenKitTests/InvoiceFieldExtractorTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class InvoiceFieldExtractorTests: XCTestCase {
    func test_extract_findsInvoiceNumberAmountAndDate() {
        let lines = [
            "Dr. Mona Cooper",
            "Rechnungsnummer: 2025-72",
            "Datum: 12.08.2025",
            "Gesamtbetrag: 150,00 €"
        ]

        let result = InvoiceFieldExtractor().extract(from: lines)

        XCTAssertEqual(result.invoiceNumber, "2025-72")
        XCTAssertEqual(result.amount, Decimal(string: "150.00"))
        XCTAssertNotNil(result.date)
    }

    func test_extract_handlesMissingFieldsGracefully() {
        let result = InvoiceFieldExtractor().extract(from: ["Irgendein Text ohne Struktur"])

        XCTAssertNil(result.invoiceNumber)
        XCTAssertNil(result.amount)
        XCTAssertNil(result.date)
    }

    func test_extract_parsesAmountWithThousandsSeparator() {
        let result = InvoiceFieldExtractor().extract(from: ["Betrag: 1.250,50 EUR"])

        XCTAssertEqual(result.amount, Decimal(string: "1250.50"))
    }

    func test_extract_usesFirstMatchWhenMultipleCandidateLinesExist() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Rechnungsnr. 2025/097",
            "Referenz Rechnungsnummer: 2025/108"
        ])

        XCTAssertEqual(result.invoiceNumber, "2025/097")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter InvoiceFieldExtractorTests`
Expected: FAIL — types don't exist yet.

- [ ] **Step 3: Implement `ExtractedInvoiceFields`**

`RechnungenKit/Sources/RechnungenKit/OCR/ExtractedInvoiceFields.swift`:

```swift
import Foundation

public struct ExtractedInvoiceFields: Equatable, Sendable {
    public var invoiceNumber: String?
    public var amount: Decimal?
    public var date: Date?

    public init(invoiceNumber: String? = nil, amount: Decimal? = nil, date: Date? = nil) {
        self.invoiceNumber = invoiceNumber
        self.amount = amount
        self.date = date
    }
}
```

- [ ] **Step 4: Implement `InvoiceFieldExtractor`**

`RechnungenKit/Sources/RechnungenKit/OCR/InvoiceFieldExtractor.swift`:

```swift
import Foundation

public struct InvoiceFieldExtractor: Sendable {
    public init() {}

    public func extract(from lines: [String]) -> ExtractedInvoiceFields {
        var result = ExtractedInvoiceFields()
        for line in lines {
            if result.invoiceNumber == nil, let value = Self.invoiceNumber(in: line) {
                result.invoiceNumber = value
            }
            if result.amount == nil, let value = Self.amount(in: line) {
                result.amount = value
            }
            if result.date == nil, let value = Self.date(in: line) {
                result.date = value
            }
        }
        return result
    }

    private static func invoiceNumber(in line: String) -> String? {
        guard let keywordRange = line.range(
            of: #"Rechnungs(nummer|nr\.?)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let remainder = line[keywordRange.upperBound...]
        guard let valueRange = remainder.range(of: #"[A-Za-z0-9\-/]+"#, options: .regularExpression) else {
            return nil
        }
        return String(remainder[valueRange])
    }

    private static func amount(in line: String) -> Decimal? {
        guard let range = line.range(of: #"\d{1,3}(\.\d{3})*,\d{2}|\d+,\d{2}"#, options: .regularExpression) else {
            return nil
        }
        let normalized = String(line[range])
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    private static func date(in line: String) -> Date? {
        guard let range = line.range(of: #"\d{1,2}\.\d{1,2}\.\d{2,4}"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(line[range])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = raw.count > 8 ? "dd.MM.yyyy" : "dd.MM.yy"
        return formatter.date(from: raw)
    }
}
```

- [ ] **Step 5: Implement `TextRecognizer` (Vision wrapper, no automated test)**

`RechnungenKit/Sources/RechnungenKit/OCR/TextRecognizer.swift`:

```swift
import Vision
import CoreGraphics

public struct TextRecognizer: Sendable {
    public init() {}

    public func recognizeLines(in cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: observations.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

No automated test for `TextRecognizer`: real OCR accuracy against camera-quality scans is validated in the manual end-to-end checklist (Task 18), consistent with the spec's testing section. `InvoiceFieldExtractor`, which carries the actual parsing logic, is fully covered above.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter InvoiceFieldExtractorTests`
Expected: PASS (4 tests)

- [ ] **Step 7: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/OCR RechnungenKit/Tests/RechnungenKitTests/InvoiceFieldExtractorTests.swift
git commit -m "Add OCR field extraction and Vision text recognition wrapper"
```

---

### Task 8: KeychainService

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/Security/KeychainServiceProtocol.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/Security/KeychainService.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/KeychainServiceTests.swift`

**Interfaces:**
- Produces: `KeychainServiceProtocol` with `saveAPIToken(_:) throws`, `readAPIToken() throws -> String?`, `deleteAPIToken() throws`. `KeychainService(service:account:)` concrete implementation. `KeychainError` enum.

- [ ] **Step 1: Write the failing tests**

`RechnungenKit/Tests/RechnungenKitTests/KeychainServiceTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class KeychainServiceTests: XCTestCase {
    private var keychain: KeychainService!

    override func setUp() {
        super.setUp()
        keychain = KeychainService(service: "test.rechnungenscanner", account: "seatable-api-token")
    }

    override func tearDown() {
        try? keychain.deleteAPIToken()
        super.tearDown()
    }

    func test_saveThenRead_roundTrips() throws {
        try keychain.saveAPIToken("secret-token")

        XCTAssertEqual(try keychain.readAPIToken(), "secret-token")
    }

    func test_readWithoutSaving_returnsNil() throws {
        XCTAssertNil(try keychain.readAPIToken())
    }

    func test_save_overwritesPreviousValue() throws {
        try keychain.saveAPIToken("first")
        try keychain.saveAPIToken("second")

        XCTAssertEqual(try keychain.readAPIToken(), "second")
    }

    func test_delete_removesStoredValue() throws {
        try keychain.saveAPIToken("secret-token")
        try keychain.deleteAPIToken()

        XCTAssertNil(try keychain.readAPIToken())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter KeychainServiceTests`
Expected: FAIL — `KeychainService` doesn't exist yet.

- [ ] **Step 3: Implement the protocol and error type**

`RechnungenKit/Sources/RechnungenKit/Security/KeychainServiceProtocol.swift`:

```swift
public protocol KeychainServiceProtocol: Sendable {
    func saveAPIToken(_ token: String) throws
    func readAPIToken() throws -> String?
    func deleteAPIToken() throws
}

public enum KeychainError: Error, Equatable {
    case unhandled(status: Int32)
}
```

- [ ] **Step 4: Implement `KeychainService`**

`RechnungenKit/Sources/RechnungenKit/Security/KeychainService.swift`:

```swift
import Foundation
import Security

public struct KeychainService: KeychainServiceProtocol {
    private let service: String
    private let account: String

    public init(service: String = "com.medicalbilltracker.rechnungenscanner", account: String = "seatable-api-token") {
        self.service = service
        self.account = account
    }

    public func saveAPIToken(_ token: String) throws {
        try deleteAPIToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func readAPIToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteAPIToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter KeychainServiceTests`
Expected: PASS (4 tests). If the test process lacks Keychain entitlements in some CI environments, `SecItemAdd` returns `errSecMissingEntitlement` — if that happens, note it in the task's commit message and re-verify on-device in Task 18; the Keychain-backed implementation itself is still correct for a real app target.

- [ ] **Step 6: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/Security RechnungenKit/Tests/RechnungenKitTests/KeychainServiceTests.swift
git commit -m "Add Keychain-backed SeaTable API token storage"
```

---

### Task 9: ScanViewModel + ProviderPickerViewModel

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/ViewModels/ProviderPickerViewModel.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/ViewModels/ScanViewModel.swift`
- Create: `RechnungenKit/Tests/RechnungenKitTests/Support/MockInvoiceRepository.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/ScanViewModelTests.swift`

**Interfaces:**
- Consumes: `InvoiceRepositoryProtocol` (Task 5), `LocalFileStorage` (Task 4), `ExtractedInvoiceFields` (Task 7), `Provider`/`Invoice`/`Patient`/`InvoiceStatus` (Task 1).
- Produces: `ProviderPickerViewModel(repository:)` with `providers: [Provider]`, `load() async`, `createProvider(name:) async -> Provider?`. `ScanViewModel(repository:fileStorage:)` with bindable form fields, `applyExtractedFields(_:)`, `save(pdfData:) async`, `didSave: Bool`.

- [ ] **Step 1: Write the mock repository test double**

`RechnungenKit/Tests/RechnungenKitTests/Support/MockInvoiceRepository.swift`:

```swift
import Foundation
@testable import RechnungenKit

actor MockInvoiceRepository: InvoiceRepositoryProtocol {
    var storedInvoices: [Invoice] = []
    var storedProviders: [Provider] = []
    var statusUpdates: [(invoiceID: UUID, status: InvoiceStatus)] = []
    var errorToThrow: Error?

    func refresh() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func invoices() async throws -> [Invoice] {
        if let errorToThrow { throw errorToThrow }
        return storedInvoices
    }

    func providers() async throws -> [Provider] {
        if let errorToThrow { throw errorToThrow }
        return storedProviders
    }

    func createProvider(name: String) async throws -> Provider {
        if let errorToThrow { throw errorToThrow }
        let provider = Provider(name: name)
        storedProviders.append(provider)
        return provider
    }

    func createInvoice(_ invoice: Invoice) async throws {
        if let errorToThrow { throw errorToThrow }
        storedInvoices.append(invoice)
    }

    func updateStatus(invoiceID: UUID, newStatus: InvoiceStatus) async throws {
        if let errorToThrow { throw errorToThrow }
        statusUpdates.append((invoiceID, newStatus))
        if let index = storedInvoices.firstIndex(where: { $0.id == invoiceID }) {
            storedInvoices[index].status = newStatus
        }
    }
}

extension MockInvoiceRepository {
    func setProviders(_ providers: [Provider]) {
        storedProviders = providers
    }

    func setInvoices(_ invoices: [Invoice]) {
        storedInvoices = invoices
    }

    func setError(_ error: Error?) {
        errorToThrow = error
    }
}
```

- [ ] **Step 2: Write the failing tests**

`RechnungenKit/Tests/RechnungenKitTests/ScanViewModelTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class ScanViewModelTests: XCTestCase {
    func test_providerPickerViewModel_load_populatesProviders() async {
        let repository = MockInvoiceRepository()
        await repository.setProviders([Provider(name: "Dr. Mona Cooper")])
        let viewModel = ProviderPickerViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.providers.map(\.name), ["Dr. Mona Cooper"])
    }

    func test_providerPickerViewModel_createProvider_appendsAndReturnsProvider() async {
        let repository = MockInvoiceRepository()
        let viewModel = ProviderPickerViewModel(repository: repository)

        let created = await viewModel.createProvider(name: "Dr. Reuter")

        XCTAssertEqual(created?.name, "Dr. Reuter")
        XCTAssertEqual(viewModel.providers.map(\.name), ["Dr. Reuter"])
    }

    func test_scanViewModel_applyExtractedFields_prefillsForm() {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)

        viewModel.applyExtractedFields(ExtractedInvoiceFields(invoiceNumber: "2025-72", amount: 150, date: nil))

        XCTAssertEqual(viewModel.invoiceNumber, "2025-72")
        XCTAssertEqual(viewModel.amountText, "150")
    }

    func test_scanViewModel_save_createsInvoiceAndSetsDidSave() async {
        let repository = MockInvoiceRepository()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileStorage = LocalFileStorage(directory: directory)
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.invoiceNumber = "2025-72"
        viewModel.amountText = "150,00"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertTrue(viewModel.didSave)
        let stored = await repository.storedInvoices
        XCTAssertEqual(stored.first?.invoiceNumber, "2025-72")
        XCTAssertEqual(stored.first?.amount, Decimal(string: "150.00"))
    }

    func test_scanViewModel_save_withInvalidAmount_setsErrorAndDoesNotSave() async {
        let repository = MockInvoiceRepository()
        let fileStorage = LocalFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = ScanViewModel(repository: repository, fileStorage: fileStorage)
        viewModel.amountText = "nicht-numerisch"

        await viewModel.save(pdfData: Data("pdf-bytes".utf8))

        XCTAssertFalse(viewModel.didSave)
        XCTAssertNotNil(viewModel.errorMessage)
        let stored = await repository.storedInvoices
        XCTAssertTrue(stored.isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter ScanViewModelTests`
Expected: FAIL — view models don't exist yet.

- [ ] **Step 4: Implement `ProviderPickerViewModel`**

`RechnungenKit/Sources/RechnungenKit/ViewModels/ProviderPickerViewModel.swift`:

```swift
import Observation

@Observable
public final class ProviderPickerViewModel {
    public private(set) var providers: [Provider] = []
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(repository: InvoiceRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        do {
            providers = try await repository.providers()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @discardableResult
    public func createProvider(name: String) async -> Provider? {
        do {
            let provider = try await repository.createProvider(name: name)
            providers.append(provider)
            return provider
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}
```

- [ ] **Step 5: Implement `ScanViewModel`**

`RechnungenKit/Sources/RechnungenKit/ViewModels/ScanViewModel.swift`:

```swift
import Observation
import Foundation

@Observable
public final class ScanViewModel {
    public var invoiceNumber: String = ""
    public var amountText: String = ""
    public var patient: Patient = .christian
    public var selectedProviderID: UUID?
    public var status: InvoiceStatus = .open
    public var errorMessage: String?
    public private(set) var didSave = false

    private let repository: InvoiceRepositoryProtocol
    private let fileStorage: LocalFileStorage

    public init(repository: InvoiceRepositoryProtocol, fileStorage: LocalFileStorage) {
        self.repository = repository
        self.fileStorage = fileStorage
    }

    public func applyExtractedFields(_ fields: ExtractedInvoiceFields) {
        if let invoiceNumber = fields.invoiceNumber { self.invoiceNumber = invoiceNumber }
        if let amount = fields.amount { self.amountText = NSDecimalNumber(decimal: amount).stringValue }
    }

    public func save(pdfData: Data) async {
        let normalizedAmount = amountText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: normalizedAmount), amount > 0 else {
            errorMessage = "Ungültiger Betrag"
            return
        }
        let fileName = "\(UUID().uuidString).pdf"
        do {
            try fileStorage.save(pdfData, fileName: fileName)
            let invoice = Invoice(
                invoiceNumber: invoiceNumber,
                amount: amount,
                patient: patient,
                providerID: selectedProviderID,
                status: status,
                localPDFFileName: fileName
            )
            try await repository.createInvoice(invoice)
            didSave = true
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter ScanViewModelTests`
Expected: PASS (5 tests)

- [ ] **Step 7: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/ViewModels/ProviderPickerViewModel.swift RechnungenKit/Sources/RechnungenKit/ViewModels/ScanViewModel.swift RechnungenKit/Tests/RechnungenKitTests/ScanViewModelTests.swift RechnungenKit/Tests/RechnungenKitTests/Support/MockInvoiceRepository.swift
git commit -m "Add ScanViewModel and ProviderPickerViewModel"
```

---

### Task 10: InvoiceBoardViewModel + InvoiceEditViewModel

**Files:**
- Create: `RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceBoardViewModel.swift`
- Create: `RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceEditViewModel.swift`
- Test: `RechnungenKit/Tests/RechnungenKitTests/InvoiceBoardViewModelTests.swift`

**Interfaces:**
- Consumes: `InvoiceRepositoryProtocol` (Task 5), `MockInvoiceRepository` (Task 9), `Invoice`/`InvoiceStatus` (Task 1).
- Produces: `InvoiceBoardViewModel(repository:)` with `invoicesByStatus: [InvoiceStatus: [Invoice]]`, `load() async`, `moveInvoice(_:to:) async`. `InvoiceEditViewModel(invoice:repository:)` with `invoice: Invoice`, `updateStatus(_:) async`.

- [ ] **Step 1: Write the failing tests**

`RechnungenKit/Tests/RechnungenKitTests/InvoiceBoardViewModelTests.swift`:

```swift
import XCTest
@testable import RechnungenKit

final class InvoiceBoardViewModelTests: XCTestCase {
    func test_load_groupsInvoicesByStatus() async {
        let repository = MockInvoiceRepository()
        await repository.setInvoices([
            Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open),
            Invoice(invoiceNumber: "B", amount: 20, patient: .melanie, status: .submittedToPublicInsurance),
            Invoice(invoiceNumber: "C", amount: 30, patient: .christian, status: .open)
        ])
        let viewModel = InvoiceBoardViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.invoicesByStatus[.open]?.count, 2)
        XCTAssertEqual(viewModel.invoicesByStatus[.submittedToPublicInsurance]?.count, 1)
    }

    func test_moveInvoice_updatesLocalGroupingOptimisticallyAndCallsRepository() async {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        await repository.setInvoices([invoice])
        let viewModel = InvoiceBoardViewModel(repository: repository)
        await viewModel.load()

        await viewModel.moveInvoice(invoice, to: .submittedToPublicInsurance)

        XCTAssertEqual(viewModel.invoicesByStatus[.open]?.count, 0)
        XCTAssertEqual(viewModel.invoicesByStatus[.submittedToPublicInsurance]?.count, 1)
        let updates = await repository.statusUpdates
        XCTAssertEqual(updates.first?.invoiceID, invoice.id)
        XCTAssertEqual(updates.first?.status, .submittedToPublicInsurance)
    }

    func test_moveInvoice_toSameStatus_isNoOp() async {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        await repository.setInvoices([invoice])
        let viewModel = InvoiceBoardViewModel(repository: repository)
        await viewModel.load()

        await viewModel.moveInvoice(invoice, to: .open)

        let updates = await repository.statusUpdates
        XCTAssertTrue(updates.isEmpty)
    }

    func test_invoiceEditViewModel_updateStatus_updatesInvoiceAndCallsRepository() async {
        let repository = MockInvoiceRepository()
        let invoice = Invoice(invoiceNumber: "A", amount: 10, patient: .christian, status: .open)
        let viewModel = InvoiceEditViewModel(invoice: invoice, repository: repository)

        await viewModel.updateStatus(.done)

        XCTAssertEqual(viewModel.invoice.status, .done)
        let updates = await repository.statusUpdates
        XCTAssertEqual(updates.first?.status, .done)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd RechnungenKit && swift test --filter InvoiceBoardViewModelTests`
Expected: FAIL — view models don't exist yet.

- [ ] **Step 3: Implement `InvoiceBoardViewModel`**

`RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceBoardViewModel.swift`:

```swift
import Observation

@Observable
public final class InvoiceBoardViewModel {
    public private(set) var invoicesByStatus: [InvoiceStatus: [Invoice]] = [:]
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(repository: InvoiceRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        do {
            try await repository.refresh()
            let invoices = try await repository.invoices()
            invoicesByStatus = Dictionary(grouping: invoices, by: \.status)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func moveInvoice(_ invoice: Invoice, to newStatus: InvoiceStatus) async {
        guard invoice.status != newStatus else { return }
        var updated = invoice
        updated.status = newStatus
        invoicesByStatus[invoice.status]?.removeAll { $0.id == invoice.id }
        invoicesByStatus[newStatus, default: []].append(updated)
        do {
            try await repository.updateStatus(invoiceID: invoice.id, newStatus: newStatus)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: Implement `InvoiceEditViewModel`**

`RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceEditViewModel.swift`:

```swift
import Observation

@Observable
public final class InvoiceEditViewModel {
    public var invoice: Invoice
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(invoice: Invoice, repository: InvoiceRepositoryProtocol) {
        self.invoice = invoice
        self.repository = repository
    }

    public func updateStatus(_ newStatus: InvoiceStatus) async {
        invoice.status = newStatus
        do {
            try await repository.updateStatus(invoiceID: invoice.id, newStatus: newStatus)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd RechnungenKit && swift test --filter InvoiceBoardViewModelTests`
Expected: PASS (4 tests)

- [ ] **Step 6: Run the entire package test suite**

Run: `cd RechnungenKit && swift test`
Expected: PASS — all tests across Tasks 1–10 pass together.

- [ ] **Step 7: Commit**

```bash
git add RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceBoardViewModel.swift RechnungenKit/Sources/RechnungenKit/ViewModels/InvoiceEditViewModel.swift RechnungenKit/Tests/RechnungenKitTests/InvoiceBoardViewModelTests.swift
git commit -m "Add InvoiceBoardViewModel and InvoiceEditViewModel"
```

This completes `RechnungenKit`. Every remaining task builds the `RechnungenScanner` Xcode app target, which depends on it. From here on, verification steps require Xcode (not just the `swift` CLI) — `xcodebuild` and the iOS Simulator.

---

### Task 11: Xcode app scaffolding (XcodeGen) + CompositionRoot

**Files:**
- Create: `RechnungenScanner/project.yml`
- Create: `RechnungenScanner/RechnungenScanner/RechnungenScannerApp.swift`
- Create: `RechnungenScanner/RechnungenScanner/CompositionRoot.swift`
- Create: `RechnungenScanner/RechnungenScanner/Views/SettingsView.swift` (minimal placeholder — replaced fully in Task 13)

**Interfaces:**
- Consumes: everything from `RechnungenKit` (Tasks 1–10).
- Produces: a buildable `RechnungenScanner.xcodeproj`, `CompositionRoot` exposing `services: Services?` where `Services { let repository: InvoiceRepositoryProtocol; let syncEngine: SyncEngine }`, and `reload()`.

- [ ] **Step 1: Install XcodeGen if not already available**

Run: `brew install xcodegen` (skip if `xcodegen --version` already succeeds)

- [ ] **Step 2: Write the XcodeGen project spec**

`RechnungenScanner/project.yml`:

```yaml
name: RechnungenScanner
options:
  bundleIdPrefix: com.medicalbilltracker
  deploymentTarget:
    iOS: "17.0"
packages:
  RechnungenKit:
    path: ../RechnungenKit
targets:
  RechnungenScanner:
    type: application
    platform: iOS
    sources:
      - RechnungenScanner
    dependencies:
      - package: RechnungenKit
    info:
      path: RechnungenScanner/Info.plist
      properties:
        UILaunchScreen: {}
        NSCameraUsageDescription: "Wird benötigt, um Arztrechnungen zu scannen."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.medicalbilltracker.rechnungenscanner
        SWIFT_VERSION: "5.9"
```

- [ ] **Step 3: Implement `CompositionRoot`**

`RechnungenScanner/RechnungenScanner/CompositionRoot.swift`:

```swift
import Observation
import SwiftData
import RechnungenKit
import Foundation

@Observable
final class CompositionRoot {
    struct Services {
        let repository: InvoiceRepositoryProtocol
        let syncEngine: SyncEngine
    }

    private(set) var services: Services?

    init() {
        reload()
    }

    func reload() {
        guard let token = (try? KeychainService().readAPIToken()) ?? nil, !token.isEmpty else {
            services = nil
            return
        }

        let apiClient = SeaTableAPIClient(configuration: .init(apiToken: token))
        let container = try! ModelContainer(for: ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self)
        let localStore = LocalStore(modelContainer: container)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileStorage = LocalFileStorage(directory: documentsURL.appendingPathComponent("Scans"))
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let syncEngine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: fileStorage)
        services = Services(repository: repository, syncEngine: syncEngine)
    }
}
```

- [ ] **Step 4: Implement a minimal `SettingsView` placeholder**

`RechnungenScanner/RechnungenScanner/Views/SettingsView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let onSaved: () -> Void

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("SeaTable API-Token") {
                    SecureField("Token", text: $tokenInput)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Button("Speichern") { save() }
                        .disabled(tokenInput.isEmpty)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }

    private func save() {
        do {
            try keychainService.saveAPIToken(tokenInput)
            onSaved()
        } catch {
            errorMessage = "Token konnte nicht gespeichert werden."
        }
    }
}
```

- [ ] **Step 5: Implement the app entry point**

`RechnungenScanner/RechnungenScanner/RechnungenScannerApp.swift`:

```swift
import SwiftUI
import RechnungenKit

@main
struct RechnungenScannerApp: App {
    @State private var root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            if let services = root.services {
                Text("Board kommt in Task 15")
                    .task { await services.syncEngine.processOutbox() }
            } else {
                SettingsView(keychainService: KeychainService(), onSaved: { root.reload() })
            }
        }
    }
}
```

- [ ] **Step 6: Generate and build the project**

Run: `cd RechnungenScanner && xcodegen generate`
Run: `xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add RechnungenScanner/project.yml RechnungenScanner/RechnungenScanner
git commit -m "Scaffold RechnungenScanner Xcode app with CompositionRoot"
```

Note: the generated `.xcodeproj` is derived from `project.yml` and should not be committed — add `RechnungenScanner/RechnungenScanner.xcodeproj/` to `.gitignore` before this commit if it isn't already ignored.

---

### Task 12: ScanService (VisionKit wrapper)

**Files:**
- Create: `RechnungenScanner/RechnungenScanner/Scan/ScanService.swift`

**Interfaces:**
- Consumes: nothing from `RechnungenKit` directly (pure UIKit/VisionKit/PDFKit wrapper).
- Produces: `ScanService` with `presentScanner(from:completion:)`, `ScanServiceError` enum. Used by Task 14's `ScanFlowView`.

- [ ] **Step 1: Implement `ScanService`**

No automated test for this task — `VNDocumentCameraViewController` requires a physical camera and cannot run in the Simulator or a unit test host. Verified manually in Task 18.

`RechnungenScanner/RechnungenScanner/Scan/ScanService.swift`:

```swift
import VisionKit
import UIKit
import PDFKit

public enum ScanServiceError: Error {
    case pdfGenerationFailed
    case cancelled
}

final class ScanService: NSObject {
    typealias Completion = (Result<Data, Error>) -> Void

    private var completion: Completion?

    func presentScanner(from viewController: UIViewController, completion: @escaping Completion) {
        self.completion = completion
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = self
        viewController.present(scannerViewController, animated: true)
    }
}

extension ScanService: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)
        let pdfDocument = PDFDocument()
        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            if let pdfPage = PDFPage(image: image) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }
        guard let data = pdfDocument.dataRepresentation() else {
            completion?(.failure(ScanServiceError.pdfGenerationFailed))
            completion = nil
            return
        }
        completion?(.success(data))
        completion = nil
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        completion?(.failure(ScanServiceError.cancelled))
        completion = nil
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        completion?(.failure(error))
        completion = nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodegen generate && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/Scan
git commit -m "Add VisionKit-based ScanService producing a merged PDF"
```

---

### Task 13: SettingsView (finalize)

Task 11 already created a working `SettingsView`. This task only adds a Keychain-token validation affordance so the user gets feedback if the token is later rejected by SeaTable (rather than a silent infinite spinner on the board).

**Files:**
- Modify: `RechnungenScanner/RechnungenScanner/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `KeychainServiceProtocol` (RechnungenKit Task 8).
- Produces: same public shape as Task 11, with an added `validationMessage` state slot other views can surface errors into (see Task 17).

- [ ] **Step 1: Add a `Section` for sync error display**

Modify `RechnungenScanner/RechnungenScanner/Views/SettingsView.swift` — add an optional `syncErrorMessage: String?` parameter (default `nil`) surfaced above the token field, since this is the natural place a user checks after a "token invalid" failure elsewhere in the app:

```swift
struct SettingsView: View {
    let keychainService: KeychainServiceProtocol
    let onSaved: () -> Void
    var syncErrorMessage: String? = nil

    @State private var tokenInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let syncErrorMessage {
                    Section("Letzter Sync-Fehler") {
                        Text(syncErrorMessage).foregroundStyle(.red)
                    }
                }
                Section("SeaTable API-Token") {
                    SecureField("Token", text: $tokenInput)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Button("Speichern") { save() }
                        .disabled(tokenInput.isEmpty)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }

    private func save() {
        do {
            try keychainService.saveAPIToken(tokenInput)
            onSaved()
        } catch {
            errorMessage = "Token konnte nicht gespeichert werden."
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/Views/SettingsView.swift
git commit -m "Surface last sync error on the Settings screen"
```

---

### Task 14: ScanFlowView + InvoiceFormView

**Files:**
- Create: `RechnungenScanner/RechnungenScanner/Views/ScanFlowView.swift`
- Create: `RechnungenScanner/RechnungenScanner/Views/InvoiceFormView.swift`

**Interfaces:**
- Consumes: `ScanService` (Task 12), `ScanViewModel`/`ProviderPickerViewModel` (RechnungenKit Task 9), `TextRecognizer`/`InvoiceFieldExtractor` (RechnungenKit Task 7), `ProviderPickerView` (produced by Task 16 — for this task, `InvoiceFormView` takes `providers: [Provider]` directly and does not embed the picker's "create new" UI; that's wired in Task 17).
- Produces: `ScanFlowView` (a `UIViewControllerRepresentable` wrapping `ScanService`, with `onScanned: (Data) -> Void`), `InvoiceFormView` (the OCR-prefilled entry form).

- [ ] **Step 1: Implement `ScanFlowView`**

`RechnungenScanner/RechnungenScanner/Views/ScanFlowView.swift`:

```swift
import SwiftUI

struct ScanFlowView: UIViewControllerRepresentable {
    let onScanned: (Data) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let scanService = ScanService()
        let hostController = UIViewController()
        context.coordinator.scanService = scanService
        DispatchQueue.main.async {
            scanService.presentScanner(from: hostController) { result in
                switch result {
                case .success(let data):
                    onScanned(data)
                case .failure:
                    onCancelled()
                }
            }
        }
        return hostController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var scanService: ScanService?
    }
}
```

- [ ] **Step 2: Implement `InvoiceFormView`**

`RechnungenScanner/RechnungenScanner/Views/InvoiceFormView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct InvoiceFormView: View {
    @Bindable var viewModel: ScanViewModel
    let providers: [Provider]
    let pdfData: Data
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section("Rechnung") {
                TextField("Rechnungsnummer", text: $viewModel.invoiceNumber)
                TextField("Betrag", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
            }
            Section("Zuordnung") {
                Picker("Patient", selection: $viewModel.patient) {
                    ForEach(Patient.allCases, id: \.self) { patient in
                        Text(patient.rawValue).tag(patient)
                    }
                }
                Picker("Arzt", selection: $viewModel.selectedProviderID) {
                    Text("Kein Arzt").tag(UUID?.none)
                    ForEach(providers) { provider in
                        Text(provider.name).tag(Optional(provider.id))
                    }
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button("Speichern") {
                Task {
                    await viewModel.save(pdfData: pdfData)
                    if viewModel.didSave { onSaved() }
                }
            }
        }
        .navigationTitle("Neue Rechnung")
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodegen generate && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/Views/ScanFlowView.swift RechnungenScanner/RechnungenScanner/Views/InvoiceFormView.swift
git commit -m "Add scan flow and OCR-prefilled invoice entry form"
```

---

### Task 15: InvoiceBoardView + InvoiceCardView (horizontal-paging Kanban)

**Files:**
- Create: `RechnungenScanner/RechnungenScanner/Views/InvoiceCardView.swift`
- Create: `RechnungenScanner/RechnungenScanner/Views/InvoiceBoardView.swift`

**Interfaces:**
- Consumes: `InvoiceBoardViewModel` (RechnungenKit Task 10), `Invoice`/`InvoiceStatus`/`Patient` (RechnungenKit Task 1).
- Produces: `InvoiceBoardView(viewModel:)` — one status column per screen (`TabView` with `.page` style), drag-and-drop between columns via `onDrag`/`onDrop`. `InvoiceCardView(invoice:)`.

- [ ] **Step 1: Implement `InvoiceCardView`**

`RechnungenScanner/RechnungenScanner/Views/InvoiceCardView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct InvoiceCardView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(invoice.invoiceNumber).font(.headline)
            Text(invoice.amount, format: .currency(code: "EUR"))
            if let providerName = invoice.providerName {
                Text(providerName).font(.caption).foregroundStyle(.secondary)
            }
            Text(invoice.patient.rawValue)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            if invoice.remoteRowID == nil {
                Label("Wartet auf Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
    }
}
```

- [ ] **Step 2: Implement `InvoiceBoardView`**

`RechnungenScanner/RechnungenScanner/Views/InvoiceBoardView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct InvoiceBoardView: View {
    let viewModel: InvoiceBoardViewModel
    let onSelectInvoice: (Invoice) -> Void
    let onAddInvoice: () -> Void

    @State private var selectedStatus: InvoiceStatus = .open
    @State private var draggingInvoice: Invoice?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedStatus) {
                ForEach(InvoiceStatus.allCases, id: \.self) { status in
                    columnView(for: status)
                        .tag(status)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .navigationTitle("Arztrechnungen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Scannen", systemImage: "plus", action: onAddInvoice)
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private func columnView(for status: InvoiceStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(status.rawValue)
                    .font(.title3.bold())
                    .padding(.horizontal)
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.invoicesByStatus[status] ?? []) { invoice in
                        InvoiceCardView(invoice: invoice)
                            .onTapGesture { onSelectInvoice(invoice) }
                            .onDrag {
                                draggingInvoice = invoice
                                return NSItemProvider(object: invoice.id.uuidString as NSString)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let invoice = draggingInvoice else { return false }
            Task { await viewModel.moveInvoice(invoice, to: status) }
            draggingInvoice = nil
            return true
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodegen generate && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/Views/InvoiceCardView.swift RechnungenScanner/RechnungenScanner/Views/InvoiceBoardView.swift
git commit -m "Add horizontal-paging Kanban board with drag-and-drop status changes"
```

---

### Task 16: InvoiceDetailView + ProviderPickerView

**Files:**
- Create: `RechnungenScanner/RechnungenScanner/Views/InvoiceDetailView.swift`
- Create: `RechnungenScanner/RechnungenScanner/Views/ProviderPickerView.swift`

**Interfaces:**
- Consumes: `InvoiceEditViewModel`, `ProviderPickerViewModel` (RechnungenKit Task 9/10).
- Produces: `InvoiceDetailView(viewModel:)`, `ProviderPickerView(viewModel:selectedProviderID:)`.

- [ ] **Step 1: Implement `InvoiceDetailView`**

`RechnungenScanner/RechnungenScanner/Views/InvoiceDetailView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct InvoiceDetailView: View {
    @Bindable var viewModel: InvoiceEditViewModel

    var body: some View {
        Form {
            Section("Rechnung") {
                LabeledContent("Rechnungsnummer", value: viewModel.invoice.invoiceNumber)
                LabeledContent("Betrag") {
                    Text(viewModel.invoice.amount, format: .currency(code: "EUR"))
                }
                if let providerName = viewModel.invoice.providerName {
                    LabeledContent("Arzt", value: providerName)
                }
            }
            Section("Status") {
                Picker("Status", selection: Binding(
                    get: { viewModel.invoice.status },
                    set: { newValue in Task { await viewModel.updateStatus(newValue) } }
                )) {
                    ForEach(InvoiceStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.inline)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Rechnungsdetail")
    }
}
```

- [ ] **Step 2: Implement `ProviderPickerView`**

`RechnungenScanner/RechnungenScanner/Views/ProviderPickerView.swift`:

```swift
import SwiftUI
import RechnungenKit

struct ProviderPickerView: View {
    @Bindable var viewModel: ProviderPickerViewModel
    @Binding var selectedProviderID: UUID?

    @State private var newProviderName = ""

    var body: some View {
        Form {
            Section("Vorhandene Ärzte") {
                ForEach(viewModel.providers) { provider in
                    Button {
                        selectedProviderID = provider.id
                    } label: {
                        HStack {
                            Text(provider.name)
                            if selectedProviderID == provider.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section("Neuen Arzt anlegen") {
                TextField("Name", text: $newProviderName)
                Button("Anlegen") {
                    Task {
                        if let provider = await viewModel.createProvider(name: newProviderName) {
                            selectedProviderID = provider.id
                            newProviderName = ""
                        }
                    }
                }
                .disabled(newProviderName.isEmpty)
            }
        }
        .task { await viewModel.load() }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodegen generate && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/Views/InvoiceDetailView.swift RechnungenScanner/RechnungenScanner/Views/ProviderPickerView.swift
git commit -m "Add invoice detail and provider picker views"
```

---

### Task 17: Final app wiring (navigation + foreground sync)

**Files:**
- Modify: `RechnungenScanner/RechnungenScanner/RechnungenScannerApp.swift`

**Interfaces:**
- Consumes: `CompositionRoot` (Task 11), `InvoiceBoardView` (Task 15), `InvoiceDetailView`/`ProviderPickerView` (Task 16), `ScanFlowView`/`InvoiceFormView` (Task 14), `TextRecognizer`/`InvoiceFieldExtractor` (RechnungenKit Task 7), `ScanViewModel`/`InvoiceBoardViewModel`/`InvoiceEditViewModel`/`ProviderPickerViewModel` (RechnungenKit Task 9/10).
- Produces: the finished app entry point — this is the last task before manual testing; nothing downstream consumes it.

- [ ] **Step 1: Replace the placeholder root view with full navigation**

Replace the body of `RechnungenScanner/RechnungenScanner/RechnungenScannerApp.swift` with a root coordinator view that ties board → detail and board → scan together, plus triggers a sync on every foreground transition:

```swift
import SwiftUI
import RechnungenKit

@main
struct RechnungenScannerApp: App {
    @State private var root = CompositionRoot()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let services = root.services {
                RootView(repository: services.repository, syncEngine: services.syncEngine)
            } else {
                SettingsView(keychainService: KeychainService(), onSaved: { root.reload() })
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let syncEngine = root.services?.syncEngine else { return }
            Task { await syncEngine.processOutbox() }
        }
    }
}

private struct RootView: View {
    let repository: InvoiceRepositoryProtocol
    let syncEngine: SyncEngine

    @State private var boardViewModel: InvoiceBoardViewModel
    @State private var isScanning = false
    @State private var selectedInvoice: Invoice?
    @State private var scannedPDFData: Data?

    init(repository: InvoiceRepositoryProtocol, syncEngine: SyncEngine) {
        self.repository = repository
        self.syncEngine = syncEngine
        _boardViewModel = State(initialValue: InvoiceBoardViewModel(repository: repository))
    }

    var body: some View {
        InvoiceBoardView(
            viewModel: boardViewModel,
            onSelectInvoice: { selectedInvoice = $0 },
            onAddInvoice: { isScanning = true }
        )
        .sheet(isPresented: $isScanning) {
            ScanFlowView(
                onScanned: { data in
                    scannedPDFData = data
                },
                onCancelled: { isScanning = false }
            )
        }
        .sheet(item: $selectedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(viewModel: InvoiceEditViewModel(invoice: invoice, repository: repository))
            }
        }
        .sheet(isPresented: Binding(
            get: { scannedPDFData != nil },
            set: { if !$0 { scannedPDFData = nil; isScanning = false } }
        )) {
            if let pdfData = scannedPDFData {
                ScanReviewFlow(
                    pdfData: pdfData,
                    repository: repository,
                    onSaved: {
                        scannedPDFData = nil
                        isScanning = false
                        Task {
                            await syncEngine.processOutbox()
                            await boardViewModel.load()
                        }
                    }
                )
            }
        }
        .task { await syncEngine.processOutbox() }
    }
}

private struct ScanReviewFlow: View {
    let pdfData: Data
    let repository: InvoiceRepositoryProtocol
    let onSaved: () -> Void

    @State private var scanViewModel: ScanViewModel
    @State private var providerPickerViewModel: ProviderPickerViewModel
    @State private var extractedFields: ExtractedInvoiceFields?

    init(pdfData: Data, repository: InvoiceRepositoryProtocol, onSaved: @escaping () -> Void) {
        self.pdfData = pdfData
        self.repository = repository
        self.onSaved = onSaved
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileStorage = LocalFileStorage(directory: documentsURL.appendingPathComponent("Scans"))
        _scanViewModel = State(initialValue: ScanViewModel(repository: repository, fileStorage: fileStorage))
        _providerPickerViewModel = State(initialValue: ProviderPickerViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            InvoiceFormView(
                viewModel: scanViewModel,
                providers: providerPickerViewModel.providers,
                pdfData: pdfData,
                onSaved: onSaved
            )
        }
        .task {
            await providerPickerViewModel.load()
            if let cgImage = PDFFirstPageRenderer.renderFirstPageAsCGImage(from: pdfData) {
                let lines = try? await TextRecognizer().recognizeLines(in: cgImage)
                scanViewModel.applyExtractedFields(InvoiceFieldExtractor().extract(from: lines ?? []))
            }
        }
    }
}
```

Note: `Invoice` needs `Identifiable` conformance for `.sheet(item:)` — already satisfied since `Invoice.id` is `UUID` (Task 1).

- [ ] **Step 2: Add the small PDF-to-CGImage helper used above**

Create `RechnungenScanner/RechnungenScanner/Scan/PDFFirstPageRenderer.swift`:

```swift
import PDFKit
import CoreGraphics
import UIKit

enum PDFFirstPageRenderer {
    static func renderFirstPageAsCGImage(from pdfData: Data) -> CGImage? {
        guard
            let document = PDFDocument(data: pdfData),
            let page = document.page(at: 0)
        else {
            return nil
        }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(pageRect)
            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd RechnungenScanner && xcodegen generate && xcodebuild -project RechnungenScanner.xcodeproj -scheme RechnungenScanner -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add RechnungenScanner/RechnungenScanner/RechnungenScannerApp.swift RechnungenScanner/RechnungenScanner/Scan/PDFFirstPageRenderer.swift
git commit -m "Wire board, scan, and detail flows together with foreground sync"
```

---

### Task 18: Manual end-to-end test checklist

**Files:**
- Create: `RechnungenScanner/MANUAL_TESTING.md`

**Interfaces:**
- Consumes: the finished app (Tasks 1–17). No downstream consumers — this is the final deliverable of Phase 1.

- [ ] **Step 1: Write the manual test checklist**

`RechnungenScanner/MANUAL_TESTING.md`:

```markdown
# Manueller Testplan — RechnungenScanner Phase 1

Auf einem echten iPhone durchführen (Simulator hat keine Kamera).

## Einrichtung
- [ ] App-Start ohne gespeichertes Token zeigt die Einstellungen-Ansicht
- [ ] Ein SeaTable-Base-API-Token für die Base "Arztrechnungen" eintragen und speichern
- [ ] Nach dem Speichern erscheint das Rechnungs-Board

## Scan-Flow
- [ ] "+" öffnet die Kamera (VisionKit-Scanner)
- [ ] Eine echte Arztrechnung fotografieren (Mehrseiten-Scan testen: 2 Seiten)
- [ ] Nach dem Scan öffnet sich das Formular vorausgefüllt (Betrag/Rechnungsnummer/Datum, wo im Dokument vorhanden)
- [ ] Vorbefüllte Werte vor dem Speichern korrigieren funktioniert
- [ ] Neuen Arzt anlegen funktioniert und ist danach im Picker auswählbar
- [ ] Nach "Speichern" erscheint die Karte sofort im Board mit "Wartet auf Sync"
- [ ] Nach kurzer Zeit (oder App-Neustart) verschwindet das Sync-Icon und der Eintrag ist in SeaTable sichtbar (inkl. hochgeladenem PDF)

## Board & Statuswechsel
- [ ] Seitliches Wischen wechselt zwischen den 6 Status-Spalten
- [ ] Eine Karte per Drag&Drop in die Nachbarspalte ziehen ändert den Status sofort lokal
- [ ] Der Statuswechsel ist nach Sync auch in SeaTable direkt sichtbar
- [ ] Tippen auf eine Karte öffnet die Detailansicht mit korrekten Werten

## Offline-Verhalten
- [ ] Flugmodus aktivieren, neue Rechnung scannen und speichern → Karte erscheint mit Sync-Icon, kein Absturz
- [ ] Flugmodus deaktivieren → Eintrag synct automatisch (spätestens beim nächsten App-Vordergrund-Wechsel)
- [ ] Statuswechsel im Flugmodus verhält sich ebenso (optimistisches Update, späterer Sync)

## Fehlerfälle
- [ ] Ungültiges Token in den Einstellungen eintragen → sinnvolle Fehlermeldung, keine Endlos-Ladeanimation
- [ ] Sync-Fehler (z. B. abgelaufenes Token) wird auf dem Einstellungen-Screen angezeigt

## Bekannte Einschränkungen dieser Phase
- Nur Arztrechnungen + Arzt sind in der App bearbeitbar; alle anderen Tabellen bleiben SeaTable-only.
- Kein Multi-User-Login — ein gemeinsames API-Token für den Haushalt.
- "Server gewinnt" bei Konflikten — keine manuelle Konfliktauflösung in Phase 1.
```

- [ ] **Step 2: Commit**

```bash
git add RechnungenScanner/MANUAL_TESTING.md
git commit -m "Add Phase 1 manual end-to-end test checklist"
```

---

## Self-Review Notes

- **Spec coverage:** Architecture overview → Tasks 1, 11; all six spec decisions (platform, backend, auth, table scope, OCR, offline, board layout) → Tasks 1–17 as noted inline; components list → one task per component; scan data flow → Tasks 12, 14, 17; drag&drop status flow → Tasks 10, 15; board-read flow → Tasks 5, 10, 15; error handling (network retry, API errors, OCR-is-a-suggestion, conflict "server wins", file-upload retry, invalid drop) → Tasks 6, 9, 13; testing section (unit/integration/UI/manual) → Tasks 1–10 unit tests, Task 18 manual checklist covers the device-only parts (XCUITest automation is out of scope for Phase 1 given no CI/device farm was specified — flagged here rather than silently added).
- **Placeholder scan:** no TBD/TODO markers; the one explicit caveat (SeaTable endpoint paths need verification against current docs) is a legitimate external-contract note, not an implementation gap, and is called out once in Global Constraints rather than repeated.
- **Type consistency:** `Invoice`/`Provider`/`InvoiceStatus`/`Patient` (Task 1) are used with identical field names throughout Tasks 4–17; `InvoiceRepositoryProtocol`'s six methods (Task 5) are implemented exactly once (`SeaTableInvoiceRepository`) and consumed identically by `MockInvoiceRepository` (Task 9), `InvoiceBoardViewModel`/`InvoiceEditViewModel` (Task 10), and `CompositionRoot` (Task 11). `OutboxOperation` cases (Task 4) match the four `switch` cases in `SyncEngine` (Task 6) one-to-one.
