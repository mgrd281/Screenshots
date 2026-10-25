import XCTest
@testable import Tendedero

/// How well a page's smallest print reads (`ScanReadability`): the mean of
/// how sure the reading was of the lines about as small as the smallest,
/// a hint "Small print is unsharp" where that is under 0.9, placed on the
/// lines read least surely. Large print read surely says nothing of the
/// small print, and a line of a letter or two does not count.
final class ScanReadabilityTests: XCTestCase {
    private func line(_ text: String, row: Int, height: CGFloat, sure: Float) -> ScanReadability.Line {
        ScanReadability.Line(text: text, box: CGRect(x: 0.1, y: 0.9 - CGFloat(row) * 0.05, width: 0.5, height: height),
                             confidence: sure)
    }

    func testSmallPrintReadUnsurelyIsAHintOnItsLines() throws {
        let lines = [
            line("Sehr geehrte Frau Kollegin,", row: 0, height: 0.02, sure: 1),
            line("die Untersuchung ergab einen unauffälligen Befund.", row: 1, height: 0.02, sure: 1),
            line("Musterwall 7a · 20354 Hamburg", row: 3, height: 0.01, sure: 0.5),
            line("Telefon 040 1234567-0", row: 4, height: 0.011, sure: 1),
            line("praxis@radiologie-musterwall.de", row: 5, height: 0.012, sure: 0.5),
        ]
        let measured = try XCTUnwrap(ScanReadability.score(lines))
        XCTAssertEqual(measured.score, 2.0 / 3, accuracy: 0.001, "the small lines only")
        let issue = try XCTUnwrap(ScanReadability.issue(lines))
        XCTAssertEqual(issue.kind, .smallPrint)
        XCTAssertEqual(issue.area, lines[2].box.union(lines[4].box), "on the lines read least surely")
        XCTAssertEqual(issue.message(in: .color), "Small print is unsharp")
        XCTAssertTrue(issue.asksForRetake)
    }

    func testSmallPrintReadSurelyAndShortLinesSayNothing() {
        let lines = [
            line("Sehr geehrte Frau Kollegin,", row: 0, height: 0.02, sure: 0.5),
            line("Musterwall 7a · 20354 Hamburg", row: 3, height: 0.01, sure: 1),
            line("a", row: 4, height: 0.005, sure: 0.3),
        ]
        XCTAssertNil(ScanReadability.issue(lines), "large print unsure, small print sure")
        XCTAssertNil(ScanReadability.score([]))
    }

    func testSmallPrintComesAfterBlurAndBeforeTheLens() {
        let issues = [ScanIssue(.smudge), ScanIssue(.smallPrint), ScanIssue(.blurred)]
        XCTAssertEqual(ScanIssue.ordered(issues).map(\.kind), [.blurred, .smallPrint, .smudge])
    }
}
