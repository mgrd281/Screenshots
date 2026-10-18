import XCTest
@testable import Tendedero

/// Crop: where the photo shows over the screen, and how a drag over it
/// becomes the part kept, as a drawing keeps it.
final class QuickCropTests: XCTestCase {
    /// A Retina screen's room, the menu bar and the hint's room left out.
    private let room = CGRect(x: 0, y: 80, width: 1512, height: 863)

    func testAWholeScreenshotShowsAt80PercentInTheMiddle() {
        let photo = QuickCropLayout.frame(for: CGSize(width: 3024, height: 1964), scale: 2, in: room)
        // Held by the height: 80% of the room, with the photo's own shape.
        XCTAssertEqual(photo.height, 690)
        XCTAssertEqual(photo.width, 1063)
        XCTAssertEqual(photo.midX, room.midX, accuracy: 1)
        XCTAssertEqual(photo.midY, room.midY, accuracy: 1)
        XCTAssertTrue(room.contains(photo))
    }

    func testASmallScreenshotIsNeverShownLargerThanItself() {
        let photo = QuickCropLayout.frame(for: CGSize(width: 600, height: 400), scale: 2, in: room)
        XCTAssertEqual(photo.size, CGSize(width: 300, height: 200))
        // A tall page fits by its height.
        let page = QuickCropLayout.frame(for: CGSize(width: 2880, height: 40000), scale: 2, in: room)
        XCTAssertEqual(page.height, 690)
        XCTAssertLessThan(page.width, 60)
    }

    func testADragBecomesThePartKeptFromTheBottomLeft() {
        let photo = CGRect(x: 100, y: 200, width: 400, height: 200)
        let crop = QuickCropLayout.crop(CGRect(x: 200, y: 250, width: 200, height: 100), in: photo)
        XCTAssertEqual(crop, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        // And back, where a part kept before shows.
        XCTAssertEqual(QuickCropLayout.area(of: crop!, in: photo), CGRect(x: 200, y: 250, width: 200, height: 100))
    }

    func testADragPastThePhotoKeepsToItsEdges() {
        let photo = CGRect(x: 100, y: 200, width: 400, height: 200)
        let crop = QuickCropLayout.crop(CGRect(x: 0, y: 300, width: 300, height: 500), in: photo)
        XCTAssertEqual(crop, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        // Over all of it, it keeps all of it, which a drawing keeps as no crop.
        let whole = QuickCropLayout.crop(CGRect(x: 0, y: 0, width: 1000, height: 1000), in: photo)
        XCTAssertEqual(whole, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertNil(Drawing.pixels(of: whole!, width: 3024, height: 1964))
    }

    func testTooLittleOnThePhotoIsNotMeant() {
        let photo = CGRect(x: 100, y: 200, width: 400, height: 200)
        XCTAssertNil(QuickCropLayout.crop(CGRect(x: 200, y: 250, width: 3, height: 80), in: photo))
        XCTAssertNil(QuickCropLayout.crop(CGRect(x: 600, y: 250, width: 80, height: 80), in: photo))
        XCTAssertNotNil(QuickCropLayout.crop(CGRect(x: 200, y: 250, width: 4, height: 4), in: photo))
    }

    func testThePartKeptIsCutFromThePixelsThatGo() {
        // The right half of the bottom half of a Retina screenshot.
        let kept = Drawing.pixels(of: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), width: 3024, height: 1964)
        XCTAssertEqual(kept, CGRect(x: 1512, y: 982, width: 1512, height: 982))
    }
}
