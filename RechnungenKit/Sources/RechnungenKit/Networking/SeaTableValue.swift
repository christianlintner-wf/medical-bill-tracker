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
