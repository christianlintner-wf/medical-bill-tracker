import Foundation

public struct PatientLinks: Codable, Equatable, Sendable {
    public var oegkURL: URL?
    public var merkurURL: URL?

    public init(oegkURL: URL? = nil, merkurURL: URL? = nil) {
        self.oegkURL = oegkURL
        self.merkurURL = merkurURL
    }

    public func url(for target: InsuranceTarget) -> URL? {
        switch target {
        case .oegk: return oegkURL
        case .merkur: return merkurURL
        }
    }
}
