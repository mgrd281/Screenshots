import Foundation
import XCTest
@testable import Tendedero

/// What the iPhone app keeps for its share extension: the kinds, the look
/// and the owner's own rules, and nothing more.
final class SharedChoiceTests: XCTestCase {
    func testTheChoiceComesBackAsItWasKept() throws {
        let rules = [OwnRule(text: "Projekt Nordlicht", kind: .word)]
        let choice = SharedChoice(details: [.names, .health, .ids], look: .blur, rules: rules)
        let back = try JSONDecoder().decode(SharedChoice.self, from: JSONEncoder().encode(choice))
        XCTAssertEqual(back, choice)
        XCTAssertEqual(back.details, [.names, .health, .ids])
        XCTAssertEqual(back.look, .blur)
        XCTAssertEqual(back.rules, rules)
    }

    func testWhatThisVersionDoesNotKnowIsLeftOrInk() throws {
        let json = #"{"kinds":["names","somethingNew"],"style":"sparkles","rules":[]}"#
        let choice = try JSONDecoder().decode(SharedChoice.self, from: Data(json.utf8))
        XCTAssertEqual(choice.details, [.names], "a kind from a later version is left out")
        XCTAssertEqual(choice.look, .ink, "a look this version does not know is ink, the surest")
    }
}
