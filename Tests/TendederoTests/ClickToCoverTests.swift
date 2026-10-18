import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Hide Part covers the word clicked, and can cover it in every photo from
/// then on, as a rule of the owner's own.
final class ClickToCoverTests: XCTestCase {
    func testALineSplitsIntoItsWords() {
        let line = "Christopher  Kelly, 5 Bestellungen"
        let words = HideModel.wordRanges(in: line).map { String(line[$0]) }
        XCTAssertEqual(words, ["Christopher", "Kelly,", "5", "Bestellungen"])
        XCTAssertEqual(HideModel.wordRanges(in: "   "), [])
    }

    func testTheWordUnderThePointerOrTheNearestOnItsRow() {
        let first = CGRect(x: 0.10, y: 0.50, width: 0.10, height: 0.02)
        let second = CGRect(x: 0.22, y: 0.50, width: 0.08, height: 0.02)
        let below = CGRect(x: 0.10, y: 0.45, width: 0.10, height: 0.02)
        let boxes = [first, second, below]
        XCTAssertEqual(HideModel.word(at: CGPoint(x: 0.15, y: 0.51), among: boxes), 0)
        XCTAssertEqual(HideModel.word(at: CGPoint(x: 0.25, y: 0.51), among: boxes), 1)
        XCTAssertEqual(HideModel.word(at: CGPoint(x: 0.15, y: 0.46), among: boxes), 2)
        // In the gap between two words, the nearer one.
        XCTAssertEqual(HideModel.word(at: CGPoint(x: 0.215, y: 0.51), among: boxes), 1)
        // Far from any word, nothing.
        XCTAssertNil(HideModel.word(at: CGPoint(x: 0.60, y: 0.51), among: boxes))
        XCTAssertNil(HideModel.word(at: CGPoint(x: 0.15, y: 0.80), among: boxes))
    }

    func testARuleTakesTheWordWithoutItsPunctuation() {
        XCTAssertEqual(HideModel.ruleText("Kelly,"), "Kelly")
        XCTAssertEqual(HideModel.ruleText("„Auenstraße“"), "Auenstraße")
        XCTAssertEqual(HideModel.ruleText("tazman21@gmx.de"), "tazman21@gmx.de")
        XCTAssertNil(HideModel.ruleText("•"))
        XCTAssertNil(HideModel.ruleText("A."))
    }

    func testAWordToCoverAlwaysIsAddedOnce() throws {
        let suite = "ClickToCoverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        OwnRules.save([OwnRule(text: "Kundennummer", kind: .label)], to: defaults)
        let told = expectation(forNotification: OwnRules.changed, object: nil)
        OwnRules.add(word: " Kelly ", to: defaults)
        wait(for: [told], timeout: 1)
        // Already a rule, in any case: nothing changes.
        OwnRules.add(word: "kelly", to: defaults)
        OwnRules.add(word: "  ", to: defaults)
        let rules = OwnRules.load(from: defaults)
        XCTAssertEqual(rules.map(\.text), ["Kundennummer", "Kelly"])
        XCTAssertEqual(rules.map(\.kind), [.label, .word])
    }
}
