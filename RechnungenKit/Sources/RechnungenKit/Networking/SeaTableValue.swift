import Foundation

public enum SeaTableValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case stringArray([String])
    case fileArray([SeaTableFileValue])
    case null

    public var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .stringArray(let values): return values
        case .fileArray(let files): return files.map { $0.jsonObject }
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
        case let values as [[String: Any]]:
            // Link-column rows come back as [{"display_value": ..., "row_id": ...}];
            // reduce to the plain row-id list the rest of the app expects.
            let ids = values.compactMap { $0["row_id"] as? String }
            self = ids.isEmpty ? .null : .stringArray(ids)
        default:
            self = .null
        }
    }
}

public struct SeaTableFileValue: Sendable, Equatable {
    public let name: String
    public let size: Int
    public let type: String
    public let url: String

    public init(name: String, size: Int, type: String = "file", url: String) {
        self.name = name
        self.size = size
        self.type = type
        self.url = url
    }

    var jsonObject: [String: Any] {
        ["name": name, "size": size, "type": type, "url": url]
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
