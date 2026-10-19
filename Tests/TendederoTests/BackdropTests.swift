import XCTest
@testable import Tendedero

final class BackdropTests: XCTestCase {
    func testFitKeepsTheRoomOnEverySide() {
        let backdrop = Backdrop(padding: 0.1, shadow: false)
        // A 400 × 100 photo: its unit is 200, so 20 pixels round it.
        let layout = backdrop.layout(width: 400, height: 100)
        XCTAssertEqual(layout.canvas, CGSize(width: 440, height: 140))
        XCTAssertEqual(layout.picture, CGRect(x: 20, y: 20, width: 400, height: 100))
        XCTAssertEqual(layout.blur, 0)
        XCTAssertEqual(layout.drop, 0)
    }

    func testARatioGrowsOnlyTheShortWay() {
        var backdrop = Backdrop(padding: 0.1)
        backdrop.ratio = .square
        let layout = backdrop.layout(width: 400, height: 100)
        XCTAssertEqual(layout.canvas.width, 440)
        XCTAssertEqual(layout.canvas.height, 440)
        // In the middle, with at least the chosen room.
        XCTAssertEqual(layout.picture.minX, 20)
        XCTAssertEqual(layout.picture.minY, 170)

        backdrop.ratio = .story
        let tall = backdrop.layout(width: 1000, height: 1000)
        XCTAssertEqual(tall.canvas.width, 1200)
        XCTAssertEqual(tall.canvas.height, (1200 * 16.0 / 9).rounded())
        XCTAssertGreaterThanOrEqual(tall.picture.minY, 100)
    }

    func testAPlaceFollowsThePhotoOntoTheCanvas() {
        let backdrop = Backdrop(padding: 0.1)
        let layout = backdrop.layout(width: 400, height: 100)
        let whole = Backdrop.place(CGRect(x: 0, y: 0, width: 1, height: 1), in: layout)
        XCTAssertEqual(whole.minX, 20.0 / 440, accuracy: 1e-9)
        XCTAssertEqual(whole.minY, 20.0 / 140, accuracy: 1e-9)
        XCTAssertEqual(whole.width, 400.0 / 440, accuracy: 1e-9)
        XCTAssertEqual(whole.height, 100.0 / 140, accuracy: 1e-9)
    }

    func testCornersNeverPassHalfTheShortSide() {
        let backdrop = Backdrop(padding: 0.02, corners: 1)
        let layout = backdrop.layout(width: 2000, height: 10)
        XCTAssertLessThanOrEqual(layout.radius, 5)
    }

    func testPaddingIsKeptInRange() {
        let tiny = Backdrop(padding: -1).layout(width: 100, height: 100)
        XCTAssertEqual(tiny.picture.minX, 2)
        let huge = Backdrop(padding: 5).layout(width: 100, height: 100)
        XCTAssertEqual(huge.picture.minX, 20)
    }

    func testAnOldDrawingStillReads() throws {
        // Saved before backgrounds: no backdrop in it.
        let old = #"{"marks":[]}"#.data(using: .utf8)!
        let drawing = try JSONDecoder().decode(Drawing.self, from: old)
        XCTAssertNil(drawing.backdrop)
        XCTAssertTrue(drawing.isEmpty)

        var framed = drawing
        framed.backdrop = Backdrop()
        XCTAssertFalse(framed.isEmpty)
        XCTAssertNotEqual(framed.key, drawing.key)
        let again = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(framed))
        XCTAssertEqual(again, framed)
    }
}
