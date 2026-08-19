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

    /// Austrian Wahlarzt invoices ("Honorarnoten") almost never use the word "Rechnungsnummer" -
    /// they label their reference number "Honorarnote Nr." or the compound "Honorarnotennr."
    func test_extract_findsInvoiceNumberLabelledHonorarnoteNr() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Honorarnote Nr. 1234/056."
        ])

        XCTAssertEqual(result.invoiceNumber, "1234/056")
    }

    func test_extract_findsInvoiceNumberLabelledHonorarnotennr() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Honorarnotennr. 2099/0042"
        ])

        XCTAssertEqual(result.invoiceNumber, "2099/0042")
    }

    /// Vision's OCR frequently renders a printed "/" as "/" surrounded by stray spaces
    /// (e.g. "2025 / 108"). The extractor should still join it into one value.
    func test_extract_joinsInvoiceNumberSegmentsSeparatedBySpacedSlash() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Honorarnote Nr. 1234 / 056"
        ])

        XCTAssertEqual(result.invoiceNumber, "1234/056")
    }

    /// Round-euro amounts are commonly written "100,-" instead of "100,00" on Austrian invoices.
    func test_extract_parsesWholeEuroAmountWrittenWithDash() {
        let result = InvoiceFieldExtractor().extract(from: ["Honorar: 80,-"])

        XCTAssertEqual(result.amount, Decimal(string: "80.00"))
    }

    /// Dentists commonly abbreviate "Rechnungsnummer" as "Re.Nr." / "Re-Nr.".
    func test_extract_findsInvoiceNumberLabelledReNr() {
        let result = InvoiceFieldExtractor().extract(from: ["Re.Nr. 4471100"])

        XCTAssertEqual(result.invoiceNumber, "4471100")
    }

    /// "Rechnungs-Nr:" (with a hyphen before "Nr") is another common label spelling.
    func test_extract_findsInvoiceNumberLabelledRechnungsHyphenNr() {
        let result = InvoiceFieldExtractor().extract(from: ["Rechnungs-Nr: 990122-40021"])

        XCTAssertEqual(result.invoiceNumber, "990122-40021")
    }

    /// A line-item unit price (e.g. "4 x 0,30") earlier in the OCR'd text must not win over
    /// the actual total, which is introduced by a label like "Rechnungsbetrag".
    func test_extract_prefersAmountNearTotalKeywordOverEarlierLineItemPrice() {
        let result = InvoiceFieldExtractor().extract(from: [
            "2 x 1,50",
            "Rechnungsbetrag EUR:",
            "63,40"
        ])

        XCTAssertEqual(result.amount, Decimal(string: "63.40"))
    }

    /// Reproduces a real GOÄ "Honorarnote" (Dr. Stollwerck, issue #20): "Rechnungsbetrag"
    /// appears as a stray label embedded in unrelated payment-instructions boilerplate, far
    /// from any value, while the actual grand total follows a "Summe" label together with two
    /// per-item subtotals - the grand total is the LAST of the three numbers, not the first.
    func test_extract_findsGrandTotalAfterSummeLabelIgnoringDistantRechnungsbetragLabel() {
        let result = InvoiceFieldExtractor().extract(from: [
            "Rechnungsbetrag",
            "Bitte überweisen Sie den Betrag unter Angabe der Rechnungsnummer",
            "bis zum 21.08.26 auf das folgende Konto.",
            "IBAN: DE42 6006 9462 0024 4000 09",
            "EUR Faktor",
            "4,66",
            "2,300",
            "9,33",
            "2,300",
            "EUR",
            "Summe",
            "10,72",
            "21,46",
            "32,18"
        ])

        XCTAssertEqual(result.amount, Decimal(string: "32.18"))
    }
}
