import XCTest
@testable import Tendedero

/// The iPhone's Protected tab: the screenshots protected lately, newest
/// first, twelve at most; some taken off at once, and put back with Undo in
/// the places they had.
final class ProtectedListTests: XCTestCase {
    private let list = (0..<8).map { "shot\($0)" }

    func testOneProtectedComesFirstAndOnlyOnce() {
        XCTAssertEqual(ProtectedList.noting("new", in: ["a", "b"]), ["new", "a", "b"])
        XCTAssertEqual(ProtectedList.noting("b", in: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testTheListKeepsTwelveAtMost() {
        let full = (0..<12).map { "old\($0)" }
        let noted = ProtectedList.noting("new", in: full)
        XCTAssertEqual(noted.count, 12)
        XCTAssertEqual(noted.first, "new")
        XCTAssertFalse(noted.contains("old11"))
    }

    func testSomeTakenOffLeaveTheRestInTheirOrder() {
        let (kept, removal) = ProtectedList.removing(["shot1", "shot4", "shot7"], from: list)
        XCTAssertEqual(kept, ["shot0", "shot2", "shot3", "shot5", "shot6"])
        XCTAssertEqual(removal.ids, ["shot1", "shot4", "shot7"])
        XCTAssertEqual(removal.count, 3)
    }

    func testAllTakenOffLeaveNothing() {
        let (kept, removal) = ProtectedList.removing(Set(list), from: list)
        XCTAssertTrue(kept.isEmpty)
        XCTAssertEqual(removal.ids, list)
    }

    func testOneNotOnTheListIsNotTakenOff() {
        let (kept, removal) = ProtectedList.removing(["elsewhere"], from: list)
        XCTAssertEqual(kept, list)
        XCTAssertTrue(removal.isEmpty)
    }

    func testUndoPutsThemBackWhereTheyWere() {
        for gone in [Set(["shot0"]), ["shot7"], ["shot1", "shot4", "shot7"], ["shot0", "shot1", "shot2"], Set(list)] {
            let (kept, removal) = ProtectedList.removing(gone, from: list)
            XCTAssertEqual(ProtectedList.restoring(removal, into: kept), list, "\(gone.sorted())")
        }
    }

    func testOneProtectedAgainMeanwhileStaysFirst() {
        let (kept, removal) = ProtectedList.removing(["shot2", "shot5"], from: list)
        // shot5 was protected again before Undo: it is first now, and stays.
        let meanwhile = ProtectedList.noting("shot5", in: kept)
        let back = ProtectedList.restoring(removal, into: meanwhile)
        XCTAssertEqual(back.first, "shot5")
        XCTAssertEqual(back.filter { $0 == "shot5" }.count, 1)
        XCTAssertTrue(back.contains("shot2"))
        XCTAssertEqual(back.count, list.count)
    }

    func testUndoNeverMakesTheListLongerThanTwelve() {
        let full = (0..<12).map { "old\($0)" }
        let (kept, removal) = ProtectedList.removing(["old0", "old1"], from: full)
        let refilled = ProtectedList.noting("new1", in: ProtectedList.noting("new0", in: kept))
        XCTAssertEqual(ProtectedList.restoring(removal, into: refilled).count, 12)
    }
}
