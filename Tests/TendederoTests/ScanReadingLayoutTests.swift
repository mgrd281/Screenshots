import XCTest
@testable import Tendedero

/// The reading order on the pages people really scan, made up and laid out as
/// they are printed: a letter to DIN 5008 with its information block beside
/// the address and three columns of small print at its foot, an invoice whose
/// table Vision reads whole lines of, a bank statement, a contract with
/// numbered clauses, a form with its labels over its fields, and an article in
/// two columns under a headline. Each is read the way a person reads it.
final class ScanReadingLayoutTests: XCTestCase {
    private static let width: CGFloat = 595, height: CGFloat = 842
    private static let aspect = width / height

    /// A stretch of words set from `x`, its top `top` points down the page,
    /// `size` points tall, every letter half as wide as the print is tall.
    private func stretch(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat = 11) -> ScanReading.Segment {
        var words: [ScanReading.Word] = []
        var cursor = x
        let advance = size * 0.5
        for word in text.split(separator: " ") {
            let wide = CGFloat(word.count) * advance
            words.append(ScanReading.Word(text: String(word), box: CGRect(x: cursor / Self.width, y: 1 - (top + size) / Self.height,
                                                                           width: wide / Self.width, height: size / Self.height)))
            cursor += wide + advance
        }
        return ScanReading.Segment(words: words)
    }

    private func lines(_ texts: [String], x: CGFloat, top: CGFloat, size: CGFloat = 11, pitch: CGFloat? = nil) -> [ScanReading.Segment] {
        texts.enumerated().map { stretch($0.element, x: x, top: top + CGFloat($0.offset) * (pitch ?? size * 1.2), size: size) }
    }

    /// A line as Vision gives a table's row: one stretch, its cells far apart,
    /// the words of a cell close.
    private func row(_ cells: [(text: String, x: CGFloat)], top: CGFloat, size: CGFloat = 11) -> ScanReading.Segment {
        ScanReading.Segment(words: cells.flatMap { stretch($0.text, x: $0.x, top: top, size: size).words })
    }

    private func read(_ segments: [ScanReading.Segment]) -> String {
        ScanReading.text(ScanReading.page(segments, aspect: Self.aspect))
    }

    private func order(_ text: String, _ parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: from..<text.endIndex) else {
                return XCTFail("\"\(part)\" not after what came before it, in:\n\(text)", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    // MARK: A letter to DIN 5008

    private var letter: [ScanReading.Segment] {
        var segments: [ScanReading.Segment] = []
        segments.append(stretch("Musterfirma GmbH · Beispielweg 5 · 10115 Berlin", x: 57, top: 100, size: 7))
        segments += lines(["Erika Mustermann", "Musterstraße 12", "20095 Hamburg"], x: 57, top: 124)
        segments += lines(["Ihr Zeichen: EM-2026", "Unser Zeichen: 4711", "Datum: 14.10.2026"], x: 400, top: 124)
        segments.append(stretch("Rechnung RE-2026-0417", x: 57, top: 230, size: 13))
        segments += lines(["Sehr geehrte Frau Mustermann,", "", "vielen Dank für Ihren Auftrag. Wir haben die vereinbarten Leistungen",
                           "erbracht und stellen sie Ihnen wie besprochen in Rechnung. Den", "Betrag überweisen Sie bitte bis zum 28.10.2026."],
                          x: 57, top: 270).filter { !$0.words.isEmpty }
        segments += lines(["Mit freundlichen Grüßen", "Max Muster"], x: 57, top: 400)
        // The foot: three columns of small print.
        segments += lines(["Musterfirma GmbH", "Beispielweg 5", "10115 Berlin"], x: 57, top: 760, size: 7)
        segments += lines(["Musterbank Hamburg", "IBAN DE12 3456 7890 1234 5678 90", "BIC MUSTDEHHXXX"], x: 230, top: 760, size: 7)
        segments += lines(["Geschäftsführer: Max Muster", "Amtsgericht Berlin HRB 123456", "USt-IdNr. DE123456789"], x: 400, top: 760, size: 7)
        return segments
    }

    func testALetterIsReadFromTheSenderLineToTheFoot() {
        let text = read(letter)
        order(text, ["Musterfirma GmbH · Beispielweg 5", "Erika Mustermann", "Musterstraße 12", "20095 Hamburg", "Ihr Zeichen", "Datum: 14.10.2026",
                     "Rechnung RE-2026-0417", "Sehr geehrte Frau Mustermann", "vielen Dank", "Mit freundlichen Grüßen", "Max Muster"])
        XCTAssertTrue(text.contains("Erika Mustermann\nMusterstraße 12\n20095 Hamburg"), "the address keeps its lines: \(text)")
        XCTAssertTrue(text.contains("Ihr Zeichen: EM-2026\nUnser Zeichen: 4711\nDatum: 14.10.2026"), "the information block keeps its lines: \(text)")
        XCTAssertTrue(text.contains("vielen Dank für Ihren Auftrag. Wir haben die vereinbarten Leistungen erbracht und stellen"), "the body runs on: \(text)")
    }

    func testTheFootsColumnsAreReadAColumnAtATimeNotAcrossEachOther() {
        let text = read(letter)
        order(text, ["Max Muster", "Musterfirma GmbH\nBeispielweg 5\n10115 Berlin", "Musterbank Hamburg\nIBAN DE12 3456 7890 1234 5678 90\nBIC MUSTDEHHXXX",
                     "Geschäftsführer: Max Muster\nAmtsgericht Berlin HRB 123456\nUSt-IdNr. DE123456789"])
    }

    // MARK: An invoice whose rows Vision reads whole

    func testAnInvoiceTableReadAsWholeLinesIsPartedIntoItsCells() {
        var segments = [stretch("Musterfirma GmbH", x: 57, top: 70, size: 18), stretch("Rechnung", x: 57, top: 150, size: 16)]
        segments.append(row([("Pos", 57), ("Beschreibung", 110), ("Menge", 340), ("Einzelpreis", 400), ("Betrag", 500)], top: 200))
        for (index, item) in [("1", "Beratung (Stunden)", "3", "85,00 €", "255,00 €"), ("2", "Druckpatronen Schwarz", "2", "24,90 €", "49,80 €"),
                              ("3", "Versandpauschale", "1", "5,90 €", "5,90 €")].enumerated() {
            segments.append(row([(item.0, 57), (item.1, 110), (item.2, 350), (item.3, 410), (item.4, 505)], top: 224 + CGFloat(index) * 22))
        }
        segments.append(row([("Netto", 400), ("310,70 €", 500)], top: 310))
        segments.append(row([("Gesamt", 400), ("369,73 €", 500)], top: 332))
        let page = ScanReading.page(segments, aspect: Self.aspect)
        let text = ScanReading.text(page)
        let tables = page.blocks.filter { if case .table = $0 { true } else { false } }
        XCTAssertEqual(tables.count, 2, "the items, and the totals under them: \(text)")
        XCTAssertTrue(text.contains("1\tBeratung (Stunden)\t3\t85,00 €\t255,00 €"), text)
        XCTAssertTrue(text.contains("3\tVersandpauschale\t1\t5,90 €\t5,90 €"), text)
        order(text, ["Rechnung", "Pos\tBeschreibung", "Beratung", "Druckpatronen", "Versandpauschale", "Netto", "Gesamt"])
    }

    // MARK: A bank statement

    func testABankStatementIsATableWithItsDatesAndAmounts() {
        var segments = [stretch("Kontoauszug 10/2026", x: 57, top: 70, size: 16)]
        segments.append(row([("Datum", 57), ("Buchungstext", 130), ("Betrag", 480)], top: 120, size: 9))
        let bookings = [("02.10.", "Gutschrift Musterfirma GmbH", "+1.250,00"), ("05.10.", "Lastschrift Stadtwerke Musterstadt", "-84,30"),
                        ("09.10.", "Kartenzahlung Supermarkt", "-23,15"), ("14.10.", "Dauerauftrag Miete", "-780,00")]
        for (index, booking) in bookings.enumerated() {
            segments.append(row([(booking.0, 57), (booking.1, 130), (booking.2, 480)], top: 140 + CGFloat(index) * 18, size: 9))
        }
        let text = read(segments)
        XCTAssertTrue(text.contains("02.10.\tGutschrift Musterfirma GmbH\t+1.250,00"), text)
        XCTAssertTrue(text.contains("14.10.\tDauerauftrag Miete\t-780,00"), text)
        order(text, ["Kontoauszug", "Datum\tBuchungstext\tBetrag", "02.10.", "05.10.", "09.10.", "14.10."])
    }

    // MARK: A contract with numbered clauses

    func testNumberedClausesStayWithTheirNumbers() {
        var segments = [stretch("Mietvertrag", x: 57, top: 70, size: 20), stretch("§ 1 Mietsache", x: 57, top: 130, size: 12)]
        segments += lines(["(1) Der Vermieter vermietet dem Mieter die Wohnung im", "zweiten Obergeschoss des Hauses Musterstraße 12 in",
                           "20095 Hamburg zum alleinigen Gebrauch."], x: 57, top: 152)
        segments += lines(["(2) Zur Wohnung gehören ein Kellerraum und ein Stellplatz", "im Hof, die dem Mieter mit überlassen werden."], x: 57, top: 200)
        segments.append(stretch("§ 2 Mietzeit", x: 57, top: 250, size: 12))
        segments += lines(["(1) Das Mietverhältnis beginnt am 01.11.2026 und läuft auf", "unbestimmte Zeit."], x: 57, top: 272)
        let text = read(segments)
        order(text, ["Mietvertrag", "§ 1 Mietsache", "(1) Der Vermieter", "(2) Zur Wohnung", "§ 2 Mietzeit", "(1) Das Mietverhältnis"])
        XCTAssertTrue(text.contains("im zweiten Obergeschoss des Hauses"), "a clause runs on: \(text)")
    }

    // MARK: A form

    func testAFormsLabelsStayOverTheirFields() {
        var segments = [stretch("Antrag auf Erstattung", x: 57, top: 70, size: 18)]
        segments.append(row([("Vorname", 57), ("Nachname", 300)], top: 140, size: 8))
        segments.append(row([("Erika", 57), ("Mustermann", 300)], top: 154, size: 12))
        segments.append(row([("Straße", 57), ("Ort", 300)], top: 190, size: 8))
        segments.append(row([("Musterstraße 12", 57), ("20095 Hamburg", 300)], top: 204, size: 12))
        let text = read(segments)
        // The grid as it stands: a row of labels, a row of values under it.
        order(text, ["Antrag auf Erstattung", "Vorname\tNachname\nErika\tMustermann", "Straße\tOrt\nMusterstraße 12\t20095 Hamburg"])
    }

    // MARK: An article in two columns

    func testAnArticleUnderAHeadlineIsReadHeadlineThenEachColumn() {
        let one = ["Die Stadt hat in diesem Jahr mehr", "Besucher als je zuvor gezählt. Vor allem", "im Sommer kamen viele Gäste aus dem",
                   "Ausland, die sich für die alten Gassen", "und die Museen begeistern. Auch die", "Hotels melden bis in den Herbst hinein", "eine hohe Auslastung."]
        let two = ["Die Verwaltung plant deshalb neue", "Radwege und mehr Platz für Fußgänger", "in der Altstadt. Anwohner begrüßen das,",
                   "fordern aber auch ruhigere Nächte in", "den belebten Straßen. Ein runder Tisch", "soll im Winter Lösungen erarbeiten.", "Besucher und Bewohner sollen gewinnen."]
        let text = read([stretch("Rekord bei den Besucherzahlen", x: 57, top: 70, size: 24)]
                        + lines(one, x: 57, top: 140, pitch: 14) + lines(two, x: 330, top: 140, pitch: 14))
        order(text, ["Rekord bei den Besucherzahlen", "Die Stadt hat", "Hotels melden bis in den Herbst hinein", "Die Verwaltung plant", "Bewohner sollen gewinnen"])
        XCTAssertTrue(text.contains("Vor allem im Sommer kamen viele Gäste"), "a column runs on: \(text)")
    }

    // MARK: Lines that must not be split

    func testJustifiedSpacesAndWideHeadlinesAreNotParted() {
        // A justified line's spaces are wider than a normal space, not a column's gap.
        var words: [ScanReading.Word] = []
        var cursor: CGFloat = 57
        for text in ["Dieser", "Satz", "ist", "im", "Blocksatz", "gesetzt", "und", "hat", "weite", "Wortabstände."] {
            let wide = CGFloat(text.count) * 5.5
            words.append(ScanReading.Word(text: text, box: CGRect(x: cursor / Self.width, y: 1 - 120 / Self.height,
                                                                  width: wide / Self.width, height: 11 / Self.height)))
            cursor += wide + 9
        }
        let page = ScanReading.page([ScanReading.Segment(words: words)] + lines(["Eine zweite Zeile steht darunter im Text."], x: 57, top: 134),
                                    aspect: Self.aspect)
        XCTAssertEqual(page.blocks.count, 1)
        XCTAssertTrue(ScanReading.text(page).hasPrefix("Dieser Satz ist im Blocksatz gesetzt und hat weite Wortabstände."))
    }
}
