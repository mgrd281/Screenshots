import Foundation
import XCTest
@testable import Tendedero

/// The questions a photo goes into ChatGPT or Claude with: the standard
/// ones until changed in Settings, blanks left out, and a way back.
final class AIQuestionsTests: XCTestCase {
    func testTheStandardQuestionsAreReady() {
        let standard = AIQuestions.standard
        XCTAssertEqual(standard.count, 5)
        XCTAssertFalse(standard.contains { $0.isBlank })
        XCTAssertEqual(Set(standard.map(\.text)).count, standard.count, "no question twice")
    }

    func testTheOwnersQuestionsTakeThePlaceOfTheStandardOnes() throws {
        let suite = "AIQuestionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AIQuestions.isCustomised(in: defaults))
        XCTAssertEqual(AIQuestions.load(from: defaults).map(\.text), AIQuestions.standard.map(\.text))
        let mine = [AIQuestion(text: "Welche Bestellnummer?"), AIQuestion(text: "  "), AIQuestion(text: "Übersetze.")]
        AIQuestions.save(mine, to: defaults)
        XCTAssertTrue(AIQuestions.isCustomised(in: defaults))
        XCTAssertEqual(AIQuestions.load(from: defaults), mine)
        // A blank waits in Settings; it is not offered on a photo.
        XCTAssertEqual(AIQuestions.offered(from: defaults).map(\.text), ["Welche Bestellnummer?", "Übersetze."])
        AIQuestions.restore(in: defaults)
        XCTAssertFalse(AIQuestions.isCustomised(in: defaults))
        XCTAssertEqual(AIQuestions.offered(from: defaults).count, 5)
    }
}
