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
