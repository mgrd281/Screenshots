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

    func testAgreeingWithAPlaceDecidesItWithoutChangingIt() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8, check: true), area(0.1, 0.6)], possible: [area(0.1, 0.4)])
        XCTAssertEqual(plan.toCheck, 2)
        XCTAssertEqual(plan.doubtful.count, 2)
        XCTAssertEqual(plan.checked, 0)
        // Checked from the top of the picture down.
        XCTAssertEqual(plan.doubtful.map(\.rect.minY), [0.8, 0.4])
        let unsure = try XCTUnwrap(plan.doubtful.first)
        let covered = plan.covered
        plan.decide([unsure.id])
        XCTAssertEqual(plan.covered, covered, "agreeing changes nothing on the picture")
        XCTAssertEqual(plan.toCheck, 1)
        XCTAssertEqual(plan.checked, 1)
        XCTAssertEqual(plan.tally.covered, 2, "a place agreed with counts as covered")
        // An offered place agreed with stays uncovered, decided.
        let offered = try XCTUnwrap(plan.marks.first { $0.origin == .possible })
        plan.decide([offered.id])
        XCTAssertEqual(plan.toCheck, 0)
        XCTAssertEqual(plan.tally.left, 1)
        XCTAssertEqual(plan.tally.exposed, 0)
        // Deciding again is no change; each decision is undone on its own.
        plan.decide([offered.id])
        plan.undo()
        XCTAssertEqual(plan.toCheck, 1)
        XCTAssertEqual(plan.tally.exposed, 1, "an offered place undecided again is not protected")
        plan.undo()
        XCTAssertEqual(plan.toCheck, 2)
        XCTAssertFalse(plan.canUndo)
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

    // MARK: Hidden by hand

    func testEveryEditByHandIsUndoneAndDoneAgain() throws {
        var plan = ProtectionPlan(aspect: 0.5)
        let id = try XCTUnwrap(plan.draw(.stroke([CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.5)], width: 0.04)))
        let drawn = try XCTUnwrap(plan.marks.first)
        XCTAssertEqual(drawn.origin, .hand)
        XCTAssertEqual(drawn.rect.minX, 0.18, accuracy: 0.0001)
        plan.move([id], by: CGPoint(x: 0.1, y: -0.1))
        XCTAssertEqual(plan.marks[0].rect.minX, 0.28, accuracy: 0.0001)
        plan.widen([id], to: 0.06)
        guard case .stroke(_, let width)? = plan.marks[0].shape else { return XCTFail("a stroke") }
        XCTAssertEqual(width, 0.06)
        plan.resize(id, to: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
        XCTAssertEqual(plan.marks[0].rect.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(plan.marks[0].rect.width, 0.3, accuracy: 0.0001)
        plan.remove([id])
        XCTAssertTrue(plan.marks.isEmpty)
        // Back through each, one at a time.
        plan.undo()
        XCTAssertEqual(plan.marks[0].rect.width, 0.3, accuracy: 0.0001)
        plan.undo()
        XCTAssertEqual(plan.marks[0].rect.minX, 0.27, accuracy: 0.0001, "wider, before the resize")
        plan.undo()
        XCTAssertEqual(plan.marks[0].rect.minX, 0.28, accuracy: 0.0001)
        plan.undo()
        XCTAssertEqual(plan.marks[0], drawn)
        plan.undo()
        XCTAssertTrue(plan.marks.isEmpty)
        XCTAssertFalse(plan.canUndo)
        for _ in 0..<5 { plan.redo() }
        XCTAssertTrue(plan.marks.isEmpty, "removed again")
        XCTAssertFalse(plan.canRedo)
    }

    func testABoxIsTurnedAndAnOutlineFilled() throws {
        var plan = ProtectionPlan(aspect: 1)
        let box = try XCTUnwrap(plan.draw(.box(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), angle: 0)))
        plan.turn(box, by: .pi / 4)
        let turned = try XCTUnwrap(plan.marks.first)
        XCTAssertEqual(turned.rect.width, 0.2 * 2.squareRoot(), accuracy: 0.0001, "the box round it grows")
        XCTAssertNotNil(plan.mark(at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertNil(plan.mark(at: CGPoint(x: 0.415, y: 0.415)), "a corner the turn left")
        XCTAssertNil(plan.draw(.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)])), "an outline needs three points")
        let outline = try XCTUnwrap(plan.draw(.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.1),
                                                        CGPoint(x: 0.2, y: 0.3)])))
        XCTAssertEqual(plan.covered.first { $0.shape != nil && $0.rect.minY < 0.2 }?.shape,
                       plan.marks.first { $0.id == outline }?.shape, "the copy is inked as drawn")
        XCTAssertEqual(plan.report.hand, 2)
    }

    func testTheEraserTakesWhatIsByHandAndUncoversWhatWasFound() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8)])
        try XCTUnwrap(plan.draw(.stroke([CGPoint(x: 0.1, y: 0.4), CGPoint(x: 0.5, y: 0.4)], width: 0.03)))
        let touched = plan.erased(along: [CGPoint(x: 0.2, y: 0.81), CGPoint(x: 0.3, y: 0.41)], reach: 0.01)
        XCTAssertEqual(touched.count, 2)
        XCTAssertTrue(plan.erased(along: [CGPoint(x: 0.9, y: 0.1)], reach: 0.01).isEmpty)
        plan.remove(touched)
        XCTAssertEqual(plan.marks.count, 1, "the stroke is gone")
        XCTAssertFalse(plan.marks[0].covered, "the original shows again")
        XCTAssertEqual(plan.left.count, 1, "and the check of the copy leaves it")
        plan.undo()
        XCTAssertEqual(plan.covered.count, 2, "both back as one change")
    }

    func testClearingByHandAndGoingBackToWhatWasFound() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8)], possible: [area(0.1, 0.5)])
        let found = try XCTUnwrap(plan.marks.first { $0.origin == .found })
        let offered = try XCTUnwrap(plan.marks.first { $0.origin == .possible })
        plan.toggle(found.id)
        plan.toggle(offered.id)
        plan.cover(CGRect(x: 0.5, y: 0.1, width: 0.2, height: 0.05))
        plan.clearHand()
        XCTAssertFalse(plan.hasHand)
        XCTAssertEqual(plan.covered.map(\.rect), [offered.rect], "the owner's turns stay")
        plan.cover(CGRect(x: 0.5, y: 0.1, width: 0.2, height: 0.05))
        plan.resetToFound()
        XCTAssertEqual(plan.covered.map(\.rect), [found.rect])
        XCTAssertFalse(plan.isChanged)
        XCTAssertEqual(plan.toCheck, 1, "the offered place waits again")
        plan.undo()
        XCTAssertTrue(plan.hasHand)
        XCTAssertEqual(plan.covered.count, 2)
    }

    func testEachPlaceIsCountedOnceAndOfferedOnesAreNeverCountedAsCovered() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8), area(0.1, 0.7, check: true)], possible: [area(0.1, 0.5)])
        XCTAssertEqual(plan.tally, ProtectionPlan.Tally(covered: 1, toCheck: 2, left: 0, exposed: 1))
        let sure = try XCTUnwrap(plan.marks.first { !$0.check })
        plan.toggle(sure.id)
        XCTAssertEqual(plan.tally, ProtectionPlan.Tally(covered: 0, toCheck: 2, left: 1, exposed: 1))
        let offered = try XCTUnwrap(plan.marks.first { $0.origin == .possible })
        plan.toggle(offered.id)
        XCTAssertEqual(plan.tally, ProtectionPlan.Tally(covered: 1, toCheck: 1, left: 1, exposed: 0))
    }

    func testAMarkMovedStaysOnThePicture() throws {
        var plan = ProtectionPlan()
        let id = try XCTUnwrap(plan.cover(CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.1)))
        plan.move([id], by: CGPoint(x: 0.5, y: -0.5))
        XCTAssertEqual(plan.marks[0].rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.marks[0].rect.minY, 0, accuracy: 0.0001)
    }

    // MARK: Who and what

    private func area(_ x: CGFloat, _ y: CGFloat, _ kind: PrivateDetail?, role: PersonRole?,
                      check: Bool = false) -> Finder.Area {
        var made = area(x, y, kind, check: check)
        made.role = role
        return made
    }

    func testWhatSettingsLeavesVisibleIsListedAndCountedAsVisibleNotAsCovered() throws {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8, .names, role: .patient)], spared: [area(0.5, 0.6, .names, role: .doctor)])
        let doctor = try XCTUnwrap(plan.marks.first { $0.origin == .spared })
        XCTAssertFalse(doctor.covered)
        XCTAssertEqual(doctor.role, .doctor)
        XCTAssertEqual(plan.tally, ProtectionPlan.Tally(covered: 1, toCheck: 0, left: 0, exposed: 0, visible: 1))
        XCTAssertEqual(plan.left, [doctor.rect], "the check of the copy leaves it too")
        let middle = CGPoint(x: doctor.rect.midX, y: doctor.rect.midY)
        XCTAssertNil(plan.mark(at: middle), "not on the picture until covered")
        plan.toggle(doctor.id)
        XCTAssertEqual(plan.mark(at: middle)?.id, doctor.id)
        XCTAssertEqual(plan.tally.covered, 2)
        XCTAssertEqual(plan.tally.visible, 0, "covered with a tap, no longer visible")
        XCTAssertEqual(plan.report.kinds[.names], 2)
        // Back to what Snapfly found: visible again.
        plan.resetToFound()
        XCTAssertEqual(plan.covered.count, 1)
    }

    func testAPlaceLeftVisibleThatIsFoundLaterIsCovered() throws {
        var plan = ProtectionPlan()
        plan.add(found: [], spared: [area(0.1, 0.8, .ids, role: .patient), area(0.1, 0.6, .ids, role: nil)])
        let touched = try XCTUnwrap(plan.marks.last)
        plan.toggle(touched.id)
        plan.toggle(touched.id)
        plan.add(found: [area(0.1, 0.8, .ids), area(0.1, 0.6, .ids)])
        XCTAssertEqual(plan.marks.count, 2)
        XCTAssertEqual(plan.marks.first?.origin, .found)
        XCTAssertEqual(plan.marks.first?.covered, true)
        XCTAssertEqual(plan.marks.first?.role, .patient, "its person is kept")
        XCTAssertEqual(plan.marks.last?.covered, false, "the owner's choice stays")
    }

    func testATopicIsCoveredOrLeftAtOnceAsOneChange() {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.8, .names, role: .doctor, check: true)],
                 spared: [area(0.1, 0.6, .names, role: .doctor), area(0.1, 0.4, .names, role: .doctor)])
        let ids = Set(plan.marks.map(\.id))
        plan.set(ids, covered: true)
        XCTAssertEqual(plan.covered.count, 3)
        XCTAssertEqual(plan.toCheck, 0, "covering them all decides each")
        plan.set(ids, covered: false)
        XCTAssertTrue(plan.covered.isEmpty)
        plan.undo()
        XCTAssertEqual(plan.covered.count, 3)
        plan.undo()
        XCTAssertEqual(plan.covered.count, 1)
        XCTAssertEqual(plan.toCheck, 1)
    }

    func testPlacesAreListedByWhoseTheyAreThenByWhatTheyAre() {
        var plan = ProtectionPlan()
        plan.add(found: [area(0.1, 0.3, .bank, role: nil), area(0.1, 0.5, .addresses, role: .patient),
                         area(0.1, 0.9, .names, role: .patient), area(0.1, 0.7, .names, role: .customer),
                         area(0.1, 0.6, .health, role: nil), area(0.1, 0.2, nil, role: nil),
                         area(0.1, 0.1, .names, role: nil)],
                 spared: [area(0.6, 0.9, .names, role: .doctor)])
        plan.cover(CGRect(x: 0.5, y: 0.05, width: 0.2, height: 0.05))
        let topics = plan.topics
        XCTAssertEqual(topics.map(\.topic), [.patient, .doctors, .otherPeople, .group(.people), .group(.money),
                                             .group(.health), .hand, .rules])
        // Each from the top of the picture down.
        XCTAssertEqual(topics[0].marks.map(\.kind), [.names, .addresses])
    }
}
