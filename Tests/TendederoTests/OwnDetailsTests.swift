import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The owner's own details: a name in every form it is written, an address
/// by its street with the house number and by its postcode with the town, a
/// card's number whole or by its last four digits after a mask, an IBAN
/// with or without spaces and a German account's number, covered whatever
/// kinds are chosen; and how each is checked, grouped and shown while it is
/// typed. Every name, address and number here is made up: the card numbers
/// and the IBAN are the ones banks print as examples.
final class OwnDetailsTests: XCTestCase {
    private let erika = OwnRule(text: "Erika Musterfrau", kind: .name)
    private let home = OwnRule(text: "Kastanienweg 14", kind: .address, postcode: "24999", city: "Neustadt")
    private let visa = OwnRule(text: "4242 4242 4242 4242", kind: .card)
    private let account = OwnRule(text: "DE89 3704 0044 0532 0130 00", kind: .account)

    private func covered(_ line: String, _ detail: OwnRule) -> [String] {
        OwnDetails.ranges(in: line, of: detail).map { String(line[$0]) }
    }

    // MARK: Names

    func testANameIsFoundInEveryFormItIsWritten() {
        XCTAssertEqual(covered("Patientin: Erika Musterfrau, geb. 17.08.1985", erika), ["Erika Musterfrau"])
        XCTAssertEqual(covered("MUSTERFRAU, ERIKA", erika), ["MUSTERFRAU, ERIKA"])
        XCTAssertEqual(covered("Musterfrau Erika", erika), ["Musterfrau Erika"])
        XCTAssertEqual(covered("E. Musterfrau", erika), ["E. Musterfrau"])
        XCTAssertEqual(covered("Sehr geehrte Frau Musterfrau,", erika), ["Musterfrau"])
        XCTAssertEqual(covered("Hallo Erika, wie geht es?", erika), ["Erika"])
        XCTAssertEqual(covered("erika.musterfrau@example.org", erika), ["erika.musterfrau"])
        XCTAssertEqual(covered("Erika Musterfrav", erika), ["Erika Musterfrav"], "a letter misread")
        XCTAssertEqual(covered("Musterfrau, Erika", OwnRule(text: "Musterfrau, Erika", kind: .name)), ["Musterfrau, Erika"])
        XCTAssertEqual(covered("Erika Musterfrau", OwnRule(text: "Musterfrau, Erika", kind: .name)), ["Erika Musterfrau"],
                       "typed surname first, found as written")
        XCTAssertEqual(covered("Ludwig van Beethoven", OwnRule(text: "Ludwig van Beethoven", kind: .name)),
                       ["Ludwig van Beethoven"])
    }

    func testANameIsNotFoundInOtherWords() {
        XCTAssertEqual(covered("Erik Mustermann", erika), [])
        XCTAssertEqual(covered("die musterfrau des Jahres", erika), [], "a word of it alone in small letters is a word")
        let max = OwnRule(text: "Max Muster", kind: .name)
        XCTAssertEqual(covered("Max. 5 Personen", max), [], "a short given name alone is a word")
        XCTAssertEqual(covered("Max Muster", max), ["Max Muster"])
        XCTAssertEqual(covered("Herr Muster", max), ["Muster"])
        XCTAssertEqual(covered("Meine Mutter", max), [], "a word one letter from a short surname is another word")
        XCTAssertEqual(covered("Frau Musterfrav", erika), ["Musterfrav"], "a long one, misread, is still hers")
    }

    func testANameShowsSomeOfItsForms() {
        XCTAssertEqual(OwnDetails.examples(of: "Erika Musterfrau"), ["Musterfrau, Erika", "E. Musterfrau", "MUSTERFRAU"])
        XCTAssertEqual(OwnDetails.examples(of: "Erika"), [])
    }

    // MARK: Addresses

    func testAnAddressIsFoundByItsStreetAndByItsTown() {
        XCTAssertEqual(covered("Kastanienweg 14", home), ["Kastanienweg 14"])
        XCTAssertEqual(covered("24999 Neustadt", home), ["24999 Neustadt"])
        XCTAssertEqual(covered("Kastanienweg 14,24999 Neustadt", home), ["Kastanienweg 14", "24999 Neustadt"])
        XCTAssertEqual(covered("Kastanien-Weg 14 · D-24999 Neustadt", home), ["Kastanien-Weg 14", "24999 Neustadt"])
        XCTAssertEqual(covered("KASTANIENWEG 14", home), ["KASTANIENWEG 14"])
    }

    func testAnAddressIsNotFoundInAnother() {
        XCTAssertEqual(covered("Kastanienweg 140", home), [])
        XCTAssertEqual(covered("Kastanienweg 14a", home), [], "another house")
        XCTAssertEqual(covered("Kastanienweg 41", home), [])
        XCTAssertEqual(covered("Neustadt", home), [], "a town alone is everyone's")
        XCTAssertEqual(covered("Postleitzahl 24999", home), [], "a postcode alone is everyone's")
        XCTAssertEqual(covered("Kastanienweg 5", OwnRule(text: "Weg 5", kind: .address)), [], "not part of a longer street")
    }

    func testAStreetIsFoundHoweverItIsShortened() {
        let main = OwnRule(text: "Hauptstraße 5", kind: .address)
        XCTAssertEqual(covered("Hauptstr. 5", main), ["Hauptstr. 5"])
        XCTAssertEqual(covered("HAUPTSTRASSE 5", main), ["HAUPTSTRASSE 5"])
        XCTAssertEqual(covered("Lange Straße 7", OwnRule(text: "Lange Str. 7", kind: .address)), ["Lange Straße 7"])
        let paris = OwnRule(text: "12 rue de la Paix", kind: .address, postcode: "75002", city: "Paris")
        XCTAssertEqual(covered("12, rue de la Paix · 75002 Paris", paris), ["12, rue de la Paix", "75002 Paris"])
    }

    func testAStreetIsReadAsItsNameAndNumber() {
        func read(_ typed: String) -> [String] {
            let street = OwnDetails.street(typed)
            return [street.name, street.number]
        }
        XCTAssertEqual(read("Kastanienweg 14a"), ["Kastanienweg", "14a"])
        XCTAssertEqual(read("Hauptstr. 5-7"), ["Hauptstr.", "5-7"])
        XCTAssertEqual(read("221B Baker Street"), ["Baker Street", "221B"])
        XCTAssertEqual(read("12 rue de la Paix"), ["rue de la Paix", "12"])
        XCTAssertEqual(read("Am Markt"), ["Am Markt", ""])
    }

    // MARK: Cards

    func testACardIsFoundWholeHoweverItIsGrouped() {
        XCTAssertEqual(covered("Karte 4242 4242 4242 4242 gültig bis 12/27", visa), ["4242 4242 4242 4242"])
        XCTAssertEqual(covered("4242424242424242", visa), ["4242424242424242"])
        XCTAssertEqual(covered("4242-4242-4242-4242", visa), ["4242-4242-4242-4242"])
        let amex = OwnRule(text: "3782 822463 10005", kind: .card)
        XCTAssertEqual(covered("378282246310005", amex), ["378282246310005"])
    }

    func testACardIsFoundByItsLastFourDigitsWhereTheRestIsHidden() {
        XCTAssertEqual(covered("Visa •••• 4242", visa), ["•••• 4242"])
        XCTAssertEqual(covered("**** **** **** 4242", visa), ["**** **** **** 4242"])
        XCTAssertEqual(covered("XXXX-XXXX-XXXX-4242", visa), ["XXXX-XXXX-XXXX-4242"])
        XCTAssertEqual(covered("Deine Karte endet auf 4242", visa), ["4242"])
        XCTAssertEqual(covered("Mastercard ending in 4242", visa), ["4242"])
    }

    func testACardIsNotFoundInOtherNumbers() {
        XCTAssertEqual(covered("4242 4242 4242 4243", visa), [])
        XCTAssertEqual(covered("Bestellnummer 4242", visa), [], "four digits alone are any number")
        XCTAssertEqual(covered("424242424242424242", visa), [], "not the middle of a longer number")
    }

    func testACardIsCheckedGroupedAndNamedAsTyped() {
        XCTAssertTrue(OwnDetails.passesLuhn("4242424242424242"))
        XCTAssertFalse(OwnDetails.passesLuhn("4242424242424241"))
        XCTAssertNil(OwnDetails.cardProblem("4242 4242 4242 4242"))
        XCTAssertNil(OwnDetails.cardProblem("4242"), "still being typed")
        XCTAssertNotNil(OwnDetails.cardProblem("4242 4242 4242 4241"))
        XCTAssertNotNil(OwnDetails.cardProblem(String(repeating: "4", count: 20)))
        XCTAssertEqual(OwnDetails.grouped(card: "4242424242424242"), "4242 4242 4242 4242")
        XCTAssertEqual(OwnDetails.grouped(card: "378282246310005"), "3782 822463 10005")
        XCTAssertEqual(OwnDetails.grouped(card: "42424"), "4242 4")
        XCTAssertEqual(OwnDetails.brand(of: "4242424242424242"), .visa)
        XCTAssertEqual(OwnDetails.brand(of: "5555555555554444"), .mastercard)
        XCTAssertEqual(OwnDetails.brand(of: "2223003122003222"), .mastercard)
        XCTAssertEqual(OwnDetails.brand(of: "378282246310005"), .amex)
        XCTAssertEqual(OwnDetails.brand(of: "6011111111111117"), .discover)
        XCTAssertEqual(OwnDetails.brand(of: "6759649826438453"), .maestro)
        XCTAssertNil(OwnDetails.brand(of: "1234"))
    }

    // MARK: Accounts

    func testAnAccountIsFoundByItsIBANAndItsNumber() {
        XCTAssertEqual(covered("IBAN: DE89 3704 0044 0532 0130 00", account), ["DE89 3704 0044 0532 0130 00"])
        XCTAssertEqual(covered("IBAN DE89370400440532013000 BIC COBADEFFXXX", account), ["DE89370400440532013000"])
        XCTAssertEqual(covered("DE89 37O4 0044 0532 0130 00", account), ["DE89 37O4 0044 0532 0130 00"],
                       "an O read for a 0")
        XCTAssertEqual(covered("Konto DE89 •••• 3000", account), ["DE89 •••• 3000"])
        XCTAssertEqual(covered("DE89 3704 **** **** **30 00", account), ["DE89 3704 **** **** **30 00"])
        XCTAssertEqual(covered("IBAN: ••••3000", account), ["••••3000"])
        XCTAssertEqual(covered("Kontonummer 532013000 BLZ 37040044", account), ["532013000"])
    }

    func testAnAccountIsNotFoundInAnother() {
        XCTAssertEqual(covered("DE89 3704 0044 0532 0130 01", account), [])
        XCTAssertEqual(covered("Vertrag 5320130001", account), [], "not the start of a longer number")
        XCTAssertEqual(covered("GB82 WEST 1234 5698 7654 32", account), [])
    }

    func testAnIBANIsCheckedAndGroupedAsTyped() {
        XCTAssertTrue(OwnDetails.ibanIsValid("DE89 3704 0044 0532 0130 00"))
        XCTAssertTrue(OwnDetails.ibanIsValid("gb82west12345698765432"))
        XCTAssertFalse(OwnDetails.ibanIsValid("DE89 3704 0044 0532 0130 01"))
        XCTAssertFalse(OwnDetails.ibanIsValid("DE89 3704 0044 0532 0130 0"), "a German IBAN has 22 characters")
        XCTAssertNil(OwnDetails.ibanProblem("DE89 3704"), "still being typed")
        XCTAssertNil(OwnDetails.ibanProblem("DE89 3704 0044 0532 0130 00"))
        XCTAssertNotNil(OwnDetails.ibanProblem("DE88 3704 0044 0532 0130 00"))
        XCTAssertNotNil(OwnDetails.ibanProblem("DE89 3704 0044 0532 0130 000"))
        XCTAssertNotNil(OwnDetails.ibanProblem("1234 5678"))
        XCTAssertEqual(OwnDetails.grouped(iban: "de89370400440532013000"), "DE89 3704 0044 0532 0130 00")
        XCTAssertEqual(OwnDetails.accountNumber(of: "DE89370400440532013000"), "532013000")
        XCTAssertNil(OwnDetails.accountNumber(of: "GB82WEST12345698765432"))
    }

    // MARK: As shown and kept

    func testADetailIsShownWithMostOfItsNumberHidden() {
        XCTAssertEqual(OwnDetails.summary(of: visa), "•••• 4242")
        XCTAssertEqual(OwnDetails.title(of: visa), "Visa")
        XCTAssertEqual(OwnDetails.summary(of: account), "DE89 •••• 3000")
        XCTAssertEqual(OwnDetails.summary(of: home), "Kastanienweg 14, 24999 Neustadt")
        var named = visa
        named.caption = "Privat"
        XCTAssertEqual(OwnDetails.title(of: named), "Privat")
        XCTAssertEqual(OwnDetails.spoken(visa), "Visa, " + String(format: L("ending in %@"), "4242"))
        XCTAssertFalse(OwnDetails.spoken(account).contains("•"))
    }

    func testADetailIsNeverKeptWithTheSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OwnDetailsTests"))
        defaults.removePersistentDomain(forName: "OwnDetailsTests")
        let word = OwnRule(text: "Projekt Nordlicht", kind: .word)
        OwnRules.save([word, erika, visa, account], to: defaults)
        XCTAssertEqual(OwnRules.load(from: defaults), [word])
        let kept = String(decoding: try XCTUnwrap(defaults.data(forKey: OwnRules.key)), as: UTF8.self)
        XCTAssertFalse(kept.contains("Musterfrau") || kept.contains("4242") || kept.contains("DE89"), kept)
    }

    func testRulesKeptBeforeTheDetailsReadAsTheyWere() {
        let old = #"[{"id":"6F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Kundennummer","kind":"label"}]"#
        XCTAssertEqual(OwnRules.decoded(Data(old.utf8)).map(\.text), ["Kundennummer"])
        let later = #"[{"id":"6F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"x","kind":"somethingNew"},"#
            + #"{"id":"7F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Snapfly","kind":"word"}]"#
        XCTAssertEqual(OwnRules.decoded(Data(later.utf8)).map(\.text), ["Snapfly"], "one this version cannot read loses no other")
    }

    func testTheOwnersNameMovesFromAWordToTheirDetailsOnce() {
        let shop = OwnRule(text: "Muster Versand GmbH", kind: .word)
        let word = OwnRule(text: "Erika Musterfrau", kind: .word)
        let moved = OwnRules.adopting([shop, word], details: [visa])
        XCTAssertEqual(moved?.rules, [shop])
        XCTAssertEqual(moved?.details.map(\.kind), [.name, .card])
        XCTAssertEqual(moved?.details.first?.text, "Erika Musterfrau")
        XCTAssertNil(OwnRules.adopting([word], details: [erika]), "a name is there already")
        XCTAssertNil(OwnRules.adopting([word, OwnRule(text: "Jonas Beispiel", kind: .word)], details: []),
                     "two names: no telling which is the owner's")
        XCTAssertNil(OwnRules.adopting([shop], details: []))
    }

    func testTheOwnersDetailsNeverReachTheAssistant() {
        let line = "Erika Musterfrau, Kastanienweg 14, IBAN DE89 3704 0044 0532 0130 00, Lea Probst"
        XCTAssertEqual(OwnDetails.masking(line, [erika, home, account, OwnRule(text: "Projekt", kind: .word)]),
                       "•••, •••, IBAN •••, Lea Probst")
        XCTAssertEqual(OwnDetails.masking(line, []), line)
    }

    func testAChangeToADetailChangesTheChecksumAndShowsNoneOfIt() {
        let sum = OwnDetails.checksum([erika, visa])
        XCTAssertEqual(sum, OwnDetails.checksum([erika, visa]))
        XCTAssertNotEqual(sum, OwnDetails.checksum([erika, account]))
        XCTAssertFalse(sum.contains("4242"))
    }

    // MARK: Covered whatever is chosen

    /// The made-up radiology letter, with nothing chosen at all: only the
    /// owner's name and address are covered, wherever they stand.
    func testTheOwnersDetailsAreCoveredWithNothingChosen() {
        let made = FormFieldsTests.layout(CategoryFidelityTests.letter)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, [], rules: [erika, home])
        let texts = Set(found.hits.map { hit -> String in
            let line = made.strings[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        })
        XCTAssertEqual(texts, ["Erika Musterfrau", "Kastanienweg 14", "24999 Neustadt", "Musterfrau, Erika"])
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == nil && !$0.check }, "the owner's own: covered for sure")
    }

    /// A statement's lines, with nothing chosen: the owner's account and card.
    func testTheOwnersAccountAndCardAreCoveredWithNothingChosen() {
        let lines = ["Kontoauszug Oktober", "IBAN DE89 3704 0044 0532 0130 00", "Kartenzahlung Visa •••• 4242",
                     "Überweisung an DE02 1203 0000 0000 2020 51"]
        let found = Finder.ruleRanges(in: lines.joined(separator: "\n") + "\n", [account, visa])
        let full = lines.joined(separator: "\n") + "\n"
        XCTAssertEqual(found.map { (full as NSString).substring(with: $0) }, ["DE89 3704 0044 0532 0130 00", "•••• 4242"])
    }
}
