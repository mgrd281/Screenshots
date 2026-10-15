import XCTest
@testable import Tendedero

/// What Apple Intelligence answers is read into lines and words to hide,
/// and words typed without it are found in the screenshot's lines.
final class HideBySayingTests: XCTestCase {
    func testWholeLinesAndWords() {
        let pieces = HideBySaying.parse("3\n5: Ahmed Ali\n7: DE89 3704", lines: 10)
        XCTAssertEqual(pieces.map(\.line), [2, 4, 6])
        XCTAssertEqual(pieces.map(\.words), [nil, "Ahmed Ali", "DE89 3704"])
    }

    func testNumbersOnOneRow() {
        let pieces = HideBySaying.parse("1, 2, 5", lines: 10)
        XCTAssertEqual(pieces.map(\.line), [0, 1, 4])
        XCTAssertTrue(pieces.allSatisfy { $0.words == nil })
    }

    func testNoneAndNumbersOutOfRange() {
        XCTAssertTrue(HideBySaying.parse("none", lines: 10).isEmpty)
        XCTAssertTrue(HideBySaying.parse("0\n11\n99: Ahmed", lines: 10).isEmpty)
    }

    func testQuotesAroundWords() {
        let pieces = HideBySaying.parse("2: \"Ahmed Ali\"", lines: 3)
        XCTAssertEqual(pieces.first?.words, "Ahmed Ali")
    }

    func testEmptyWordsHideTheLine() {
        let pieces = HideBySaying.parse("2:", lines: 3)
        XCTAssertEqual(pieces.first?.line, 1)
        XCTAssertNil(pieces.first?.words)
    }

    func testMatchingIgnoresCaseAndAccents() {
        let lines = ["Rechnung 1024", "Kunde: AHMED Ali", "Café Müller", "Total 45 €"]
        let pieces = HideBySaying.matching("ahmed, cafe", lines)
        XCTAssertEqual(pieces.map(\.line), [1, 2])
        XCTAssertEqual(pieces.map(\.words), ["ahmed", "cafe"])
    }

    func testMatchingArabicComma() {
        let lines = ["الاسم: أحمد", "المبلغ 45", "الهاتف 0176"]
        let pieces = HideBySaying.matching("أحمد، 0176", lines)
        XCTAssertEqual(pieces.map(\.line), [0, 2])
    }

    func testMatchingNothingTyped() {
        XCTAssertTrue(HideBySaying.matching(" , ", ["Ahmed"]).isEmpty)
    }
}
