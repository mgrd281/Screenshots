import XCTest
@testable import Tendedero

/// The time stamp: its words, the band's size, what it records, and which
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

    func testBandGrowsWithTheImage() {
        // A Retina screen: the text is 27 pixels, about 14 points.
        XCTAssertEqual(TimeStamp.Metrics(width: 2880).font, 27)
        // A small capture keeps a readable minimum.
        XCTAssertEqual(TimeStamp.Metrics(width: 800).font, 11)
    }

    func testBandIsTallerForMoreLines() {
        let m = TimeStamp.Metrics(width: 2880)
        let short = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: false), text: "", locale: german,
                                   timeZone: utc, rightToLeft: false)
        let full = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: "https://example.com/",
                                                   fingerprint: "ab12"),
                                  text: "", locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertEqual(short.rows.count, 2)
        XCTAssertEqual(full.rows.count, 4)
        XCTAssertGreaterThan(m.height(for: full.rows), m.height(for: short.rows))
    }

    func testBandSaysWhereTheTimeCameFrom() {
        let atomic = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true), text: "Officehauss",
                                    locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertTrue(atomic.rows[0].text.hasPrefix("Officehauss · "))
        XCTAssertTrue(atomic.rows[1].text.contains("PTB"))
        let mac = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: false), text: "",
                                 locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertFalse(mac.rows[1].text.contains("PTB"))
    }

    func testWebsiteAndFingerprintAreWritten() {
        let mark = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: "www.kaufland.de",
                                                   fingerprint: "0f3a"),
                                  text: "", locale: german, timeZone: utc, rightToLeft: true)
        XCTAssertTrue(mark.rows[2].text.contains("www.kaufland.de"))
        XCTAssertEqual(mark.rows[3].kind, .code)
        XCTAssertTrue(mark.rows[3].text.contains("0f3a"))
        XCTAssertTrue(mark.rightToLeft)
    }

    /// The page's whole address, as evidence needs it, as a link.
    func testThePagesWholeAddressIsALink() {
        let page = "https://businessapp.b2b.trustpilot.com/reviews?filter=1"
        let mark = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: page),
                                  text: "", locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertEqual(mark.rows.count, 3)
        XCTAssertEqual(mark.rows[2].kind, .link)
        XCTAssertTrue(mark.rows[2].text.contains("/reviews?filter=1"))
        XCTAssertEqual(mark.rows[2].url, URL(string: page))
        // A file open in the browser is no website: no line for it.
        let file = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: "file:///Users/lena/Kontoauszug.pdf"),
                                  text: "", locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertEqual(file.rows.count, 2)
    }

    /// A long address goes on over three lines at most, each a link to it.
    func testALongAddressGoesOnOverThreeLinesAtMost() {
        let page = "https://example.com/" + String(repeating: "a", count: 900)
        let mark = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: page),
                                  text: "", locale: german, timeZone: utc, rightToLeft: false)
        let rows = TimeStamp.laidOut(mark, width: 1200)
        let links = rows.filter { $0.kind == .link }
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.allSatisfy { $0.url == URL(string: page) })
        XCTAssertEqual(rows.count, 5)
        // A short one stays on one line.
        let short = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: "https://example.com/a"),
                                   text: "", locale: german, timeZone: utc, rightToLeft: false)
        XCTAssertEqual(TimeStamp.laidOut(short, width: 1200).count, 3)
    }

    /// The band says where each line of the address is, from its top left.
    func testTheBandKnowsWhereItsLinksAre() throws {
        let page = "https://example.com/review/42"
        let mark = TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: page),
                                  text: "", locale: german, timeZone: utc, rightToLeft: false)
        let band = try XCTUnwrap(TimeStamp.band(mark, width: 1600))
        XCTAssertEqual(band.image.width, 1600)
        XCTAssertEqual(band.image.height, TimeStamp.bandHeight(mark, width: 1600))
        let link = try XCTUnwrap(band.links.first)
        XCTAssertEqual(band.links.count, 1)
        XCTAssertEqual(link.url, URL(string: page))
        XCTAssertGreaterThan(link.rect.width, 0)
        XCTAssertGreaterThan(link.rect.minY, 0)
        XCTAssertLessThanOrEqual(link.rect.maxY, CGFloat(band.image.height))
    }

    func testRecordSurvivesTheRoundTrip() throws {
        let record = TimeStamp.Record(taken: taken, atomic: true, page: "https://example.com/", fingerprint: "ab")
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(TimeStamp.Record.self, from: data), record)
    }

    func testFingerprintIsSHA256() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(TimeStamp.fingerprint(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testWholeScreenIsOneOfTheScreens() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        XCTAssertTrue(TimeStamp.isScreen(CGRect(x: 1512, y: 0, width: 1920, height: 1080), among: screens))
        XCTAssertTrue(TimeStamp.isScreen(CGRect(x: 0.5, y: 0, width: 1511.5, height: 982), among: screens))
        XCTAssertFalse(TimeStamp.isScreen(CGRect(x: 100, y: 100, width: 800, height: 600), among: screens))
    }
}
