import XCTest
@testable import RechnungenKit

final class PatientInsuranceAssignmentStoreTests: XCTestCase {
    private func makeStore() -> PatientInsuranceAssignmentStore {
        PatientInsuranceAssignmentStore(userDefaults: UserDefaults(suiteName: "PatientInsuranceAssignmentStoreTests-\(UUID().uuidString)")!)
    }

    func test_publicProvider_withoutSavedValue_returnsExpectedDefaultsPerPatient() {
        let store = makeStore()

        XCTAssertEqual(store.publicProvider(for: .christian), .oegk)
        XCTAssertEqual(store.publicProvider(for: .melanie), .oegk)
        XCTAssertEqual(store.publicProvider(for: .theresa), .oegk)
        XCTAssertEqual(store.publicProvider(for: .kathi), .bva)
        XCTAssertEqual(store.publicProvider(for: .sarah), .bva)
    }

    func test_setPublicProviderThenPublicProvider_roundTripsForSpecificPatient() {
        let store = makeStore()

        store.setPublicProvider(.bva, for: .christian)

        XCTAssertEqual(store.publicProvider(for: .christian), .bva)
        XCTAssertEqual(store.publicProvider(for: .melanie), .oegk)
    }
}
