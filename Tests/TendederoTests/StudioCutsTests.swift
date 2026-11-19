import XCTest
@testable import Tendedero

/// Studio's cuts and speeds: splitting, the parts kept in order, how long
/// the video is, and which moment of the recording shows when.
final class StudioCutsTests: XCTestCase {
    func testNoPartsIsTheWholeRecordingAsItIs() {
        let parts = StudioCuts.parts([], duration: 10)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].start, 0)
        XCTAssertEqual(parts[0].end, 10)
        XCTAssertFalse(StudioCuts.edits(parts))
        XCTAssertEqual(StudioCuts.length(of: parts), 10)
        XCTAssertEqual(StudioCuts.source(at: 4, in: parts), 4)
    }

    func testASplitMakesTwoPartsAndNeverOneTooShort() throws {
        let whole = StudioCuts.parts([], duration: 10)
        let split = try XCTUnwrap(StudioCuts.split(whole, at: 4))
        XCTAssertEqual(split.map(\.start), [0, 4])
        XCTAssertEqual(split.map(\.end), [4, 10])
        XCTAssertNotEqual(split[0].id, split[1].id)
        XCTAssertNil(StudioCuts.split(split, at: 4.1))
        XCTAssertNil(StudioCuts.split(split, at: 0.1))
        XCTAssertNil(StudioCuts.split(split, at: 12))
    }

    func testCutPartsAreLeftOutAndFasterOnesAreShorter() throws {
        var parts = try XCTUnwrap(StudioCuts.split(StudioCuts.parts([], duration: 10), at: 2))
        parts = try XCTUnwrap(StudioCuts.split(parts, at: 6))
        parts[0].removed = true
        parts[1].speed = 2
        XCTAssertTrue(StudioCuts.edits(parts))
        // Nothing of 0–2, 2–6 in two seconds, 6–10 as it is.
        XCTAssertEqual(StudioCuts.length(of: parts), 6, accuracy: 0.0001)
        XCTAssertEqual(StudioCuts.source(at: 0, in: parts), 2, accuracy: 0.0001)
        XCTAssertEqual(StudioCuts.source(at: 1, in: parts), 4, accuracy: 0.0001)
        XCTAssertEqual(StudioCuts.source(at: 3, in: parts), 7, accuracy: 0.0001)
        XCTAssertEqual(StudioCuts.source(at: 99, in: parts), 10, accuracy: 0.0001)
        XCTAssertNil(StudioCuts.output(at: 1, in: parts))
        XCTAssertEqual(try XCTUnwrap(StudioCuts.output(at: 4, in: parts)), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(StudioCuts.output(at: 8, in: parts)), 4, accuracy: 0.0001)
    }

    func testPlayingGoesOnPastACut() throws {
        var parts = try XCTUnwrap(StudioCuts.split(StudioCuts.parts([], duration: 10), at: 3))
        parts = try XCTUnwrap(StudioCuts.split(parts, at: 5))
        parts[1].removed = true
        XCTAssertEqual(StudioCuts.playable(from: 4, in: parts), 5)
        XCTAssertEqual(StudioCuts.playable(from: 1, in: parts), 1)
        parts[2].removed = true
        XCTAssertNil(StudioCuts.playable(from: 4, in: parts))
    }

    func testJoiningKeepsTheFirstPartsSpeed() throws {
        var parts = try XCTUnwrap(StudioCuts.split(StudioCuts.parts([], duration: 10), at: 5))
        parts[0].speed = 4
        let joined = try XCTUnwrap(StudioCuts.joined(parts, at: 0))
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].end, 10)
        XCTAssertEqual(joined[0].speed, 4)
        XCTAssertNil(StudioCuts.joined(parts, at: 1))
    }

    func testPartsAreMadeWholeFromStartToEnd() {
        let gappy = [StudioPart(start: 1, end: 3, speed: 2), StudioPart(start: 4, end: 20, removed: true)]
        let parts = StudioCuts.parts(gappy, duration: 8)
        XCTAssertEqual(parts.first?.start, 0)
        XCTAssertEqual(parts.last?.end, 8)
        for (a, b) in zip(parts, parts.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertEqual(parts.map(\.speed), [2, 1])
        XCTAssertEqual(parts.map(\.removed), [false, true])
    }

    func testTrimmingMovesThePartsToTheNewStart() throws {
        var parts = try XCTUnwrap(StudioCuts.split(StudioCuts.parts([], duration: 10), at: 6))
        parts[1].speed = 2
        let trimmed = StudioCuts.trimmed(parts, from: 2, keeping: 6)
        XCTAssertEqual(trimmed.map(\.start), [0, 4])
        XCTAssertEqual(trimmed.map(\.end), [4, 6])
        XCTAssertEqual(trimmed.map(\.speed), [1, 2])
        // Trimmed down to one part as it was: nothing left to keep.
        XCTAssertEqual(StudioCuts.trimmed(parts, from: 0, keeping: 5), [])
    }

    func testWorkWithPartsIsKeptAndOlderWorkOpens() throws {
        var project = StudioProject()
        project.parts = [StudioPart(start: 0, end: 2, removed: true), StudioPart(start: 2, end: 5, speed: 1.5)]
        let read = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(read.parts, project.parts)
        let older = try JSONDecoder().decode(StudioProject.self, from: Data(#"{"zooms":[],"marks":[]}"#.utf8))
        XCTAssertEqual(older.parts, [])
    }
}
