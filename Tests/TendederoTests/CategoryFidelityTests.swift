import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Only what Settings chooses is covered, whatever found it: each kind on
/// its own covers nothing of another kind; Names, Patient names and Other
/// people each cover the people their names say; a model's answer never
/// covers what its kind does not fit; the owner's own name is a sure name;
/// a place is covered whole; and a medical term is never a name or an ID.
/// The letter is made up for the tests, laid out as a radiology practice
/// writes one: no name, address or number in it is anyone's.
final class CategoryFidelityTests: XCTestCase {
    typealias Piece = FormFieldsTests.Piece

    /// A radiology report as a letter: the practice's line, the patient's
    /// address, the place and date, the reference, the subject with the date
    /// of birth beside it, the findings, the signatures, and a side column
    /// of headings, doctors, contacts and bank details.
    static let letter: [Piece] = [
        ("RADIOLOGIE NORDTOR Lindenplatz 3, Nordwall 9b, 20999 Hamburg", 0.08, 8),
        ("Erika Musterfrau", 0.08, 9),
        ("Kastanienweg 14", 0.08, 11),
        ("24999 Neustadt", 0.08, 12),
        ("Hamburg, den 12.03.2026", 0.40, 14),
        ("Unser Zeichen: 7654321", 0.08, 15),
        ("Musterfrau, Erika", 0.08, 16),
        ("geb. 17.08.1985", 0.55, 16),
        ("Kastanienweg 14,24999 Neustadt", 0.08, 17),
        ("MRT der Lendenwirbelsäule nativ vom 12.03.2026.", 0.08, 19),
        ("Bilderportal: bilder.radiologie-nordtor.example Referenznummer: QRX482910", 0.08, 20),
        ("Klinik und Fragestellung:", 0.08, 22),
        ("Lumboischialgie links", 0.08, 23),
        ("Befund:", 0.08, 25),
        ("Zum Vergleich liegt keine Untersuchung vor.", 0.08, 26),
        ("An den Abschlussplatten der Wirbelkörper finden sich Residuen eines Morbus", 0.08, 27),
        ("Scheuermann in Form von unregelmäßigen Konturierungen und", 0.08, 28),
        ("Schmorlschen Knötchen. Im Segment LWK 5/SWK 1 zeigt sich ein Signalverlust.", 0.08, 29),
        ("Beurteilung:", 0.08, 31),
        ("1. Mediale Bandscheibenextrusion LWK 5/SWK 1 mit Einengung der S1-Wurzel.", 0.08, 32),
        ("2. Residuen eines Morbus Scheuermann.", 0.08, 33),
        ("Mit freundlichen Grüßen", 0.08, 35),
        ("Dr. med. Jonas Beispiel", 0.08, 37),
        ("Lea Probst", 0.30, 37),
        ("MRT-DIAGNOSTIK", 0.80, 9),
        ("NORDWALL", 0.80, 10),
        ("Telefon 040 3333333-0", 0.80, 12),
        ("info@radiologie-nordtor.example", 0.80, 13),
        ("Ärzte für Radiologie", 0.80, 18),
        ("Dr. med. Jonas Beispiel", 0.80, 19),
        ("Lea Probst", 0.80, 20),
        ("Dt. Apotheker- u. Ärztebank", 0.80, 22),
        ("DE02 1203 0000 0000 2020 51", 0.80, 23),
        ("BYLADEM1001", 0.80, 24),
        ("WEITERER STANDORT", 0.80, 26),
        ("IN HAMBURG", 0.80, 27),
        ("RADIOLOGIE BIRKENHAIN", 0.80, 28),
        ("VOLKSDORF", 0.80, 29),
    ]

    /// What is not a person's name in the letter, and what is never a name
    /// or an ID: places, dates, numbers, headings and medical terms.
    private let neverNames = ["Kastanienweg", "24999", "Neustadt", "Hamburg", "12.03.2026", "17.08.1985", "7654321",
                              "QRX482910", "LWK", "SWK", "Scheuermann", "Schmorl", "S1-Wurzel", "STANDORT", "HAMBURG",
                              "VOLKSDORF", "NORDTOR", "Radiologie", "Lumboischialgie", "DE02", "040"]

    private let medicalTerms = ["LWK", "SWK", "Scheuermann", "Schmorl", "S1-Wurzel", "Morbus", "Lendenwirbelsäule"]

    // MARK: Each kind alone, all, none

    func testEachKindAloneCoversNothingOfAnotherKind() {
        for kind in PrivateDetail.allCases {
            let found = protect(Self.letter, [kind])
            let allowed = Finder.resolved([kind]).chosen
            for place in found.covered + found.offered {
                XCTAssertTrue(Finder.allowed(place.kind, allowed),
                              "\(kind): \(place.text) covered as \(String(describing: place.kind))")
            }
        }
    }

    func testWithNothingChosenNothingIsCovered() {
        let found = protect(Self.letter, [])
        XCTAssertTrue(found.covered.isEmpty, "\(found.covered)")
        XCTAssertTrue(found.offered.isEmpty, "\(found.offered)")
    }

    func testWithEverythingChosenTheLettersDetailsAreCovered() {
        let found = protect(Self.letter, Set(PrivateDetail.allCases))
        for detail in ["Musterfrau, Erika", "Erika Musterfrau", "17.08.1985", "7654321", "QRX482910",
                       "DE02 1203 0000 0000 2020 51", "info@radiologie-nordtor.example", "Jonas Beispiel"] {
            XCTAssertTrue(found.texts.contains { $0.contains(detail) }, "\(detail) in \(found.texts)")
        }
        XCTAssertTrue(found.texts.contains { $0.contains("Kastanienweg 14") }, "the street with its number: \(found.texts)")
    }

    /// The owner's settings when the fault was seen: the names on, the
    /// address, the date of birth, the emails and the phone numbers off.
    func testTheReportedSettingsCoverTheNamesAndNothingElse() {
        let found = protect(Self.letter, [.names, .patientNames, .otherPeople])
        assertOnlyNames(found)
        for name in ["Erika Musterfrau", "Musterfrau, Erika", "Jonas Beispiel", "Lea Probst"] {
            XCTAssertTrue(found.texts.contains(name), "\(name) in \(found.texts)")
        }
        // The patient's name, over an address and beside a date of birth, is sure.
        XCTAssertFalse(found.checked.contains("Erika Musterfrau"), "\(found.checked)")
        XCTAssertFalse(found.checked.contains("Musterfrau, Erika"), "\(found.checked)")
        // A side column's heading in capitals is offered at most, never covered.
        XCTAssertFalse(found.texts.contains { $0.contains("STANDORT") || $0.contains("HAMBURG") }, "\(found.texts)")
    }

    // MARK: Names, Patient names, Other people

    func testNamesAloneCoverEveryonesNameAndNothingElse() {
        let found = protect(Self.letter, [.names])
        assertOnlyNames(found)
        for name in ["Erika Musterfrau", "Musterfrau, Erika", "Jonas Beispiel", "Lea Probst"] {
            XCTAssertTrue(found.texts.contains(name), "\(name) in \(found.texts)")
        }
    }

    func testPatientNamesAloneCoverThePatientOnly() {
        let found = protect(Self.letter, [.patientNames])
        assertOnlyNames(found)
        XCTAssertTrue(found.texts.contains("Erika Musterfrau"), "\(found.texts)")
        XCTAssertTrue(found.texts.contains("Musterfrau, Erika"), "\(found.texts)")
        XCTAssertFalse(found.texts.contains { $0.contains("Beispiel") || $0.contains("Probst") },
                       "the doctors stay: \(found.texts)")
    }

    func testOtherPeopleAloneCoverTheDoctorsNotThePatient() {
        let found = protect(Self.letter, [.otherPeople])
        assertOnlyNames(found)
        XCTAssertTrue(found.texts.contains("Jonas Beispiel"), "\(found.texts)")
        XCTAssertFalse(found.texts.contains { $0.contains("Musterfrau") || $0.contains("Erika") },
                       "the patient stays: \(found.texts)")
    }

    func testNamesCoverWhatBothOfItsKindsCoverTogether() {
        let names = Set(protect(Self.letter, [.names]).texts)
        let both = Set(protect(Self.letter, [.patientNames, .otherPeople]).texts)
        XCTAssertTrue(both.isSubset(of: names), "\(both.subtracting(names))")
    }

    // MARK: The owner's own name

    /// A short note where nothing but the owner's saved name vouches for
    /// the name: no address under it, no date of birth beside it.
    private func note(_ name: [String]) -> [Piece] {
        var pieces: [Piece] = [("Radiologie Nordtor", 0.08, 2), ("Befundbericht", 0.08, 4)]
        for (i, line) in name.enumerated() { pieces.append((line, 0.08, 6 + i)) }
        pieces += [("MRT der Halswirbelsäule", 0.08, 10), ("Beurteilung: kein Nachweis einer Fraktur.", 0.08, 11)]
        return pieces
    }

    private let saved = [OwnRule(text: "Erika Musterfrau", kind: .word)]

    func testTheOwnNameIsASureNameHoweverItIsWritten() {
        let variants: [(lines: [String], covered: [String])] = [
            (["Erika Musterfrau"], ["Erika Musterfrau"]),
            (["Musterfrau, Erika"], ["Musterfrau, Erika"]),
            (["ERIKA MUSTERFRAU"], ["ERIKA MUSTERFRAU"]),
            (["erika musterfrau"], ["erika musterfrau"]),
            (["Erika", "Musterfrau"], ["Erika", "Musterfrau"]),
            (["Erlka Musterfrau"], ["Erlka Musterfrau"]),
            (["Erika Musterfrav"], ["Erika Musterfrav"]),
        ]
        for variant in variants {
            for chosen: Set<PrivateDetail> in [[.names], [.patientNames]] {
                let found = protect(note(variant.lines), chosen, rules: saved)
                for name in variant.covered {
                    XCTAssertTrue(found.covered.contains { $0.text.contains(name) && $0.kind == .names },
                                  "\(chosen): \(name) covered as a name: \(found.covered)")
                    XCTAssertFalse(found.checked.contains { $0.contains(name) }, "\(chosen): \(name) is sure: \(found.checked)")
                }
            }
        }
    }

    func testTheOwnNameOnlyHelpsAndNeverCoversWithoutANameKind() {
        // No name kind on: only the rule's own words, written as saved, are covered.
        let found = protect(note(["Musterfrau, Erika"]), [.health, .addresses], rules: saved)
        XCTAssertFalse(found.covered.contains { $0.kind == .names }, "\(found.covered)")
        XCTAssertFalse(found.texts.contains { $0.contains("Musterfrau") }, "\(found.texts)")
        // With Other people alone, the owner's name in their own medical
        // letter is the patient's, and stays.
        let others = protect(note(["Musterfrau, Erika"]), [.otherPeople], rules: saved)
        XCTAssertFalse(others.texts.contains { $0.contains("Musterfrau") }, "\(others.texts)")
        // It never narrows what is covered: the doctors are still covered.
        let names = protect(Self.letter, [.names], rules: saved)
        XCTAssertTrue(names.texts.contains("Jonas Beispiel"), "\(names.texts)")
        XCTAssertTrue(names.texts.contains("Lea Probst"), "\(names.texts)")
    }

    func testAShortWordOfTheOwnNameInSmallLettersIsJustAWord() {
        let found = protect(note(["Ute Muster", "max. 5 Termine pro Woche"]), [.names],
                            rules: [OwnRule(text: "Ute Max", kind: .word)])
        XCTAssertFalse(found.texts.contains { $0.contains("max") }, "\(found.texts)")
    }

    func testWithoutASavedNameTheNameIsStillCovered() {
        for lines in [["Erika Musterfrau"], ["Musterfrau, Erika"]] {
            let found = protect(note(lines), [.names])
            XCTAssertTrue(found.texts.contains(lines[0]), "\(lines[0]) in \(found.texts)")
        }
    }

    func testOnlyANamesWordRuleIsTheOwnersName() {
        XCTAssertEqual(Finder.ownNames(in: saved), [["erika", "musterfrau"]])
        XCTAssertEqual(Finder.ownNames(in: [OwnRule(text: "Musterfrau, Erika", kind: .word)]), [["musterfrau", "erika"]])
        XCTAssertTrue(Finder.ownNames(in: [OwnRule(text: "Muster Versand GmbH", kind: .word),
                                           OwnRule(text: "Snapfly", kind: .word),
                                           OwnRule(text: "Erika Musterfrau", kind: .label),
                                           OwnRule(text: "SKU-[0-9]+", kind: .pattern),
                                           OwnRule(text: "Zimmer 12", kind: .word)]).isEmpty)
    }

    // MARK: A model's answer

    /// What a small model answers when asked for names alone: everything
    /// private-looking called a name.
    private func answer(_ rows: [(String, PrivateDetail, String)]) -> [Finder.IntelligentPiece] {
        let strings = Self.letter.map(\.text)
        return rows.compactMap { row in
            strings.firstIndex(of: row.0).map { Finder.IntelligentPiece(line: $0, kind: row.1, words: row.2) }
        }
    }

    func testAppleIntelligenceCannotCoverWhatItsKindDoesNotFit() {
        let strings = Self.letter.map(\.text)
        let pieces = answer([
            ("Erika Musterfrau", .names, "Erika"),
            ("Kastanienweg 14", .names, "Kastanienweg"),
            ("24999 Neustadt", .names, "Neustadt"),
            ("Kastanienweg 14,24999 Neustadt", .names, "Kastanienweg"),
            ("Hamburg, den 12.03.2026", .names, "Hamburg"),
            ("geb. 17.08.1985", .names, "17.08.1985"),
            ("Bilderportal: bilder.radiologie-nordtor.example Referenznummer: QRX482910", .names, "QRX482910"),
            ("Schmorlschen Knötchen. Im Segment LWK 5/SWK 1 zeigt sich ein Signalverlust.", .names, "LWK 5/SWK 1"),
            ("Scheuermann in Form von unregelmäßigen Konturierungen und", .names, "Scheuermann"),
            ("2. Residuen eines Morbus Scheuermann.", .names, "Morbus Scheuermann"),
            ("IN HAMBURG", .names, "HAMBURG"),
            ("RADIOLOGIE BIRKENHAIN", .names, "RADIOLOGIE BIRKENHAIN"),
        ])
        XCTAssertEqual(pieces.count, 12)
        let found = Finder.vetted(pieces, in: strings, Finder.resolved([.names, .patientNames, .otherPeople]).chosen)
        let covered = found.hits.map { text($0, in: strings) }
        XCTAssertEqual(covered, ["Erika Musterfrau"], "only the name, whole")
        let offered = found.possible.map { text($0, in: strings) }
        for kept in neverNames {
            XCTAssertFalse(offered.contains { $0.contains(kept) }, "\(kept) is no name: \(offered)")
        }
    }

    func testAModelsKindIsCheckedForEveryKind() {
        let strings = Self.letter.map(\.text)
        let pieces = answer([
            ("Schmorlschen Knötchen. Im Segment LWK 5/SWK 1 zeigt sich ein Signalverlust.", .ids, "LWK 5/SWK 1"),
            ("Bilderportal: bilder.radiologie-nordtor.example Referenznummer: QRX482910", .ids, "QRX482910"),
            ("Schmorlschen Knötchen. Im Segment LWK 5/SWK 1 zeigt sich ein Signalverlust.", .health, "LWK 5/SWK 1"),
            ("Hamburg, den 12.03.2026", .addresses, "Hamburg"),
            ("Kastanienweg 14", .addresses, "Kastanienweg"),
            ("geb. 17.08.1985", .birthDates, "17.08.1985"),
            ("Lumboischialgie links", .birthDates, "Lumboischialgie"),
            ("Telefon 040 3333333-0", .phones, "040 3333333-0"),
            ("Unser Zeichen: 7654321", .phones, "Unser Zeichen"),
            ("DE02 1203 0000 0000 2020 51", .bank, "1203 0000"),
        ])
        let all = Finder.vetted(pieces, in: strings, Set(PrivateDetail.allCases))
        let covered = all.hits.map { "\($0.kind!.rawValue): \(text($0, in: strings))" }
        XCTAssertEqual(Set(covered), [
            "ids: QRX482910", "health: LWK 5/SWK 1", "addresses: Kastanienweg 14", "birthDates: 17.08.1985",
            "phones: 040 3333333-0", "bank: DE02 1203 0000 0000 2020 51",
        ])
        // A kind that is off is never kept, however well it fits.
        let none = Finder.vetted(pieces, in: strings, [.names])
        XCTAssertTrue(none.hits.isEmpty && none.possible.isEmpty, "\(none.hits) \(none.possible)")
    }

    // MARK: The whole entity

    func testAPlaceIsCoveredWhole() {
        let line = "Kastanienweg 14,24999 Neustadt"
        func whole(_ part: String, _ kind: PrivateDetail?, in line: String, widely: Bool = false) -> String {
            let range = line.range(of: part)!
            return String(line[Finder.wholeEntity(range, kind: kind, in: line, widely: widely)])
        }
        // Never part of a word or a number.
        XCTAssertEqual(whole("tanien", .names, in: line), "Kastanienweg")
        XCTAssertEqual(whole("499", .ids, in: line), "24999")
        // A street with its number; a postcode with its town.
        XCTAssertEqual(whole("Kastanienweg", .addresses, in: line), "Kastanienweg 14")
        XCTAssertEqual(whole("Neustadt", .addresses, in: line), "24999 Neustadt")
        // A model's part of a name, or of a number, is the whole of it.
        XCTAssertEqual(whole("Erika", .names, in: "Frau Erika Musterfrau kam heute", widely: true), "Erika Musterfrau")
        XCTAssertEqual(whole("Erika", .names, in: "Musterfrau, Erika", widely: true), "Musterfrau, Erika")
        XCTAssertEqual(whole("1203 0000", .bank, in: "IBAN DE02 1203 0000 0000 2020 51", widely: true),
                       "DE02 1203 0000 0000 2020 51")
    }

    func testNoHouseNumberIsLeftBesideACoveredStreet() {
        let found = protect(Self.letter, [.addresses])
        let streets = found.texts.filter { $0.contains("Kastanienweg") }
        XCTAssertFalse(streets.isEmpty, "\(found.texts)")
        for street in streets {
            XCTAssertTrue(street.contains("Kastanienweg 14"), "the number with its street: \(street)")
        }
    }

    // MARK: Medical terms

    func testNoMedicalTermIsCoveredAsANameOrANumber() {
        let kinds: [Set<PrivateDetail>] = [[.names], [.patientNames], [.otherPeople], [.patientNames, .otherPeople],
                                           [.ids], [.orders], [.codes], [.names, .ids, .orders, .codes, .tracking]]
        for chosen in kinds {
            let found = protect(Self.letter, chosen)
            for term in medicalTerms {
                XCTAssertFalse(found.texts.contains { $0.contains(term) }, "\(chosen): \(term) in \(found.texts)")
                XCTAssertFalse(found.offeredTexts.contains { $0.contains(term) }, "\(chosen): \(term) in \(found.offeredTexts)")
            }
        }
    }

    func testMedicalTermsAreFound() {
        func terms(_ line: String, medical: Bool = true) -> [String] {
            DocumentSense.medicalRanges(in: line, medical: medical).map { String(line[$0]) }
        }
        XCTAssertTrue(terms("Im Segment LWK 5/SWK 1 zeigt sich").contains("LWK 5/SWK 1"))
        XCTAssertTrue(terms("Residuen eines Morbus Scheuermann.").contains("Morbus Scheuermann"))
        XCTAssertTrue(terms("Schmorlschen Knötchen im Segment").contains("Schmorlschen Knötchen"))
        XCTAssertTrue(terms("Protrusion L5/S1 mit Einengung der S1-Wurzel").contains("L5/S1"))
        XCTAssertTrue(terms("Protrusion L5/S1 mit Einengung der S1-Wurzel").contains("S1-Wurzel"))
        XCTAssertTrue(terms("Diagnose: M51.2 G").contains("M51.2 G"))
        // Short codes only in a medical document; people stay people.
        XCTAssertTrue(terms("Platz L5/S1", medical: false).isEmpty)
        XCTAssertTrue(terms("Dr. med. Jonas Beispiel und Erika Musterfrau").isEmpty)
    }

    // MARK: Helpers

    private func assertOnlyNames(_ found: Found, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(found.covered.allSatisfy { $0.kind == .names }, "only names: \(found.covered)", file: file, line: line)
        for kept in neverNames {
            XCTAssertFalse(found.texts.contains { $0.contains(kept) }, "\(kept) stays: \(found.texts)", file: file, line: line)
        }
    }

    private struct Found {
        var covered: [(text: String, kind: PrivateDetail?)]
        var offered: [(text: String, kind: PrivateDetail?)]
        var checked: [String]
        var texts: [String] { covered.map(\.text) }
        var offeredTexts: [String] { offered.map(\.text) }
    }

    private func text(_ hit: Finder.Hit, in strings: [String]) -> String {
        let line = strings[hit.line]
        return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
    }

    /// What the engine covers, offers and marks to check in a made-up page,
    /// as text, with the chosen kinds and the owner's rules.
    private func protect(_ pieces: [Piece], _ chosen: Set<PrivateDetail>, rules: [OwnRule] = []) -> Found {
        let made = FormFieldsTests.layout(pieces)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, chosen, rules: rules)
        return Found(covered: found.hits.map { (text($0, in: made.strings), $0.kind) },
                     offered: found.possible.map { (text($0, in: made.strings), $0.kind) },
                     checked: found.hits.filter(\.check).map { text($0, in: made.strings) })
    }
}
