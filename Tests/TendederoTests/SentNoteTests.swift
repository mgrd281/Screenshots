import Foundation
import XCTest
@testable import Tendedero

/// The note once sent photos have left the line: where they went, how many
/// when several, and the click that puts them back.
final class SentNoteTests: XCTestCase {
    func testTheNoteSaysWhereTheyWentAndHowMany() {
        XCTAssertEqual(Line.leftNote(count: 1, to: "WhatsApp"), "Sent to WhatsApp. Click to put it back on the line.")
        XCTAssertEqual(Line.leftNote(count: 3, to: "chatgpt.com"), "3 sent to chatgpt.com. Click to put them back on the line.")
        // Dragged into an app, which one is not known.
        XCTAssertEqual(Line.leftNote(count: 1, to: nil), "Sent. Click to put it back on the line.")
        XCTAssertEqual(Line.leftNote(count: 2, to: nil), "2 sent. Click to put them back on the line.")
    }
}
