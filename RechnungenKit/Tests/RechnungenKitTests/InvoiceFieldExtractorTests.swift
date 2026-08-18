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

    /// Reproduces a real invoice where Vision's OCR reads a two-column label/value table
    /// column-by-column, so "Rechnungsnummer:" and its value land in separate lines with
    /// other labels in between.
    func test_extract_findsInvoiceNumberWhenLabelAndValueAreInSeparateOCRLines() {
        let result = InvoiceFieldExtractor().extract(from: [
            "RECHNUNG",
            "Rechnungsnummer:",
            "Rechnungsdatum:",
            "Zahlungsstatus:",
            "2026-00282",
            "13. August 2026",
            "Bezahlt am 13. August 2026"
        ])

        XCTAssertEqual(result.invoiceNumber, "2026-00282")
    }

    func test_extract_splitColumnFallbackIgnoresUnrelatedLabelOnlyLine() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Rechnungsnummer:",
            "Ohne passenden Wert in der Nähe"
        ])

        XCTAssertNil(result.invoiceNumber)
    }
}
