import Foundation
import XCTest
@testable import Tendedero

/// Receipts for the books: a name that says what each is, and a line in
/// the folder's table, both leaving out what is covered.
final class BookkeepingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let day = Date(timeIntervalSince1970: 1_792_234_567)
    private let fields = [OrderCard.Field(part: .order, value: "1024"), OrderCard.Field(part: .total, value: "74,00 €")]

    func testTheNameSaysTheDayTheOrderAndTheTotal() {
        XCTAssertEqual(Bookkeeping.name(day: day, fields: fields, covering: [], timeZone: utc),
                       "2026-10-17 \(L("Order")) 1024 74,00 €")
        XCTAssertEqual(Bookkeeping.name(day: day, fields: fields, covering: [.orders], timeZone: utc), "2026-10-17 74,00 €")
        XCTAssertEqual(Bookkeeping.name(day: day, fields: [], covering: [], timeZone: utc), "2026-10-17")
        // Nothing a file name cannot hold.
        XCTAssertEqual(Bookkeeping.name(day: day, fields: [OrderCard.Field(part: .order, value: "A/B:1")], covering: [],
                                        timeZone: utc), "2026-10-17 \(L("Order")) A-B-1")
    }

    func testTheTableLineLeavesOutWhatIsCovered() {
        XCTAssertEqual(Bookkeeping.line(day: day, file: "Beleg.png", fields: fields, covering: [.amounts],
                                        separator: ";", timeZone: utc), "2026-10-17;Beleg.png;1024;\r\n")
        XCTAssertEqual(Bookkeeping.headings(separator: ","),
                       "\(L("Date")),\(L("File")),\(L("Order")),\(L("Total"))\r\n")
    }
}
