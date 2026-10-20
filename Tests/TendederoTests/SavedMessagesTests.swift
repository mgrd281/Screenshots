import Foundation
import XCTest
@testable import Tendedero

/// Saved messages: their blanks fill in from the photo's order, but never
/// with a kind that is covered.
final class SavedMessagesTests: XCTestCase {
    private let fields = [OrderCard.Field(part: .order, value: "1024"), OrderCard.Field(part: .total, value: "74,00 €"),
                          OrderCard.Field(part: .name, value: "Lena Hoffmann")]

    func testBlanksFillFromThePhoto() {
        let text = "Hallo {name}, hier ist die Rechnung zu {order} über {total}."
        XCTAssertEqual(SavedMessages.fill(text, with: fields, covering: []),
                       "Hallo Lena Hoffmann, hier ist die Rechnung zu 1024 über 74,00 €.")
    }

    func testABlankOfACoveredKindStaysEmpty() {
        let text = "Hallo {name}, Bestellung {order}."
        XCTAssertEqual(SavedMessages.fill(text, with: fields, covering: [.names]), "Hallo …, Bestellung 1024.")
        // A name stays empty with any of the names' switches on: any of them may cover it.
        for kind in PrivateDetail.allNames {
            XCTAssertEqual(SavedMessages.fill(text, with: fields, covering: [kind]), "Hallo …, Bestellung 1024.", "\(kind)")
        }
        XCTAssertEqual(SavedMessages.fill(text, with: fields, covering: [.orders]), "Hallo Lena Hoffmann, Bestellung ….")
    }

    func testABlankThePhotoDoesNotShowStaysEmpty() {
        XCTAssertEqual(SavedMessages.fill("Paket {tracking}", with: fields, covering: []), "Paket …")
        XCTAssertEqual(SavedMessages.fill("Danke!", with: fields, covering: []), "Danke!")
        XCTAssertTrue(SavedMessages.hasBlanks("Rechnung {order}"))
        XCTAssertFalse(SavedMessages.hasBlanks("Danke!"))
    }

    func testMessagesAreKept() throws {
        let suite = "SavedMessagesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let messages = [SavedMessage(text: "Rechnung {order}"), SavedMessage(text: "  ")]
        SavedMessages.save(messages, to: defaults)
        XCTAssertEqual(SavedMessages.load(from: defaults), messages)
        XCTAssertTrue(messages[1].isBlank)
    }
}
