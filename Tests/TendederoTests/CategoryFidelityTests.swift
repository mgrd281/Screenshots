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

    func testAllThreeCoverEveryonesNameAndNothingElse() {
        let found = protect(Self.letter, PrivateDetail.allNames)
        assertOnlyNames(found)
        for name in ["Erika Musterfrau", "Musterfrau, Erika", "Jonas Beispiel", "Lea Probst"] {
            XCTAssertTrue(found.texts.contains(name), "\(name) in \(found.texts)")
        }
    }

    /// Names alone covers the names whose role is not clear, and no one the
    /// words round a name tell: not the patient, not a doctor.
    func testNamesAloneCoverOnlyTheNamesWhoseRoleIsNotClear() {
        let found = protect(Self.letter, [.names])
        assertOnlyNames(found)
        XCTAssertFalse(found.texts.contains { $0.contains("Musterfrau") || $0.contains("Beispiel") || $0.contains("Probst") },
                       "every role here is clear: \(found.texts)")
        // A name with nothing round it to say whose it is, vouched for by its
        // email, is covered with Names, and sure; with Patient names alone
        // too, and marked for checking.
        let card: [Piece] = [("Lena Weber", 0.08, 2), ("lena.weber@example.com", 0.08, 3)]
        let names = protect(card, [.names])
        XCTAssertEqual(names.texts, ["Lena Weber"])
        XCTAssertEqual(names.checked, [])
        let patients = protect(card, [.patientNames])
        XCTAssertEqual(patients.texts, ["Lena Weber"])
        XCTAssertEqual(patients.checked, ["Lena Weber"])
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

    func testTheThreeTogetherCoverWhatEachCoversAlone() {
        let all = Set(protect(Self.letter, PrivateDetail.allNames).texts)
        let each = PrivateDetail.allNames.reduce(into: Set<String>()) { $0.formUnion(protect(Self.letter, [$1]).texts) }
        XCTAssertEqual(all, each)
    }

    /// Names, Patient names and Other people are three switches, each
    /// turned on and off by itself: none turns another, and each covers its
    /// own people. Together they cover what each of them covers alone.
    func testNamesAndItsTwoPartsAreEachTheirOwnSwitch() {
        let kinds: [PrivateDetail] = [.names, .patientNames, .otherPeople]
        func covered(_ chosen: Set<PrivateDetail>) -> Set<String> { Set(protect(Self.letter, chosen).texts) }
        let alone = Dictionary(uniqueKeysWithValues: kinds.map { ($0, covered([$0])) })
        for mask in 1..<(1 << kinds.count) {
            let chosen = Set(kinds.indices.filter { mask & (1 << $0) != 0 }.map { kinds[$0] })
            let each = chosen.reduce(into: Set<String>()) { $0.formUnion(alone[$1] ?? []) }
            XCTAssertEqual(covered(chosen), each, "\(chosen.map(\.rawValue).sorted())")
        }
        // Names alone covers neither the patient nor a doctor; each part, its own.
        XCTAssertFalse(alone[.names]?.contains { $0.contains("Musterfrau") || $0.contains("Beispiel") } ?? true, "\(alone)")
        XCTAssertTrue(alone[.patientNames]?.contains("Erika Musterfrau") == true, "\(alone)")
        XCTAssertFalse(alone[.patientNames]?.contains { $0.contains("Beispiel") } ?? true)
        XCTAssertTrue(alone[.otherPeople]?.contains("Jonas Beispiel") == true, "\(alone)")
        XCTAssertFalse(alone[.otherPeople]?.contains { $0.contains("Musterfrau") } ?? true)
    }

    // MARK: The fault the owner saw

    /// A radiology practice's answer to the doctor who referred the
    /// patient, laid out as such letters are: the practice's line over the
    /// referring practice's address, the practice's contacts, a column of
    /// its doctors with one written without "Dr. med.", the date and
    /// reference, the greeting to the colleague, and the patient with a
    /// date of birth and a first name no list knows. Made up.
    static let referral: [Piece] = [
        ("Radiologie Nordtor | Lindenplatz 3 | 20999 Hamburg", 0.08, 8),
        ("Gemeinschaftspraxis", 0.08, 9),
        ("Dr. med. Paul Beispiel", 0.08, 10),
        ("Ahornweg 26", 0.08, 11),
        ("24999 Neustadt", 0.08, 12),
        ("Radiologie Nordtor", 0.45, 8),
        ("Lindenplatz 3", 0.45, 9),
        ("20999 Hamburg", 0.45, 10),
        ("Tel. 040 - 33 33 33 33", 0.45, 11),
        ("Dr. med. Lena Probst", 0.75, 8),
        ("Dr. med. Karl Muster", 0.75, 9),
        ("Tom Lorenz", 0.75, 10),
        ("Dr. med. Hanna Vogel", 0.75, 11),
        ("PD Dr. med. Felix Brandt", 0.75, 12),
        ("Hamburg, den 28.09.2025", 0.65, 14),
        ("1234567", 0.75, 15),
        ("Sehr geehrter Herr Kollege Beispiel,", 0.08, 16),
        ("vielen Dank für die freundliche Überweisung Ihres Patienten:", 0.08, 18),
        ("Herr Zorvak Musteryan, geb. am 05.03.1990", 0.08, 19),
        ("Indikation:", 0.08, 21),
        ("Ausgeprägte therapierefraktäre Schmerzen linksseitigen Lumboischialgien seit 10 Tagen.", 0.08, 22),
        ("Magnetresonanztomographie der Lendenwirbelsäule nativ vom 28.09.2025", 0.08, 24),
        ("Befund:", 0.08, 26),
        ("Flach linkskonvexe Skoliose. Reguläre lumbale Wirbelkörperhöhen.", 0.08, 27),
        ("Beurteilung:", 0.08, 29),
        ("1. Wurzelbedrängung S1 links im Segment L5/S1 bei Osteochondrose.", 0.08, 30),
        ("3. Scheuermann'sche Residuen lumbal.", 0.08, 31),
        ("Das Bildmaterial wurde mitgegeben.", 0.08, 33),
    ]

    private let doctors = ["Paul Beispiel", "Lena Probst", "Karl Muster", "Tom Lorenz", "Hanna Vogel", "Felix Brandt"]

    /// The owner's settings when the fault was seen: Names on, Patient
    /// names and Other people off, and their own name saved. Only their own
    /// name is covered: no doctor, not the colleague the letter greets.
    func testNamesAloneWithTheOwnNameCoverTheOwnNameAndNoOneElse() {
        for kind in [OwnRule.Kind.name, .word] {
            let found = protect(Self.referral, [.names], rules: [OwnRule(text: "Zorvak Musteryan", kind: kind)])
            XCTAssertTrue(found.texts.contains("Zorvak Musteryan"), "\(kind): \(found.texts)")
            for name in doctors + ["Beispiel"] {
                XCTAssertFalse(found.texts.contains { $0.contains(name) }, "\(kind): \(name) stays: \(found.texts)")
            }
            XCTAssertFalse(found.texts.contains { $0.contains("Herr") }, "\(kind): \(found.texts)")
        }
    }

    func testTheReferralsPatientAndDoctorsAreEachTheirOwn() {
        let patients = protect(Self.referral, [.patientNames]).texts
        XCTAssertTrue(patients.contains("Zorvak Musteryan"), "\(patients)")
        for name in doctors + ["Beispiel"] {
            XCTAssertFalse(patients.contains { $0.contains(name) }, "\(name) stays: \(patients)")
        }
        let others = protect(Self.referral, [.otherPeople]).texts
        for doctor in doctors {
            XCTAssertTrue(others.contains(doctor), "\(doctor) in \(others)")
        }
        XCTAssertTrue(others.contains("Beispiel"), "the colleague the letter greets: \(others)")
        XCTAssertFalse(others.contains { $0.contains("Musteryan") }, "\(others)")
        let all = Set(protect(Self.referral, PrivateDetail.allNames).texts)
        XCTAssertTrue(all.isSuperset(of: doctors + ["Beispiel", "Zorvak Musteryan"]), "\(all)")
    }

    /// A title is no one's name: the greeting's "Herr" stays, wherever the
    /// patient's "Herr" was found before, and so does the patient's own.
    func testATitleIsNeverCoveredAsAName() {
        for chosen in [PrivateDetail.allNames, [.patientNames], [.otherPeople]] {
            let found = protect(Self.referral, chosen)
            XCTAssertFalse(found.texts.contains { $0.hasPrefix("Herr") || $0.hasPrefix("Dr.") || $0.hasPrefix("PD") },
                           "\(chosen): \(found.texts)")
        }
    }

    /// A practice lists its doctors in a column: a name in it with nothing
    /// round it is one of them, not someone to check.
    func testANameInAColumnOfDoctorsIsADoctor() {
        let made = FormFieldsTests.layout(Self.referral)
        let column = Finder.doctorsColumn(made.strings, boxes: made.boxes)
        XCTAssertEqual(column.map { made.strings[$0] }, ["Tom Lorenz"])
        XCTAssertFalse(protect(Self.referral, [.patientNames]).texts.contains("Tom Lorenz"), "a doctor, not unclear")
        // Not without doctors round it: a list of names alone stays a list.
        let list = FormFieldsTests.layout([("Lena Weber", 0.08, 4), ("Jonas Kraft", 0.08, 5), ("Tom Lorenz", 0.08, 6)])
        XCTAssertTrue(Finder.doctorsColumn(list.strings, boxes: list.boxes).isEmpty)
        // Nor after them, as a patient's name under the practice's doctors.
        let after: [Piece] = [("Befundbericht", 0.08, 2), ("Dr. med. Anna Schmidt", 0.08, 4),
                              ("Dr. med. Bernd Weber", 0.08, 5), ("Erika Musterfrau", 0.08, 6), ("01.02.1960", 0.08, 7),
                              ("Befund: kein Nachweis einer Fraktur.", 0.08, 9)]
        let below = FormFieldsTests.layout(after)
        XCTAssertTrue(Finder.doctorsColumn(below.strings, boxes: below.boxes).isEmpty)
        XCTAssertTrue(protect(after, [.patientNames]).texts.contains("Erika Musterfrau"))
        // Nor outside a medical document, where "Dr." is no doctor.
        let firm: [Piece] = [("Kanzlei am Markt", 0.08, 2), ("Dr. Anna Schmidt", 0.70, 4), ("Clara Neumann", 0.70, 5),
                             ("Dr. Bernd Weber", 0.70, 6), ("Ihr Schreiben vom 3. März", 0.08, 8)]
        let lawyers = FormFieldsTests.layout(firm)
        XCTAssertTrue(Finder.doctorsColumn(lawyers.strings, boxes: lawyers.boxes).isEmpty)
    }

    /// Names covers whoever the words round a name do not place, and someone
    /// else's, as the one who signs a letter that is no doctor's.
    func testNamesCoverTheOneWhoSignsALetter() {
        let mail: [Piece] = [("Hallo Lena,", 0.08, 2), ("danke für die Unterlagen.", 0.08, 3), ("Viele Grüße", 0.08, 5),
                             ("Anna Schmidt", 0.08, 6), ("anna.schmidt@example.com", 0.08, 7)]
        XCTAssertTrue(protect(mail, [.names]).texts.contains("Anna Schmidt"), "\(protect(mail, [.names]).texts)")
        XCTAssertTrue(protect(mail, [.otherPeople]).texts.contains("Anna Schmidt"))
        XCTAssertFalse(protect(mail, [.patientNames]).texts.contains("Anna Schmidt"), "no patient's")
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
            for chosen: Set<PrivateDetail> in [[.names], [.patientNames], [.otherPeople], PrivateDetail.allNames] {
                let found = protect(note(variant.lines), chosen, rules: saved)
                for name in variant.covered {
                    XCTAssertTrue(found.covered.contains { $0.text.contains(name) && $0.kind == .names },
                                  "\(chosen): \(name) covered as a name: \(found.covered)")
                    XCTAssertFalse(found.checked.contains { $0.contains(name) }, "\(chosen): \(name) is sure: \(found.checked)")
                }
            }
        }
    }

    func testTheOwnNameNeverCoversWithoutANameKindAndAlwaysWithOne() {
        // No name kind on: only the rule's own words, written as saved, are covered.
        let found = protect(note(["Musterfrau, Erika"]), [.health, .addresses], rules: saved)
        XCTAssertFalse(found.covered.contains { $0.kind == .names }, "\(found.covered)")
        XCTAssertFalse(found.texts.contains { $0.contains("Musterfrau") }, "\(found.texts)")
        // With any of the names' switches on, the owner's name is covered
        // however it is written, whoever it is there: in their own medical
        // letter, the patient's.
        for chosen: Set<PrivateDetail> in [[.names], [.otherPeople]] {
            let covered = protect(note(["Musterfrau, Erika"]), chosen, rules: saved)
            XCTAssertTrue(covered.texts.contains("Musterfrau, Erika"), "\(chosen): \(covered.texts)")
        }
        // It never narrows what is covered: the doctors are still covered.
        let names = protect(Self.letter, PrivateDetail.allNames, rules: saved)
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

    func testAModelsBareNumberOnADocumentIsNoPhoneNumber() {
        let strings = Self.letter.map(\.text)
        let pieces = answer([
            ("Unser Zeichen: 7654321", .phones, "7654321"),
            ("Telefon 040 3333333-0", .phones, "040 3333333-0"),
        ])
        XCTAssertEqual(pieces.count, 2)
        // A letter prints its numbers with their labels: only the one said to be a phone number is one.
        let found = Finder.vetted(pieces, in: strings, Set(PrivateDetail.allCases))
        XCTAssertEqual(found.hits.map { "\($0.kind!.rawValue): \(text($0, in: strings))" }, ["phones: 040 3333333-0"])
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
