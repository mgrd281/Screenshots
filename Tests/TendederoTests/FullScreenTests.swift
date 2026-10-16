import XCTest
@testable import Tendedero

/// How the App Store edition tells a full screen app from an ordinary window.
final class FullScreenTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testWindowCoveringTheScreen() {
        XCTAssertTrue(FullScreen.fills(display, display: display, notch: 0))
    }

    func testFullScreenBelowTheNotch() {
        let below = CGRect(x: 0, y: 32, width: 1512, height: 950)
        XCTAssertTrue(FullScreen.fills(below, display: display, notch: 32))
        XCTAssertFalse(FullScreen.fills(below, display: display, notch: 0))
    }

    func testZoomedWindowUnderTheMenuBarIsNot() {
        let zoomed = CGRect(x: 0, y: 25, width: 1512, height: 880)
        XCTAssertFalse(FullScreen.fills(zoomed, display: display, notch: 0))
    }

    func testSecondDisplay() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        XCTAssertTrue(FullScreen.fills(second, display: second, notch: 0))
        XCTAssertFalse(FullScreen.fills(second, display: display, notch: 0))
    }
}
