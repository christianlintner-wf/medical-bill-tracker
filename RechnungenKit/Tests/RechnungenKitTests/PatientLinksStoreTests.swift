import XCTest
@testable import RechnungenKit

final class PatientLinksStoreTests: XCTestCase {
    private func makeStore() -> PatientLinksStore {
        PatientLinksStore(userDefaults: UserDefaults(suiteName: "PatientLinksStoreTests-\(UUID().uuidString)")!)
    }

    func test_links_withoutSavedValue_returnsEmptyLinks() {
        let store = makeStore()

        let links = store.links(for: .christian)

        XCTAssertNil(links.oegkURL)
        XCTAssertNil(links.merkurURL)
    }

    func test_setLinksThenLinks_roundTripsForSpecificPatient() {
        let store = makeStore()
        let links = PatientLinks(oegkURL: URL(string: "https://gesundheitskasse.at"), merkurURL: URL(string: "https://merkur.at"))

        store.setLinks(links, for: .melanie)

        XCTAssertEqual(store.links(for: .melanie), links)
        XCTAssertEqual(store.links(for: .christian), PatientLinks())
    }

    func test_setLinks_forOnePatient_doesNotAffectOthers() {
        let store = makeStore()
        store.setLinks(PatientLinks(oegkURL: URL(string: "https://a.example")), for: .christian)
        store.setLinks(PatientLinks(oegkURL: URL(string: "https://b.example")), for: .melanie)

        XCTAssertEqual(store.links(for: .christian).oegkURL?.absoluteString, "https://a.example")
        XCTAssertEqual(store.links(for: .melanie).oegkURL?.absoluteString, "https://b.example")
    }

    func test_patientLinks_urlForTarget_returnsMatchingField() {
        let links = PatientLinks(oegkURL: URL(string: "https://oegk.example"), merkurURL: URL(string: "https://merkur.example"))

        XCTAssertEqual(links.url(for: .oegk), links.oegkURL)
        XCTAssertEqual(links.url(for: .merkur), links.merkurURL)
    }
}
