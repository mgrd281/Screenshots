import XCTest
@testable import Tendedero

/// A scanned document's name and kind, on made-up pages: only words the
/// covers leave visible, never a covered value or the owner's own name,
/// never a sender the page doesn't show or a person's name; the date as
/// written; the name by when it was scanned with Apple Intelligence off or
/// nothing found. And when a photo from Photos is offered as a document.
final class ScanNamingTests: XCTestCase {
    /// A made-up invoice's first page as read, top first, its customer's
    /// name and e-mail address covered.
    private static let customer = CGRect(x: 0.08, y: 0.78, width: 0.3, height: 0.025)
    private static let email = CGRect(x: 0.38, y: 0.08, width: 0.4, height: 0.02)

    private static func line(_ text: String, y: CGFloat, x: CGFloat = 0.08) -> [ScanNaming.Word] {
        var words: [ScanNaming.Word] = []
        var left = x
        for word in text.split(separator: " ") {
            let width = CGFloat(word.count) * 0.012
            words.append(ScanNaming.Word(text: String(word), box: CGRect(x: left, y: y, width: width, height: 0.02)))
            left += width + 0.01
        }
        return words
    }

    private static var invoice: [[ScanNaming.Word]] {
        [line("Musterfirma GmbH", y: 0.93),
         line("Beispielweg 5 · 10115 Berlin", y: 0.9),
         line("Erika Mustermann", y: 0.783),
         line("Musterstraße 12", y: 0.75),
         line("Rechnungsnr. RE-2026-0417", y: 0.72, x: 0.6),
         line("Datum 14.10.2026", y: 0.69, x: 0.6),
         line("Rechnung", y: 0.62),
         line("Gesamt 369,73 €", y: 0.4, x: 0.6),
         line("Bitte überweisen Sie den Betrag bis zum 28.10.2026.", y: 0.2),
         line("Telefon: 030 1234567 · E-Mail: buchhaltung@musterfirma.de", y: 0.085)]
    }

    private static var visible: ScanNaming.Visible {
        ScanNaming.visible(invoice, covered: [customer, email])
    }

    func testCoveredWordsAreHiddenAndTheLinesReadTopFirst() {
        let shown = Self.visible
        XCTAssertEqual(shown.lines.first, "Musterfirma GmbH")
        XCTAssertFalse(shown.lines.joined(separator: " ").contains("Mustermann"))
        XCTAssertFalse(shown.lines.joined(separator: " ").contains("buchhaltung@"))
        XCTAssertTrue(shown.hidden.isSuperset(of: ["erika", "mustermann"]))
        // Upside down in, top first out.
        let reversed = ScanNaming.visible(Self.invoice.reversed(), covered: [])
        XCTAssertEqual(reversed.lines.first, "Musterfirma GmbH")
    }

    func testAWordACoverOnlyTouchesIsHiddenToo() {
        let word = ScanNaming.Word(text: "Erika", box: CGRect(x: 0.1, y: 0.5, width: 0.1, height: 0.02))
        let edge = CGRect(x: 0.195, y: 0.49, width: 0.2, height: 0.04)
        let shown = ScanNaming.visible([[word]], covered: [edge])
        XCTAssertTrue(shown.lines.isEmpty)
        XCTAssertEqual(shown.hidden, ["erika"])
    }

    func testTheSuggestionIsKindSenderAndDateFromWhatShows() {
        let reading = ScanNaming.Reading(kind: .invoice, sender: "Musterfirma GmbH")
        let name = ScanNaming.suggestion(reading, visible: Self.visible, own: [])
        XCTAssertEqual(name, "\(PaperKind.invoice.title) Musterfirma 14.10.2026")
    }

    func testACoveredNameIsNeverInTheSuggestion() {
        // Apple Intelligence names the covered customer as the sender, as a model might.
        for sender in ["Erika Mustermann", "Mustermann", "Frau Erika Mustermann", "Mustermann GmbH"] {
            let reading = ScanNaming.Reading(kind: .invoice, sender: sender)
            let name = ScanNaming.suggestion(reading, visible: Self.visible, own: []) ?? ""
            XCTAssertFalse(name.localizedCaseInsensitiveContains("Mustermann"), sender)
            XCTAssertFalse(name.localizedCaseInsensitiveContains("Erika"), sender)
            let result = ScanNaming.result(reading, visible: Self.visible, own: [], scanned: Date())
            XCTAssertFalse(result.name.localizedCaseInsensitiveContains("Mustermann"), sender)
        }
    }

    func testTheOwnersOwnNameIsNeverInTheSuggestionEvenWhereItShows() {
        let lines = [Self.line("Max Muster Consulting", y: 0.9), Self.line("Rechnung", y: 0.6),
                     Self.line("Datum 14.10.2026", y: 0.5)]
        let shown = ScanNaming.visible(lines, covered: [])
        let reading = ScanNaming.Reading(kind: .invoice, sender: "Max Muster Consulting")
        let name = ScanNaming.suggestion(reading, visible: shown, own: ["max", "muster"])
        XCTAssertEqual(name, "\(PaperKind.invoice.title) 14.10.2026")
    }

    func testASenderThePageDoesntShowOrAPersonsNameIsLeftOut() {
        let invented = ScanNaming.Reading(kind: .invoice, sender: "Beispiel Versand AG")
        XCTAssertEqual(ScanNaming.suggestion(invented, visible: Self.visible, own: []),
                       "\(PaperKind.invoice.title) 14.10.2026")
        let lines = [Self.line("Hans Beispiel", y: 0.9), Self.line("Sehr geehrte Damen und Herren", y: 0.6)]
        let shown = ScanNaming.visible(lines, covered: [])
        let person = ScanNaming.Reading(kind: .letter, sender: "Hans Beispiel")
        XCTAssertEqual(ScanNaming.suggestion(person, visible: shown, own: []), PaperKind.letter.title)
        // Neither a kind nor a sender: nothing to suggest.
        XCTAssertNil(ScanNaming.suggestion(ScanNaming.Reading(kind: nil, sender: "Hans Beispiel"), visible: shown, own: []))
    }

    func testACoveredDateIsLeftOut() {
        let lines = [Self.line("Musterfirma GmbH", y: 0.9), Self.line("Datum 14.10.2026", y: 0.7)]
        let date = CGRect(x: 0.15, y: 0.69, width: 0.2, height: 0.04)
        let shown = ScanNaming.visible(lines, covered: [date])
        let reading = ScanNaming.Reading(kind: .invoice, sender: "Musterfirma GmbH")
        XCTAssertEqual(ScanNaming.suggestion(reading, visible: shown, own: []), "\(PaperKind.invoice.title) Musterfirma")
    }

    func testWithAppleIntelligenceOffTheNameIsWhenItWasScanned() {
        let parts = DateComponents(year: 2026, month: 10, day: 21, hour: 14, minute: 5)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanned = calendar.date(from: parts)!
        XCTAssertEqual(ScanNaming.fallback(at: scanned, in: calendar.timeZone), String(format: L("Scan %@"), "21.10.2026, 14.05"))
        let fallback = ScanNaming.fallback(at: scanned)
        let result = ScanNaming.result(nil, visible: Self.visible, own: [], scanned: scanned)
        XCTAssertEqual(result.name, fallback)
        XCTAssertFalse(result.suggested)
        XCTAssertEqual(result.kind, .invoice, "the kind from its words")
        // Read, but nothing that holds: the same name.
        let empty = ScanNaming.result(ScanNaming.Reading(), visible: ScanNaming.Visible(lines: ["Hallo"], hidden: []),
                                      own: [], scanned: scanned)
        XCTAssertEqual(empty.name, fallback)
        XCTAssertFalse(empty.suggested)
    }

    func testAppleIntelligenceIsNotAskedWhileItIsOff() async {
        let before = Finder.usesIntelligence
        defer { Finder.usesIntelligence = before }
        Finder.usesIntelligence = false
        XCTAssertFalse(ScanNaming.asksIntelligence)
        let reading = await ScanNaming.ask(Self.visible)
        XCTAssertNil(reading)
    }

    func testTheKindComesFromTheWords() {
        XCTAssertEqual(ScanNaming.kind(of: Self.visible.lines), .invoice)
        XCTAssertEqual(ScanNaming.kind(of: ["Sehr geehrte Frau Beispiel,", "Mit freundlichen Grüßen"]), .letter)
        XCTAssertEqual(ScanNaming.kind(of: ["Antrag auf Wohngeld", "Bitte ankreuzen"]), .form)
        XCTAssertEqual(ScanNaming.kind(of: ["Kassenbon", "Summe 12,40", "Rückgeld 7,60"]), .receipt)
        XCTAssertNil(ScanNaming.kind(of: ["Einkaufsliste", "Milch", "Brot"]))
    }

    func testTheDateIsAsWrittenAndOneAfterALabelComesFirst() {
        XCTAssertEqual(ScanNaming.date(in: ["Zahlbar bis 28.10.2026", "Datum: 14.10.2026"]), "14.10.2026")
        XCTAssertEqual(ScanNaming.date(in: ["Lieferung 3.2.2026"]), "3.2.2026")
        XCTAssertEqual(ScanNaming.date(in: ["Date 14/10/2026"]), "14-10-2026")
        XCTAssertEqual(ScanNaming.date(in: ["Issued 2026-10-14"]), "2026-10-14")
        XCTAssertNil(ScanNaming.date(in: ["Kundennr. 32.13.2026", "Tel. 030 1234567"]))
    }

    func testANameIsSafeForFiles() {
        XCTAssertEqual(ScanNaming.safe("Rechnung A/B: Test?  \"x\" "), "Rechnung A B Test x")
        XCTAssertEqual(ScanNaming.safe(String(repeating: "a", count: 120)).count, 80)
        XCTAssertEqual(ScanNaming.safe("Brief ..."), "Brief")
    }

    func testTheAnswerIsReadLineByLine() {
        XCTAssertEqual(ScanNaming.parse("type: invoice\nsender: Musterfirma GmbH"),
                       ScanNaming.Reading(kind: .invoice, sender: "Musterfirma GmbH"))
        XCTAssertEqual(ScanNaming.parse("Type: Letter\nSender: none"), ScanNaming.Reading(kind: .letter, sender: nil))
        XCTAssertEqual(ScanNaming.parse("type: other\nsender: unknown"), ScanNaming.Reading())
        XCTAssertEqual(ScanNaming.parse("I think it is a bill."), ScanNaming.Reading())
    }

    func testAPhotoIsOfferedOnlyAsAPageOfText() {
        let page = ScanQuad(topLeft: CGPoint(x: 0.17, y: 0.9), topRight: CGPoint(x: 0.85, y: 0.88),
                            bottomRight: CGPoint(x: 0.92, y: 0.12), bottomLeft: CGPoint(x: 0.08, y: 0.15))
        XCTAssertTrue(DocumentPhoto.offers(screenshot: false, page: page, confidence: 0.9, words: 40))
        XCTAssertFalse(DocumentPhoto.offers(screenshot: true, page: page, confidence: 0.9, words: 40), "a screenshot")
        XCTAssertFalse(DocumentPhoto.offers(screenshot: false, page: page, confidence: 0.5, words: 40), "unsure")
        XCTAssertFalse(DocumentPhoto.offers(screenshot: false, page: page, confidence: 0.9, words: 5), "a sign")
        XCTAssertFalse(DocumentPhoto.offers(screenshot: false, page: nil, confidence: nil, words: 40), "no page")
        XCTAssertFalse(DocumentPhoto.offers(screenshot: false, page: .inset(0.4), confidence: 0.9, words: 40), "too small")
    }

    func testEveryQuestionSaysNeverToGuessOrChangeANumber() {
        let rule = L("Parts are covered for privacy: never guess them. Never fill in or correct a number. Where something cannot be read, say so.")
        for ask in ScanAsk.allCases {
            XCTAssertTrue(ask.prompt.hasSuffix(rule), ask.rawValue)
            XCTAssertFalse(ask.title.isEmpty)
        }
    }
}

/// A scanned document's pages keep the order the photos were chosen in;
/// one dragged onto another takes its place, the rest closing up.
final class ScanOrderTests: XCTestCase {
    func testAPageMovesToAnothersPlace() {
        let chosen = ["third", "first", "second"]
        XCTAssertEqual(ScanOrder.moving(chosen, from: 0, to: 2), ["first", "second", "third"])
        XCTAssertEqual(ScanOrder.moving(chosen, from: 2, to: 0), ["second", "third", "first"])
        XCTAssertEqual(ScanOrder.moving(chosen, from: 1, to: 1), chosen)
        XCTAssertEqual(ScanOrder.moving(chosen, from: 1, to: 9), ["third", "second", "first"], "kept within")
        XCTAssertEqual(ScanOrder.moving(chosen, from: 1, to: -3), ["first", "third", "second"])
        XCTAssertEqual(ScanOrder.moving(chosen, from: 5, to: 0), chosen, "no such page")
    }
}
