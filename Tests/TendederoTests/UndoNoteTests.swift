import Foundation
import XCTest
@testable import Tendedero

/// The order of the icons under photos, as dragged in Settings, and the
/// note that offers photos back once they have left the line.
final class UndoNoteTests: XCTestCase {
    func testTheIconsKeepTheOrderTheyWereDraggedInto() throws {
        XCTAssertEqual(ChatTarget.order(from: []), ChatTarget.allCases)
        // Unknown names and repeats are left out; the rest follow as listed.
        let order = ChatTarget.order(from: ["claude", "nonsense", "claude", "gmail"])
        XCTAssertEqual(Array(order.prefix(2)), [.claude, .gmail])
        XCTAssertEqual(Set(order), Set(ChatTarget.allCases))
        XCTAssertEqual(order.count, ChatTarget.allCases.count)

        let suite = "UndoNoteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ChatTarget.setOrder(order, in: defaults)
        XCTAssertEqual(ChatTarget.ordered(in: defaults), order)
    }

    func testOneMovesToWhereAnotherStands() {
        let order: [ChatTarget] = [.chatGPT, .claude, .whatsApp, .gmail]
        XCTAssertEqual(ChatTarget.moving(.gmail, to: .chatGPT, in: order), [.gmail, .chatGPT, .claude, .whatsApp])
        XCTAssertEqual(ChatTarget.moving(.chatGPT, to: .whatsApp, in: order), [.claude, .whatsApp, .chatGPT, .gmail])
        XCTAssertEqual(ChatTarget.moving(.claude, to: .claude, in: order), order)
        XCTAssertEqual(ChatTarget.moving(.gmx, to: .claude, in: order), order)
    }

    func testTheNoteSaysWhereTheyWentAndHowMany() {
        XCTAssertEqual(Line.goneNote(count: 1, trashed: false), "Taken down. Click to put it back on the line.")
        XCTAssertEqual(Line.goneNote(count: 4, trashed: false), "4 taken down. Click to put them back on the line.")
        XCTAssertEqual(Line.goneNote(count: 1, trashed: true), "Moved to the Trash. Click to put it back on the line.")
        XCTAssertEqual(Line.goneNote(count: 2, trashed: true), "2 moved to the Trash. Click to put them back on the line.")
    }
}
