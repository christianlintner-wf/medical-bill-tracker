import Foundation

enum SeaTableDateFormatter {
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // SeaTable accepts a plain "yyyy-MM-dd" on write, but its API always
    // returns Date columns as a full ISO8601 datetime with a timezone offset
    // (e.g. "2026-08-18T00:00:00+02:00") on read - confirmed via real device
    // logs, not documented anywhere. Both directions need their own formatter.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? dateOnlyFormatter.date(from: string)
    }
}
