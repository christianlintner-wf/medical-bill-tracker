import XCTest
@testable import RechnungenKit

final class InsuranceProviderTests: XCTestCase {
    func test_displayName_returnsGermanLabels() {
        XCTAssertEqual(InsuranceProvider.oegk.displayName, "ÖGK")
        XCTAssertEqual(InsuranceProvider.bva.displayName, "BVA")
        XCTAssertEqual(InsuranceProvider.merkur.displayName, "Merkur")
    }

    func test_category_groupsOegkAndBvaAsPublicAndMerkurAsPrivate() {
        XCTAssertEqual(InsuranceProvider.oegk.category, .publicInsurance)
        XCTAssertEqual(InsuranceProvider.bva.category, .publicInsurance)
        XCTAssertEqual(InsuranceProvider.merkur.category, .privateInsurance)
    }

    func test_submissionPhase_mapsOpenAndSubmittedToPublicInsuranceToPublicPhase() {
        XCTAssertEqual(InvoiceStatus.open.submissionPhase, .publicInsurance)
        XCTAssertEqual(InvoiceStatus.submittedToPublicInsurance.submissionPhase, .publicInsurance)
    }

    func test_submissionPhase_mapsPublicInsuranceCompletedToPrivatePhase() {
        XCTAssertEqual(InvoiceStatus.publicInsuranceCompleted.submissionPhase, .privateInsurance)
    }

    func test_submissionPhase_isNilForStatusesAfterPrivateInsuranceSubmission() {
        XCTAssertNil(InvoiceStatus.submittedToPrivateInsurance.submissionPhase)
        XCTAssertNil(InvoiceStatus.privateInsuranceCompleted.submissionPhase)
        XCTAssertNil(InvoiceStatus.done.submissionPhase)
    }
}
