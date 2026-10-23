import XCTest
@testable import Tendedero

/// Whether cleaning kept the text: every number read before is read after,
/// in the same place, however the reading splits or spaces it; a number gone
/// or changed marks its line, and so do lines gone when enough of them are.
final class ScanContentTests: XCTestCase {
    private func line(_ text: String, row: Int, x: CGFloat = 0.1, width: CGFloat = 0.6) -> ScanContent.Line {
        let down: CGFloat = CGFloat(row) * 0.04
        let y: CGFloat = 0.9 - down
        return ScanContent.Line(text: text, box: CGRect(x: x, y: y, width: width, height: 0.025))
    }

    private var invoice: [ScanContent.Line] {
        [line("Rechnungsnr. RE-2026-0417", row: 0), line("Datum 14.10.2026", row: 1),
         line("Beratung (Stunden) 3 85,00 € 255,00 €", row: 3), line("Druckpatronen Schwarz 2 24,90 € 49,80 €", row: 4),
         line("Gesamt 369,73 €", row: 6), line("IBAN: DE89 3704 0044 0532 0130 00", row: 8),
         line("Bitte überweisen Sie den Betrag", row: 9)]
    }

    func testTheSameReadingLosesNothing() {
        XCTAssertEqual(ScanContent.lost(before: invoice, after: invoice), [])
    }

    func testANumberReadOtherwiseSpacedOrSplitIsStillThere() {
        var after = invoice
        // Read with other spaces, and the amounts as lines of their own.
        after[5] = line("IBAN: DE89370400440532013000", row: 8)
        after[2] = line("Beratung (Stunden) 3", row: 3, width: 0.3)
        after.append(line("85,00 €", row: 3, x: 0.45, width: 0.1))
        after.append(line("255,00 €", row: 3, x: 0.6, width: 0.1))
        XCTAssertEqual(ScanContent.lost(before: invoice, after: after), [])
    }

    /// A typewriter's Z read as 2, or its O as 0, one reading to the next, is
    /// the same number; a letter away from digits stays a letter.
    func testALetterReadForADigitBesideDigitsIsTheSameNumber() {
        let before = [line("200.0 G", row: 0), line("Fax 040-1234567", row: 1)]
        let after = [line("Z00.0 G", row: 0), line("Fax O40-1234567", row: 1)]
        XCTAssertEqual(ScanContent.lost(before: before, after: after), [])
        XCTAssertEqual(ScanContent.readAsDigits("Z00.0 Gesamt O4O"), "200.0 Gesamt 040")
        XCTAssertTrue(ScanContent.lost(before: [line("Muster 16", row: 0)], after: [line("Muster 1b", row: 0)]).isEmpty,
                      "a 6 read as b beside a digit")
        XCTAssertEqual(ScanContent.readAsDigits("Schwarz 2 Seite"), "Schwarz 2 Seite")
        XCTAssertFalse(ScanContent.lost(before: [line("Z00.0 G", row: 0)], after: [line("Z0.0 G", row: 0)]).isEmpty,
                       "a digit gone is still gone")
    }

    func testANumberGoneOrChangedMarksItsLine() {
        var after = invoice
        // 49,80 read as 49,30, and the total not read at all.
        after[3] = line("Druckpatronen Schwarz 2 24,90 € 49,30 €", row: 4)
        after[4] = line("Gesamt", row: 6)
        let lost = ScanContent.lost(before: invoice, after: after)
        XCTAssertEqual(lost.count, 2)
        XCTAssertTrue(lost.contains { $0.intersects(invoice[3].box) }, "the changed amount")
        XCTAssertTrue(lost.contains { $0.intersects(invoice[4].box) }, "the total gone")
    }

    func testLinesGoneCountOnlyWhenEnoughAreGone() {
        var after = invoice
        after.removeLast()
        XCTAssertEqual(ScanContent.lost(before: invoice, after: after), [], "one line read less is a reading's way")
        let long = (0..<20).map { line("Zeile mit Worten \($0 % 2 == 0 ? "und" : "oder") mehr", row: $0) }
        let fewer = Array(long.prefix(15))
        let lost = ScanContent.lost(before: long, after: fewer)
        XCTAssertFalse(lost.isEmpty)
        XCTAssertTrue(lost.allSatisfy { $0.maxY <= long[15].box.maxY + 0.001 }, "only where lines are gone")
    }

    func testNumbersAreDigitsWithTheirSeparators() {
        XCTAssertEqual(ScanContent.numbers(in: "Datum: 14.10.2026"), ["14102026"])
        XCTAssertEqual(ScanContent.numbers(in: "1.234,56 € und 7"), ["123456"])
        XCTAssertEqual(ScanContent.numbers(in: "Tel. 030 1234567"), ["0301234567"])
        XCTAssertEqual(ScanContent.numbers(in: "RE-2026-0417"), ["20260417"])
        XCTAssertEqual(ScanContent.numbers(in: "Seite 1 von 2"), [])
        XCTAssertEqual(ScanContent.numbers(in: "10 ..20"), ["10", "20"])
    }

    func testPlacesThatTouchAreOne() {
        let merged = ScanContent.merged([CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.03),
                                         CGRect(x: 0.1, y: 0.47, width: 0.3, height: 0.031),
                                         CGRect(x: 0.6, y: 0.1, width: 0.1, height: 0.03)])
        XCTAssertEqual(merged.count, 2)
    }
}
