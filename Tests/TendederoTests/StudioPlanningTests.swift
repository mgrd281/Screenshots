import CoreGraphics
import XCTest
@testable import Tendedero

/// Studio's planning, made-up recordings only: where it zooms, how the
/// camera moves, and the timeline's rules.
final class StudioPlanningTests: XCTestCase {
    private func events(clicks: [(Double, Double, Double)] = [], keys: [Double] = [],
                        pointer: [(Double, Double, Double)] = [], width: Double = 1512, height: Double = 982) -> StudioEvents {
        StudioEvents(width: width, height: height,
                     pointer: pointer.map { StudioEvents.Point(t: $0.0, x: $0.1, y: $0.2) },
                     clicks: clicks.map { StudioEvents.Click(t: $0.0, x: $0.1, y: $0.2) },
                     keys: keys)
    }

    // MARK: Events

    func testPointerIsBetweenThePlacesSeen() {
        let seen = events(pointer: [(1, 0.2, 0.2), (2, 0.4, 0.6)])
        XCTAssertNil(events().pointer(at: 1))
        XCTAssertEqual(seen.pointer(at: 0), CGPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(seen.pointer(at: 5), CGPoint(x: 0.4, y: 0.6))
        let middle = seen.pointer(at: 1.5)!
        XCTAssertEqual(middle.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(middle.y, 0.4, accuracy: 0.0001)
    }

    func testTrimmingMovesEverythingToTheNewStart() {
        let seen = events(clicks: [(1, 0.5, 0.5), (4, 0.5, 0.5), (9, 0.5, 0.5)], keys: [2, 4.5, 9],
                          pointer: [(0, 0.1, 0.1), (4, 0.5, 0.5), (8, 0.9, 0.9)])
        let trimmed = seen.trimmed(from: 2, keeping: 5)
        XCTAssertEqual(trimmed.clicks.map(\.t), [2])
        XCTAssertEqual(trimmed.keys, [0, 2.5])
        XCTAssertEqual(trimmed.pointer.first?.t, 0)
        XCTAssertEqual(trimmed.pointer.first?.x ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(trimmed.pointer.map(\.t), [0, 2])
    }

    // MARK: Zooming in on what was done

    func testARunOfClicksIsOneZoomStartingBeforeIt() {
        let zooms = StudioAutoZoom.zooms(for: events(clicks: [(3, 0.3, 0.6), (4, 0.32, 0.62), (5.5, 0.35, 0.6)]),
                                         duration: 20)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 3 - StudioAutoZoom.lead, accuracy: 0.0001)
        XCTAssertEqual(zooms[0].end, 5.5 + StudioAutoZoom.hold, accuracy: 0.0001)
        XCTAssertEqual(zooms[0].scale, 2.0)
        XCTAssertEqual(zooms[0].focus, .pointer)
        XCTAssertTrue(zooms[0].automatic)
    }

    func testRunsFarApartAreZoomedApartAndCloseOnesJoined() {
        let apart = StudioAutoZoom.zooms(for: events(clicks: [(2, 0.5, 0.5), (12, 0.5, 0.5)]), duration: 20)
        XCTAssertEqual(apart.count, 2)
        // 2.6 s after the first, past the gap, but the zooms would nearly touch.
        let close = StudioAutoZoom.zooms(for: events(clicks: [(2, 0.5, 0.5), (4.6, 0.5, 0.5)]), duration: 20)
        XCTAssertEqual(close.count, 1)
        XCTAssertEqual(close[0].end, 4.6 + StudioAutoZoom.hold, accuracy: 0.0001)
    }

    func testClicksAllOverTheScreenAreNotZoomedInOn() {
        let zooms = StudioAutoZoom.zooms(for: events(clicks: [(2, 0.05, 0.05), (3, 0.95, 0.95)]), duration: 10)
        XCTAssertTrue(zooms.isEmpty)
    }

    func testAWiderRunComesLessClose() {
        let zooms = StudioAutoZoom.zooms(for: events(clicks: [(2, 0.2, 0.5), (3, 0.8, 0.5)]), duration: 10)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertLessThan(zooms[0].scale, 2.0)
        XCTAssertGreaterThanOrEqual(zooms[0].scale, StudioZoom.scales.lowerBound)
        // The run still fits inside the view.
        XCTAssertLessThanOrEqual(0.6, StudioAutoZoom.fill / zooms[0].scale + 0.01)
    }

    func testTypingIsZoomedInOnWhereThePointerIs() {
        let zooms = StudioAutoZoom.zooms(for: events(keys: [5, 5.2, 5.4, 6.0], pointer: [(0, 0.7, 0.3)]), duration: 30)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 5 - StudioAutoZoom.lead, accuracy: 0.0001)
        // Typing off the recorded area isn't.
        XCTAssertTrue(StudioAutoZoom.zooms(for: events(keys: [5], pointer: [(0, 1.5, 0.3)]), duration: 30).isEmpty)
    }

    func testClicksOffTheAreaAndPastTheEndAreLeftOut() {
        XCTAssertTrue(StudioAutoZoom.zooms(for: events(clicks: [(2, -0.4, 0.5)]), duration: 10).isEmpty)
        XCTAssertTrue(StudioAutoZoom.zooms(for: events(clicks: [(12, 0.5, 0.5)]), duration: 10).isEmpty)
        XCTAssertTrue(StudioAutoZoom.zooms(for: events(clicks: [(1, 0.5, 0.5)]), duration: 0).isEmpty)
    }

    func testAZoomStaysWithinTheRecording() {
        let zooms = StudioAutoZoom.zooms(for: events(clicks: [(0.2, 0.5, 0.5), (9.9, 0.4, 0.4)]), duration: 10)
        XCTAssertEqual(zooms.count, 2)
        XCTAssertEqual(zooms.first?.start, 0)
        XCTAssertEqual(zooms.last?.end ?? 0, 10, accuracy: 0.0001)
        // Near the end, it starts earlier rather than being cut short.
        XCTAssertEqual(zooms.last?.duration ?? 0, StudioAutoZoom.shortest, accuracy: 0.0001)
    }

    func testSmallerAreasComeLessClose() {
        XCTAssertEqual(StudioAutoZoom.defaultScale(width: 2560, height: 1440), 2.0)
        XCTAssertEqual(StudioAutoZoom.defaultScale(width: 1000, height: 700), 1.7)
        XCTAssertEqual(StudioAutoZoom.defaultScale(width: 640, height: 480), 1.4)
    }

    func testMakingAgainKeepsTheZoomsChangedByHand() {
        let seen = events(clicks: [(2, 0.5, 0.5), (12, 0.5, 0.5)])
        var zooms = StudioAutoZoom.zooms(for: seen, duration: 20)
        zooms[0].automatic = false
        zooms[0].scale = 3
        let remade = StudioAutoZoom.remade(zooms, events: seen, duration: 20, scale: nil)
        XCTAssertEqual(remade.count, 2)
        XCTAssertEqual(remade[0].scale, 3)
        XCTAssertFalse(remade[0].automatic)
        XCTAssertTrue(remade[1].automatic)
    }

    // MARK: The camera

    func testWithoutZoomsTheWholeRecordingShows() {
        let camera = StudioCamera(zooms: [], events: nil, duration: 10)
        XCTAssertEqual(camera.rect(at: 4), CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testTheCameraSettlesOnAFixedPlaceAndComesBack() {
        let zoom = StudioZoom(start: 1, end: 6, scale: 2, focus: .point(x: 0.3, y: 0.7))
        let camera = StudioCamera(zooms: [zoom], events: nil, duration: 10)
        XCTAssertEqual(camera.rect(at: 0.5), CGRect(x: 0, y: 0, width: 1, height: 1))
        let settled = camera.rect(at: 5.5)
        XCTAssertEqual(settled.width, 0.5, accuracy: 0.01)
        XCTAssertEqual(settled.midX, 0.3, accuracy: 0.01)
        XCTAssertEqual(settled.midY, 0.7, accuracy: 0.01)
        let back = camera.rect(at: 9.9)
        XCTAssertEqual(back.width, 1, accuracy: 0.01)
    }

    func testTheCameraNeverOvershootsOrLeavesTheRecording() {
        let zoom = StudioZoom(start: 0.5, end: 4, scale: 2.5, focus: .point(x: 0.95, y: 0.05))
        let camera = StudioCamera(zooms: [zoom], events: nil, duration: 6)
        var widest = 0.0, last = 1.0
        for i in 0...360 {
            let t = Double(i) / 60
            let rect = camera.rect(at: t)
            XCTAssertGreaterThanOrEqual(rect.minX, -0.0001)
            XCTAssertGreaterThanOrEqual(rect.minY, -0.0001)
            XCTAssertLessThanOrEqual(rect.maxX, 1.0001)
            XCTAssertLessThanOrEqual(rect.maxY, 1.0001)
            XCTAssertGreaterThanOrEqual(camera.frame(at: t).scale, 1)
            XCTAssertLessThanOrEqual(camera.frame(at: t).scale, 2.5 + 0.001)
            if t > 0.5 && t < 4 {
                // Coming in, it only ever comes closer.
                XCTAssertLessThanOrEqual(Double(rect.width), last + 0.0001)
                last = Double(rect.width)
            }
            widest = max(widest, Double(rect.width))
        }
        XCTAssertEqual(widest, 1, accuracy: 0.0001)
    }

    func testTheCameraFollowsThePointerOnlyOnceItNearsTheEdge() {
        // Still for a while, a small move, then a long one to the right.
        let seen = events(pointer: [(0, 0.3, 0.5), (3, 0.3, 0.5), (3.5, 0.34, 0.5), (5, 0.34, 0.5), (6, 0.8, 0.5)])
        let zoom = StudioZoom(start: 0, end: 10, scale: 2, focus: .pointer)
        let camera = StudioCamera(zooms: [zoom], events: seen, duration: 10)
        let before = camera.rect(at: 2.9).midX
        let small = camera.rect(at: 4.9).midX
        XCTAssertEqual(before, small, accuracy: 0.005)
        let after = camera.rect(at: 9).midX
        XCTAssertGreaterThan(after, before + 0.2)
        // The pointer stays in view.
        XCTAssertTrue(camera.rect(at: 9).contains(CGPoint(x: 0.8, y: 0.5)))
    }

    func testPlacesMapBetweenTheRecordingAndTheView() {
        let rect = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)
        let shown = StudioCamera.shown(CGPoint(x: 0.5, y: 0.75), through: rect)
        XCTAssertEqual(shown, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(StudioCamera.recorded(shown, through: rect), CGPoint(x: 0.5, y: 0.75))
    }

    // MARK: Coming and going

    func testAMarkDrawsInThenFadesOut() {
        XCTAssertNil(StudioFade.presence(at: 0.9, start: 1, end: 4))
        XCTAssertNil(StudioFade.presence(at: 4, start: 1, end: 4))
        let early = StudioFade.presence(at: 1.1, start: 1, end: 4)!
        XCTAssertLessThan(early.drawn, 1)
        let middle = StudioFade.presence(at: 2.5, start: 1, end: 4)!
        XCTAssertEqual(middle.drawn, 1)
        XCTAssertEqual(middle.opacity, 1)
        XCTAssertLessThan(StudioFade.presence(at: 3.9, start: 1, end: 4)!.opacity, 0.5)
        XCTAssertEqual(StudioFade.presence(at: 1.05, start: 1, end: 4, still: true)!.drawn, 1)
    }

    func testAClickRingSpreadsAndFades() {
        XCTAssertNil(StudioFade.ripple(at: 0.9, click: 1))
        XCTAssertNil(StudioFade.ripple(at: 1.5, click: 1))
        let start = StudioFade.ripple(at: 1, click: 1)!
        XCTAssertEqual(start.size, 0.45, accuracy: 0.0001)
        XCTAssertEqual(start.opacity, 1, accuracy: 0.0001)
        let late = StudioFade.ripple(at: 1.4, click: 1)!
        XCTAssertGreaterThan(late.size, 0.95)
        XCTAssertLessThan(late.opacity, 0.05)
    }

    // MARK: The timeline

    func testSpansStayInsideTheRecording() {
        let kept = StudioTimeline.kept(start: 8, end: 12, duration: 10, shortest: 0.5)
        XCTAssertEqual(kept.start, 6)
        XCTAssertEqual(kept.end, 10)
        let short = StudioTimeline.kept(start: 2, end: 2.1, duration: 10, shortest: 0.5)
        XCTAssertEqual(short.end - short.start, 0.5, accuracy: 0.0001)
        let moved = StudioTimeline.moved(start: 2, end: 4, by: -5, low: 1, high: 10)
        XCTAssertEqual(moved.start, 1)
        XCTAssertEqual(moved.end, 3)
    }

    func testAZoomHasRoomBetweenItsNeighbours() {
        let a = StudioZoom(start: 1, end: 3, scale: 2), b = StudioZoom(start: 5, end: 7, scale: 2),
            c = StudioZoom(start: 9, end: 10, scale: 2)
        let room = StudioTimeline.room(for: b.id, among: [a, b, c], duration: 12)
        XCTAssertEqual(room.low, 3)
        XCTAssertEqual(room.high, 9)
    }

    func testAZoomAddedByHandFitsWhereThereIsRoom() {
        let a = StudioZoom(start: 5, end: 7, scale: 2)
        let added = StudioTimeline.added(at: 1, scale: 1.8, among: [a], duration: 10)!
        XCTAssertEqual(added.start, 1)
        XCTAssertEqual(added.end, 4)
        XCTAssertFalse(added.automatic)
        let squeezed = StudioTimeline.added(at: 4.5, scale: 1.8, among: [a], duration: 10)!
        XCTAssertEqual(squeezed.end, 5)
        XCTAssertGreaterThanOrEqual(squeezed.duration, StudioZoom.shortest - 0.0001)
        XCTAssertNil(StudioTimeline.added(at: 6, scale: 2, among: [a], duration: 10))
    }

    func testStepsAreNumberedInTheOrderTheyShow() {
        let a = UUID(), b = UUID(), c = UUID()
        let numbers = StudioTimeline.numbers(of: [(a, 5), (b, 1), (c, 5)])
        XCTAssertEqual(numbers[b], 1)
        XCTAssertEqual(numbers[a], 2)
        XCTAssertEqual(numbers[c], 3)
    }

    func testMarksAtTheSameTimeSitInRowsOfTheirOwn() {
        let rows = StudioTimeline.rows(of: [(0, 3), (1, 4), (3, 5), (2, 6), (2.5, 7)])
        XCTAssertEqual(rows, [0, 1, 0, 2, 2])
        XCTAssertEqual(StudioTimeline.rows(of: []), [])
    }

    func testTimesReadAsAClock() {
        XCTAssertEqual(StudioTimeline.text(7.9), "0:07")
        XCTAssertEqual(StudioTimeline.text(65), "1:05")
        XCTAssertEqual(StudioTimeline.text(3723), "1:02:03")
        XCTAssertEqual(StudioTimeline.tick(pointsPerSecond: 100), 1)
        XCTAssertEqual(StudioTimeline.tick(pointsPerSecond: 10), 10)
    }

    // MARK: Sound

    func testTheLoudestPartIsOne() {
        let peaks = StudioWave.peaks([0, 0.1, -0.5, 0.2, 0.25, -0.05], count: 3)
        XCTAssertEqual(peaks.count, 3)
        XCTAssertEqual(peaks[0], 0.2, accuracy: 0.0001)
        XCTAssertEqual(peaks[1], 1, accuracy: 0.0001)
        XCTAssertEqual(peaks[2], 0.5, accuracy: 0.0001)
        XCTAssertTrue(StudioWave.peaks([], count: 4).isEmpty)
        XCTAssertEqual(StudioWave.peaks([0, 0], count: 2), [0, 0])
    }
}
