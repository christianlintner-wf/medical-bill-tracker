import XCTest
@testable import RechnungenKit

final class InvoiceFieldExtractorTests: XCTestCase {
    func test_extract_findsInvoiceNumberAmountAndDate() {
        let lines = [
            "Dr. Mona Cooper",
            "Rechnungsnummer: 2025-72",
            "Datum: 12.08.2025",
            "Gesamtbetrag: 150,00 €"
        ]

        let result = InvoiceFieldExtractor().extract(from: lines)

        XCTAssertEqual(result.invoiceNumber, "2025-72")
        XCTAssertEqual(result.amount, Decimal(string: "150.00"))
        XCTAssertNotNil(result.date)
    }

    func test_extract_handlesMissingFieldsGracefully() {
        let result = InvoiceFieldExtractor().extract(from: ["Irgendein Text ohne Struktur"])

        XCTAssertNil(result.invoiceNumber)
        XCTAssertNil(result.amount)
        XCTAssertNil(result.date)
    }

    func test_extract_parsesAmountWithThousandsSeparator() {
        let result = InvoiceFieldExtractor().extract(from: ["Betrag: 1.250,50 EUR"])

        XCTAssertEqual(result.amount, Decimal(string: "1250.50"))
    }

    func test_extract_usesFirstMatchWhenMultipleCandidateLinesExist() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Rechnungsnr. 2025/097",
            "Referenz Rechnungsnummer: 2025/108"
        ])

        XCTAssertEqual(result.invoiceNumber, "2025/097")
    }
}
