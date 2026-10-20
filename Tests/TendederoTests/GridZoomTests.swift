import XCTest
@testable import Tendedero

/// The iPhone's grids of screenshots: three to a row, four pinched closer,
/// three rows on the Photos tab, and how the grid follows a pinch.
final class GridZoomTests: XCTestCase {
    func testThreeToARowUntilPinchedCloser() {
        XCTAssertEqual(GridZoom.standard, 3)
        XCTAssertEqual(GridZoom.after(pinch: 0.8, from: 3), 4)
        XCTAssertEqual(GridZoom.after(pinch: 1.25, from: 4), 3)
    }

    func testASmallPinchChangesNothing() {
        XCTAssertEqual(GridZoom.after(pinch: 0.95, from: 3), 3)
        XCTAssertEqual(GridZoom.after(pinch: 1.05, from: 4), 4)
    }

    func testThePinchStopsAtThreeAndFour() {
        XCTAssertEqual(GridZoom.after(pinch: 2, from: 3), 3)
        XCTAssertEqual(GridZoom.after(pinch: 0.3, from: 4), 4)
        // A number kept by another version is brought into range.
        XCTAssertEqual(GridZoom.clamped(7), 4)
        XCTAssertEqual(GridZoom.clamped(0), 3)
        XCTAssertEqual(GridZoom.after(pinch: 0.5, from: 9), 4)
    }

    func testTheGridFollowsTheFingersAsFarAsTheNextGrid() {
        XCTAssertEqual(GridZoom.scale(pinch: 0.9, columns: 3), 0.9, accuracy: 0.0001)
        // Four to a row is three quarters of three.
        XCTAssertEqual(GridZoom.scale(pinch: 0.5, columns: 3), 0.75, accuracy: 0.0001)
        XCTAssertEqual(GridZoom.scale(pinch: 2, columns: 4), 4.0 / 3.0, accuracy: 0.0001)
        // Where the grid can't change, it only gives a little.
        XCTAssertEqual(GridZoom.scale(pinch: 2, columns: 3), 1.04, accuracy: 0.0001)
        XCTAssertEqual(GridZoom.scale(pinch: 0.5, columns: 4), 0.96, accuracy: 0.0001)
        XCTAssertEqual(GridZoom.scale(pinch: 1.1, columns: 3), 1.015, accuracy: 0.0001)
    }

    func testThePhotosTabShowsThreeRows() {
        XCTAssertEqual(GridZoom.preview(columns: 3), 9)
        XCTAssertEqual(GridZoom.preview(columns: 4), 12)
    }
}
