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

    /// A number a signature crosses, read before and not after, is the
    /// reading's way with the signature, not text the cleaning lost.
    func testALineASignatureCrossesIsNotCounted() {
        var page = ScanBitmap(width: 400, height: 100, red: 255, green: 255, blue: 255)
        func paint(_ xs: Range<Int>, _ ys: Range<Int>, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            for y in ys { for x in xs { let i = (y * 400 + x) * 4; page.pixels[i] = r; page.pixels[i + 1] = g; page.pixels[i + 2] = b } }
        }
        // Grey print along the line, a blue stroke over its right half.
        for x in stride(from: 20, to: 380, by: 12) { paint(x..<(x + 3), 40..<60, 60, 60, 60) }
        for x in 200..<380 { paint(x..<(x + 1), (45 + (x / 7) % 10)..<(48 + (x / 7) % 10), 40, 60, 170) }
        let box = CGRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        XCTAssertTrue(ScanContent.crossed(page, box), "the signature crosses the line")
        let before = [ScanContent.Line(text: "Fax 040-12", box: box)]
        XCTAssertTrue(ScanContent.lost(before: before, after: [], crossed: { ScanContent.crossed(page, $0) }).isEmpty)
        XCTAssertFalse(ScanContent.lost(before: before, after: []).isEmpty, "uncrossed, it would count")
        // Print in colour alone is not crossed.
        var blue = ScanBitmap(width: 400, height: 100, red: 255, green: 255, blue: 255)
        for x in stride(from: 20, to: 380, by: 12) {
            for y in 40..<60 { for xx in x..<(x + 3) { let i = (y * 400 + xx) * 4; blue.pixels[i] = 30; blue.pixels[i + 1] = 60; blue.pixels[i + 2] = 170 } }
        }
        XCTAssertFalse(ScanContent.crossed(blue, box), "a line printed in blue is read as it is")
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

    // MARK: The guard: what a line says, each character

    private func read(_ text: String, row: Int, x: CGFloat = 0.1, width: CGFloat = 0.6,
                      sure: Float = 0.95) -> ScanContent.Read {
        let box = line(text, row: row, x: x, width: width).box
        return ScanContent.Read(text: text, box: box, confidence: sure)
    }

    /// An umlaut's dots, an accent, an @ or a digit read before cleaning and
    /// not after changes the line; spaces, and more read beside it, do not.
    func testALineWhoseDotsAreLostChanged() {
        let before = [read("Ärzte für Radiologie", row: 0), read("Dr. med. René Brückner", row: 1),
                      read("praxis@radiologie-musterwall.de", row: 2), read("Telefon 040 1234567-0", row: 3),
                      read("Größer, Weiß", row: 4)]
        let same = [line("Ärzte für  Radiologie", row: 0), line("Dr.med. René Brückner", row: 1),
                    line("praxis@radiologie-musterwall.de", row: 2), line("Telefon 040 1234567-0 Telefax", row: 3),
                    line("Größer,", row: 4, width: 0.2), line("Weiß", row: 4, x: 0.35, width: 0.2)]
        XCTAssertEqual(ScanContent.changed(before: before, after: same), [], "the same, spaced or split otherwise")
        let changed = [line("Arzte fur Radiologie", row: 0), line("Dr. med. Rene Bruckner", row: 1),
                       line("praxisradiologie-musterwall.de", row: 2), line("Telefon 040 123456-0", row: 3),
                       line("Grosser, Weiss", row: 4)]
        XCTAssertEqual(ScanContent.changed(before: before, after: changed).count, 5, "each line changed")
    }

    /// A mark read after cleaning that the reading before missed, an
    /// umlaut's dots the photo left too faint, is the print made clearer,
    /// not changed; a mark read before and lost after is a change, and so is
    /// another letter under the same mark. A dash or a centred dot is read
    /// as either of its kinds.
    func testAMarkTheReadingBeforeMissedIsNoChange() {
        let before = [read("Arzte fur Radiologie", row: 0), read("Dr. med. Rene Bruckner", row: 1),
                      read("Öffnungszeiten Mo-Fr 8-18 Uhr", row: 2), read("Musterwall 7a • 20354 Hamburg", row: 3)]
        let after = [line("Ärzte für Radiologie", row: 0), line("Dr. med. René Brückner", row: 1),
                     line("Öffnungszeiten Mo–Fr 8–18 Uhr", row: 2), line("Musterwall 7a · 20354 Hamburg", row: 3)]
        XCTAssertEqual(ScanContent.changed(before: before, after: after), [], "clearer, not changed")
        XCTAssertEqual(ScanContent.changed(before: [read("Ärzte für Radiologie", row: 0)],
                                           after: [line("Arzte für Radiologie", row: 0)]).count, 1, "a mark lost")
        XCTAssertEqual(ScanContent.changed(before: [read("Arzte fur Radiologie", row: 0)],
                                           after: [line("Örzte für Radiologie", row: 0)]).count, 1, "another letter")
        XCTAssertTrue(ScanContent.says("Größer,MBA", "Größer, MBA"))
        XCTAssertFalse(ScanContent.says("Grosser, MBA", "Größer, MBA"))
    }

    /// A line read unsurely before says nothing sure of the page, and a line
    /// of a letter or two is too short to tell; another column's line on the
    /// same row is no part of it.
    func testOnlySureLinesCount() {
        let before = [read("Ärzte für Radiologie", row: 0, sure: 0.6), read("Ä", row: 1)]
        let after = [line("Arzte fur Radiologie", row: 0), line("A", row: 1)]
        XCTAssertEqual(ScanContent.changed(before: before, after: after), [])
        let beside = [read("Musterbank Hamburg", row: 0, x: 0.7, width: 0.25)]
        let otherColumn = [line("Musterbank Hamburg", row: 0, x: 0.7, width: 0.25), line("Befund vom 05.06.2026", row: 0)]
        XCTAssertEqual(ScanContent.changed(before: beside, after: otherColumn), [])
        XCTAssertEqual(ScanContent.changed(before: beside, after: [line("Befund vom 05.06.2026", row: 0)]).count, 1,
                       "read nowhere on its row is changed")
    }
}
