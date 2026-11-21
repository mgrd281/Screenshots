import XCTest
@testable import Tendedero

/// Studio's own pointer: it glides after the hand, presses in at a click,
/// fades while still if chosen, keeps the looks it had, and old work opens.
final class StudioPointerTests: XCTestCase {
    private func events(_ pointer: [(Double, Double, Double)], clicks: [Double] = []) -> StudioEvents {
        var events = StudioEvents(width: 1440, height: 900)
        events.pointer = pointer.map { StudioEvents.Point(t: $0.0, x: $0.1, y: $0.2) }
        events.clicks = clicks.map { StudioEvents.Click(t: $0, x: 0.5, y: 0.5) }
        events.drawsPointer = true
        return events
    }

    func testItGlidesAfterAJumpAndArrives() throws {
        let jump = events([(0, 0.2, 0.5), (1, 0.2, 0.5), (1.02, 0.8, 0.5), (3, 0.8, 0.5)])
        let smooth = StudioPointerPath(events: jump, duration: 3, smooth: true)
        let raw = StudioPointerPath(events: jump, duration: 3, smooth: false)
        let soon = try XCTUnwrap(smooth.point(at: 1.06))
        XCTAssertGreaterThan(soon.x, 0.2)
        XCTAssertLessThan(soon.x, try XCTUnwrap(raw.point(at: 1.06)).x)
        XCTAssertEqual(Double(try XCTUnwrap(smooth.point(at: 2.5)).x), 0.8, accuracy: 0.005)
        XCTAssertEqual(Double(try XCTUnwrap(raw.point(at: 2)).x), 0.8, accuracy: 0.0001)
        XCTAssertNil(StudioPointerPath(events: nil, duration: 3, smooth: true).point(at: 1))
    }

    func testAClickPressesItInAndLetsItGo() {
        let clicks = [StudioEvents.Click(t: 1, x: 0.5, y: 0.5)]
        XCTAssertEqual(StudioPointerPath.scale(at: 0.9, clicks: clicks), 1)
        XCTAssertLessThan(StudioPointerPath.scale(at: 1.06, clicks: clicks), 0.9)
        XCTAssertEqual(StudioPointerPath.scale(at: 1.5, clicks: clicks), 1)
    }

    func testItFadesWhileStillOnlyIfChosen() {
        let still = events([(0, 0.5, 0.5), (1, 0.6, 0.5)])
        XCTAssertEqual(StudioPointerPath.presence(at: 2, events: still, hides: true), 1)
        XCTAssertEqual(StudioPointerPath.presence(at: 5, events: still, hides: true), 0)
        XCTAssertEqual(StudioPointerPath.presence(at: 5, events: still, hides: false), 1)
    }

    func testItsLooksAreKeptAndMoveWithATrim() throws {
        var made = events([(0, 0.5, 0.5)])
        let arrow = StudioCursor(image: Data([1]), hotX: 4, hotY: 4, width: 17, height: 23)
        let beam = StudioCursor(image: Data([2]), hotX: 4, hotY: 9, width: 9, height: 18)
        made.cursors = [arrow, beam]
        made.looks = [StudioEvents.Look(t: 0, index: 0), StudioEvents.Look(t: 2, index: 1), StudioEvents.Look(t: 5, index: 0)]
        XCTAssertEqual(made.look(at: 1), 0)
        XCTAssertEqual(made.look(at: 3), 1)
        XCTAssertEqual(made.look(at: 6), 0)
        let read = try JSONDecoder().decode(StudioEvents.self, from: JSONEncoder().encode(made))
        XCTAssertEqual(read, made)
        let trimmed = made.trimmed(from: 3, keeping: 4)
        XCTAssertEqual(trimmed.looks.map(\.index), [1, 0])
        XCTAssertEqual(trimmed.looks.map(\.t), [0, 2])
    }

    func testEventsAndWorkKeptBeforeTheSmoothPointerStillOpen() throws {
        let old = #"{"width":1440,"height":900,"pointer":[{"t":0,"x":0.5,"y":0.5}],"clicks":[],"keys":[]}"#
        let events = try JSONDecoder().decode(StudioEvents.self, from: Data(old.utf8))
        XCTAssertFalse(events.drawsPointer)
        XCTAssertEqual(events.pointer.count, 1)
        XCTAssertNil(events.look(at: 1))
        let project = try JSONDecoder().decode(StudioProject.self, from: Data(#"{"zooms":[]}"#.utf8))
        XCTAssertEqual(project.pointer, StudioPointerStyle())
    }

    func testStudioDrawsItOnlyOnARecordingMadeWithoutTheMacsPointer() {
        let made = events([(0, 0.5, 0.5)])
        let pixels = CGSize(width: 2880, height: 1800)
        XCTAssertNotNil(StudioLook(project: StudioProject(), events: made, duration: 2, pixels: pixels,
                                   drawsPointer: true).pointer)
        XCTAssertNil(StudioLook(project: StudioProject(), events: made, duration: 2, pixels: pixels).pointer)
        var off = StudioProject()
        off.pointer.shows = false
        XCTAssertNil(StudioLook(project: off, events: made, duration: 2, pixels: pixels, drawsPointer: true).pointer)
        // The recording's pixels for each of the screen's points.
        XCTAssertEqual(StudioLook(project: StudioProject(), events: made, duration: 2, pixels: pixels,
                                  drawsPointer: true).pointer?.pixelScale, 2)
    }
}
