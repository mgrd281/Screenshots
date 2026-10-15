import XCTest
@testable import Tendedero

/// Recordings stay within 4K with even sides, and GIFs within 300 frames.
final class CaptureTests: XCTestCase {
    func testVideoSizeKeepsSmallAreas() {
        let (w, h) = Capture.videoSize(1200, 800)
        XCTAssertEqual(w, 1200)
        XCTAssertEqual(h, 800)
    }

    func testVideoSizeIsEven() {
        let (w, h) = Capture.videoSize(1001, 333)
        XCTAssertEqual(Int(w) % 2, 0)
        XCTAssertEqual(Int(h) % 2, 0)
    }

    func testVideoSizeFitsWithin4K() {
        // A 5K display at full resolution.
        let (w, h) = Capture.videoSize(5120, 2880)
        XCTAssertLessThanOrEqual(w, 3840)
        XCTAssertLessThanOrEqual(w * h, 3840 * 2160)
        XCTAssertEqual(w / h, 5120 / 2880, accuracy: 0.01)
    }

    func testVideoSizeFitsTallWindows() {
        let (w, h) = Capture.videoSize(1964, 6048)
        XCTAssertLessThanOrEqual(h, 3840)
        XCTAssertGreaterThanOrEqual(w, 2)
    }

    func testGIFPlanShortRecording() {
        let plan = GIF.plan(for: 4)
        XCTAssertEqual(plan.fps, 10)
        XCTAssertEqual(plan.count, 40)
    }

    func testGIFPlanLongRecordingStaysWithinFrames() {
        let plan = GIF.plan(for: 120)
        XCTAssertLessThanOrEqual(plan.count, GIF.maxFrames)
        XCTAssertGreaterThan(plan.fps, 0)
    }

    func testGIFPlanVeryShortRecording() {
        XCTAssertGreaterThanOrEqual(GIF.plan(for: 0.05).count, 1)
    }

    @MainActor
    func testTimerModesDiffer() {
        XCTAssertNotEqual(Capture.Mode.timer(3), Capture.Mode.timer(10))
        XCTAssertEqual(Capture.Mode.timer(5), Capture.Mode.timer(5))
        XCTAssertNotEqual(Capture.Mode.screenshot, Capture.Mode.record)
        XCTAssertEqual(Capture.timerChoices, [3, 5, 10])
    }
}

/// The screenshot button's choice is saved by name, so it survives updates.
final class CaptureButtonTests: XCTestCase {
    func testClickChoicesKeepTheirNames() {
        XCTAssertEqual(CaptureButton.Click.allCases.map(\.rawValue), ["choose", "screen", "lastArea"])
    }
}
