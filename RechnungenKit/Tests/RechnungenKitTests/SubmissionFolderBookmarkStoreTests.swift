import XCTest
@testable import RechnungenKit

final class SubmissionFolderBookmarkStoreTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SubmissionFolderBookmarkStoreTests-\(UUID().uuidString)")!
    }

    func test_resolvedFolderURL_withoutSavedBookmark_throwsNotConfigured() {
        let store = SubmissionFolderBookmarkStore(userDefaults: makeUserDefaults())

        XCTAssertThrowsError(try store.resolvedFolderURL()) { error in
            XCTAssertEqual(error as? SubmissionFolderBookmarkStore.ResolveError, .notConfigured)
        }
    }

    func test_resolvedFolderURL_withCorruptBookmarkData_throws() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(Data("not-a-real-bookmark".utf8), forKey: "submissionFolderBookmark")
        let store = SubmissionFolderBookmarkStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.resolvedFolderURL())
    }

    func test_saveThenResolvedFolderURL_roundTripsToSameDirectory() throws {
        let store = SubmissionFolderBookmarkStore(userDefaults: makeUserDefaults())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try store.save(folderURL: directory)
        let resolved = try store.resolvedFolderURL()

        XCTAssertEqual(resolved.standardizedFileURL, directory.standardizedFileURL)
    }

    func test_isConfigured_reflectsSavedState() throws {
        let store = SubmissionFolderBookmarkStore(userDefaults: makeUserDefaults())
        XCTAssertFalse(store.isConfigured)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.save(folderURL: directory)

        XCTAssertTrue(store.isConfigured)
    }

    func test_withAccess_passesResolvedURLToBody() throws {
        let store = SubmissionFolderBookmarkStore(userDefaults: makeUserDefaults())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.save(folderURL: directory)

        let result = try store.withAccess { url in url.lastPathComponent }

        XCTAssertEqual(result, directory.lastPathComponent)
    }
}
