import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Always Hide: the owner's details and rules as Snapfly keeps them, the
/// ways a name is shown and looked for, which are the same list, what is
/// found however a page prints it, covered for sure whatever kinds are
/// chosen, a rule turned off, a label's reach, the made-up page that shows
/// a rule, and what may be kept. Every name, address and number is made up:
/// the cards and IBANs are the ones banks print as examples.
final class AlwaysHideTests: XCTestCase {
    private let max = OwnRule(text: OwnDetails.nameText(given: "Max", surname: "Mustermann"), kind: .name)
    private let home = OwnRule(text: "Musterstraße 12", kind: .address, postcode: "12345", city: "Musterstadt")
    private let visa = OwnRule(text: "4242424242424242", kind: .card)
    private let account = OwnRule(text: "DE89370400440532013000", kind: .account)

    private func covered(_ line: String, _ detail: OwnRule) -> [String] {
        OwnDetails.ranges(in: line, of: detail).map { String(line[$0]) }
    }

    /// Lines one under another, as a page prints them.
    private func page(_ lines: [String]) -> (strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?) {
        FormFieldsTests.layout(lines.enumerated().map { (text: $0.element, x: 0.1, row: $0.offset) })
    }

    /// What the owner's details cover in text of many lines, each part of a
    /// line as it is covered there.
    private func covered(lines: [String], _ rules: [OwnRule]) -> [String] {
        let full = lines.joined(separator: "\n") + "\n"
        return Finder.ruleRanges(in: full, rules).sorted { $0.location < $1.location }
            .map { (full as NSString).substring(with: $0) }
    }

    // MARK: Kept before

    func testRulesKeptBeforeTheSwitchReadAsTheyWereOnAndAutomatic() {
        let old = #"[{"id":"6F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Kundennummer","kind":"label"},"#
            + #"{"id":"7F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Projekt Nordlicht","kind":"word"}]"#
        let rules = OwnRules.decoded(Data(old.utf8))
        XCTAssertEqual(rules.map(\.text), ["Kundennummer", "Projekt Nordlicht"])
        XCTAssertEqual(rules.map(\.isEnabled), [true, true])
        XCTAssertEqual(rules.first?.reach, .automatic, "a label decides as it always did")
        XCTAssertEqual(rules.first?.id.uuidString, "6F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B")
    }

    func testARuleTurnedOffAndItsReachAreKept() throws {
        var label = OwnRule(text: "Aktenzeichen", kind: .label)
        label.reach = .nextLine
        label.isEnabled = false
        let back = OwnRules.decoded(try JSONEncoder().encode([label]))
        XCTAssertEqual(back, [label])
    }

    func testAReachALaterVersionMadeReadsAsAutomaticAndTheRuleStays() {
        let later = #"[{"id":"6F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Kundennummer","kind":"label","reach":"twoLines","isEnabled":false}]"#
        let rules = OwnRules.decoded(Data(later.utf8))
        XCTAssertEqual(rules.map(\.reach), [.automatic])
        XCTAssertEqual(rules.map(\.isEnabled), [false])
    }

    func testDetailsKeptBeforeReadAsTheyWere() {
        // As the keychain holds them since the details came: no switch, no reach.
        let kept = #"[{"id":"1F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"Erika Musterfrau","kind":"name","postcode":"","city":"","caption":""},"#
            + #"{"id":"2F1E8E0A-4D3B-4B0E-9C7B-1C2D3E4F5A6B","text":"4242424242424242","kind":"card","postcode":"","city":"","caption":"Privat"}]"#
        let details = OwnRules.decoded(Data(kept.utf8))
        XCTAssertEqual(details.map(\.text), ["Erika Musterfrau", "4242424242424242"])
        XCTAssertEqual(details.map(\.caption), ["", "Privat"])
        XCTAssertTrue(details.allSatisfy { $0.isEnabled && $0.isActive })
        XCTAssertEqual(OwnDetails.displayName(details[0].text), "Erika Musterfrau")
    }

    func testANameTypedOnOneLineBeforeOpensInItsTwoFields() {
        func parts(_ text: String) -> [String] {
            let parts = OwnDetails.nameParts(text)
            return [parts.given.joined(separator: " "), parts.surname.joined(separator: " ")]
        }
        XCTAssertEqual(parts("Erika Musterfrau"), ["Erika", "Musterfrau"])
        XCTAssertEqual(parts("Anna Maria Musterfrau"), ["Anna Maria", "Musterfrau"])
        XCTAssertEqual(parts("Ludwig van Beethoven"), ["Ludwig", "van Beethoven"])
        XCTAssertEqual(parts("Musterfrau, Erika"), ["Erika", "Musterfrau"])
        XCTAssertEqual(parts("Erika"), ["", "Erika"], "one word alone is a surname")
        XCTAssertEqual(OwnDetails.nameText(given: " Max ", surname: "Mustermann"), "Mustermann, Max")
        XCTAssertEqual(parts(OwnDetails.nameText(given: "Max", surname: "")), ["Max", ""], "a given name alone stays one")
        XCTAssertEqual(OwnDetails.nameText(given: "", surname: "Mustermann"), "Mustermann")
        XCTAssertEqual(OwnDetails.displayName(OwnDetails.nameText(given: "Max", surname: "Mustermann")), "Max Mustermann")
    }

    // MARK: The ways of a name

    func testTheSheetShowsTheWaysTheCoveringLooksFor() {
        let variants = OwnDetails.nameVariants(max.text)
        XCTAssertEqual(variants, ["Max Mustermann", "MUSTERMANN, Max", "Mustermann, Max", "M. Mustermann",
                                  "Mustermann, M.", "Mustermann"])
        // The covering's forms are these, and only these.
        let folded = Set(variants.map { $0.replacingOccurrences(of: ",", with: " ")
                .split(separator: " ").map { OwnDetails.fold(String($0)) } })
        XCTAssertEqual(Set(OwnDetails.nameForms(max.text)), folded)
        XCTAssertEqual(OwnDetails.nameVariants(OwnDetails.nameText(given: "Erika", surname: "Musterfrau")).last, "Erika",
                       "a given name of four letters or more alone too")
        XCTAssertEqual(OwnDetails.nameVariants(OwnDetails.nameText(given: "", surname: "Mustermann")),
                       ["Mustermann", "MUSTERMANN"])
        XCTAssertEqual(OwnDetails.nameVariants(""), [])
    }

    func testEveryWayTheSheetShowsIsFound() {
        for detail in [max, OwnRule(text: OwnDetails.nameText(given: "Anna Maria", surname: "von Musterfrau"), kind: .name)] {
            for variant in OwnDetails.nameVariants(detail.text) {
                // An initial's dot after the name is no part of it.
                let shown = variant.hasSuffix(".") ? String(variant.dropLast()) : variant
                XCTAssertEqual(covered("Seite 2 · \(variant) · Datum", detail), [shown], variant)
            }
        }
    }

    func testANameIsFoundInCapitalsOverTwoLinesAndWithALetterMisread() {
        XCTAssertEqual(covered("MAX MUSTERMANN", max), ["MAX MUSTERMANN"])
        XCTAssertEqual(covered("max mustermann", max), ["max mustermann"], "two words of it together in any case")
        XCTAssertEqual(covered("MUSTERMANN/MAX", max), ["MUSTERMANN/MAX"], "as a ticket prints it")
        XCTAssertEqual(covered("Max Mustermarn", max), ["Max Mustermarn"], "a letter misread")
        XCTAssertEqual(covered("Herr Musterman", max), ["Musterman"], "a letter left out, in a long surname alone")
        XCTAssertEqual(covered(lines: ["Rechnung an: Max", "Mustermann, Musterstadt"], [max]), ["Max\nMustermann"],
                       "broken over two lines")
    }

    func testTwoLettersMisreadAreAnotherName() {
        XCTAssertEqual(covered("Mox Mustermarn", max), ["Mustermarn"],
                       "one letter in each word: not the whole name, but the long surname alone still")
        XCTAssertEqual(covered("Herr Musterrnann", max), [], "'rn' for 'm' is two")
        XCTAssertEqual(covered("Meine Mutter", OwnRule(text: "Max Muster", kind: .name)), [],
                       "a short surname alone takes no misread letter")
    }

    // MARK: Numbers and addresses

    func testAnIBANIsFoundWithAndWithoutSpacesOverTwoLinesAndMisread() {
        XCTAssertEqual(covered("DE89 3704 0044 0532 0130 00", account), ["DE89 3704 0044 0532 0130 00"])
        XCTAssertEqual(covered("DE89370400440532013000", account), ["DE89370400440532013000"])
        XCTAssertEqual(covered("de89 3704 0044 0532 0130 00", account), ["de89 3704 0044 0532 0130 00"], "in small letters")
        XCTAssertEqual(covered("DE89 3704 0044 0532 0180 00", account), ["DE89 3704 0044 0532 0180 00"],
                       "a digit misread: no other IBAN is one character from it")
        XCTAssertEqual(covered(lines: ["IBAN: DE89 3704 0044", "0532 0130 00"], [account]), ["DE89 3704 0044\n0532 0130 00"])
        XCTAssertEqual(covered("DE89 3704 0044 0532 0180 01", account), [], "two characters off")
        XCTAssertEqual(covered("DE02 1203 0000 0000 2020 51", account), [], "another account")
    }

    func testACardIsFoundOverTwoLinesAndWithADigitMisread() {
        XCTAssertEqual(covered("4242 4242 4242 4243", visa), ["4242 4242 4242 4243"],
                       "no other card's number is one digit from it")
        XCTAssertEqual(covered(lines: ["Karte 4242 4242", "4242 4242 gültig bis 12/27"], [visa]), ["4242 4242\n4242 4242"])
        XCTAssertEqual(covered("4000 0566 5566 5556", visa), [], "another card")
        XCTAssertEqual(covered("4242 4242 4242 4233", visa), [], "two digits off")
    }

    func testAStreetOrATownMisreadByALetterIsStillFound() {
        XCTAssertEqual(covered("Mustcrstraße 12", home), ["Mustcrstraße 12"])
        XCTAssertEqual(covered("12345 Musterstodt", home), ["12345 Musterstodt"])
        XCTAssertEqual(covered("Musterstr. 12", home), ["Musterstr. 12"], "shortened")
        XCTAssertEqual(covered("Musterstraße 13", home), [], "never a misread house number: another house")
        XCTAssertEqual(covered("12346 Musterstadt", home), [], "nor another postcode")
    }

    // MARK: Covered for sure

    /// A made-up letter to the owner, with every kind off: every way of
    /// their name, their address, card and IBAN are covered, for sure, and
    /// nothing else is.
    func testTheOwnersDetailsAreCoveredForSureWithEveryKindOff() {
        let lines = ["Muster Versand GmbH · Lindenallee 3 · 54321 Beispielstadt",
                     "Herrn Max Mustermann", "Musterstraße 12", "12345 Musterstadt",
                     "Kundenkonto: MUSTERMANN, Max", "Sehr geehrter Herr Mustermann,",
                     "Ihre Karte 4242 4242 4242 4242 und Ihr Konto DE89 3704 0044 0532 0130 00",
                     "wurden geprüft. Mit freundlichen Grüßen", "Lena Probst"]
        let made = page(lines)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, [], rules: [max, home, visa, account])
        let texts = found.hits.map { hit -> String in
            let line = made.strings[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
        XCTAssertEqual(Set(texts), ["Max Mustermann", "Musterstraße 12", "12345 Musterstadt", "MUSTERMANN, Max", "Mustermann",
                                    "4242 4242 4242 4242", "DE89 3704 0044 0532 0130 00"])
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == nil && !$0.check }, "the owner's own: covered for sure")
        XCTAssertTrue(found.possible.isEmpty)
    }

    /// With names on, the owner's name is covered as theirs, never to check,
    /// and the other people's names are as the switches say.
    func testWhatTheOwnersDetailsCoverIsNeverToCheck() {
        let lines = ["Termin mit Max Mustermann und Lena Probst", "am Montag um 9 Uhr"]
        let made = page(lines)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, PrivateDetail.allNames, rules: [max])
        let mine = found.hits.filter { hit in
            hit.range.flatMap { Range($0, in: made.strings[hit.line]) }.map { made.strings[hit.line][$0].contains("Mustermann") } == true
        }
        XCTAssertFalse(mine.isEmpty)
        XCTAssertTrue(mine.allSatisfy { !$0.check })
    }

    // MARK: Rules

    func testARuleTurnedOffCoversNothing() {
        var word = OwnRule(text: "Projekt Nordlicht", kind: .word)
        var label = OwnRule(text: "Kundennummer", kind: .label)
        let lines = ["Projekt Nordlicht", "Kundennummer: 48213"]
        let made = page(lines)
        func found() -> Int {
            Finder.findings(made.strings, boxes: made.boxes, part: made.part, [], rules: [word, label]).hits.count
        }
        XCTAssertEqual(found(), 2)
        word.isEnabled = false
        label.isEnabled = false
        XCTAssertEqual(found(), 0)
        XCTAssertTrue(Finder.ruleRanges(in: "Projekt Nordlicht\n", [word]).isEmpty)
        XCTAssertTrue(Finder.ownNames(in: [OwnRule(text: "Erika Musterfrau", kind: .word, isEnabled: false)]).isEmpty,
                      "a name kept as a word, turned off, is no one's own")
    }

    func testTheOwnersDetailsHaveNoSwitch() {
        var name = max
        name.isEnabled = false
        XCTAssertTrue(name.isActive, "always on")
        XCTAssertEqual(covered(lines: ["Max Mustermann"], [name]), ["Max Mustermann"])
    }

    func testALabelCoversWhatItsReachSays() {
        let lines = ["Kundennummer: 48213", "Aktenzeichen", "AZ 7-1024", "Kundennummer", "99 100"]
        let made = page(lines)
        func covered(_ reach: OwnRule.Reach, _ text: String) -> [String] {
            var rule = OwnRule(text: text, kind: .label)
            rule.reach = reach
            return Finder.findings(made.strings, boxes: made.boxes, part: made.part, [], rules: [rule]).hits.map { hit in
                let line = made.strings[hit.line]
                return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
            }.sorted()
        }
        XCTAssertEqual(covered(.automatic, "Kundennummer"), ["48213", "99 100"], "the rest, else the line below")
        XCTAssertEqual(covered(.restOfLine, "Kundennummer"), ["48213"])
        XCTAssertEqual(covered(.nextLine, "Kundennummer"), ["99 100", "Aktenzeichen"])
        XCTAssertEqual(covered(.automatic, "Aktenzeichen"), ["AZ 7-1024"])
        XCTAssertEqual(covered(.restOfLine, "Aktenzeichen"), [], "nothing follows it on its line")
    }

    func testTheSamplePageShowsWhatTheRuleCovers() throws {
        var label = OwnRule(text: "Kundennummer", kind: .label)
        let rest = try XCTUnwrap(RuleSample.of(label))
        XCTAssertEqual(rest.lines.count, 3)
        let line = rest.lines[1]
        XCTAssertEqual(line.text, "Kundennummer: " + RuleSample.value)
        XCTAssertEqual(line.covered.map { String(line.text[$0]) }, [RuleSample.value])
        XCTAssertFalse(rest.lines[0].whole || rest.lines[2].whole)
        label.reach = .nextLine
        let below = try XCTUnwrap(RuleSample.of(label))
        XCTAssertEqual(below.lines.map(\.whole), [false, false, true, false])
        let word = try XCTUnwrap(RuleSample.of(OwnRule(text: "Nordlicht", kind: .word)))
        XCTAssertEqual(word.lines.map { line in line.covered.map { String(line.text[$0]) } }, [["Nordlicht"], ["NORDLICHT"]],
                       "in any case")
        XCTAssertTrue(word.coversSomething)
        XCTAssertNil(RuleSample.of(OwnRule(text: "SKU-[0-9]+", kind: .pattern)))
        XCTAssertNil(RuleSample.of(OwnRule(text: " ", kind: .word)))
        XCTAssertFalse(below.lines[2].spoken.contains(RuleSample.value), "VoiceOver says it is covered")
    }

    func testWhatGoesToTheAssistantHasTheRulesAndDetailsHidden() {
        var label = OwnRule(text: "Kundennummer", kind: .label)
        label.reach = .automatic
        let lines = ["Max Mustermann", "Projekt Nordlicht, intern", "Kundennummer: 48213", "Kundennummer", "99 100",
                     "mustermann@example.org", "Lena Probst"]
        let masked = Finder.masking(lines, [max, OwnRule(text: "Projekt Nordlicht", kind: .word), label])
        XCTAssertEqual(masked, ["•••", "•••, intern", "Kundennummer: •••", "Kundennummer", "•••", "•••@example.org",
                                "Lena Probst"])
        var off = OwnRule(text: "Projekt Nordlicht", kind: .word)
        off.isEnabled = false
        XCTAssertEqual(Finder.masking(["Projekt Nordlicht"], [off]), ["Projekt Nordlicht"], "a rule turned off hides nothing")
    }

    func testTheFingerprintChangesWithARuleTurnedOffOrItsReach() {
        var label = OwnRule(text: "Kundennummer", kind: .label)
        let before = OwnRules.fingerprint(of: [label])
        XCTAssertEqual(before, "label:Kundennummer", "as before for a label that decides as it always did")
        label.reach = .nextLine
        XCTAssertNotEqual(OwnRules.fingerprint(of: [label]), before)
        label.isEnabled = false
        XCTAssertEqual(OwnRules.fingerprint(of: [label]), "")
    }

    func testAWordToCoverAlwaysTurnsOnTheOneTurnedOff() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AlwaysHideTests"))
        defaults.removePersistentDomain(forName: "AlwaysHideTests")
        var word = OwnRule(text: "Nordlicht", kind: .word)
        word.isEnabled = false
        OwnRules.save([word], to: defaults)
        OwnRules.add(word: "nordlicht", to: defaults)
        XCTAssertEqual(OwnRules.load(from: defaults).map(\.isEnabled), [true])
        XCTAssertEqual(OwnRules.load(from: defaults).count, 1)
    }

    // MARK: What may be kept, and how it shows

    func testOnlyANumberThatAddsUpIsKept() {
        XCTAssertTrue(OwnDetails.canKeep(visa))
        XCTAssertFalse(OwnDetails.canKeep(OwnRule(text: "4242 4242 4242 4241", kind: .card)), "does not add up")
        XCTAssertFalse(OwnDetails.canKeep(OwnRule(text: "4242 4242", kind: .card)), "too short for a card")
        XCTAssertTrue(OwnDetails.canKeep(account))
        XCTAssertFalse(OwnDetails.canKeep(OwnRule(text: "DE88 3704 0044 0532 0130 00", kind: .account)))
        XCTAssertTrue(OwnDetails.canKeep(max))
        XCTAssertTrue(OwnDetails.canKeep(OwnRule(text: OwnDetails.nameText(given: "Max", surname: ""), kind: .name)))
        XCTAssertFalse(OwnDetails.canKeep(OwnRule(text: OwnDetails.nameText(given: " ", surname: " "), kind: .name)))
        XCTAssertFalse(OwnDetails.canKeep(OwnRule(text: ",", kind: .name)))
    }

    func testARowShowsANumberByItsLastFourDigits() {
        XCTAssertEqual(OwnDetails.masked(visa), "•••• •••• •••• 4242")
        XCTAssertEqual(OwnDetails.masked(account), "DE•• •••• •••• 3000")
        XCTAssertEqual(OwnDetails.masked(max), "Max Mustermann")
        XCTAssertFalse(OwnDetails.masked(account).contains("89"), "not even the check digits")
    }
}
