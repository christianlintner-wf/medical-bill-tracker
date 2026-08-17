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
}
