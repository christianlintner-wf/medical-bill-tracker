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
