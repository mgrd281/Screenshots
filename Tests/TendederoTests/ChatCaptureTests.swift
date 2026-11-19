import CoreGraphics
import XCTest
@testable import Tendedero

/// How a whole chat is scrolled for its pictures and its video: how far
/// each glide goes, how smoothly, and how the bottom is told.
final class ChatCaptureTests: XCTestCase {
    func testEachGlideGoesWellUnderHalfTheWindow() {
        XCTAssertEqual(ChatScroll.step(forHeight: 900), 304)
        XCTAssertLessThan(CGFloat(ChatScroll.step(forHeight: 900)), 900 / 2)
        // A small window still moves.
        XCTAssertEqual(ChatScroll.step(forHeight: 150), 80)
    }

    func testAKnownBoxIsScrolledByItsHeightLessALine() {
        XCTAssertEqual(ChatScroll.step(forBox: 432), 400)
        XCTAssertEqual(ChatScroll.step(forBox: 432.9), 400)
        // A tiny box still moves.
        XCTAssertEqual(ChatScroll.step(forBox: 50), 80)
    }

    func testTheBottomIsWhereAGlideFallsShort() {
        XCTAssertFalse(ChatScroll.reachedBottom(moved: 800, asked: 800))
        XCTAssertFalse(ChatScroll.reachedBottom(moved: 721, asked: 800))
        XCTAssertTrue(ChatScroll.reachedBottom(moved: 719, asked: 800))
        XCTAssertTrue(ChatScroll.reachedBottom(moved: 1, asked: 800))
    }

    func testThePageMovingAroundTheBoxIsNotANewPicture() {
        // The header above the box moved too: only the page moved.
        XCTAssertTrue(ChatScroll.onlyThePageMoved(top: 30, boxTop: 70, moved: 50))
        // The box scrolled, its header stayed.
        XCTAssertFalse(ChatScroll.onlyThePageMoved(top: 70, boxTop: 70, moved: 300))
        XCTAssertFalse(ChatScroll.onlyThePageMoved(top: 62, boxTop: 70, moved: 300))
        // Something changed but no one move fits, as when both moved.
        XCTAssertFalse(ChatScroll.onlyThePageMoved(top: 0, boxTop: 70, moved: 1))
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
