import XCTest
@testable import RechnungenKit

final class InsuranceTargetTests: XCTestCase {
    func test_displayName_returnsGermanLabels() {
        XCTAssertEqual(InsuranceTarget.oegk.displayName, "ÖGK")
        XCTAssertEqual(InsuranceTarget.merkur.displayName, "Merkur")
    }

    func test_submissionTarget_mapsOpenAndSubmittedToPublicInsuranceToOEGK() {
        XCTAssertEqual(InvoiceStatus.open.submissionTarget, .oegk)
        XCTAssertEqual(InvoiceStatus.submittedToPublicInsurance.submissionTarget, .oegk)
    }

    func test_submissionTarget_mapsPublicInsuranceCompletedToMerkur() {
        XCTAssertEqual(InvoiceStatus.publicInsuranceCompleted.submissionTarget, .merkur)
    }

    func test_submissionTarget_isNilForStatusesAfterMerkurSubmission() {
        XCTAssertNil(InvoiceStatus.submittedToPrivateInsurance.submissionTarget)
        XCTAssertNil(InvoiceStatus.privateInsuranceCompleted.submissionTarget)
        XCTAssertNil(InvoiceStatus.done.submissionTarget)
    }
}
