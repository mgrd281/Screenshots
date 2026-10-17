import XCTest
@testable import Tendedero

/// Telling a picture that says what a sent one said, from its print alone.
final class TextPrintTests: XCTestCase {
    private let order = [
        "Bestellung #1024", "Lena Mueller", "Hauptstrasse 5", "10115 Berlin",
        "1 x Leinentasche natur 24,00 EUR", "2 x Becher blau 25,00 EUR", "Versand 4,90 EUR",
        "Summe 78,90 EUR", "Bezahlt mit PayPal am 17.10.2026", "Vielen Dank fuer deinen Einkauf!",
    ]
    private let anotherOrder = [
        "Bestellung #2048", "Jonas Weber", "Gartenweg 12", "80331 Muenchen",
        "1 x Leinentasche natur 24,00 EUR", "1 x Teller weiss 18,50 EUR", "Versand 4,90 EUR",
        "Summe 47,40 EUR", "Bezahlt mit PayPal am 12.10.2026", "Vielen Dank fuer deinen Einkauf!",
    ]
    private let footer = [
        "Thank you for shopping with us at the corner store today",
        "Returns are accepted within thirty days of delivery with the receipt",
        "Questions about your order can be sent to our friendly support team",
        "We ship from our workshop in Berlin every working day of the week",
        "Please keep this confirmation for your records and your accountant",
    ]

    func testThePictureTakenAgainMatches() throws {
        let sent = try XCTUnwrap(TextPrint.of(order))
        // Read again in capitals, with its last line cut off, or its first.
        let capitals = try XCTUnwrap(TextPrint.of(order.dropLast().map { $0.uppercased() }))
        let lower = try XCTUnwrap(TextPrint.of(Array(order.dropFirst())))
        XCTAssertTrue(sent.matches(sent))
        XCTAssertTrue(sent.matches(capitals))
        XCTAssertTrue(sent.matches(lower))
    }

    func testAnotherOrderFromTheShopDoesNot() throws {
        let sent = try XCTUnwrap(TextPrint.of(order))
        let another = try XCTUnwrap(TextPrint.of(anotherOrder))
        XCTAssertFalse(sent.matches(another))
    }

    func testTheSameWordsWithOtherNumbersDoNot() throws {
        let first = try XCTUnwrap(TextPrint.of(["Order 1024", "Total 74.00", "Paid on 17.10.2026"] + footer))
        let second = try XCTUnwrap(TextPrint.of(["Order 2048", "Total 18.50", "Paid on 12.09.2026"] + footer))
        // The words alone would pass; the numbers tell the two apart.
        XCTAssertGreaterThanOrEqual(TextPrint.likeness(first.words, second.words), 0.7)
        XCTAssertFalse(first.matches(second))
    }

    func testTooFewWordsMakeNoPrint() {
        XCTAssertNil(TextPrint.of(["Hallo Welt"]))
        XCTAssertNil(TextPrint.of([]))
    }

    func testTheHashStaysTheSameFromLaunchToLaunch() {
        XCTAssertEqual(TextPrint.hash(""), 2_872_998_923)
        XCTAssertEqual(TextPrint.hash("a"), 444_641_715)
    }

    func testLikenessCountsTheSharedSmallestHashes() {
        XCTAssertEqual(TextPrint.likeness([1, 2, 3], [1, 2, 3]), 1)
        XCTAssertEqual(TextPrint.likeness([1, 2], [3, 4]), 0)
        XCTAssertEqual(TextPrint.likeness([1, 2, 3, 4], [3, 4, 5, 6]), 2.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(TextPrint.likeness([], []), 0)
    }

    func testCaseAndAccentsDontCount() {
        let tokens = TextPrint.tokens(in: "Café #1024, RECHNUNG")
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens, TextPrint.tokens(in: "cafe 1024 rechnung"))
    }

    func testAPrintIsKeptAndReadBack() throws {
        let kept = try XCTUnwrap(TextPrint.of(order))
        let data = try JSONEncoder().encode(kept)
        let read = try JSONDecoder().decode(TextPrint.self, from: data)
        XCTAssertEqual(read, kept)
    }
}
