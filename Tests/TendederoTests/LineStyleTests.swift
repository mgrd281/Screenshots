import Foundation
import XCTest
@testable import Tendedero

/// Every way to hang: where the photos hang from stays inside the line's
/// strip, what holds them, and how a fan leans.
final class LineStyleTests: XCTestCase {
    private var saved: Layout.Style!

    override func setUp() {
        saved = Layout.style
    }

    override func tearDown() {
        Layout.style = saved
    }

    func testEveryStyleHasANameAndHangsInsideTheStrip() {
        let width: CGFloat = 1440
        for style in Layout.Style.allCases {
            Layout.style = style
            XCTAssertFalse(style.title.isEmpty, "\(style)")
            for x in stride(from: CGFloat(0), through: width, by: 60) {
                let y = Layout.ropeY(x: x, width: width)
                XCTAssertGreaterThanOrEqual(y, Layout.ropeTop, "\(style) at \(x)")
                // The tallest card still fits under the hanging point.
                let card = Layout.cardBelowTop + Layout.photoMaxHeight + 2 * Frame.inset
                XCTAssertLessThanOrEqual(y - Layout.pinAbove + card, Layout.panelHeight, "\(style) at \(x)")
            }
        }
    }

    func testOnlyARopeAndAWireHaveClipsAndOnlyARopeSways() {
        XCTAssertEqual(Layout.Style.allCases.filter(\.clipped), [.clothesline, .wire])
        XCTAssertEqual(Layout.Style.allCases.filter(\.swings), [.clothesline])
        XCTAssertEqual(Layout.Style.allCases.filter(\.held), [.shelf, .island, .filmstrip])
        XCTAssertEqual(Layout.Style.allCases.filter(\.dark), [.island, .filmstrip])
    }

    func testAWireRunsStraight() {
        Layout.style = .wire
        XCTAssertEqual(Layout.ropeY(x: 0, width: 1440), Layout.ropeY(x: 720, width: 1440))
        XCTAssertEqual(Layout.ropeY(x: 100, width: 1440), Layout.ropeY(x: 1400, width: 1440))
    }

    func testAFanArcsDownAndLeansOutFromTheMiddle() {
        Layout.style = .fan
        let width: CGFloat = 1440
        let middle = width / 2, step = Layout.spacing
        XCTAssertEqual(Layout.fanTilt(x: middle, width: width), 0)
        // Mirror images either side, the outer ones lower and leaning further.
        XCTAssertEqual(Layout.ropeY(x: middle - step, width: width), Layout.ropeY(x: middle + step, width: width))
        XCTAssertGreaterThan(Layout.ropeY(x: middle + 2 * step, width: width), Layout.ropeY(x: middle + step, width: width))
        XCTAssertGreaterThan(Layout.ropeY(x: middle + step, width: width), Layout.ropeY(x: middle, width: width))
        XCTAssertLessThan(Layout.fanTilt(x: middle + step, width: width), 0)
        XCTAssertEqual(Layout.fanTilt(x: middle - step, width: width), -Layout.fanTilt(x: middle + step, width: width))
        // Never more than 14° nor below the deepest point, however far out.
        XCTAssertEqual(Layout.fanTilt(x: width, width: width), -14)
        XCTAssertEqual(Layout.fanDrop(x: 0, width: width), Layout.fanDeepest)
    }

    func testAFilmstripLeavesRoomForItsHoles() throws {
        Layout.style = .filmstrip
        let frame = try XCTUnwrap(Layout.holder(count: 3, width: 1440, visible: 6, scroll: 0))
        let x = Layout.x(index: 0, count: 3, width: 1440, visible: 6, scroll: 0)
        let cardTop = Layout.ropeY(x: x, width: 1440) - Layout.pinAbove + Layout.cardBelowTop
        XCTAssertLessThanOrEqual(frame.minY, cardTop - FilmStrip.band)
        Layout.style = .floating
        XCTAssertNil(Layout.holder(count: 3, width: 1440, visible: 6, scroll: 0))
    }
}
