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

    /// Whether the boxes hug the letters, as Vision's do: a word with no tall
    /// letter starts lower, one with no tail ends higher. Every page is read
    /// both ways.
    private var hugging = false

    private func both(_ body: () -> Void) {
        for mode in [false, true] {
            hugging = mode
            body()
        }
        hugging = false
    }

    /// A stretch of words set from `x`, its top `top` points down the page,
    /// `size` points tall, every letter half as wide as the print is tall.
    private func stretch(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat = 11, space: CGFloat? = nil) -> ScanReading.Segment {
        var words: [ScanReading.Word] = []
        var cursor = x
        let advance = size * 0.5
        for word in text.split(separator: " ") {
            let wide = CGFloat(word.count) * advance
            var from = top, to = top + size
            if hugging {
                // The line's ascent is 0.78 of the size above the baseline, its tail 0.22 below.
                let tall = word.contains { $0.isUppercase || $0.isNumber || "bdfhklt".contains($0) || "äöüÄÖÜ".contains($0) }
                let tail = word.contains { "gjpqy,;".contains($0) }
                from = top + (tall ? 0.05 : 0.30) * size
                to = top + (tail ? 1.0 : 0.80) * size
            }
            words.append(ScanReading.Word(text: String(word), box: CGRect(x: cursor / Self.width, y: 1 - to / Self.height,
                                                                           width: wide / Self.width, height: (to - from) / Self.height)))
            cursor += wide + (space ?? advance)
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
                return XCTFail("\"\(part)\" not after what came before it (hugging boxes: \(hugging)), in:\n\(text)", file: file, line: line)
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
        both {
            let text = read(letter)
            order(text, ["Musterfirma GmbH · Beispielweg 5", "Erika Mustermann", "Musterstraße 12", "20095 Hamburg", "Ihr Zeichen", "Datum: 14.10.2026",
                         "Rechnung RE-2026-0417", "Sehr geehrte Frau Mustermann", "vielen Dank", "Mit freundlichen Grüßen", "Max Muster"])
            XCTAssertTrue(text.contains("Erika Mustermann\nMusterstraße 12\n20095 Hamburg"), "the address keeps its lines: \(text)")
            XCTAssertTrue(text.contains("Ihr Zeichen: EM-2026\nUnser Zeichen: 4711\nDatum: 14.10.2026"), "the information block keeps its lines: \(text)")
            XCTAssertTrue(text.contains("vielen Dank für Ihren Auftrag. Wir haben die vereinbarten Leistungen erbracht und stellen"), "the body runs on: \(text)")
        }
    }

    func testTheFootsColumnsAreReadAColumnAtATimeNotAcrossEachOther() {
        both {
            let text = read(letter)
            order(text, ["Max Muster", "Musterfirma GmbH\nBeispielweg 5\n10115 Berlin", "Musterbank Hamburg\nIBAN DE12 3456 7890 1234 5678 90\nBIC MUSTDEHHXXX",
                         "Geschäftsführer: Max Muster\nAmtsgericht Berlin HRB 123456\nUSt-IdNr. DE123456789"])
        }
    }

    // MARK: An invoice whose rows Vision reads whole

    func testAnInvoiceTableReadAsWholeLinesIsPartedIntoItsCells() {
        both {
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
    }

    // MARK: Descriptions that wrap

    func testADescriptionThatWrapsStaysInItsRowAndATitleDoesNot() {
        both {
            var segments = [stretch("Rechnung", x: 57, top: 150, size: 16)]
            segments.append(row([("Pos", 57), ("Beschreibung", 110), ("Menge", 340), ("Betrag", 500)], top: 200))
            segments.append(stretch("Hardware", x: 110, top: 226))
            segments.append(row([("1", 57), ("Beratung und Einrichtung des Systems", 110), ("3", 350), ("255,00 €", 505)], top: 250))
            segments.append(stretch("inklusive Schulung", x: 110, top: 262))
            segments.append(row([("2", 57), ("Druckpatronen Schwarz", 110), ("2", 350), ("49,80 €", 505)], top: 288))
            segments.append(row([("3", 57), ("Versandpauschale Express", 110), ("1", 350), ("5,90 €", 505)], top: 324))
            segments.append(stretch("Original Paket", x: 110, top: 336))
            segments.append(row([("4", 57), ("Lizenz", 110), ("1", 350), ("90,00 €", 505)], top: 372))
            let page = ScanReading.page(segments, aspect: Self.aspect)
            let text = ScanReading.text(page)
            XCTAssertTrue(text.contains("1\tBeratung und Einrichtung des Systems inklusive Schulung\t3\t255,00 €"), "hugging boxes: \(hugging): \(text)")
            XCTAssertTrue(text.contains("3\tVersandpauschale Express Original Paket\t1\t5,90 €"), "a wrapped line near its row, in capitals too: \(text)")
            XCTAssertTrue(text.contains("2\tDruckpatronen Schwarz\t2\t49,80 €"), text)
            XCTAssertTrue(text.contains("4\tLizenz\t1\t90,00 €"), text)
            XCTAssertFalse(text.contains("Systems inklusive Schulung 2"), "no row runs into the next: \(text)")
        }
    }

    // MARK: Rows set with room between them

    func testRowsSetFarApartAreStillATable() {
        both {
            // 3 usual lines from one row to the next, as invoices set with rules between rows are.
            var segments = [stretch("Rechnung", x: 57, top: 150, size: 16)]
            segments.append(row([("Pos", 57), ("Beschreibung", 110), ("Menge", 340), ("Betrag", 500)], top: 200))
            for (index, item) in [("Beratung", "3", "255,00 €"), ("Druckpatronen", "2", "49,80 €"), ("Versand", "1", "5,90 €"), ("Lizenz", "1", "90,00 €")].enumerated() {
                segments.append(row([("\(index + 1)", 57), (item.0, 110), (item.1, 350), (item.2, 505)], top: 236 + CGFloat(index) * 34))
            }
            segments += lines(["Bitte überweisen Sie den Betrag innerhalb von vierzehn Tagen", "auf das unten genannte Konto, damit nichts verloren geht."], x: 57, top: 420)
            let page = ScanReading.page(segments, aspect: Self.aspect)
            let text = ScanReading.text(page)
            let tables = page.blocks.filter { if case .table = $0 { true } else { false } }
            XCTAssertEqual(tables.count, 1, "hugging boxes: \(hugging): \(text)")
            XCTAssertTrue(text.contains("Pos\tBeschreibung\tMenge\tBetrag\n1\tBeratung\t3\t255,00 €\n2\tDruckpatronen"), text)
            XCTAssertTrue(text.hasSuffix("Bitte überweisen Sie den Betrag innerhalb von vierzehn Tagen auf das unten genannte Konto, damit nichts verloren geht."), text)
        }
    }

    func testTwoColumnsWhoseParagraphsDoNotLineUpAreReadAColumnAtATime() {
        both {
            let left = ["Die Stadt hat in diesem Jahr mehr", "Besucher als je zuvor gezählt.", "", "Vor allem im Sommer kamen viele", "Gäste aus dem Ausland, die sich", "für die alten Gassen begeistern.", "", "Auch die Hotels melden viel."]
            let right = ["Die Verwaltung plant neue Radwege", "und mehr Platz für Fußgänger in", "der Altstadt. Anwohner begrüßen", "das, fordern aber auch ruhigere", "Nächte in den belebten Straßen.", "", "Ein runder Tisch soll im Winter", "Lösungen erarbeiten."]
            let text = read(lines(left, x: 57, top: 140, pitch: 14).filter { !$0.words.isEmpty } + lines(right, x: 330, top: 140, pitch: 14).filter { !$0.words.isEmpty })
            order(text, ["Die Stadt hat", "Auch die Hotels melden viel.", "Die Verwaltung plant", "Lösungen erarbeiten."])
        }
    }

    // MARK: A bank statement

    func testABankStatementIsATableWithItsDatesAndAmounts() {
        both {
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
    }

    // MARK: A contract with numbered clauses

    func testNumberedClausesStayWithTheirNumbers() {
        both {
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
    }

    // MARK: A form

    func testAFormsLabelsStayOverTheirFields() {
        both {
            var segments = [stretch("Antrag auf Erstattung", x: 57, top: 70, size: 18)]
            segments.append(row([("Vorname", 57), ("Nachname", 300)], top: 140, size: 8))
            segments.append(row([("Erika", 57), ("Mustermann", 300)], top: 154, size: 12))
            segments.append(row([("Straße", 57), ("Ort", 300)], top: 190, size: 8))
            segments.append(row([("Musterstraße 12", 57), ("20095 Hamburg", 300)], top: 204, size: 12))
            let text = read(segments)
            // The grid as it stands: a row of labels, a row of values under it.
            order(text, ["Antrag auf Erstattung", "Vorname\tNachname\nErika\tMustermann", "Straße\tOrt\nMusterstraße 12\t20095 Hamburg"])
        }
    }

    // MARK: An article in two columns

    func testAnArticleUnderAHeadlineIsReadHeadlineThenEachColumn() {
        both {
            let one = ["Die Stadt hat in diesem Jahr mehr", "Besucher als je zuvor gezählt. Vor allem", "im Sommer kamen viele Gäste aus dem",
                       "Ausland, die sich für die alten Gassen", "und die Museen begeistern. Auch die", "Hotels melden bis in den Herbst hinein", "eine hohe Auslastung."]
            let two = ["Die Verwaltung plant deshalb neue", "Radwege und mehr Platz für Fußgänger", "in der Altstadt. Anwohner begrüßen das,",
                       "fordern aber auch ruhigere Nächte in", "den belebten Straßen. Ein runder Tisch", "soll im Winter Lösungen erarbeiten.", "Besucher und Bewohner sollen gewinnen."]
            let text = read([stretch("Rekord bei den Besucherzahlen", x: 57, top: 70, size: 24)]
                            + lines(one, x: 57, top: 140, pitch: 14) + lines(two, x: 330, top: 140, pitch: 14))
            order(text, ["Rekord bei den Besucherzahlen", "Die Stadt hat", "Hotels melden bis in den Herbst hinein", "Die Verwaltung plant", "Bewohner sollen gewinnen"])
            XCTAssertTrue(text.contains("Vor allem im Sommer kamen viele Gäste"), "a column runs on: \(text)")
        }
    }

    // MARK: A long paragraph of lines unlike in height

    func testALongParagraphStaysWholeWhateverLettersItsLinesHold() {
        both {
            // Some lines have tails (g, j, p, q, y), some do not; a box that hugs the letters differs by about a fifth.
            let body = ["Im Anschluss an unser Gespräch vom vergangenen Dienstag", "möchten wir Ihnen die vereinbarten Unterlagen zusenden.",
                        "Die Dokumente enthalten alle Angaben, die wir besprochen", "haben: die Fristen, die Beträge und die Ansprechpartner.",
                        "Bitte prüfen Sie die Unterlagen in Ruhe und melden Sie", "sich bei uns, falls etwas unklar sein sollte oder wenn",
                        "Sie noch Fragen haben. Wir helfen gern weiter, und zwar", "so schnell wie möglich, damit nichts liegen bleibt.",
                        "Die nächste Frist läuft am Ende des Monats ab, dann", "ist die Entscheidung endgültig und nicht mehr änderbar."]
            let page = ScanReading.page(lines(body, x: 57, top: 200, pitch: 14), aspect: Self.aspect)
            XCTAssertEqual(page.blocks.count, 1, "hugging boxes: \(hugging): \(ScanReading.text(page))")
        }
    }

    // MARK: Lines that must not be split

    func testJustifiedSpacesAndWideHeadlinesAreNotParted() {
        both {
            // A justified line's spaces are wider than a normal space, not a column's gap.
        let line = stretch("Dieser Satz ist im Blocksatz gesetzt und hat weite Wortabstände.", x: 57, top: 120, space: 9)
        let page = ScanReading.page([line] + lines(["Eine zweite Zeile steht darunter im Text."], x: 57, top: 134), aspect: Self.aspect)
        XCTAssertEqual(page.blocks.count, 1)
            XCTAssertTrue(ScanReading.text(page).hasPrefix("Dieser Satz ist im Blocksatz gesetzt und hat weite Wortabstände."))
        }
    }
}
