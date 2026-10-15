import XCTest
@testable import Tendedero

/// A photo dragged along the line goes after each one whose middle it has
/// passed, from the line's start, whichever way the line runs.
final class OrderTests: XCTestCase {
    func testLeftToRight() {
        let middles: [CGFloat] = [100, 200, 300]
        XCTAssertEqual(Line.slot(for: 50, among: middles, reversed: false), 0)
        XCTAssertEqual(Line.slot(for: 150, among: middles, reversed: false), 1)
        XCTAssertEqual(Line.slot(for: 250, among: middles, reversed: false), 2)
        XCTAssertEqual(Line.slot(for: 400, among: middles, reversed: false), 3)
    }

    func testRightToLeft() {
        // Arabic: the first photo hangs at the right end.
        let middles: [CGFloat] = [300, 200, 100]
        XCTAssertEqual(Line.slot(for: 400, among: middles, reversed: true), 0)
        XCTAssertEqual(Line.slot(for: 250, among: middles, reversed: true), 1)
        XCTAssertEqual(Line.slot(for: 50, among: middles, reversed: true), 3)
    }
}
