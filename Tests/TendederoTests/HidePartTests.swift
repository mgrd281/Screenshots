import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// How large the Hide Part window opens: the picture as large as fits
/// beside the inspector, never larger than itself, and the window never
/// smaller than its minimum nor larger than the room on the screen.
final class HidePartTests: XCTestCase {
    private let room = CGSize(width: 1152, height: 720)

    func testAPortraitPageOpensAWideWindowThatFitsTheScreen() {
        let size = HidePartLayout.windowSize(for: CGSize(width: 595, height: 842), pages: 2, in: room)
        XCTAssertGreaterThan(size.width, size.height)
        XCTAssertLessThanOrEqual(size.width, room.width)
        XCTAssertLessThanOrEqual(size.height, room.height)
        // The page takes all the height there is.
        XCTAssertGreaterThanOrEqual(size.height, room.height - 1)
        // Beside it, the inspector and the margins; the rest is the page.
        let page = size.width - HidePartLayout.panelWidth - 2 * HidePartLayout.margin
        XCTAssertEqual(page / (size.height - 2 * HidePartLayout.margin - HidePartLayout.pagesHeight), 595.0 / 842, accuracy: 0.01)
    }

    func testASmallPictureIsNotEnlargedAndTheWindowIsNeverSmallerThanItsMinimum() {
        let small = CGSize(width: 300, height: 200)
        XCTAssertEqual(HidePartLayout.fitted(small, in: CGSize(width: 1000, height: 1000)), small)
        XCTAssertEqual(HidePartLayout.windowSize(for: small, pages: 1, in: room), HidePartLayout.minimum)
    }

    func testAHugePictureFillsTheRoomAndNoMore() {
        let size = HidePartLayout.windowSize(for: CGSize(width: 5000, height: 3000), pages: 1, in: room)
        XCTAssertEqual(size.width, room.width)
        XCTAssertLessThanOrEqual(size.height, room.height)
        XCTAssertGreaterThanOrEqual(size.height, HidePartLayout.minimum.height)
    }

    func testNothingBreaksOnAnEmptyPictureOrNoRoom() {
        XCTAssertEqual(HidePartLayout.fitted(.zero, in: room), .zero)
        XCTAssertEqual(HidePartLayout.fitted(CGSize(width: 10, height: 10), in: CGSize(width: -5, height: -5)), .zero)
        XCTAssertEqual(HidePartLayout.windowSize(for: CGSize(width: 800, height: 600), pages: 1, in: .zero),
                       HidePartLayout.minimum)
    }
}
