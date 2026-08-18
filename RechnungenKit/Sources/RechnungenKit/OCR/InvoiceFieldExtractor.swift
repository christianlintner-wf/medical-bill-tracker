import Foundation

public struct InvoiceFieldExtractor: Sendable {
    public init() {}

    public func extract(from lines: [String]) -> ExtractedInvoiceFields {
        var result = ExtractedInvoiceFields()
        for line in lines {
            if result.invoiceNumber == nil, let value = Self.invoiceNumber(in: line) {
                result.invoiceNumber = value
            }
            if result.amount == nil, let value = Self.amount(in: line) {
                result.amount = value
            }
            if result.date == nil, let value = Self.date(in: line) {
                result.date = value
            }
        }
        if result.invoiceNumber == nil {
            result.invoiceNumber = Self.invoiceNumberFromSplitColumns(in: lines)
        }
        return result
    }

    private static func invoiceNumber(in line: String) -> String? {
        guard let keywordRange = line.range(
            of: #"Rechnungs(nummer|nr\.?)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let remainder = line[keywordRange.upperBound...]
        guard let valueRange = remainder.range(of: #"[A-Za-z0-9\-/]+"#, options: .regularExpression) else {
            return nil
        }
        return String(remainder[valueRange])
    }

    /// Some invoices lay the "Rechnungsnummer:" label and its value out in separate table
    /// columns; Vision's OCR then returns them as two distinct lines (all labels, then all
    /// values) instead of one, so `invoiceNumber(in:)` never sees a value to pair with the
    /// keyword. Look for a bare alphanumeric value shortly after a label-only line instead.
    private static func invoiceNumberFromSplitColumns(in lines: [String]) -> String? {
        guard let labelIndex = lines.firstIndex(where: { line in
            line.range(
                of: #"^\s*Rechnungs(nummer|nr\.?)\s*:?\s*$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }) else {
            return nil
        }
        let searchEnd = min(labelIndex + 7, lines.count)
        guard labelIndex + 1 < searchEnd else { return nil }
        for line in lines[(labelIndex + 1)..<searchEnd] {
            if line.range(of: #"^[A-Za-z0-9][A-Za-z0-9\-/]*$"#, options: .regularExpression) != nil {
                return line
            }
        }
        return nil
    }

    private static func amount(in line: String) -> Decimal? {
        guard let range = line.range(of: #"\d{1,3}(\.\d{3})*,\d{2}|\d+,\d{2}"#, options: .regularExpression) else {
            return nil
        }
        let normalized = String(line[range])
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    private static func date(in line: String) -> Date? {
        guard let range = line.range(of: #"\d{1,2}\.\d{1,2}\.\d{2,4}"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(line[range])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = raw.count > 8 ? "dd.MM.yyyy" : "dd.MM.yy"
        return formatter.date(from: raw)
    }
}
