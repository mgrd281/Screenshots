import XCTest
@testable import Tendedero

/// What is done with a page's text once it is read (`ScanReadingTools`): the
/// words the reading was unsure of kept apart in the text, a correction typed
/// by hand that never lands on another block, a table handed to a spreadsheet
/// without a cell run as a formula, the text found by a few letters whatever
/// the case and accents, and what is spoken matched to what is shown, a cover
/// said as a word and what it hides never in it.
final class ScanReadingToolsTests: XCTestCase {
    private func word(_ text: String, _ x: CGFloat, _ y: CGFloat = 0.5, unsure: Bool = false) -> ScanReading.Word {
        ScanReading.Word(text: text, box: CGRect(x: x, y: y, width: 0.05, height: 0.01), unsure: unsure)
    }

    private func words(_ text: String, x: CGFloat = 0.1, y: CGFloat = 0.5, unsure: Set<String> = []) -> [ScanReading.Word] {
        text.split(separator: " ").enumerated().map { word(String($0.element), x + CGFloat($0.offset) * 0.06, y, unsure: unsure.contains(String($0.element))) }
    }

    private func paragraph(_ lines: [[ScanReading.Word]], flows: Bool = true, heading: Bool = false) -> ScanReading.Block {
        .paragraph(ScanReading.Paragraph(lines: lines, flows: flows, heading: heading))
    }

    private func page(_ blocks: ScanReading.Block...) -> ScanReading.Page {
        ScanReading.Page(blocks: blocks, rightToLeft: false)
    }

    private func table(_ rows: [[String]]) -> ScanReading.Block {
        .table(ScanReading.Table(rows: rows.enumerated().map { row, cells in
            cells.enumerated().map { column, text in words(text, x: 0.1 + CGFloat(column) * 0.3, y: 0.9 - CGFloat(row) * 0.03) }
        }))
    }

    // MARK: Unsure

    func testTheUnsureWordsAreStretchesOfTheirOwnAndTheTextIsTheSame() {
        let block = paragraph([words("Die Summe beträgt 1.234,56 Euro", unsure: ["1.234,56"])])
        guard case .paragraph(let paragraph) = block else { return XCTFail() }
        let runs = ScanReading.runs(of: paragraph, rightToLeft: false)
        XCTAssertEqual(runs, [.init(text: "Die Summe beträgt ", unsure: false), .init(text: "1.234,56", unsure: true),
                              .init(text: " Euro", unsure: false)])
        XCTAssertEqual(runs.map(\.text).joined(), ScanReading.text(page(block)))
        XCTAssertEqual(ScanReading.text(page(block)), "Die Summe beträgt 1.234,56 Euro", "marking changes no letter")
    }

    func testAJoinedWordIsUnsureIfEitherPartWas() {
        let block = paragraph([words("das Bildschirm-", unsure: ["Bildschirm-"]), words("foto zeigt es", x: 0.1, y: 0.48)])
        guard case .paragraph(let paragraph) = block else { return XCTFail() }
        let runs = ScanReading.runs(of: paragraph, rightToLeft: false)
        XCTAssertEqual(runs.map(\.text).joined(), "das Bildschirmfoto zeigt es")
        XCTAssertEqual(runs.filter(\.unsure).map(\.text), ["Bildschirmfoto"])
    }

    func testLinesThatStandOnTheirOwnKeepTheirBreaksAndOneUnsureRun() {
        let block = paragraph([words("Erika Mustermann"), words("Musterstraße 12", y: 0.48, unsure: ["12"]), words("20095 Hamburg", y: 0.46)], flows: false)
        guard case .paragraph(let paragraph) = block else { return XCTFail() }
        let runs = ScanReading.runs(of: paragraph, rightToLeft: false)
        XCTAssertEqual(runs.map(\.text).joined(), "Erika Mustermann\nMusterstraße 12\n20095 Hamburg")
        XCTAssertEqual(runs.filter(\.unsure).map(\.text), ["12"])
    }

    func testWhereTheReadingWasUnsureIsFoundAndCounted() {
        let sure = paragraph([words("Alles sicher gelesen")])
        let unsure = paragraph([words("Betrag 12,50 €", y: 0.3, unsure: ["12,50"])])
        let unsureTable = table([["Posten", "Preis"], ["Lampe", "49,00"]])
        let pages = [page(sure, unsure), page(unsureTable)]
        XCTAssertEqual(ScanReading.unsureBoxes(pages[0]).count, 1)
        XCTAssertEqual(ScanReading.unsureCount(pages), 1)
        let box = ScanReading.unsureBoxes(pages[0])[0]
        XCTAssertEqual(box.minY, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ScanReading.unsureCount([page(sure)]), 0)
    }

    func testACoverIsNeverUnsure() {
        let block = paragraph([[word("Patient:", 0.1), .covered(CGRect(x: 0.2, y: 0.5, width: 0.1, height: 0.01)), word("geb.", 0.4)]])
        XCTAssertEqual(ScanReading.text(page(block)), "Patient: \(ScanReading.mark) geb.")
        XCTAssertEqual(ScanReading.unsureCount([page(block)]), 0)
    }

    // MARK: Corrections

    func testACorrectionReplacesTheTextItWasMadeOnAndNothingElse() {
        let one = paragraph([words("Die Rechnung vom 14.10. liegt bei")])
        let two = paragraph([words("Mit freundlichen Grüßen")], flows: false)
        guard case .paragraph(let first) = one else { return XCTFail() }
        let key = ScanReading.editKey(of: first, rightToLeft: false)
        let fixed = ScanReading.applying([key: "Die Rechnung vom 14.11. liegt bei"], to: page(one, two))
        XCTAssertEqual(ScanReading.text(fixed), "Die Rechnung vom 14.11. liegt bei\n\nMit freundlichen Grüßen")
        // The same correction on a page whose text is another changes nothing.
        let other = page(paragraph([words("Ein ganz anderer Absatz")]))
        XCTAssertEqual(ScanReading.text(ScanReading.applying([key: "x"], to: other)), "Ein ganz anderer Absatz")
    }

    func testACorrectedBlockIsNoLongerUnsureAndKeepsItsPlace() {
        let block = paragraph([words("Betrag 12,5O €", unsure: ["12,5O"])], heading: true)
        guard case .paragraph(let original) = block else { return XCTFail() }
        let fixed = ScanReading.applying([ScanReading.editKey(of: original, rightToLeft: false): "Betrag 12,50 €"], to: page(block))
        XCTAssertEqual(ScanReading.unsureCount([fixed]), 0)
        guard case .paragraph(let made) = fixed.blocks[0] else { return XCTFail() }
        XCTAssertTrue(made.heading)
        XCTAssertEqual(ScanReading.box(of: fixed.blocks[0]), ScanReading.box(of: block))
    }

    func testACorrectedCellStaysOneCellAndAMultilineTextStaysItsLines() {
        let grid = table([["Lampe", "49,0O"], ["Kabel", "25,00"]])
        guard case .table(let original) = grid else { return XCTFail() }
        let key = ScanReading.editKey(ofCell: original.rows[0][1])
        let fixed = ScanReading.applying([key: "49,00\tEUR\nnetto"], to: page(grid))
        XCTAssertEqual(ScanReading.text(fixed), "Lampe\t49,00 EUR netto\nKabel\t25,00")
        let multi = paragraph([words("Zeile eins Zeile zwei")], flows: false)
        guard case .paragraph(let source) = multi else { return XCTFail() }
        let text = ScanReading.applying([ScanReading.editKey(of: source, rightToLeft: false): "Zeile eins\nZeile zwei\n"], to: page(multi))
        XCTAssertEqual(ScanReading.text(text), "Zeile eins\nZeile zwei")
    }

    func testEmptiedTextLeavesTheBlockOut() {
        let one = paragraph([words("Weg damit")])
        let two = paragraph([words("Bleibt")], flows: false)
        guard case .paragraph(let source) = one else { return XCTFail() }
        let fixed = ScanReading.applying([ScanReading.editKey(of: source, rightToLeft: false): "  \n"], to: page(one, two))
        XCTAssertEqual(ScanReading.text(fixed), "Bleibt")
    }

    func testNoCorrectionsLeavesThePageAsItIs() {
        let block = paragraph([words("Unverändert")])
        XCTAssertEqual(ScanReading.applying([:], to: page(block)), page(block))
    }

    // MARK: Tables

    func testATableIsCopiedAsTabsForASpreadsheet() {
        let grid = table([["Pos", "Beschreibung", "Betrag"], ["1", "Beratung (Stunden)", "255,00 €"]])
        guard case .table(let table) = grid else { return XCTFail() }
        XCTAssertEqual(ScanReading.tsv(table), "Pos\tBeschreibung\tBetrag\n1\tBeratung (Stunden)\t255,00 €")
    }

    func testACoveredCellIsAMarkInTheTable() {
        let cover = ScanReading.Word.covered(CGRect(x: 0.4, y: 0.9, width: 0.1, height: 0.01))
        let grid = ScanReading.Table(rows: [[[word("Name", 0.1)], [cover]], [[word("Betrag", 0.1, 0.8)], [word("12,50", 0.4, 0.8)]]])
        XCTAssertEqual(ScanReading.tsv(grid), "Name\t███\nBetrag\t12,50")
        XCTAssertTrue(ScanReading.csv(grid).hasPrefix("Name,███"))
    }

    func testCSVQuotesWhatNeedsItAndPartsRowsByCRLF() {
        let grid = table([["Name", "Notiz"], ["Müller, Anna", "sagte \"ja\""], ["Zeile", "a b"]])
        guard case .table(let table) = grid else { return XCTFail() }
        XCTAssertEqual(ScanReading.csv(table), "Name,Notiz\r\n\"Müller, Anna\",\"sagte \"\"ja\"\"\"\r\nZeile,a b")
        XCTAssertEqual(ScanReading.csv(table, delimiter: ";"), "Name;Notiz\r\nMüller, Anna;\"sagte \"\"ja\"\"\"\r\nZeile;a b")
    }

    func testTheDelimiterFollowsTheDecimalSeparator() {
        XCTAssertEqual(ScanReading.csvDelimiter(decimalSeparator: ","), ";")
        XCTAssertEqual(ScanReading.csvDelimiter(decimalSeparator: "."), ",")
        XCTAssertEqual(ScanReading.csvDelimiter(decimalSeparator: nil), ",")
    }

    func testACellASpreadsheetWouldRunAsAFormulaIsDefused() {
        for cell in ["=HYPERLINK(\"http://x\")", "@SUM(A1)", "+SUM(A1)", "-A1", "-cmd|' /C calc'!A0", "\tx"] {
            XCTAssertTrue(ScanReading.neutralized(cell).hasPrefix("'"), cell)
        }
        for cell in ["-12,50", "+49 30 1234567", "- ", "-", "+", "-.5", "Rechnung", "12,50", "= "] where cell != "= " {
            XCTAssertEqual(ScanReading.neutralized(cell), cell, cell)
        }
        XCTAssertEqual(ScanReading.neutralized("= 1"), "'= 1")
        XCTAssertEqual(ScanReading.neutralized(""), "")
    }

    // MARK: Finding

    func testFindingIgnoresCaseAndAccents() {
        let text = "Über die Brücke: ÜBER alles, uber nichts"
        XCTAssertEqual(ScanReading.find("uber", in: text), [0..<4, 17..<21, 29..<33])
        XCTAssertEqual(ScanReading.find("BRUCKE", in: text), [9..<15])
        XCTAssertEqual(ScanReading.find("  ", in: text), [])
        XCTAssertEqual(ScanReading.find("nothing", in: text), [])
        XCTAssertEqual(ScanReading.find("aa", in: "aaaa"), [0..<2, 2..<4], "matches do not overlap")
    }

    func testFindingWorksInEveryScript() {
        XCTAssertEqual(ScanReading.find("مرحبا", in: "قال مرحبا للعالم").count, 1)
        XCTAssertEqual(ScanReading.find("москва", in: "Город Москва, Россия"), [6..<12])
        XCTAssertEqual(ScanReading.find("東京", in: "東京都新宿区"), [0..<2])
    }

    // MARK: Spots and matches

    func testUnsureSpotsSayWhichLineAndCellAndEachHasItsOwnID() {
        let block = paragraph([words("Alles sicher"), words("Betrag 12,50 €", y: 0.4, unsure: ["12,50"]), words("Datum 1.1.", y: 0.3, unsure: ["1.1."])])
        let grid = table([["Lampe", "49,0O"], ["Kabel", "25,00"]])
        guard case .table(var inner) = grid else { return XCTFail() }
        inner.rows[1][1][0].unsure = true
        let spots = ScanReading.unsureSpots(page(block, .table(inner)), number: 3)
        XCTAssertEqual(spots.map(\.spot), [.init(page: 3, block: 0), .init(page: 3, block: 0), .init(page: 3, block: 1, row: 1, column: 1)])
        XCTAssertEqual(spots.map(\.line), [1, 2, 0])
        XCTAssertEqual(Set(spots.map(\.id)).count, 3)
    }

    func testTheTextAndTheKeyAtASpot() throws {
        let one = paragraph([words("Erste Zeile"), words("zweite Zeile", y: 0.48)])
        let grid = table([["Lampe", "49,00"], ["Kabel", "25,00"]])
        let pages = [page(one, grid)]
        XCTAssertEqual(ScanReading.text(at: .init(page: 0, block: 0), in: pages), "Erste Zeile zweite Zeile")
        XCTAssertEqual(ScanReading.text(at: .init(page: 0, block: 1, row: 1, column: 1), in: pages), "25,00")
        XCTAssertEqual(ScanReading.editKey(at: .init(page: 0, block: 1, row: 0, column: 0), in: pages), "c:Lampe")
        XCTAssertEqual(ScanReading.editKey(at: .init(page: 0, block: 0), in: pages), "p:Erste Zeile zweite Zeile")
        XCTAssertNil(ScanReading.text(at: .init(page: 1, block: 0), in: pages))
        XCTAssertNil(ScanReading.text(at: .init(page: 0, block: 1), in: pages), "a table needs a cell")
        XCTAssertNil(ScanReading.editKey(at: .init(page: 0, block: 5), in: pages))
        XCTAssertNotNil(ScanReading.box(at: .init(page: 0, block: 1, row: 0, column: 1), in: pages))
    }

    func testMatchesAreFoundInReadingOrderInParagraphsAndCells() {
        let one = paragraph([words("Die Rechnung liegt bei. Rechnung 4711")])
        let grid = table([["Rechnungsnr.", "4711"], ["Datum", "14.10."]])
        let matches = ScanReading.matches("rechnung", in: [page(one), page(grid)])
        XCTAssertEqual(matches.map(\.spot), [.init(page: 0, block: 0), .init(page: 0, block: 0), .init(page: 1, block: 0, row: 0, column: 0)])
        XCTAssertEqual(matches[0].range, 4..<12)
        XCTAssertTrue(ScanReading.matches("   ", in: [page(one)]).isEmpty)
        XCTAssertTrue(ScanReading.matches("zzz", in: [page(one)]).isEmpty)
    }

    func testCharacterRangesFollowUTF16() {
        let text = "Café 😀 offen"
        let range = (text as NSString).range(of: "offen")
        XCTAssertEqual(ScanReading.characterRange(range, in: text), 7..<12)
        XCTAssertNil(ScanReading.characterRange(NSRange(location: 99, length: 3), in: text))
    }

    // MARK: Speaking

    func testACoverIsSpokenAsAWordAndWhatItHidesIsNotThere() {
        let cover = ScanReading.Word.covered(CGRect(x: 0.2, y: 0.5, width: 0.1, height: 0.01))
        let block = paragraph([[word("Patient:", 0.1), cover, word("geb.", 0.4), word("05.03.1992", 0.5)]])
        let said = ScanReading.utterances([page(block)], spokenMark: "verdeckt")
        XCTAssertEqual(said.count, 1)
        XCTAssertEqual(said[0].spoken, "Patient: verdeckt geb. 05.03.1992")
        XCTAssertEqual(said[0].shown, "Patient: ███ geb. 05.03.1992")
        XCTAssertFalse(said[0].spoken.contains("█"))
    }

    func testTheSpokenWordIsFoundInTheShownText() throws {
        let cover = ScanReading.Word.covered(CGRect(x: 0.2, y: 0.5, width: 0.1, height: 0.01))
        let block = paragraph([[word("Patient:", 0.1), cover, word("geb.", 0.4)]])
        let said = try XCTUnwrap(ScanReading.utterances([page(block)], spokenMark: "verdeckt").first)
        let shown = said.shown as NSString
        let spoken = said.spoken as NSString
        // "geb." after the cover.
        let spokenRange = spoken.range(of: "geb.")
        XCTAssertEqual(shown.substring(with: try XCTUnwrap(said.shownRange(spokenRange))), "geb.")
        // The cover's word, all of it, is the mark.
        let cover1 = spoken.range(of: "verdeckt")
        XCTAssertEqual(shown.substring(with: try XCTUnwrap(said.shownRange(cover1))), "███")
        // Half the cover's word is still the whole mark.
        XCTAssertEqual(shown.substring(with: try XCTUnwrap(said.shownRange(NSRange(location: cover1.location, length: 3)))), "███")
        XCTAssertNil(said.shownRange(NSRange(location: 0, length: 0)))
        XCTAssertNil(said.shownRange(NSRange(location: 999, length: 3)))
    }

    func testLinesAndCellsArePauses() throws {
        let address = paragraph([words("Erika Mustermann"), words("Musterstraße 12", y: 0.48)], flows: false)
        let said = ScanReading.utterances([page(address, table([["Lampe", "49,00 €"], ["Kabel", "25,00 €"]]))], spokenMark: "covered")
        XCTAssertEqual(said.map(\.spoken), ["Erika Mustermann, Musterstraße 12", "Lampe, 49,00 €", "Kabel, 25,00 €"])
        XCTAssertEqual(said.map(\.row), [nil, 0, 1])
        XCTAssertEqual(said.map(\.block), [0, 1, 1])
        let second = said[0]
        let range = (second.spoken as NSString).range(of: "Musterstraße")
        XCTAssertEqual((second.shown as NSString).substring(with: try XCTUnwrap(second.shownRange(range))), "Musterstraße")
    }

    func testPagesAreSpokenInOrderAndEmptyBlocksAreSilent() {
        let a = paragraph([words("Seite eins")])
        let b = paragraph([[]])
        let c = paragraph([words("Seite zwei")])
        let said = ScanReading.utterances([page(a, b), page(c)], spokenMark: "covered")
        XCTAssertEqual(said.map(\.spoken), ["Seite eins", "Seite zwei"])
        XCTAssertEqual(said.map(\.page), [0, 1])
    }

    func testAnEmojiAndAnAccentSurviveTheMap() throws {
        let block = paragraph([words("Café 😀 offen")])
        let said = try XCTUnwrap(ScanReading.utterances([page(block)], spokenMark: "covered").first)
        XCTAssertEqual(said.spoken, "Café 😀 offen")
        XCTAssertEqual(said.from.count, said.spoken.utf16.count)
        let range = (said.spoken as NSString).range(of: "offen")
        XCTAssertEqual((said.shown as NSString).substring(with: try XCTUnwrap(said.shownRange(range))), "offen")
    }
}
