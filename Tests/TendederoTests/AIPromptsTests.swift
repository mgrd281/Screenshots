import Foundation
import XCTest
@testable import Tendedero

/// The prompts for AI chats: the standard ones until changed in Settings,
/// numbered in order, blanks left out, nine at most, and a way back.
final class AIPromptsTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "AIPromptsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testTheStandardPromptsAreReady() {
        let standard = AIPrompts.standard
        XCTAssertEqual(standard.count, 2)
        XCTAssertFalse(standard.contains { $0.isBlank })
        XCTAssertFalse(standard.contains { $0.title.isEmpty })
        // Natural writing comes in paragraphs, the way a chat reads it best.
        XCTAssertEqual(standard[0].text.components(separatedBy: "\n\n").count, 10)
    }

    func testTheOwnersPromptsTakeThePlaceOfTheStandardOnes() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AIPrompts.isCustomised(in: defaults))
        XCTAssertEqual(AIPrompts.offered(from: defaults).map(\.title), AIPrompts.standard.map(\.title))
        let mine = [AIPrompt(title: "Kurz", text: "Fass das kurz zusammen."), AIPrompt(title: "Leer", text: " \n"),
                    AIPrompt(title: "", text: "Antworte freundlich.")]
        AIPrompts.save(mine, to: defaults)
        XCTAssertTrue(AIPrompts.isCustomised(in: defaults))
        XCTAssertEqual(AIPrompts.load(from: defaults), mine)
        // A blank waits in Settings; the others are numbered as they stand.
        let offered = AIPrompts.offered(from: defaults)
        XCTAssertEqual(offered.map(\.text), ["Fass das kurz zusammen.", "Antworte freundlich."])
        XCTAssertEqual(offered[1].name(number: 2), String(format: L("Prompt %d"), 2))
        AIPrompts.restore(in: defaults)
        XCTAssertFalse(AIPrompts.isCustomised(in: defaults))
        XCTAssertEqual(AIPrompts.offered(from: defaults).count, 2)
    }

    func testTheStandardPromptsAreNotKept() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // Saved as they stand, they are not kept, so they follow the
        // language Snapfly speaks; kept that way before, they still count
        // as standard.
        AIPrompts.save(AIPrompts.standard, to: defaults)
        XCTAssertNil(defaults.data(forKey: AIPrompts.key))
        XCTAssertFalse(AIPrompts.isCustomised(in: defaults))
        defaults.set(try JSONEncoder().encode(AIPrompts.standard), forKey: AIPrompts.key)
        XCTAssertFalse(AIPrompts.isCustomised(in: defaults))
        // A new title is a change, and kept.
        var changed = AIPrompts.standard
        changed[1].title = "Antwort an die Kundin"
        AIPrompts.save(changed, to: defaults)
        XCTAssertTrue(AIPrompts.isCustomised(in: defaults))
        XCTAssertTrue(AIPrompts.sameWords(AIPrompts.load(from: defaults), changed))
    }

    func testNineAtMostOneDigitEach() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AIPrompts.save((1...12).map { AIPrompt(title: "\($0)", text: "Prompt \($0)") }, to: defaults)
        XCTAssertEqual(AIPrompts.load(from: defaults).count, 9)
        XCTAssertEqual(AIPrompts.offered(from: defaults).last?.title, "9")
    }

    func testTheNumbersShowUntilTurnedOff() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AIPrompts.showsBesideButton(in: defaults))
        AIPrompts.setShowsBesideButton(false, in: defaults)
        XCTAssertFalse(AIPrompts.showsBesideButton(in: defaults))
    }
}
