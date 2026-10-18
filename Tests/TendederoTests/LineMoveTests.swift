import Foundation
import XCTest
@testable import Tendedero

/// Holding the grip and dragging moves the line across the screen: every
/// photo and the tag stay on it, a rope's tag stays clipped near its end,
/// a fan arcs around its own middle, and a line longer than the screen
/// stays where it always hung.
final class LineMoveTests: XCTestCase {
    private var savedStyle: Layout.Style!
    private var savedAcross: CGFloat = 0
    private var savedKeep: Int?
    private let width: CGFloat = 1440
    private let visible = 7

    override func setUp() {
        savedStyle = Layout.style
        savedAcross = Layout.across
        savedKeep = Line.keepOnLine
        Layout.across = 0
        Line.keepOnLine = nil
    }

    override func tearDown() {
        Layout.style = savedStyle
        Layout.across = savedAcross
        Line.keepOnLine = savedKeep
    }

    private func xs(_ count: Int) -> [CGFloat] {
        (0..<count).map { Layout.x(index: $0, count: count, width: width, visible: visible, scroll: 0) }
    }

    private func tag(_ count: Int) -> CGFloat {
        Layout.tagX(count: count, width: width, visible: visible, scroll: 0)
    }

    func testWhereItAlwaysHungIsTheMiddle() {
        Layout.style = .floating
        XCTAssertEqual(Layout.shift(count: 1, width: width, visible: visible), 0)
        XCTAssertEqual(xs(1), [width / 2])
    }

    func testMovedLeftThePhotosAndTheTagGoTogether() {
        Layout.style = .floating
        let before = tag(2) - xs(2)[1]
        Layout.across = -0.3
        XCTAssertEqual(Layout.shift(count: 2, width: width, visible: visible), -0.3 * width, accuracy: 0.001)
        XCTAssertEqual(tag(2) - xs(2)[1], before, accuracy: 0.001)
        XCTAssertLessThan(xs(2)[1], width / 2)
    }

    func testEveryStyleKeepsThePhotosAndTheTagOnTheScreen() {
        for style in Layout.Style.allCases {
            Layout.style = style
            for across in [-0.5, -0.2, 0.2, 0.5] as [CGFloat] {
                Layout.across = across
                for count in 1...visible {
                    let photos = xs(count), tag = tag(count)
                    let label = "\(style), \(across), \(count)"
                    XCTAssertGreaterThanOrEqual(photos.min()!, Layout.photoInset - 0.001, label)
                    XCTAssertLessThanOrEqual(photos.max()!, width - Layout.photoInset + 0.001, label)
                    XCTAssertLessThanOrEqual(tag + Layout.tagWidth / 2, width - 16, label)
                    XCTAssertGreaterThan(tag, photos.max()!, label)
                    if style != .stack {
                        // The tag never stands on the last photo.
                        XCTAssertGreaterThanOrEqual(tag - Layout.tagWidth / 2, photos.max()! + Layout.cardWidth / 2,
                                                    label)
                    }
                }
            }
        }
    }

    func testARopeKeepsItsTagNearItsEnd() {
        Layout.style = .clothesline
        Layout.across = -0.4
        XCTAssertEqual(tag(3), width - 64)
        XCTAssertLessThan(xs(3)[1], width / 2)
        Layout.across = 0.5
        XCTAssertLessThanOrEqual(xs(3)[2] + Layout.cardWidth / 2, tag(3) - Layout.tagWidth / 2)
    }

    func testAFanArcsAroundItsOwnMiddle() {
        Layout.style = .fan
        Layout.across = -0.25
        let photos = xs(3)
        let shift = Layout.shift(count: 3, width: width, visible: visible)
        XCTAssertEqual(Layout.ropeY(x: photos[0], width: width, shift: shift),
                       Layout.ropeY(x: photos[2], width: width, shift: shift), accuracy: 0.001)
        XCTAssertLessThan(Layout.ropeY(x: photos[1], width: width, shift: shift),
                          Layout.ropeY(x: photos[0], width: width, shift: shift))
    }

    func testAStackMovesWithItsTag() {
        Layout.style = .stack
        let before = tag(3) - xs(3)[2]
        Layout.across = -0.4
        XCTAssertLessThan(xs(3)[2], width / 2)
        XCTAssertEqual(tag(3) - xs(3)[2], before, accuracy: 0.001)
    }

    func testALineLongerThanTheScreenStaysWhereItAlwaysHung() {
        Layout.style = .floating
        Line.keepOnLine = 25
        Layout.across = -0.4
        XCTAssertEqual(Layout.shift(count: 12, width: width, visible: visible), 0)
        XCTAssertTrue(Layout.scrolls(count: 12, visible: visible))
        XCTAssertFalse(Layout.scrolls(count: 3, visible: visible))
    }

    func testAMoveIsHeldBackAtTheEdgeAndKeptAsAShare() {
        Layout.style = .floating
        let farthest = Layout.shift(count: 1, width: width, visible: visible, wanted: -10_000)
        XCTAssertEqual(width / 2 + farthest, Layout.photoInset, accuracy: 0.001)
        // The same share of a narrower screen.
        Layout.across = -0.25
        XCTAssertEqual(Layout.shift(count: 1, width: 1000, visible: visible), -250, accuracy: 0.001)
        Layout.across = 3
        XCTAssertEqual(Layout.across, 0.5)
    }
}
