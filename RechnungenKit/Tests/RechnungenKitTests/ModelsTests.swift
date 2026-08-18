import XCTest
@testable import RechnungenKit

final class ModelsTests: XCTestCase {
    func test_invoiceStatus_rawValuesMatchSeaTableOptionStrings() {
        XCTAssertEqual(InvoiceStatus.open.rawValue, "Offen")
        XCTAssertEqual(InvoiceStatus.submittedToPublicInsurance.rawValue, "Krankenkasse eingereicht")
        XCTAssertEqual(InvoiceStatus.publicInsuranceCompleted.rawValue, "Krankenkasse abgeschlossen")
        XCTAssertEqual(InvoiceStatus.submittedToPrivateInsurance.rawValue, "Merkur eingereicht")
        XCTAssertEqual(InvoiceStatus.privateInsuranceCompleted.rawValue, "Merkur abgeschlossen")
        XCTAssertEqual(InvoiceStatus.done.rawValue, "Erledigt")
    }

    func test_invoiceStatus_ordersAsWorkflowSequence() {
        let ordered = InvoiceStatus.allCases
        XCTAssertEqual(ordered, [
            .open,
            .submittedToPublicInsurance,
            .publicInsuranceCompleted,
            .submittedToPrivateInsurance,
            .privateInsuranceCompleted,
            .done
        ])
        XCTAssertTrue(InvoiceStatus.open < InvoiceStatus.done)
        XCTAssertFalse(InvoiceStatus.done < InvoiceStatus.open)
    }

    func test_invoice_defaultsToOpenStatusAndStableID() {
        let invoice = Invoice(invoiceNumber: "2025-72", amount: 150, patient: .christian)
        XCTAssertEqual(invoice.status, .open)
        XCTAssertNil(invoice.remoteRowID)
        XCTAssertNil(invoice.providerID)
    }

    func test_provider_defaultsToNilRemoteRowID() {
        let provider = Provider(name: "Dr. Mona Cooper")
        XCTAssertNil(provider.remoteRowID)
        XCTAssertEqual(provider.name, "Dr. Mona Cooper")
    }

    func test_finding_defaultsToNilRemoteState() {
        let invoiceID = UUID()
        let finding = Finding(invoiceID: invoiceID)
        XCTAssertNil(finding.remoteRowID)
        XCTAssertNil(finding.invoiceRemoteRowID)
        XCTAssertNil(finding.localPDFFileName)
        XCTAssertNil(finding.remoteFileURL)
        XCTAssertEqual(finding.invoiceID, invoiceID)
    }
}
