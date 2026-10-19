import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// A picture being protected, place by place, without a picture: what is
/// covered, what is only offered, what the owner turns on or off or covers
/// by hand, undoing it and doing it again, and what Snapfly finds later.
final class ProtectionPlanTests: XCTestCase {
    private func area(_ x: CGFloat, _ y: CGFloat, _ kind: PrivateDetail? = .names, check: Bool = false) -> Finder.Area {
        Finder.Area(rect: CGRect(x: x, y: y, width: 0.2, height: 0.03), kind: kind, text: "Lena Weber", check: check)
    }

    func testFoundPlacesAreCoveredAndOfferedOnesAreNot() {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8), area(0.1, 0.7, .phones)], possible: [area(0.1, 0.5)])
        XCTAssertEqual(plan.marks.count, 3)
        XCTAssertEqual(plan.covered.count, 2)
        XCTAssertEqual(plan.marks.filter { $0.origin == .possible }.count, 1)
        XCTAssertEqual(plan.toCheck, 1, "what is only offered waits to be checked")
        XCTAssertEqual(plan.left.count, 1, "and the check of the copy leaves it")
        XCTAssertEqual(plan.report.kinds[.names], 1)
        XCTAssertEqual(plan.report.kinds[.phones], 1)
    }

    func testTheOwnerTurnsPlacesOffAndOnAndUndoes() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8)], possible: [area(0.1, 0.5)])
        let found = try XCTUnwrap(plan.marks.first { $0.origin == .found })
        let offered = try XCTUnwrap(plan.marks.first { $0.origin == .possible })
        plan.toggle(found.id)
        plan.toggle(offered.id)
        XCTAssertEqual(plan.covered.map(\.rect), [offered.rect])
        XCTAssertEqual(plan.left, [found.rect], "left as the owner chose, by the check too")
        XCTAssertEqual(plan.toCheck, 0, "both decided")
        plan.undo()
        XCTAssertTrue(plan.covered.isEmpty, "the offered place is uncovered again")
        plan.undo()
        XCTAssertEqual(plan.covered.map(\.rect), [found.rect])
        XCTAssertFalse(plan.canUndo)
        plan.redo()
        XCTAssertTrue(plan.covered.isEmpty)
        XCTAssertTrue(plan.canRedo)
        // A new change starts a new story: what was undone stays undone.
        plan.toggle(found.id)
        XCTAssertFalse(plan.canRedo)
    }

    func testCoveringByHand() {
        var plan = ProtectionPlan()
        plan.cover(CGRect(x: 0.6, y: 0.4, width: -0.2, height: 0.1))
        XCTAssertEqual(plan.marks.first?.origin, .hand)
        XCTAssertEqual(plan.covered.first?.rect.minX ?? 0, 0.4, accuracy: 0.0001, "drawn either way")
        XCTAssertNil(plan.covered.first?.kind)
        XCTAssertEqual(plan.report.total, 1)
        plan.cover(CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001))
        XCTAssertEqual(plan.marks.count, 1, "too small to see")
        plan.undo()
        XCTAssertTrue(plan.marks.isEmpty)
        plan.redo()
        XCTAssertEqual(plan.marks.count, 1)
        XCTAssertTrue(plan.left.isEmpty, "a hand's place is never left for the check")
    }

    func testWhatIsFoundLaterJoinsWithoutUndoingTheOwner() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8)], possible: [area(0.1, 0.5), area(0.1, 0.3)])
        let first = try XCTUnwrap(plan.marks.first)
        plan.toggle(first.id)
        // Apple Intelligence answers: the same name, one offered before, and a new one.
        plan.add(found: [area(0.1, 0.8), area(0.11, 0.5), area(0.1, 0.2, .emails)])
        XCTAssertEqual(plan.marks.count, 4)
        XCTAssertFalse(plan.marks.first { $0.id == first.id }?.covered ?? true, "the owner's choice holds")
        XCTAssertEqual(plan.marks.first { $0.rect.minY == 0.5 }?.origin, .found, "found now, so covered")
        XCTAssertEqual(plan.marks.first { $0.rect.minY == 0.3 }?.origin, .possible)
        XCTAssertEqual(plan.covered.count, 2)
        plan.undo()
        XCTAssertEqual(plan.covered.count, 3, "undo still undoes the owner's change")
    }

    func testAFingerMeansTheSmallestPlaceUnderIt() {
        var plan = ProtectionPlan()
        plan.add(found: [Finder.Area(rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.2), kind: .addresses),
                         Finder.Area(rect: CGRect(x: 0.2, y: 0.55, width: 0.2, height: 0.05), kind: .names)])
        XCTAssertEqual(plan.mark(at: CGPoint(x: 0.3, y: 0.57))?.kind, .names)
        XCTAssertEqual(plan.mark(at: CGPoint(x: 0.8, y: 0.6))?.kind, .addresses)
        XCTAssertNil(plan.mark(at: CGPoint(x: 0.5, y: 0.1)))
    }

    func testTwoPlacesAreOneWhenTheyNearlyCoincide() {
        let line = CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.03)
        XCTAssertTrue(ProtectionPlan.same(line, CGRect(x: 0.11, y: 0.501, width: 0.48, height: 0.028)))
        XCTAssertFalse(ProtectionPlan.same(line, CGRect(x: 0.2, y: 0.505, width: 0.2, height: 0.02)), "a part of it")
        XCTAssertFalse(ProtectionPlan.same(line, CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.03)))
        XCTAssertFalse(ProtectionPlan.same(line, CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.03)))
    }
}
