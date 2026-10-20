import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The iPhone's first run, without a screen: the sample invoice is covered
/// as the engine covers it, the story keeps its times, and the categories
/// chosen alone say what is covered, however often they change.
final class FirstRunTests: XCTestCase {
    // MARK: The sample and the engine

    /// The invoice laid out as a page: the title, then each line.
    private func page(_ lines: [String]) -> (strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?) {
        FormFieldsTests.layout(lines.enumerated().map { (text: $0.element, x: CGFloat(0.06), row: $0.offset) })
    }

    /// What the engine covers on the invoice for some kinds, by field.
    private func covered(_ chosen: Set<PrivateDetail>, labels: [FirstRun.Field.ID: String]? = nil,
                         title: String = "Rechnung") -> [FirstRun.Field.ID: [String]] {
        let lines = labels.map { FirstRun.lines(title: title, labels: $0) } ?? FirstRun.lines(title: title)
        let made = page(lines)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, chosen)
        var byField: [FirstRun.Field.ID: [String]] = [:]
        for hit in found.hits {
            // The title is line 0; the fields follow in order.
            XCTAssertGreaterThan(hit.line, 0, "nothing on the title: \(lines[hit.line])")
            guard hit.line > 0 else { continue }
            let line = made.strings[hit.line]
            let text = hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
            byField[FirstRun.fields[hit.line - 1].id, default: []].append(text)
        }
        return byField
    }

    func testEachCategoryCoversItsOwnDetailAndNothingElse() {
        for category in FirstRun.Category.allCases {
            let found = covered([category.detail])
            let expected = FirstRun.fields.filter { $0.category == category }
            XCTAssertEqual(Set(found.keys), Set(expected.map(\.id)), "\(category): \(found)")
            for field in expected {
                XCTAssertTrue(found[field.id]?.contains { $0.contains(field.value) || field.value.contains($0) } == true,
                              "\(category) covers \(field.value): \(found)")
            }
        }
    }

    func testTheAmountStaysReadableAndIsAnAmountToTheEngine() {
        let chosen = Set(FirstRun.Category.allCases.map(\.detail))
        XCTAssertNil(covered(chosen)[.amount], "the amount stays readable")
        XCTAssertEqual(covered([.amounts])[.amount], ["149,90 €"])
    }

    func testTheSampleIsReadTheSameWithEnglishLabels() {
        let labels: [FirstRun.Field.ID: String] = [.name: "Name:", .email: "Email:", .iban: "IBAN:", .amount: "Amount:"]
        for category in FirstRun.Category.allCases {
            let found = covered([category.detail], labels: labels, title: "Invoice")
            XCTAssertEqual(Set(found.keys), Set(FirstRun.fields.filter { $0.category == category }.map(\.id)),
                           "\(category): \(found)")
        }
    }

    // MARK: The story

    func testItOpensReadableAndIsProtectedWithinTwoSeconds() {
        let start = FirstRun.state(at: 0)
        XCTAssertEqual(start.scene, .reveal)
        XCTAssertEqual(start.phase, .initial)
        XCTAssertTrue(FirstRun.fields.allSatisfy { !start.isCovered($0) && !start.isFound($0) })

        let protected = FirstRun.state(at: 2)
        XCTAssertEqual(protected.phase, .protected)
        XCTAssertTrue(protected.showsShield)
        for field in FirstRun.fields {
            XCTAssertEqual(protected.isCovered(field), field.category != nil, field.value)
        }
    }

    func testTheDetailsAreFoundAsTheLineReachesThemThenCoveredInTurn() {
        let found = FirstRun.state(at: 1.2)
        XCTAssertEqual(found.phase, .highlighted)
        XCTAssertTrue(FirstRun.privateFields.allSatisfy { found.isFound($0) && !found.isCovered($0) })
        let half = FirstRun.state(at: 1.31 + FirstRun.stagger)
        XCTAssertEqual(half.phase, .redacting)
        XCTAssertEqual(FirstRun.privateFields.map(half.isCovered), [true, true, false])
    }

    func testTheScriptKeepsItsOrderAndEndsWithinFifteenSeconds() {
        let times = FirstRun.script.map(\.at)
        XCTAssertEqual(times, times.sorted())
        XCTAssertLessThanOrEqual(times.last ?? 0, 15)
        let scenes = FirstRun.script.compactMap { beat -> FirstRun.Scene? in
            if case .scene(let scene) = beat.event { return scene }
            return nil
        }
        XCTAssertEqual(scenes, [.control, .scan, .share, .complete])
        // The phases it goes through, each change once.
        var state = FirstRun.State()
        var phases = [state.phase]
        for beat in FirstRun.script {
            FirstRun.apply(beat.event, to: &state)
            if phases.last != state.phase { phases.append(state.phase) }
        }
        XCTAssertEqual(phases, [.initial, .detecting, .highlighted, .redacting, .protected, .revealing, .protected,
                                .redacting, .protected, .initial, .detecting, .highlighted, .redacting, .protected,
                                .complete])
    }

    func testTurningACategoryOffShowsItsDetailAndOnCoversItAgain() {
        var state = FirstRun.state(at: FirstRun.controlStart)
        let name = FirstRun.field(.name)
        XCTAssertTrue(state.isCovered(name))
        FirstRun.toggle(.names, in: &state)
        XCTAssertFalse(state.isCovered(name))
        XCTAssertFalse(state.isFound(name), "readable again, without its marks")
        XCTAssertEqual(state.phase, .revealing)
        XCTAssertTrue(state.isCovered(FirstRun.field(.email)), "the others stay covered")
        FirstRun.apply(.settle, to: &state)
        XCTAssertEqual(state.phase, .protected)
        FirstRun.toggle(.names, in: &state)
        XCTAssertTrue(state.isCovered(name))
        XCTAssertEqual(state.phase, .redacting)
    }

    func testRapidChangesEndWhereTheLastOneLeftIt() {
        var state = FirstRun.state(at: 2.5)
        for _ in 0..<7 { FirstRun.toggle(.bank, in: &state) }
        XCTAssertFalse(state.chosen.contains(.bank))
        XCTAssertFalse(state.isCovered(FirstRun.field(.iban)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.name)))
    }

    func testTheStoryLeavesTheOwnersChoiceAlone() {
        var state = FirstRun.state(at: 2.5)
        FirstRun.toggle(.emails, in: &state)
        for beat in FirstRun.script where beat.at > 2.5 {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.chosen, [.names, .bank], "the story turned nothing for the owner")
        XCTAssertFalse(state.isCovered(FirstRun.field(.email)), "the scan covers what is chosen")
        XCTAssertTrue(state.isCovered(FirstRun.field(.name)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.iban)))
    }

    func testTheScannedPageIsReadThenFoundThenCoveredAsChosen() {
        var state = FirstRun.state(at: FirstRun.scanStart)
        XCTAssertEqual(state.scan, .placed)
        XCTAssertTrue(FirstRun.fields.allSatisfy { !state.isCovered($0) }, "the page as printed")
        FirstRun.toggle(.names, in: &state)
        for beat in FirstRun.script where beat.at > FirstRun.scanStart && beat.at <= 9.25 {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.scan, .reading)
        XCTAssertFalse(state.isFound(FirstRun.field(.name)), "only what is chosen is marked")
        XCTAssertTrue(state.isFound(FirstRun.field(.iban)))
        for beat in FirstRun.script where beat.at > 9.25 && beat.at < FirstRun.shareStart {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.scan, .done)
        XCTAssertFalse(state.isCovered(FirstRun.field(.name)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.iban)))
    }

    func testWhileTheStoryWaitsItSaysPausedAndTheEndStays() {
        XCTAssertEqual(FirstRun.state(at: 3).reported(held: true), .paused)
        XCTAssertEqual(FirstRun.state(at: 3).reported(held: false), FirstRun.state(at: 3).phase)
        var end = FirstRun.state(at: 14)
        XCTAssertEqual(end.reported(held: true), .complete)
        FirstRun.toggle(.names, in: &end)
        XCTAssertEqual(end.phase, .complete)
    }

    func testWithNothingChosenNothingIsCoveredAndNoShieldShows() {
        var state = FirstRun.state(at: 2.5)
        for category in FirstRun.Category.allCases { FirstRun.toggle(category, in: &state) }
        XCTAssertTrue(FirstRun.fields.allSatisfy { !state.isCovered($0) })
        XCTAssertFalse(state.showsShield)
    }

    // MARK: The scanner's perspective

    func testThePageIsStraightenedFromTippedToFlat() {
        XCTAssertEqual(FirstRun.corners(straightened: 0), FirstRun.tipped)
        XCTAssertEqual(FirstRun.corners(straightened: 1), FirstRun.flat)
        let size = CGSize(width: 300, height: 220)
        for progress in [0.0, 0.4, 1.0] {
            let corners = FirstRun.corners(straightened: progress).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let matrix = FirstRun.homography(size, to: corners)
            let rectangle = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                             CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
            for (point, corner) in zip(rectangle, corners) {
                let projected = FirstRun.project(point, by: matrix)
                XCTAssertEqual(projected.x, corner.x, accuracy: 0.001)
                XCTAssertEqual(projected.y, corner.y, accuracy: 0.001)
            }
        }
        // Straight, it changes nothing.
        let flat = FirstRun.homography(size, to: [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0),
                                                  CGPoint(x: 300, y: 220), CGPoint(x: 0, y: 220)])
        for (value, identity) in zip(flat, [1.0, 0, 0, 0, 1, 0, 0, 0, 1]) {
            XCTAssertEqual(value, identity, accuracy: 1e-9)
        }
    }
}
