import XCTest
@testable import RechnungenKit

final class SeaTableDateFormatterTests: XCTestCase {
    func test_date_parsesSeaTablesActualISO8601DateTimeFormat() {
        // This is the real shape SeaTable's API returns for a Date column,
        // confirmed via device console logs - not the plain "yyyy-MM-dd" the
        // formatter originally assumed.
        let parsed = SeaTableDateFormatter.date(from: "2026-08-18T00:00:00+02:00")

        XCTAssertNotNil(parsed)
    }

    func test_date_stillParsesPlainDateOnlyStrings() {
        let parsed = SeaTableDateFormatter.date(from: "2026-08-18")

        XCTAssertNotNil(parsed)
    }

    func test_string_thenDate_roundTrips() {
        let original = Date(timeIntervalSince1970: 1_700_000_000)

        let string = SeaTableDateFormatter.string(from: original)
        let parsed = SeaTableDateFormatter.date(from: string)

        XCTAssertNotNil(parsed)
    }
}
