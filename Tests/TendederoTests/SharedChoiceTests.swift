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

    /// A choice the app kept before each of the names' switches covered its
    /// own people covers what it did, brought up to date as the app does
    /// it, for a picture shared before the app was opened again.
    func testAChoiceKeptBeforeTheNamesPartedCoversWhatItDid() throws {
        let json = #"{"kinds":["emails","names","patientNames"],"style":"ink","rules":[]}"#
        let before = try JSONDecoder().decode(SharedChoice.self, from: Data(json.utf8))
        XCTAssertEqual(before.details, [.names, .patientNames, .otherPeople, .emails])
        let alone = try JSONDecoder().decode(SharedChoice.self, from: Data(#"{"kinds":["names"],"style":"ink","rules":[]}"#.utf8))
        XCTAssertEqual(alone.details, [.names], "Names alone stays as it was chosen")
        // Kept now, as chosen.
        XCTAssertEqual(SharedChoice(details: [.names, .patientNames], look: .ink, rules: []).details, [.names, .patientNames])
    }

    func testWhatThisVersionDoesNotKnowIsLeftOrInk() throws {
        let json = #"{"kinds":["names","somethingNew"],"style":"sparkles","rules":[]}"#
        let choice = try JSONDecoder().decode(SharedChoice.self, from: Data(json.utf8))
        XCTAssertEqual(choice.details, [.names], "a kind from a later version is left out")
        XCTAssertEqual(choice.look, .ink, "a look this version does not know is ink, the surest")
    }
}
