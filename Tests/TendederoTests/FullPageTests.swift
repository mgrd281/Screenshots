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
        XCTAssertEqual(point.x, 1000)
        XCTAssertEqual(point.y, 490)
        XCTAssertTrue(frame.insetBy(dx: 50, dy: 50).contains(point))
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

    func testAnAppKitFrameIsCountedFromTheTop() {
        // A 40 pt window whose bottom edge sits 200 pt above the bottom of a 900 pt screen.
        let frame = Scrolling.topLeft(CGRect(x: 10, y: 200, width: 40, height: 40), screenHeight: 900)
        XCTAssertEqual(frame, CGRect(x: 10, y: 660, width: 40, height: 40))
    }
}
