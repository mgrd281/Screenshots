import XCTest
@testable import Tendedero

/// Choosing several screenshots at once on the iPhone: a tap turns one, a
/// finger drawn across takes in a run in reading order, and the card under
/// the finger is found from the grid's size alone.
final class GridSelectionTests: XCTestCase {
    private let ids = (0..<12).map { "shot\($0)" }

    func testATapTurnsOneOnAndOff() {
        var selection = GridSelection()
        selection.toggle("shot3")
        XCTAssertTrue(selection.contains("shot3"))
        selection.toggle("shot3")
        XCTAssertTrue(selection.isEmpty)
    }

    func testAFingerTakesInEveryCardBetweenInReadingOrder() {
        var selection = GridSelection()
        selection.begin(at: 2, in: ids)
        XCTAssertEqual(selection.chosen, ["shot2"])
        // Down a row of three and across: from the third card to the seventh.
        selection.move(to: 6, in: ids)
        XCTAssertEqual(selection.chosen, Set(ids[2...6]))
        // Back up: the cards it left are as they were.
        selection.move(to: 4, in: ids)
        XCTAssertEqual(selection.chosen, Set(ids[2...4]))
        // And before where it started, backwards.
        selection.move(to: 0, in: ids)
        XCTAssertEqual(selection.chosen, Set(ids[0...2]))
        selection.end()
        XCTAssertFalse(selection.isSweeping)
    }

    func testAFingerKeepsWhatWasChosenBefore() {
        var selection = GridSelection(["shot9"])
        selection.begin(at: 0, in: ids)
        selection.move(to: 1, in: ids)
        selection.end()
        XCTAssertEqual(selection.chosen, ["shot0", "shot1", "shot9"])
    }

    func testStartingOnAChosenCardTurnsCardsOff() {
        var selection = GridSelection(Set(ids[0...5]))
        selection.begin(at: 1, in: ids)
        selection.move(to: 3, in: ids)
        selection.end()
        XCTAssertEqual(selection.chosen, ["shot0", "shot4", "shot5"])
    }

    func testAFingerPastTheEndStopsAtTheLastCard() {
        var selection = GridSelection()
        selection.begin(at: 10, in: ids)
        selection.move(to: 40, in: ids)
        XCTAssertEqual(selection.chosen, ["shot10", "shot11"])
        // A move with no finger down changes nothing.
        selection.end()
        selection.move(to: 0, in: ids)
        XCTAssertEqual(selection.chosen, ["shot10", "shot11"])
    }

    func testAllOrNone() {
        var selection = GridSelection(["shot1"])
        selection.toggleAll(ids)
        XCTAssertEqual(selection.count, 12)
        selection.toggleAll(ids)
        XCTAssertTrue(selection.isEmpty)
    }

    func testOnlyThoseToDoAgainStay() {
        var selection = GridSelection(Set(ids[0...3]))
        selection.keep(["shot2", "shot7"])
        XCTAssertEqual(selection.chosen, ["shot2"])
    }

    func testTheCardUnderTheFinger() {
        // Three to a row across 360 pt, 8 pt apart: cards of 114.67 pt.
        func at(_ x: Double, _ y: Double, count: Int = 12) -> Int? {
            GridSelection.index(atX: x, y: y, width: 360, columns: 3, spacing: 8, count: count)
        }
        XCTAssertEqual(at(10, 10), 0)
        XCTAssertEqual(at(130, 10), 1)
        XCTAssertEqual(at(350, 10), 2)
        XCTAssertEqual(at(10, 130), 3)
        XCTAssertEqual(at(250, 260), 8)
        // Off the sides and above, the nearest card.
        XCTAssertEqual(at(-20, 10), 0)
        XCTAssertEqual(at(500, 10), 2)
        XCTAssertEqual(at(130, -40), 1)
        // Past the last card, the last.
        XCTAssertEqual(at(250, 900), 11)
        XCTAssertEqual(at(250, 260, count: 7), 6)
        XCTAssertNil(at(10, 10, count: 0))
        // Four to a row: cards of 84 pt, so 100 pt down is the second row.
        XCTAssertEqual(GridSelection.index(atX: 200, y: 100, width: 360, columns: 4, spacing: 8, count: 12), 6)
    }
}
