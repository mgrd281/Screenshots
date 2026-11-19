import CoreGraphics
import XCTest
@testable import Tendedero

/// How the window in front is scrolled for a whole page: the wheel's turns
/// in small pieces, and where the pointer rests to scroll it.
final class FullPageTests: XCTestCase {
    func testAScrollIsGivenInSmallPiecesThatAddUp() {
        XCTAssertEqual(Scrolling.pieces(of: 250), [100, 100, 50])
        XCTAssertEqual(Scrolling.pieces(of: -640), [-100, -100, -100, -100, -100, -100, -40])
        XCTAssertEqual(Scrolling.pieces(of: 40), [40])
        XCTAssertEqual(Scrolling.pieces(of: 0), [])
        let pieces = Scrolling.pieces(of: 3000)
        XCTAssertEqual(pieces.reduce(0) { $0 + Int($1) }, 3000)
        XCTAssertTrue(pieces.allSatisfy { abs(Int($0)) <= Scrolling.mostPerTurn })
    }

    func testThePointerRestsInsideTheWindowTowardsItsTrailingSide() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let point = Scrolling.restingPoint(in: frame)
        XCTAssertEqual(point.x, 1000, accuracy: 0.001)
        XCTAssertEqual(point.y, 490, accuracy: 0.001)
        XCTAssertTrue(frame.insetBy(dx: 50, dy: 50).contains(point))
        // Whole points, whatever the window's size.
        let odd = Scrolling.restingPoint(in: CGRect(x: 33.3, y: 7.7, width: 1013, height: 777))
        XCTAssertEqual(odd.x, odd.x.rounded())
        XCTAssertEqual(odd.y, odd.y.rounded())
    }

    func testThePointerMovesClearOfSnapflysOwnWindows() {
        let point = CGPoint(x: 1000, y: 490)
        // Nothing in the way: it stays.
        XCTAssertEqual(Scrolling.clear(point, of: []), point)
        XCTAssertEqual(Scrolling.clear(point, of: [CGRect(x: 0, y: 0, width: 200, height: 40)]), point)
        // The screenshot button right there: one move left clears it.
        let button = CGRect(x: 980, y: 470, width: 40, height: 40)
        let moved = Scrolling.clear(point, of: [button])
        XCTAssertEqual(moved, CGPoint(x: 920, y: 490))
        XCTAssertFalse(button.insetBy(dx: -12, dy: -12).contains(moved))
        // A wide window over the point: five moves at most, then it gives up.
        let wide = CGRect(x: 0, y: 400, width: 1200, height: 200)
        XCTAssertEqual(Scrolling.clear(point, of: [wide]).x, 600)
    }

    func testAPageIsTriedFirstWhereItsOwnBoxesSeldomAre() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let points = Scrolling.candidates(in: frame, pointer: CGPoint(x: 400, y: 300), chat: false)
        XCTAssertEqual(points, [CGPoint(x: 1000, y: 490), CGPoint(x: 400, y: 300),
                                CGPoint(x: 700, y: 450), CGPoint(x: 450, y: 490)])
    }

    func testAChatIsTriedFirstUnderThePointer() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let points = Scrolling.candidates(in: frame, pointer: CGPoint(x: 400.4, y: 300.6), chat: true)
        XCTAssertEqual(points.first, CGPoint(x: 400, y: 301))
        XCTAssertEqual(points.count, 4)
        // The pointer in the menu bar, as when the menu started it: the
        // middle first, and the pointer not at all.
        let fromMenu = Scrolling.candidates(in: frame, pointer: CGPoint(x: 500, y: 10), chat: true)
        XCTAssertEqual(fromMenu, [CGPoint(x: 700, y: 450), CGPoint(x: 450, y: 490), CGPoint(x: 1000, y: 490)])
        // A pointer right on another point is tried once.
        let onTheMiddle = Scrolling.candidates(in: frame, pointer: CGPoint(x: 705, y: 455), chat: true)
        XCTAssertEqual(onTheMiddle.count, 3)
    }

    func testAPointIsInTheColumnUnderIt() {
        let frame = CGRect(x: 100, y: 50, width: 960, height: 800)
        XCTAssertEqual(Scrolling.column(of: CGPoint(x: 100, y: 300), in: frame), 0)
        XCTAssertEqual(Scrolling.column(of: CGPoint(x: 580, y: 300), in: frame), PageStitch.samples / 2)
        XCTAssertEqual(Scrolling.column(of: CGPoint(x: 5000, y: 300), in: frame), PageStitch.samples - 1)
        XCTAssertEqual(Scrolling.column(of: CGPoint(x: 0, y: 300), in: frame), 0)
    }

    /// A window with a chat's box on the left, 36 columns wide, scrolled
    /// this far, and a list of ticket details on the right that stays put.
    private func chatWindow(at offset: Int) -> PageStitch.Rows {
        (0..<400).map { i in
            (0..<PageStitch.samples).map { j in
                j < 36 ? UInt8((((offset + i) * 131) + j * 17) % 200) : UInt8((i * 7 + j * 3) % 250)
            }
        }
    }

    func testTheScrolledBoxIsFoundBesideWhatStays() throws {
        let band = try XCTUnwrap(PageStitch.band(chatWindow(at: 0), chatWindow(at: 120), around: 20))
        XCTAssertEqual(band, 0..<36)
        // Nothing moved under a point over the list on the right.
        XCTAssertNil(PageStitch.band(chatWindow(at: 0), chatWindow(at: 120), around: 44))
        XCTAssertNil(PageStitch.band(chatWindow(at: 0), chatWindow(at: 0), around: 20))
    }

    func testTheBoxMovesAsFarAsItWasScrolledThoughTheListStays() {
        let moved = Scrolling.distance(from: chatWindow(at: 0), to: chatWindow(at: 120), around: 20, expected: 120)
        XCTAssertEqual(moved.rows, 120)
        XCTAssertEqual(moved.band, 0..<36)
        // The whole width, list and all, finds no move that fits.
        XCTAssertNil(PageStitch.step(from: chatWindow(at: 0), to: chatWindow(at: 120), expected: 120))
        // Over the list, nothing scrolled.
        let still = Scrolling.distance(from: chatWindow(at: 0), to: chatWindow(at: 120), around: 44, expected: 120)
        XCTAssertEqual(still.rows, 0)
        XCTAssertNil(still.band)
    }

    /// A page in a window: a toolbar of 30 rows that never moves, then the
    /// page scrolled `page` rows: a header of 40, a chat's box of 250
    /// scrolled `box` rows inside, then its message box and the page's foot.
    private func boxedPage(page: Int, box: Int) -> PageStitch.Rows {
        let toolbar: PageStitch.Rows = (0..<30).map { (i: Int) -> [UInt8] in pattern(i, 1, 1, 0, 30, plus: 220) }
        let header: PageStitch.Rows = (0..<40).map { (i: Int) -> [UInt8] in pattern(i, 37, 5, 3, 190) }
        let messages: PageStitch.Rows = (0..<250).map { (i: Int) -> [UInt8] in pattern(box + i, 131, 17, 0, 200) }
        let foot: PageStitch.Rows = (0..<300).map { (i: Int) -> [UInt8] in pattern(i, 89, 11, 7, 180) }
        let content: PageStitch.Rows = header + messages + foot
        return toolbar + Array(content[page..<(page + 370)])
    }

    /// Row `i` of a pattern: each column's sample is
    /// `(i * down + column * across + start) % range + plus`.
    private func pattern(_ i: Int, _ down: Int, _ across: Int, _ start: Int, _ range: Int,
                         plus: Int = 0) -> [UInt8] {
        var row: [UInt8] = []
        for j in 0..<PageStitch.samples {
            let value: Int = i * down + j * across + start
            row.append(UInt8(value % range + plus))
        }
        return row
    }

    func testTheBoxsHeightIsWhatMovesBetweenWhatStays() {
        let moved = Scrolling.distance(from: boxedPage(page: 0, box: 0), to: boxedPage(page: 0, box: 120),
                                       around: 20, expected: 120)
        XCTAssertEqual(moved.rows, 120)
        XCTAssertEqual(moved.top, 70)
        XCTAssertEqual(moved.span, 250)
    }

    func testThePageMovingAroundTheBoxMovesTheHeaderToo() {
        let moved = Scrolling.distance(from: boxedPage(page: 0, box: 250), to: boxedPage(page: 50, box: 250),
                                       around: 20, expected: 120)
        XCTAssertEqual(moved.rows, 50)
        XCTAssertEqual(moved.top, 30)
        XCTAssertTrue(ChatScroll.onlyThePageMoved(top: moved.top, boxTop: 70, moved: moved.rows))
    }

    func testTheBoxToItsBottomAndThePageTheRestIsNoOneMove() {
        // The box's last 50 rows, then the page 30 more: no one move fits,
        // so the picture is kept, as the last.
        let both = Scrolling.distance(from: boxedPage(page: 0, box: 200), to: boxedPage(page: 30, box: 250),
                                      around: 20, expected: 80)
        XCTAssertEqual(both.rows, 1)
        XCTAssertFalse(ChatScroll.onlyThePageMoved(top: both.top, boxTop: 70, moved: both.rows))
        XCTAssertTrue(ChatScroll.reachedBottom(moved: both.rows, asked: 80))
    }

    func testOnlyTheBoxsColumnsAreCompared() {
        let rows: PageStitch.Rows = [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]]
        XCTAssertEqual(PageStitch.columns(rows, 1..<3), [[2, 3], [7, 8]])
        XCTAssertEqual(PageStitch.columns(rows, 3..<9), [[4, 5], [9, 10]])
    }

    func testAnAppKitFrameIsCountedFromTheTop() {
        // A 40 pt window whose bottom edge sits 200 pt above the bottom of a 900 pt screen.
        let frame = Scrolling.topLeft(CGRect(x: 10, y: 200, width: 40, height: 40), screenHeight: 900)
        XCTAssertEqual(frame, CGRect(x: 10, y: 660, width: 40, height: 40))
    }
}
