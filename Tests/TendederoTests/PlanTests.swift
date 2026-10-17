import Foundation
import XCTest
@testable import Tendedero

/// Pro, later: nothing is held back before it begins, and whoever used
/// Snapfly before keeps every feature.
final class PlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)
    private let day: TimeInterval = 86_400

    func testNothingIsHeldBackYet() {
        XCTAssertNil(Plan.proStarts)
        for feature in Plan.ProFeature.allCases {
            XCTAssertTrue(Plan.allows(feature, firstLaunch: nil, subscribed: false), feature.rawValue)
        }
    }

    func testEverythingStaysOpenUntilProBegins() {
        let dayBefore = start.addingTimeInterval(-day)
        XCTAssertTrue(Plan.allows(.sendLog, now: dayBefore, proStarts: start, firstLaunch: dayBefore))
    }

    func testWhoeverCameBeforeKeepsEveryFeature() {
        let monthLater = start.addingTimeInterval(30 * day)
        let founder = start.addingTimeInterval(-200 * day)
        for feature in Plan.ProFeature.allCases {
            XCTAssertTrue(Plan.allows(feature, now: monthLater, proStarts: start, firstLaunch: founder),
                          feature.rawValue)
        }
    }

    func testNewcomersNeedPro() {
        let monthLater = start.addingTimeInterval(30 * day)
        let newcomer = start.addingTimeInterval(day)
        XCTAssertFalse(Plan.allows(.orderBinder, now: monthLater, proStarts: start, firstLaunch: newcomer))
        XCTAssertFalse(Plan.allows(.orderBinder, now: monthLater, proStarts: start, firstLaunch: nil))
        XCTAssertTrue(Plan.allows(.orderBinder, now: monthLater, proStarts: start, firstLaunch: newcomer,
                                  subscribed: true))
    }

    func testTheFirstLaunchIsKept() throws {
        let suite = "PlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Plan.recordFirstLaunch(in: defaults, now: first), first)
        XCTAssertEqual(Plan.recordFirstLaunch(in: defaults, now: first.addingTimeInterval(3600)), first)
        XCTAssertEqual(defaults.object(forKey: Plan.firstLaunchKey) as? Date, first)
    }
}
