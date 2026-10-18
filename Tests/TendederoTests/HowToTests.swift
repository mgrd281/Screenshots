import Foundation
import XCTest
@testable import Tendedero

/// Step-by-step guides: what each step says, which part of the screen it
/// shows and what it marks there, how steps share pages, and how guides are
/// kept.
final class HowToTests: XCTestCase {
    private let open: (String) -> Bool = { _ in false }

    private func step(point: CGPoint, target: CGRect? = nil, focused: Bool = true) -> HowToStep {
        HowToStep(text: "", file: "a.png", width: 3000, height: 2000, point: point, target: target, focused: focused)
    }

    // MARK: Wording

    func testEachKindOfThingIsSaidItsOwnWay() {
        func said(_ role: String, _ subrole: String? = nil, _ name: String = "Orders") -> String {
            HowToWording.sentence(.single, on: .init(role: role, subrole: subrole, name: name), isPrivate: open)
        }
        XCTAssertEqual(said("AXButton"), "Click “Orders”.")
        XCTAssertEqual(said("AXMenuItem"), "Choose “Orders”.")
        XCTAssertEqual(said("AXMenuBarItem"), "Open the “Orders” menu.")
        XCTAssertEqual(said("AXLink"), "Click the “Orders” link.")
        XCTAssertEqual(said("AXTextField", "AXSearchField", "Search"), "Click the “Search” field.")
        XCTAssertEqual(said("AXRadioButton", "AXTabButton"), "Open the “Orders” tab.")
        XCTAssertEqual(said("AXDockItem", nil, "Safari"), "Open “Safari” in the Dock.")
    }

    func testAClickWithoutANameSaysWhere() {
        XCTAssertEqual(HowToWording.sentence(.single, on: nil, isPrivate: open), "Click here.")
        XCTAssertEqual(HowToWording.sentence(.single, on: .init(role: "AXTextField"), isPrivate: open), "Click the field.")
        XCTAssertEqual(HowToWording.sentence(.double, on: nil, isPrivate: open), "Double-click here.")
        XCTAssertEqual(HowToWording.sentence(.right, on: .init(role: "AXButton", name: "Photo"), isPrivate: open),
                       "Right-click “Photo”.")
    }

    func testNothingPrivateGoesIntoASentence() {
        let names: (String) -> Bool = { $0.contains("Mustermann") }
        XCTAssertEqual(HowToWording.sentence(.single, on: .init(role: "AXStaticText", name: "Max Mustermann"),
                                             isPrivate: names), "Click here.")
        // Amounts and order numbers on a page stay out; a control's may stay.
        XCTAssertNil(HowToWording.usableName("Order 10248", kind: .content, isPrivate: open))
        XCTAssertNil(HowToWording.usableName("€ 149,90", kind: .link, isPrivate: open))
        XCTAssertEqual(HowToWording.usableName("Save 2026", kind: .control, isPrivate: open), "Save 2026")
    }

    func testANameIsTidiedAndALongOneCutAtAWord() {
        XCTAssertEqual(HowToWording.usableName("  Add \n to   cart ", kind: .control, isPrivate: open), "Add to cart")
        let long = Array(repeating: "word", count: 20).joined(separator: " ")
        let cut = HowToWording.usableName(long, kind: .control, isPrivate: open)
        XCTAssertNotNil(cut)
        XCTAssertLessThanOrEqual(cut!.count, HowToWording.longestName)
        XCTAssertTrue(cut!.hasSuffix("word…"))
        XCTAssertNil(HowToWording.usableName("   ", kind: .control, isPrivate: open))
    }

    // MARK: Focus and mark

    func testAStepShowsThePartAroundItsClickInsideThePicture() {
        let middle = HowToFrame.focus(of: step(point: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(middle.width, HowToFrame.focusShare, accuracy: 0.0001)
        XCTAssertEqual(middle.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(middle.width * 3000 / (middle.height * 2000), HowToFrame.focusAspect, accuracy: 0.001)
        // Near a corner it stops at the edges.
        let corner = HowToFrame.focus(of: step(point: CGPoint(x: 0.98, y: 0.02)))
        XCTAssertEqual(corner.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(corner.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(HowToFrame.focus(of: step(point: CGPoint(x: 0.5, y: 0.5), focused: false)), HowToFrame.whole)
    }

    func testAWideTargetWidensThePartAndAHugeOneShowsAll() {
        let wide = step(point: CGPoint(x: 0.5, y: 0.5), target: CGRect(x: 0.05, y: 0.45, width: 0.85, height: 0.1))
        XCTAssertEqual(HowToFrame.focus(of: wide), HowToFrame.whole)
        let button = step(point: CGPoint(x: 0.3, y: 0.3), target: CGRect(x: 0.28, y: 0.29, width: 0.04, height: 0.02))
        let shown = HowToFrame.focus(of: button)
        XCTAssertTrue(shown.minX <= 0.28 && shown.minY <= 0.29 && shown.maxX >= 0.32 && shown.maxY >= 0.31)
        // A target the click is not in, or a whole page, is left out.
        XCTAssertNil(HowToFrame.target(of: step(point: CGPoint(x: 0.9, y: 0.9),
                                                target: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05))))
        XCTAssertNil(HowToFrame.target(of: step(point: CGPoint(x: 0.5, y: 0.5), target: HowToFrame.whole)))
    }

    func testTheMarkIsABoxAroundTheTargetOrARingAtTheClick() {
        let button = step(point: CGPoint(x: 0.3, y: 0.3), target: CGRect(x: 0.28, y: 0.29, width: 0.04, height: 0.02))
        let part = HowToFrame.focus(of: button)
        guard case let .box(box) = HowToFrame.mark(of: button, in: part) else { return XCTFail("a box") }
        // The target's pixels, measured from the part's corner, inside the box.
        let inPart = CGRect(x: 0.28 * 3000 - part.minX * 3000, y: 0.29 * 2000 - part.minY * 2000, width: 120, height: 40)
        XCTAssertTrue(box.minX <= inPart.minX && box.minY <= inPart.minY
                      && box.maxX >= inPart.maxX && box.maxY >= inPart.maxY)
        let bare = step(point: CGPoint(x: 0.5, y: 0.5))
        guard case let .ring(center, radius) = HowToFrame.mark(of: bare, in: HowToFrame.whole) else {
            return XCTFail("a ring")
        }
        XCTAssertEqual(center.x, 1500, accuracy: 0.001)
        XCTAssertEqual(center.y, 1000, accuracy: 0.001)
        XCTAssertGreaterThan(radius, 20)
    }

    // MARK: Pages

    func testStepsFillPagesInOrderAndATallOneHasAPageToItself() {
        XCTAssertEqual(HowToPages.paginate(heights: [100, 100, 100], firstRoom: 250, room: 300, gap: 20), [[0, 1], [2]])
        XCTAssertEqual(HowToPages.paginate(heights: [500, 100], firstRoom: 300, room: 400, gap: 20), [[0], [1]])
        XCTAssertEqual(HowToPages.paginate(heights: [], firstRoom: 300, room: 400, gap: 20), [[]])
        XCTAssertEqual(HowToPages.paginate(heights: [100, 100, 100, 100], firstRoom: 400, room: 400, gap: 0),
                       [[0, 1, 2, 3]])
    }

    // MARK: Keeping

    func testAGuideIsKeptAndTheOldestLetGo() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("HowTo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        var guides: [HowToGuide] = []
        for n in 0..<4 {
            var guide = HowToGuide(title: "Guide \(n)", created: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)))
            guide.steps = [step(point: CGPoint(x: 0.25, y: 0.75), target: CGRect(x: 0.2, y: 0.7, width: 0.1, height: 0.1))]
            try HowToStore.save(guide, in: base)
            guides.append(guide)
        }
        XCTAssertEqual(HowToStore.load(guides[2].id, in: base), guides[2])
        XCTAssertEqual(HowToStore.recent(in: base).map(\.title), ["Guide 3", "Guide 2", "Guide 1", "Guide 0"])
        // An empty one goes, and past two kept the oldest, but not the one open.
        try HowToStore.save(HowToGuide(title: "Empty"), in: base)
        HowToStore.prune(keeping: 2, sparing: guides[0].id, in: base)
        XCTAssertEqual(HowToStore.recent(in: base).map(\.title), ["Guide 3", "Guide 0"])
        XCTAssertEqual(HowToStore.coveredName(of: guides[0].steps[0]), "a-covered.png")
    }
}
