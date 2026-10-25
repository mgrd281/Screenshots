import XCTest
@testable import Tendedero

/// A page's words put in reading order (`ScanReading`), on made-up A4 pages
/// drawn as Vision measures them: each stretch of a line its words' boxes,
/// every letter half as wide as the print is tall. A column is read to its
/// end before the next, a table row by row, prose runs on with its broken
/// words made whole, an address keeps its lines, a cover is a mark where it
/// lies and nothing it hides is ever written, and an Arabic page is read
/// from the right.
final class ScanReadingTests: XCTestCase {
    private static let width: CGFloat = 595, height: CGFloat = 842
    private static let aspect = width / height

    /// A stretch of words set from `x`, its top `top` points down the page,
    /// `size` points tall.
    private func stretch(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat = 11) -> ScanReading.Segment {
        var words: [ScanReading.Word] = []
        var cursor = x
        let advance = size * 0.5
        for word in text.split(separator: " ") {
            let wide = CGFloat(word.count) * advance
            let box = CGRect(x: cursor / Self.width, y: 1 - (top + size) / Self.height,
                             width: wide / Self.width, height: size / Self.height)
            words.append(ScanReading.Word(text: String(word), box: box))
            cursor += wide + advance
        }
        return ScanReading.Segment(words: words)
    }

    /// Lines set one under another, `pitch` points apart.
    private func lines(_ texts: [String], x: CGFloat, top: CGFloat, size: CGFloat = 11, pitch: CGFloat = 13.2) -> [ScanReading.Segment] {
        texts.enumerated().map { stretch($0.element, x: x, top: top + CGFloat($0.offset) * pitch, size: size) }
    }

    private func read(_ segments: [ScanReading.Segment]) -> ScanReading.Page {
        ScanReading.page(segments, aspect: Self.aspect)
    }

    // MARK: Columns and tables

    private let columnA = ["Erste Spalte, erste Zeile mit Worten aus", "der Mitte eines langen Satzes, der weiter",
                           "und weiter läuft, bis die Spalte endet und", "der Leser oben in der nächsten Spalte", "seine Zeilen weiterliest."]
    private let columnB = ["Zweite Spalte, erste Zeile mit Worten aus", "einem anderen Satz, der hier beginnt und",
                           "ebenso lange weiterläuft wie der erste in", "der linken Spalte, Zeile für Zeile, bis", "auch er zu Ende ist."]

    func testTwoColumnsOfProseAreReadAColumnAtATime() {
        // The columns' lines stand exactly side by side, as a table's would.
        let page = read(lines(columnA, x: 50, top: 100) + lines(columnB, x: 320, top: 100))
        let text = ScanReading.text(page)
        XCTAssertEqual(page.blocks.count, 2, text)
        XCTAssertTrue(text.hasPrefix("Erste Spalte, erste Zeile"), text)
        let first = try? XCTUnwrap(text.range(of: "seine Zeilen weiterliest."))
        let second = try? XCTUnwrap(text.range(of: "Zweite Spalte"))
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        if let first, let second { XCTAssertLessThan(first.lowerBound, second.lowerBound, "the left column to its end first") }
        XCTAssertTrue(text.contains("aus der Mitte eines langen Satzes"), "prose runs on: \(text)")
    }

    func testALetterheadsSideColumnComesAfterTheBody() {
        let body = ["Sehr geehrte Frau Hoffmann, vielen Dank für Ihren Besuch in", "unserer Praxis. Anbei erhalten Sie die Unterlagen, die wir",
                    "besprochen haben, und die Rechnung für die Behandlung vom", "14. Oktober. Bei Fragen erreichen Sie uns jederzeit.",
                    "Mit freundlichen Grüßen"]
        let side = ["Praxis Dr. Muster", "Musterwall 7a", "20354 Hamburg", "Telefon 040 123456", "praxis@example.com", "Sprechzeiten Mo–Fr"]
        let page = read(lines(body, x: 50, top: 200) + lines(side, x: 440, top: 190, size: 8, pitch: 10))
        let text = ScanReading.text(page)
        XCTAssertTrue(text.hasPrefix("Sehr geehrte Frau Hoffmann"), text)
        XCTAssertTrue(text.contains("in unserer Praxis"), "the body runs on: \(text)")
        XCTAssertTrue(text.hasSuffix("Praxis Dr. Muster\nMusterwall 7a\n20354 Hamburg\nTelefon 040 123456\npraxis@example.com\nSprechzeiten Mo–Fr"),
                      "the side column after, each line its own: \(text)")
    }

    func testAnInvoicesItemsAreReadRowByRow() {
        var segments = [stretch("Musterfirma GmbH", x: 50, top: 60, size: 18), stretch("Rechnung 2026-1042", x: 50, top: 110, size: 14)]
        segments += lines(["Lena Hoffmann", "Lindenstraße 12", "10969 Berlin"], x: 50, top: 160)
        segments.append(stretch("14. Oktober 2026", x: 440, top: 160))
        for (index, row) in [("Schreibtischlampe", "1 ×", "49,00 €"), ("Kabelset", "2 ×", "25,00 €"), ("Versand", "1 ×", "0,00 €")].enumerated() {
            let top = 260 + CGFloat(index) * 16 + (index == 1 ? 0.8 : 0)
            segments += [stretch(row.0, x: 50, top: top), stretch(row.1, x: 340, top: top), stretch(row.2, x: 470, top: top)]
        }
        segments += [stretch("Gesamt", x: 340, top: 330), stretch("74,00 €", x: 470, top: 330)]
        let page = read(segments)
        let text = ScanReading.text(page)
        XCTAssertTrue(text.hasPrefix("Musterfirma GmbH\n\nRechnung 2026-1042\n\nLena Hoffmann\nLindenstraße 12\n10969 Berlin\n\n14. Oktober 2026"), text)
        XCTAssertTrue(text.contains("Schreibtischlampe\t1 ×\t49,00 €\nKabelset\t2 ×\t25,00 €\nVersand\t1 ×\t0,00 €"), "row by row: \(text)")
        XCTAssertTrue(text.hasSuffix("Gesamt 74,00 €"), "one line across columns reads as one line: \(text)")
        let tables = page.blocks.filter { if case .table = $0 { return true } else { return false } }
        XCTAssertEqual(tables.count, 1)
        guard case .paragraph(let heading) = page.blocks.first else { return XCTFail("a heading first") }
        XCTAssertTrue(heading.heading, "set larger than the page's print")
    }

    func testAFormsLabelsAndValuesAreATable() {
        let labels = ["Name", "Geburtsdatum", "Versichertennummer", "Arbeitgeber"]
        let values = ["Lena Hoffmann", "01.02.1980", "A123456789", "Musterfirma GmbH"]
        let page = read(lines(labels, x: 50, top: 300, pitch: 18) + lines(values, x: 260, top: 300, pitch: 18))
        XCTAssertEqual(ScanReading.text(page),
                       "Name\tLena Hoffmann\nGeburtsdatum\t01.02.1980\nVersichertennummer\tA123456789\nArbeitgeber\tMusterfirma GmbH")
    }

    func testALettersInformationBlockStandsBesideItsAddressNotWithIt() {
        // As DIN 5008 sets them: the address and the information block on one grid.
        let address = ["Lena Hoffmann", "Lindenstraße 12", "10969 Berlin", "Deutschland"]
        let block = ["Ihr Zeichen: LH-12", "Unser Zeichen: AB/77", "Telefon: 040 123456", "Datum: 14.10.2026"]
        let page = read(lines(address, x: 70, top: 150, pitch: 12.7) + lines(block, x: 360, top: 150, pitch: 12.7))
        XCTAssertEqual(ScanReading.text(page), "Lena Hoffmann\nLindenstraße 12\n10969 Berlin\nDeutschland\n\n"
                       + "Ihr Zeichen: LH-12\nUnser Zeichen: AB/77\nTelefon: 040 123456\nDatum: 14.10.2026")
    }

    func testAReceiptsItemsAndPricesStayTogether() {
        let names = ["Brot", "Milch 1,5 %", "Äpfel 1 kg", "Kaffee"]
        let prices = ["2,49", "1,19", "2,99", "6,49"]
        let page = read(lines(names, x: 40, top: 200) + lines(prices, x: 220, top: 200.6))
        XCTAssertEqual(ScanReading.text(page), "Brot\t2,49\nMilch 1,5 %\t1,19\nÄpfel 1 kg\t2,99\nKaffee\t6,49")
    }

    // MARK: Paragraphs

    func testProseRunsOnAndItsBrokenWordsAreMadeWhole() {
        let prose = ["Jedes Bildschirmfoto hängt an einer Leine oben am Bildschirm-",
                     "rand. Schreib uns eine E-Mail oder eine kurze Nachricht an unsere",
                     "Adresse, und für Fragen zu Haus- und Gartenbedarf ruf uns an.",
                     "Die Leine verschwindet wieder, sobald alles gesendet ist."]
        let text = ScanReading.text(read(lines(prose, x: 50, top: 100)))
        XCTAssertTrue(text.contains("Bildschirmrand."), text)
        XCTAssertTrue(text.contains("unsere Adresse"), text)
        XCTAssertFalse(text.contains("\n"), "one paragraph: \(text)")
    }

    func testBrokenWordsAreJoinedAsWrittenOnThePage() {
        XCTAssertEqual(ScanReading.runOn(["Bildschirm-", "foto"]), "Bildschirmfoto")
        XCTAssertEqual(ScanReading.runOn(["Ab-", "teilung"]), "Abteilung")
        XCTAssertEqual(ScanReading.runOn(["Schreib uns eine E-", "Mail"]), "Schreib uns eine E-Mail")
        XCTAssertEqual(ScanReading.runOn(["eine E-", "mail"]), "eine E-mail")
        XCTAssertEqual(ScanReading.runOn(["Haus-", "und Gartenbedarf"]), "Haus- und Gartenbedarf")
        XCTAssertEqual(ScanReading.runOn(["Schreibtisch-", "Lampe"]), "Schreibtisch-Lampe")
        XCTAssertEqual(ScanReading.runOn(["Berlin -", "Hamburg"]), "Berlin - Hamburg")
        XCTAssertEqual(ScanReading.runOn(["Bildschirm\u{00AD}", "foto"]), "Bildschirmfoto", "a soft hyphen")
        XCTAssertEqual(ScanReading.runOn(["Seite 1–", "3"]), "Seite 1– 3", "a digit follows: nothing joined")
    }

    func testAnAddressKeepsItsLines() {
        let page = read(lines(["Lena Hoffmann", "Lindenstraße 12", "10969 Berlin"], x: 50, top: 150))
        XCTAssertEqual(ScanReading.text(page), "Lena Hoffmann\nLindenstraße 12\n10969 Berlin")
    }

    func testParagraphsArePartedWhereSpaceRunsAcrossNotBetweenTheirLines() {
        let one = ["Der erste Absatz hat zwei Zeilen, und beide sind lang genug, um", "zusammen zu laufen, wie Prosa es tut."]
        let two = ["Der zweite Absatz beginnt nach einer Leerzeile und läuft", "ebenso weiter bis zu seinem Ende."]
        // Set at one and a half spacing: the space between lines is wide, the one between paragraphs wider.
        let page = read(lines(one, x: 50, top: 100, pitch: 20) + lines(two, x: 50, top: 100 + 20 * 2 + 14, pitch: 20))
        XCTAssertEqual(ScanReading.text(page),
                       "Der erste Absatz hat zwei Zeilen, und beide sind lang genug, um zusammen zu laufen, wie Prosa es tut.\n\n"
                       + "Der zweite Absatz beginnt nach einer Leerzeile und läuft ebenso weiter bis zu seinem Ende.")
    }

    func testAShortLineEndingASentenceEndsItsParagraph() {
        let prose = ["Der erste Absatz läuft über eine lange Zeile weiter bis hier", "und endet kurz.",
                     "Der zweite beginnt gleich darunter, ohne eine leere Zeile, und", "läuft ebenso weiter."]
        let text = ScanReading.text(read(lines(prose, x: 50, top: 100)))
        XCTAssertEqual(text, "Der erste Absatz läuft über eine lange Zeile weiter bis hier und endet kurz.\n\n"
                       + "Der zweite beginnt gleich darunter, ohne eine leere Zeile, und läuft ebenso weiter.")
    }

    // MARK: Covers

    func testACoverIsAMarkWhereItLiesAndWhatItHidesIsNeverWritten() {
        let line = stretch("Patient: Lena Hoffmann geb. 01.02.1980 in Berlin", x: 50, top: 200)
        let name = line.words[1].box.union(line.words[2].box), born = line.words[4].box
        let segments = ScanReading.segments(line.words, hiding: [name, born]) + ScanReading.marks([name, born])
        let page = read(segments)
        XCTAssertEqual(ScanReading.text(page), "Patient: ███ geb. ███ in Berlin")
        XCTAssertEqual(ScanReading.text(page, mark: "[verdeckt]"), "Patient: [verdeckt] geb. [verdeckt] in Berlin")
        let words = ScanReading.words(page).map(\.text)
        XCTAssertEqual(words, ["Patient: ", "geb. ", "in ", "Berlin"], "the PDF's words leave covers out")
        XCTAssertFalse(ScanReading.text(page).contains("Lena"))
    }

    func testCoveredWordsSideBySideAreOneMark() {
        let words = stretch("IBAN DE89 3704 0044 0532", x: 50, top: 300).words
        var line = Array(words.prefix(1))
        line += words.dropFirst().map { ScanReading.Word.covered($0.box) }
        XCTAssertEqual(ScanReading.line(of: line), "IBAN ███")
    }

    func testATallCoverHidesAPictureAndIsLeftOutOfTheText() {
        let text = lines(["Ausweis der Musterstadt", "Gültig bis 2030"], x: 50, top: 100)
        let face = CGRect(x: 400 / Self.width, y: 1 - 220 / Self.height, width: 120 / Self.width, height: 140 / Self.height)
        let page = read(text + ScanReading.marks([face]))
        XCTAssertEqual(ScanReading.text(page), "Ausweis der Musterstadt\nGültig bis 2030")
    }

    // MARK: Right to left

    func testAnArabicPageIsReadFromTheRight() {
        // On one line, the stretch on the right first.
        let line = [stretch("مرحبا بكم", x: 400, top: 100), stretch("فاتورة رقم ١٠٤٢", x: 60, top: 100)]
        let page = read(line)
        XCTAssertTrue(page.rightToLeft)
        XCTAssertEqual(ScanReading.text(page), "مرحبا بكم فاتورة رقم ١٠٤٢")
        // Two columns of prose: the right one first.
        let right = lines(Array(repeating: "هذا سطر طويل من النص العربي في العمود الأيمن", count: 5), x: 320, top: 300)
        let left = lines(Array(repeating: "وهذا سطر آخر طويل من النص في العمود الأيسر هنا", count: 5), x: 50, top: 300)
        let columns = ScanReading.text(read(left + right))
        XCTAssertTrue(columns.hasPrefix("هذا سطر طويل"), columns)
    }

    func testTheDirectionIsTheMostLettersOnes() {
        XCTAssertTrue(ScanReading.rightToLeft("فاتورة رقم Snapfly"))
        XCTAssertFalse(ScanReading.rightToLeft("Rechnung فاتورة 2026"))
        XCTAssertFalse(ScanReading.rightToLeft("12345"))
    }

    // MARK: Pages

    func testAnEmptyPageReadsAsNothing() {
        XCTAssertEqual(read([]).blocks, [])
        XCTAssertEqual(ScanReading.text([read([]), read(lines(["Seite zwei"], x: 50, top: 100))]), "Seite zwei")
    }

    func testThePDFsWordsFollowTheReadingOrder() {
        let page = read(lines(["Zweite Zeile"], x: 50, top: 120) + lines(["Erste Zeile"], x: 50, top: 100))
        XCTAssertEqual(ScanReading.words(page).map(\.text), ["Erste ", "Zeile", "Zweite ", "Zeile"])
    }
}
