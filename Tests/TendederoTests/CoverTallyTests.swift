import Foundation
import XCTest
@testable import Tendedero

/// The week's line in Settings › Privacy: counts kept day by day, the last
/// seven summed, nothing said before something was covered, and the count
/// the menu bar icon says.
final class CoverTallyTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testTheLastSevenDaysAreSummed() throws {
        let suite = "CoverTallyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        XCTAssertNil(CoverTally.sentence(CoverTally.week(until: now, in: defaults)), "nothing to say yet")
        CoverTally.note(details: 3, on: now, in: defaults)
        CoverTally.note(details: 2, on: now.addingTimeInterval(-2 * day), in: defaults)
        CoverTally.note(details: 0, on: now, in: defaults)
        // Eight days ago is outside the week.
        CoverTally.note(details: 9, on: now.addingTimeInterval(-8 * day), in: defaults)
        XCTAssertEqual(CoverTally.week(until: now, in: defaults), CoverTally.Day(photos: 2, details: 5))
        XCTAssertEqual(CoverTally.sentence(CoverTally.Day(photos: 2, details: 5)),
                       "In the last 7 days, Snapfly covered 5 details in 2 photos you sent.")
        XCTAssertEqual(CoverTally.sentence(CoverTally.Day(photos: 1, details: 4)),
                       "In the last 7 days, Snapfly covered 4 details in one photo you sent.")
        XCTAssertEqual(CoverTally.sentence(CoverTally.Day(photos: 1, details: 1)),
                       "In the last 7 days, Snapfly covered one detail in a photo you sent.")
    }

    func testTheMenuBarIconSaysHowManyHang() {
        XCTAssertNil(AppDelegate.statusCount(0, new: false))
        XCTAssertEqual(AppDelegate.statusCount(1, new: false), "One photo on the line")
        XCTAssertEqual(AppDelegate.statusCount(4, new: true), "4 photos on the line, something new")
    }
}
