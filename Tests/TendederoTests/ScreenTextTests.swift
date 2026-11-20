import XCTest
@testable import Tendedero

/// Copy Text from Screen: the lines read put back in reading order, rows
/// from the top, a row's parts in its own direction, paragraphs apart.
final class ScreenTextTests: XCTestCase {
    private func line(_ text: String, x: Double, y: Double, width: Double = 0.3, height: Double = 0.04) -> (string: String, box: CGRect) {
        (text, CGRect(x: x, y: y, width: width, height: height))
    }

    func testRowsGoFromTheTopAndARowsPartsFromTheLeft() {
        let text = ScreenText.text(of: [
            line("12345", x: 0.5, y: 0.84),
            line("Tracking number", x: 0.1, y: 0.89),
            line("Order", x: 0.1, y: 0.84),
            line("DHL 00340434161234567890", x: 0.5, y: 0.89),
        ])
        XCTAssertEqual(text, "Tracking number DHL 00340434161234567890\nOrder 12345")
    }

    func testAWideGapIsANewParagraph() {
        let text = ScreenText.text(of: [
            line("Dear customer,", x: 0.1, y: 0.9),
            line("Thank you for your order.", x: 0.1, y: 0.85),
            line("Kind regards", x: 0.1, y: 0.6),
        ])
        XCTAssertEqual(text, "Dear customer,\nThank you for your order.\n\nKind regards")
    }

    func testArabicPartsOfARowGoFromTheRight() {
        let text = ScreenText.text(of: [
            line("رقم الطلب", x: 0.6, y: 0.8),
            line("١٢٣٤٥", x: 0.1, y: 0.8),
        ])
        XCTAssertEqual(text, "رقم الطلب ١٢٣٤٥")
        XCTAssertTrue(ScreenText.isRightToLeft("مرحبا بك"))
        XCTAssertFalse(ScreenText.isRightToLeft("Hello"))
    }

    func testNothingReadIsNothingCopied() {
        XCTAssertEqual(ScreenText.text(of: []), "")
        XCTAssertEqual(ScreenText.text(of: [line("  ", x: 0.1, y: 0.5)]), "")
    }

    func testTheNoteShowsTheStartOnOneLine() {
        XCTAssertEqual(ScreenText.preview("Order\n12345"), "Order 12345")
        let long = String(repeating: "word ", count: 20)
        XCTAssertTrue(ScreenText.preview(long).hasSuffix("…"))
        XCTAssertLessThanOrEqual(ScreenText.preview(long).count, 41)
    }

    func testItHasAShortcutOfItsOwn() {
        XCTAssertEqual(Shortcut.Role.text.standard.display, "⌃⌥C")
    }
}
