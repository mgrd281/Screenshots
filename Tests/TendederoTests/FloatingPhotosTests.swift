import CoreGraphics
import XCTest
@testable import Tendedero

/// Keep on Top: a photo floats with its longer side at most 360 points, in
/// its own shape, and never larger than it is.
final class FloatingPhotosTests: XCTestCase {
    func testAPhotoFloatsInItsShape() {
        XCTAssertEqual(FloatingPhotos.fitted(CGSize(width: 2880, height: 1800), within: 360), CGSize(width: 360, height: 225))
        XCTAssertEqual(FloatingPhotos.fitted(CGSize(width: 1000, height: 3000), within: 360), CGSize(width: 120, height: 360))
    }

    func testASmallPhotoKeepsItsSize() {
        XCTAssertEqual(FloatingPhotos.fitted(CGSize(width: 200, height: 100), within: 360), CGSize(width: 200, height: 100))
    }
}
