import XCTest
@testable import Tendedero

/// What a document asks to be paid, read from its text as Scan reads it:
/// the day, the amount, the company and the number, only as written, and
/// nothing for one paid already, paid by direct debit, or a credit note.
/// The documents are made up.
final class PaymentDueTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> PaymentDue.Day? {
        PaymentDue.Day(year: year, month: month, day: day)
    }

    /// The made-up invoice as Vision read it on a Mac, its text as the
    /// scan's text shows it: stamped BEZAHLT, with the 28th to pay by.
    private var invoice: String {
        ScanReading.text(ScanReadingVisionTests.page(ScanReadingVisionTests.invoice))
    }

    func testAnInvoiceStampedPaidAsksForNothing() {
        XCTAssertTrue(invoice.contains("BEZAHLT"), invoice)
        XCTAssertNil(PaymentDue.find(in: invoice))
    }

    func testTheInvoiceToPayGivesItsDayAmountCompanyAndNumber() {
        let unpaid = invoice.replacingOccurrences(of: "BEZAHLT", with: "")
        let found = PaymentDue.find(in: unpaid)
        XCTAssertEqual(found?.day, day(2026, 10, 28), unpaid)
        XCTAssertEqual(found?.amount, "369,73 €", "the total, not the net or the tax")
        XCTAssertEqual(found?.payee, "Musterfirma GmbH", "without the logo's letter")
        XCTAssertEqual(found?.reference, "RE-2026-0417")
    }

    func testOnlyACompanyIsNamedAsTheOneToPay() {
        let practice = "Praxis Dr. med. Anna Schmidt\nRechnungsdatum: 14.10.2026\nRechnungsbetrag: 86,45 €\n"
            + "Bitte überweisen Sie den Rechnungsbetrag innerhalb von 30 Tagen."
        let found = PaymentDue.find(in: practice)
        XCTAssertEqual(found?.day, day(2026, 11, 13))
        XCTAssertEqual(found?.amount, "86,45 €")
        XCTAssertNil(found?.payee, "a practice, and a person's name, are no company")
        XCTAssertEqual(PaymentDue.find(in: "Stadtwerke Muster GmbH & Co. KG · Postfach 12\nFällig am 28.10.2026")?.payee,
                       "Stadtwerke Muster GmbH & Co. KG")
    }

    func testTheOwnersOwnCompanyIsNeverTheOneToPay() {
        // A form the owner's shop name heads, the company to pay under it.
        let text = "Beispiel Laden GmbH · Kundennr. 4711\nAbsender: Muster Handel GmbH\nRechnungsdatum: 14.10.2026\nZahlbar bis 28.10.2026"
        XCTAssertEqual(PaymentDue.find(in: text)?.payee, "Beispiel Laden GmbH")
        XCTAssertEqual(PaymentDue.find(in: text, own: ["beispiel", "laden"])?.payee, "Muster Handel GmbH")
    }

    func testDaysAreCountedFromTheDocumentsDate() {
        let text = """
            Rechnungsdatum: 14.10.2026
            Gesamtbetrag\t120,00 €
            Zahlbar innerhalb von 14 Tagen ohne Abzug.
            """
        XCTAssertEqual(PaymentDue.find(in: text)?.day, day(2026, 10, 28))
        XCTAssertEqual(PaymentDue.find(in: text)?.amount, "120,00 €")
        XCTAssertEqual(PaymentDue.find(in: "Invoice date: 2026-10-21\nPayment terms: Net 30\nTotal due $1,250.00")?.day,
                       day(2026, 11, 20))
        // Without the document's date, days from it are not guessed.
        XCTAssertNil(PaymentDue.find(in: "Zahlbar innerhalb von 14 Tagen."))
    }

    func testADayWithoutItsYearTakesTheDocumentsYearOrTheNext() {
        XCTAssertEqual(PaymentDue.find(in: "Datum 21.10.2026\nGesamt 380,68 €\nBitte bis 04.11. überweisen.")?.day,
                       day(2026, 11, 4), "named before the cue, as the last day")
        XCTAssertEqual(PaymentDue.find(in: "Datum 21.12.2026\nZahlbar bis 08.01.")?.day, day(2027, 1, 8))
        XCTAssertNil(PaymentDue.find(in: "Zahlbar bis 08.01."), "no year to give it")
    }

    func testDaysAreReadAsTheyAreWritten() {
        XCTAssertEqual(PaymentDue.find(in: "Fällig am 5. November 2026")?.day, day(2026, 11, 5))
        XCTAssertEqual(PaymentDue.find(in: "Due date: November 4, 2026")?.day, day(2026, 11, 4))
        XCTAssertEqual(PaymentDue.find(in: "Please pay by 4 Nov 2026.")?.day, day(2026, 11, 4))
        XCTAssertEqual(PaymentDue.find(in: "Fälligkeitsdatum\t28.10.26")?.day, day(2026, 10, 28))
        XCTAssertEqual(PaymentDue.find(in: "Payment due 2026-11-04")?.day, day(2026, 11, 4))
        XCTAssertEqual(PaymentDue.find(in: "Due date: 24/11/2026")?.day, day(2026, 11, 24))
        // The 4th of November or the 11th of April: not guessed.
        XCTAssertNil(PaymentDue.find(in: "Due date: 04/11/2026"))
        XCTAssertNil(PaymentDue.find(in: "Zahlbar bis 31.04.2026"), "no such day")
    }

    func testASentenceThatWrapsIsReadOn() {
        let text = "Datum 14.10.2026\nBitte überweisen Sie den Betrag von 49,90 € bis zum\n28.10.2026 auf unser Konto."
        XCTAssertEqual(PaymentDue.find(in: text)?.day, day(2026, 10, 28))
        XCTAssertEqual(PaymentDue.find(in: text)?.amount, "49,90 €", "the amount the sentence names")
    }

    func testTheLastDayGivenIsTheOneToPayBy() {
        // A reminder names the day missed and a new one; a discount's day comes first.
        let reminder = "Mahnung\nDatum 01.11.2026\nUnsere Rechnung war fällig am 28.10.2026.\nBitte zahlen Sie bis zum 10.11.2026."
        XCTAssertEqual(PaymentDue.find(in: reminder)?.day, day(2026, 11, 10))
        let discount = "Datum 14.10.2026\nZahlbar bis 21.10.2026 mit 2 % Skonto (7,39 €)\nZahlbar bis 28.10.2026 ohne Abzug\nGesamt 369,73 €"
        XCTAssertEqual(PaymentDue.find(in: discount)?.day, day(2026, 10, 28))
        XCTAssertEqual(PaymentDue.find(in: discount)?.amount, "369,73 €", "never the discount")
    }

    func testTheAmountToPayIsTheSurestLabelled() {
        let text = "Datum 14.10.2026\nNetto 100,00 €\nMwSt. 19 % 19,00 €\nGesamt 119,00 €\nAnzahlung -50,00 €\nZu zahlen 69,00 €\nZahlbar bis 28.10.2026"
        XCTAssertEqual(PaymentDue.find(in: text)?.amount, "69,00 €")
        XCTAssertNil(PaymentDue.find(in: "Datum 14.10.2026\nZahlbar bis 28.10.2026")?.amount, "none written, none given")
    }

    func testADayBeforeItsCueIsTheOneWhereItSaysSo() {
        let text = "Datum 20.10.2026\nIhr Beitrag in Höhe von 120,00 € ist am 15.11.2026 fällig."
        XCTAssertEqual(PaymentDue.find(in: text)?.day, day(2026, 11, 15))
        XCTAssertEqual(PaymentDue.find(in: text)?.amount, "120,00 €")
        // The document's own date before a cue is no day to pay by.
        XCTAssertNil(PaymentDue.find(in: "Ihre Rechnung vom 14.10.2026 ist fällig."))
    }

    func testNothingIsAskedWhereNothingIsToPay() {
        let debit = "Datum 14.10.2026\nGesamt 49,90 €\nDer Betrag wird am 28.10.2026 von Ihrem Konto abgebucht."
        XCTAssertNil(PaymentDue.find(in: debit), "a direct debit")
        XCTAssertNil(PaymentDue.find(in: "Datum 14.10.2026\nZahlungsart: SEPA-Lastschrift\nFällig am 28.10.2026"))
        XCTAssertNil(PaymentDue.find(in: "Datum 14.10.2026\nDer Saldo ist am 05.11.2026 fällig und wird Ihrem Konto belastet."))
        XCTAssertNil(PaymentDue.find(in: "Gutschrift Nr. 2026-0042\nDatum 14.10.2026\nWir überweisen Ihnen den Betrag bis zum 28.10.2026."))
        XCTAssertNil(PaymentDue.find(in: "Datum 14.10.2026\nZahlbar bis 28.10.2026\nBetrag dankend erhalten."))
        XCTAssertNil(PaymentDue.find(in: "Invoice date: 2026-10-14\nDue date: 2026-10-28\nPAID"))
        // A letter with days, but no payment asked for.
        XCTAssertNil(PaymentDue.find(in: "Sehr geehrte Frau Weber,\nIhr Termin am 28.10.2026 um 9 Uhr ist bestätigt."))
        // Due to the holidays, nothing is due.
        XCTAssertNil(PaymentDue.find(in: "Due to the holidays we are closed on 24.12.2026."))
    }

    func testAReturnedDebitsFeeIsNoDirectDebit() {
        let text = "Datum 14.10.2026\nRücklastschriftgebühr 3,00 €\nGesamt 52,90 €\nBitte überweisen Sie den Betrag bis zum 28.10.2026."
        XCTAssertEqual(PaymentDue.find(in: text)?.day, day(2026, 10, 28))
    }

    func testADayBeforeTheDocumentsOwnIsNoneToPayBy() {
        XCTAssertNil(PaymentDue.find(in: "Datum 14.10.2026\nZahlbar bis 01.10.2026"))
    }

    func testADayIsTheOneInTheOwnersCalendar() throws {
        let due = try XCTUnwrap(day(2026, 10, 28))
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let start = try XCTUnwrap(due.date(in: berlin))
        XCTAssertEqual(berlin.dateComponents([.year, .month, .day, .hour], from: start),
                       DateComponents(year: 2026, month: 10, day: 28, hour: 0))
        XCTAssertEqual(PaymentDue.Day(start, in: berlin), due)
        XCTAssertEqual(due.adding(days: 4), day(2026, 11, 1))
    }
}
