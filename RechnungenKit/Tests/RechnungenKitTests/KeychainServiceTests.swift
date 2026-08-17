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
