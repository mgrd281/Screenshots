import CoreGraphics
import XCTest
@testable import Tendedero

/// How a whole chat is scrolled for its pictures and its video: where the
/// pointer rests, how far each glide goes, how smoothly, and how the bottom
/// is told.
final class ChatCaptureTests: XCTestCase {
    func testThePointerStaysWhereItIsWhenItIsOverTheWindow() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let point = ChatScroll.restingPoint(in: frame, pointer: CGPoint(x: 400.4, y: 300.6))
        XCTAssertEqual(point, CGPoint(x: 400, y: 301))
    }

    func testElseThePointerRestsRightOfTheMiddle() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        // In the menu bar, as when the menu started it.
        XCTAssertEqual(ChatScroll.restingPoint(in: frame, pointer: CGPoint(x: 500, y: 10)), CGPoint(x: 700, y: 450))
        // At the window's very edge, where its own bars are.
        XCTAssertEqual(ChatScroll.restingPoint(in: frame, pointer: CGPoint(x: 110, y: 400)), CGPoint(x: 700, y: 450))
        XCTAssertEqual(ChatScroll.restingPoint(in: frame, pointer: nil), CGPoint(x: 700, y: 450))
    }

    func testEachGlideGoesWellUnderHalfTheWindow() {
        XCTAssertEqual(ChatScroll.step(forHeight: 900), 304)
        XCTAssertLessThan(CGFloat(ChatScroll.step(forHeight: 900)), 900 / 2)
        // A small window still moves.
        XCTAssertEqual(ChatScroll.step(forHeight: 150), 80)
    }

    func testAGlideAddsUpAndIsSlowAtBothEnds() {
        let pieces = ChatScroll.glide(-304)
        XCTAssertEqual(pieces.reduce(0) { $0 + Int($1) }, -304)
        XCTAssertTrue(pieces.allSatisfy { $0 < 0 })
        XCTAssertTrue(pieces.allSatisfy { abs(Int($0)) <= Scrolling.mostPerTurn })
        let middle = abs(Int(pieces[pieces.count / 2]))
        XCTAssertLessThan(abs(Int(pieces.first!)), middle)
        XCTAssertLessThan(abs(Int(pieces.last!)), middle)

        let up = ChatScroll.glide(500, turns: 10)
        XCTAssertEqual(up.reduce(0) { $0 + Int($1) }, 500)
        XCTAssertTrue(up.allSatisfy { $0 > 0 })
        // Fewer points than turns: no turn of nothing.
        let short = ChatScroll.glide(5, turns: 42)
        XCTAssertEqual(short.reduce(0) { $0 + Int($1) }, 5)
        XCTAssertFalse(short.contains(0))
        XCTAssertEqual(ChatScroll.glide(0), [])
    }

    func testTheBottomIsWhereTheChatNoLongerMoves() {
        let plain = Array(repeating: [UInt8](repeating: 200, count: PageStitch.samples), count: 400)
        // The same view: it did not move.
        XCTAssertFalse(ChatScroll.moved(plain, plain))
        // A blinking caret, two rows: still not moved.
        var caret = plain
        caret[300] = [UInt8](repeating: 0, count: PageStitch.samples)
        caret[301] = [UInt8](repeating: 0, count: PageStitch.samples)
        XCTAssertFalse(ChatScroll.moved(plain, caret))
        // A small chat box, scrolled: it moved, though so much of the window
        // stayed as it was that the views count as alike for a whole page.
        var scrolled = plain
        for row in 100..<190 where row % 3 == 0 {
            scrolled[row] = [UInt8](repeating: 40, count: PageStitch.samples)
        }
        XCTAssertTrue(PageStitch.alike(plain, scrolled))
        XCTAssertTrue(ChatScroll.moved(plain, scrolled))
    }
}
