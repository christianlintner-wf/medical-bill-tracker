import XCTest
@testable import RechnungenKit

final class InsuranceProviderLinksStoreTests: XCTestCase {
    private func makeStore() -> InsuranceProviderLinksStore {
        InsuranceProviderLinksStore(userDefaults: UserDefaults(suiteName: "InsuranceProviderLinksStoreTests-\(UUID().uuidString)")!)
    }

    func test_url_withoutSavedValue_returnsDefaultLinkForProvider() {
        let store = makeStore()

        XCTAssertEqual(store.url(for: .oegk)?.absoluteString, "https://meine.oegk.at/cdscontent/?contentid=10007.883235&portal=oegkportal")
        XCTAssertEqual(store.url(for: .bva)?.absoluteString, "https://www.bvaeb.at")
        XCTAssertEqual(store.url(for: .merkur)?.absoluteString, "https://www.merkur.at/")
    }

    func test_setURLThenUrl_roundTripsForSpecificProvider() {
        let store = makeStore()
        let customURL = URL(string: "https://custom.example")!

        store.setURL(customURL, for: .oegk)

        XCTAssertEqual(store.url(for: .oegk), customURL)
        XCTAssertEqual(store.url(for: .bva)?.absoluteString, "https://www.bvaeb.at")
    }

    func test_setURL_forOneProvider_doesNotAffectOthers() {
        let store = makeStore()
        store.setURL(URL(string: "https://a.example"), for: .oegk)
        store.setURL(URL(string: "https://b.example"), for: .merkur)

        XCTAssertEqual(store.url(for: .oegk)?.absoluteString, "https://a.example")
        XCTAssertEqual(store.url(for: .merkur)?.absoluteString, "https://b.example")
    }
}
