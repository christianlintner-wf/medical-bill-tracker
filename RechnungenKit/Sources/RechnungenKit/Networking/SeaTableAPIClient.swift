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

    /// A table column's real shape, resolved from the base's metadata endpoint.
    /// SeaTable's row endpoints key fields by an opaque internal `key` (e.g. "8TrB"), not the
    /// display `name` ("Rechnungsnummer") shown in the UI - and single-/multi-select columns
    /// store option ids ("950504"), not option text ("Erledigt"), in row data. This type carries
    /// what's needed to translate a raw row into the name-keyed, text-valued fields the rest of
    /// the app expects.
    private struct Column {
        let key: String
        let name: String
        let optionNamesByID: [String: String]
    }

    private let configuration: Configuration
    private let session: URLSession
    private var cachedToken: BaseAccessToken?
    private var cachedTokenFetchedAt: Date?
    private let tokenLifetime: TimeInterval = 3000
    private var cachedColumnsByTable: [String: [Column]] = [:]

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

    private func rowsURL(dtableServer: String, dtableUUID: String) -> URL {
        URL(string: dtableServer)!.appendingPathComponent("api/v2/dtables/\(dtableUUID)/rows/")
    }

    /// Fetches and caches a table's column definitions (key <-> display name, and for
    /// single-/multi-select columns, option id <-> option text) from the base metadata endpoint.
    private func columns(forTable table: String) async throws -> [Column] {
        if let cached = cachedColumnsByTable[table] {
            return cached
        }
        let token = try await baseAccessToken()
        let url = URL(string: token.dtableServer)!.appendingPathComponent("api/v2/dtables/\(token.dtableUUID)/metadata/")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let metadata = json["metadata"] as? [String: Any],
            let tables = metadata["tables"] as? [[String: Any]],
            let tableDict = tables.first(where: { ($0["name"] as? String) == table }),
            let rawColumns = tableDict["columns"] as? [[String: Any]]
        else {
            throw SeaTableAPIError.invalidResponse
        }
        let columns: [Column] = rawColumns.compactMap { raw in
            guard let key = raw["key"] as? String, let name = raw["name"] as? String else { return nil }
            var optionNamesByID: [String: String] = [:]
            if let columnData = raw["data"] as? [String: Any], let options = columnData["options"] as? [[String: Any]] {
                for option in options {
                    if let optionID = option["id"] as? String, let optionName = option["name"] as? String {
                        optionNamesByID[optionID] = optionName
                    }
                }
            }
            return Column(key: key, name: name, optionNamesByID: optionNamesByID)
        }
        cachedColumnsByTable[table] = columns
        return columns
    }

    public func listRows(table: String) async throws -> [SeaTableRow] {
        let token = try await baseAccessToken()
        let columns = try await columns(forTable: table)
        var components = URLComponents(
            url: rowsURL(dtableServer: token.dtableServer, dtableUUID: token.dtableUUID),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "table_name", value: table)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.parseRows(from: data, columns: columns)
    }

    public func createRow(table: String, fields: [String: SeaTableValue]) async throws -> String {
        let token = try await baseAccessToken()
        var request = URLRequest(url: rowsURL(dtableServer: token.dtableServer, dtableUUID: token.dtableUUID))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "table_name": table,
            "rows": [fields.mapValues { $0.jsonObject }],
            "apply_default": false
        ])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rowIDs = json["row_ids"] as? [[String: Any]],
            let rowID = rowIDs.first?["_id"] as? String
        else {
            throw SeaTableAPIError.invalidResponse
        }
        return rowID
    }

    public func updateRow(table: String, rowID: String, fields: [String: SeaTableValue]) async throws {
        let token = try await baseAccessToken()
        var request = URLRequest(url: rowsURL(dtableServer: token.dtableServer, dtableUUID: token.dtableUUID))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "table_name": table,
            "updates": [
                [
                    "row_id": rowID,
                    "row": fields.mapValues { $0.jsonObject }
                ]
            ]
        ])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    private static func parseRows(from data: Data, columns: [Column]) throws -> [SeaTableRow] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawRows = json["rows"] as? [[String: Any]]
        else {
            throw SeaTableAPIError.invalidResponse
        }
        let columnsByKey = Dictionary(uniqueKeysWithValues: columns.map { ($0.key, $0) })
        return rawRows.compactMap { raw in
            guard let id = raw["_id"] as? String else { return nil }
            var fields: [String: SeaTableValue] = [:]
            for (key, value) in raw where key != "_id" {
                // Row data is keyed by the column's internal key, not its display name - and
                // fields we don't have a column definition for (deleted columns, etc.) are
                // skipped rather than surfaced under a meaningless key.
                guard let column = columnsByKey[key] else { continue }
                var parsed = SeaTableValue(jsonObject: value)
                if !column.optionNamesByID.isEmpty {
                    parsed = Self.resolvingSelectOptionNames(parsed, optionNamesByID: column.optionNamesByID)
                }
                fields[column.name] = parsed
            }
            return SeaTableRow(id: id, fields: fields)
        }
    }

    /// Single-/multi-select columns store option ids in row data; swap them for the option's
    /// display text so the rest of the app can keep working with human-readable values
    /// (e.g. matching `InvoiceStatus` raw values like "Erledigt").
    private static func resolvingSelectOptionNames(_ value: SeaTableValue, optionNamesByID: [String: String]) -> SeaTableValue {
        switch value {
        case .string(let id):
            return .string(optionNamesByID[id] ?? id)
        case .stringArray(let ids):
            return .stringArray(ids.map { optionNamesByID[$0] ?? $0 })
        case .number, .fileArray, .null:
            return value
        }
    }

    public func uploadFile(data: Data, fileName: String) async throws -> SeaTableUploadedFile {
        // app-upload-link rejects the exchanged base access-token with 403 Permission denied
        // (a deliberate SeaTable security change since v4.0) - it must be called with the raw
        // API token instead, the same way app-access-token itself is authorized.
        var linkRequest = URLRequest(url: configuration.serverBaseURL.appendingPathComponent("api/v2.1/dtable/app-upload-link/"))
        linkRequest.setValue("Token \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        let (linkData, linkResponse) = try await session.data(for: linkRequest)
        try Self.validate(response: linkResponse, data: linkData)
        guard
            let linkJSON = try JSONSerialization.jsonObject(with: linkData) as? [String: Any],
            let uploadLinkString = linkJSON["upload_link"] as? String,
            let parentPath = linkJSON["parent_path"] as? String,
            let fileRelativePath = linkJSON["file_relative_path"] as? String,
            let workspaceID = linkJSON["workspace_id"] as? Int,
            let uploadLinkBase = URL(string: uploadLinkString)
        else {
            throw SeaTableAPIError.invalidResponse
        }
        // The underlying Seafile upload endpoint returns a tab-separated file list by default;
        // ret-json=1 makes it return the JSON array this method parses below.
        var uploadLinkComponents = URLComponents(url: uploadLinkBase, resolvingAgainstBaseURL: false)!
        uploadLinkComponents.queryItems = [URLQueryItem(name: "ret-json", value: "1")]
        guard let uploadLink = uploadLinkComponents.url else {
            throw SeaTableAPIError.invalidResponse
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var uploadRequest = URLRequest(url: uploadLink)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendFormField(name: "parent_dir", value: parentPath)
        appendFormField(name: "relative_path", value: fileRelativePath)
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
        let assetURL = "/workspace/\(workspaceID)\(parentPath)/\(fileRelativePath)/\(relativeName)"
        return SeaTableUploadedFile(name: relativeName, size: size, url: assetURL)
    }
}
