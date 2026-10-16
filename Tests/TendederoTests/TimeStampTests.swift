import XCTest
@testable import Tendedero

/// The time stamp: its words, its size on an image, its corner, and which
/// captures are of a whole screen.
final class TimeStampTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let german = Locale(identifier: "de_DE")
    // October 16, 2026, 23:30 in UTC: already the 17th in Berlin.
    private let taken = Date(timeIntervalSince1970: 1_792_193_400)

    func testDateAndTimeAloneWithoutWords() {
        let label = TimeStamp.label(text: "  ", date: taken, locale: german, timeZone: utc)
        XCTAssertFalse(label.contains("·"))
        XCTAssertTrue(label.contains("2026"))
        XCTAssertTrue(label.contains("23:30"))
    }

    func testWordsComeFirst() {
        let label = TimeStamp.label(text: " Officehauss ", date: taken, locale: german, timeZone: utc)
        XCTAssertTrue(label.hasPrefix("Officehauss · "))
    }

    func testTimeIsTheMacsOwn() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let label = TimeStamp.label(text: "", date: taken, locale: german, timeZone: berlin)
        XCTAssertTrue(label.contains("01:30"))
        XCTAssertTrue(label.contains("17"))
    }

    func testStampGrowsWithTheImage() {
        // A Retina screen: the text is 29 pixels, about 15 points.
        XCTAssertEqual(TimeStamp.metrics(width: 2880, height: 1800).font, 29)
        // A small capture keeps a readable minimum.
        XCTAssertEqual(TimeStamp.metrics(width: 800, height: 600).font, 12)
    }

    func testStampSitsInTheTrailingCorner() {
        let m = TimeStamp.metrics(width: 2880, height: 1800)
        let ltr = TimeStamp.capsule(width: 2880, height: 1800, content: 400, metrics: m, rightToLeft: false)
        XCTAssertEqual(ltr?.maxX, 2880 - m.margin)
        XCTAssertEqual(ltr?.minY, m.margin)
        let rtl = TimeStamp.capsule(width: 2880, height: 1800, content: 400, metrics: m, rightToLeft: true)
        XCTAssertEqual(rtl?.minX, m.margin)
        XCTAssertEqual(rtl?.width, 400 + m.padding * 2)
    }

    func testNoStampWhereItDoesNotFit() {
        let m = TimeStamp.metrics(width: 120, height: 40)
        XCTAssertNil(TimeStamp.capsule(width: 120, height: 40, content: 300, metrics: m, rightToLeft: false))
    }

    func testWholeScreenIsOneOfTheScreens() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        XCTAssertTrue(TimeStamp.isScreen(CGRect(x: 1512, y: 0, width: 1920, height: 1080), among: screens))
        XCTAssertTrue(TimeStamp.isScreen(CGRect(x: 0.5, y: 0, width: 1511.5, height: 982), among: screens))
        XCTAssertFalse(TimeStamp.isScreen(CGRect(x: 100, y: 100, width: 800, height: 600), among: screens))
    }
}
