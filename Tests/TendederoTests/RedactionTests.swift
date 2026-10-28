import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// What is covered of a whole document, kind by kind, without a picture:
/// finding, telling what each find is, and covering only what the owner
/// chose are kept apart. With everyone's names on (Names, Patient names and
/// Other people), a person's name is covered and nothing else: not a
/// company, a phone number, an address, a date, an amount or a diagnosis.
/// With Patient names alone, the doctors' names stay, and every place the
/// patient is named is covered. The documents are made up for the tests;
/// none is a real one, and none is the screenshot a fault was first seen in.
final class RedactionTests: XCTestCase {
    /// A radiology report: the practice's header, the patient, the
    /// referring doctor, the findings and the doctor who signs.
    private let report = [
        "Radiologie Zentrum Nord GmbH",
        "Dr. med. Anna Schmidt · Fachärztin für Radiologie",
        "Hauptstraße 12, 20095 Hamburg",
        "Tel. 040 1234567",
        "Patient: Mustermann, Max, geb. 01.02.1960",
        "Überweisender Arzt: Dr. med. Klaus Weber",
        "Befund",
        "Wir berichten über Ihren Patienten Herrn Max Mustermann.",
        "Kein Nachweis einer Fraktur.",
        "Mit freundlichen Grüßen",
        "Anna Schmidt",
        "Fachärztin für Radiologie",
    ]

    /// A shop's invoice: the shop, the customer, the address, the total and
    /// the account to pay to.
    private let invoice = [
        "Muster Versand GmbH",
        "Rechnung Nr. 2024-1187",
        "Kunde: Lena Weber",
        "Musterweg 5, 12345 Berlin",
        "Tel. +49 30 1234567",
        "Summe: 49,90 €",
        "IBAN: DE89 3704 0044 0532 0130 00",
        "Sparkasse KölnBonn",
    ]

    func testEveryonesNamesCoverThePeopleAndNothingElse() {
        let found = protect(report, PrivateDetail.allNames)
        for name in ["Anna Schmidt", "Mustermann, Max", "Klaus Weber", "Max Mustermann"] {
            XCTAssertTrue(found.covered.contains(name), "\(name) in \(found.covered)")
        }
        for kept in ["GmbH", "Radiologie", "Hauptstraße", "Hamburg", "040", "1960", "Fraktur", "Befund", "Dr.", "geb."] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(found.covered)")
        }
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == .names }, "only names")
    }

    func testEveryonesNamesLeaveTheShopTheAddressAndTheMoney() {
        let found = protect(invoice, PrivateDetail.allNames)
        XCTAssertTrue(found.covered.contains("Lena Weber"), "\(found.covered)")
        for kept in ["Muster Versand", "Musterweg", "Berlin", "1234567", "49,90", "DE89", "Sparkasse", "2024"] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(found.covered)")
        }
    }

    func testCompaniesAreCoveredOnlyAsCompanies() {
        let names = protect(invoice, PrivateDetail.allNames)
        XCTAssertFalse(names.possible.contains { $0.contains("GmbH") || $0.contains("Sparkasse") },
                       "a company is never offered as a name: \(names.possible)")
        let companies = protect(invoice, [.organizations])
        XCTAssertTrue(companies.covered.contains("Muster Versand GmbH"), "\(companies.covered)")
        XCTAssertTrue(companies.covered.contains("Sparkasse KölnBonn"), "\(companies.covered)")
        XCTAssertFalse(companies.covered.contains { $0.contains("Lena") }, "a person is no company: \(companies.covered)")
        XCTAssertTrue(companies.hits.allSatisfy { $0.kind == .organizations })
    }

    func testOnlyThePatientsNameIsCoveredWhenOnlyItIsChosen() {
        let found = protect(report, [.patientNames])
        XCTAssertTrue(found.covered.contains("Mustermann, Max"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains("Max Mustermann"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Schmidt") || $0.contains("Weber") || $0.contains("Anna") },
                       "the doctors' names stay: \(found.covered)")
        XCTAssertFalse(found.checked.contains { $0.contains("Mustermann") || $0.contains("Schmidt") },
                       "every role here is clear: \(found.checked)")
    }

    func testOnlyTheOtherPeopleAreCoveredWhenOnlyTheyAreChosen() {
        let found = protect(report, [.otherPeople])
        XCTAssertTrue(found.covered.contains("Klaus Weber"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains("Anna Schmidt"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Mustermann") }, "\(found.covered)")
    }

    func testANameWhoseRoleIsUnclearIsCoveredAndMarkedForChecking() {
        let lines = ["Befund", "Diagnose: Gastritis", "Name: Lena Weber"]
        let found = protect(lines, [.patientNames])
        XCTAssertTrue(found.covered.contains("Lena Weber"), "privacy first: \(found.covered)")
        XCTAssertTrue(found.checked.contains("Lena Weber"), "and shown to be checked: \(found.checked)")
        // With everyone's names covered, there is nothing to check; with
        // Names, such a name is covered as one whose role is not clear.
        XCTAssertTrue(protect(lines, PrivateDetail.allNames).checked.isEmpty)
        let names = protect(lines, [.names])
        XCTAssertTrue(names.covered.contains("Lena Weber"), "\(names.covered)")
        XCTAssertTrue(names.checked.isEmpty, "\(names.checked)")
    }

    func testTheDiagnosisIsHealthNotAName() {
        let found = protect(["Patientin: Weber, Lena", "Diagnose: Morbus Crohn"], [.health])
        XCTAssertTrue(found.covered.contains("Morbus Crohn"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Lena") }, "\(found.covered)")
        let names = protect(["Patientin: Weber, Lena", "Diagnose: Morbus Crohn"], PrivateDetail.allNames)
        XCTAssertEqual(names.covered.filter { $0.contains("Crohn") }, [], "a disease named after a person is no name")
    }

    func testAnEnglishLettersHeadingsAreNoNames() {
        let lines = ["Internal Medicine Practice", "Dr. Anna Schmidt", "Doctor's Letter", "Patient: Erika Mustermann"]
        let found = protect(lines, PrivateDetail.allNames)
        XCTAssertTrue(found.covered.contains("Erika Mustermann"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains { $0.contains("Anna Schmidt") }, "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Practice") || $0.contains("Letter") },
                       "a practice and a letter are no one: \(found.covered)")
    }

    func testANameIsCoveredWithoutItsTitleOrWhatFollowsIt() {
        let found = protect(["Arztbrief", "Behandelnder Arzt: Dr. med. Klaus Weber",
                             "Kunde: Frau Lena Weber (Kundennr. 4711)"], PrivateDetail.allNames)
        XCTAssertTrue(found.covered.contains("Klaus Weber"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains("Lena Weber"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Dr.") || $0.contains("Frau") || $0.contains("4711") },
                       "\(found.covered)")
    }

    func testEveryKindChosenIsCoveredAsItself() {
        let found = protect(invoice, PrivateDetail.allNames.union([.addresses, .phones, .amounts, .bank, .organizations, .orders]))
        let kinds = Set(found.hits.compactMap(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.names, .bank, .organizations, .amounts]), "\(kinds)")
        XCTAssertTrue(found.covered.contains { $0.contains("DE89") })
        XCTAssertTrue(found.covered.contains { $0.contains("49,90") })
    }

    func testALineShapedLikeANameIsNeverDroppedSilently() {
        let found = protect(["Projekt Übersicht", "Lena Weber", "3 Aufgaben offen"], [.names])
        XCTAssertTrue(found.covered.contains("Lena Weber") || found.possible.contains("Lena Weber"),
                      "covered, or offered to check: \(found.covered) \(found.possible)")
    }

    // MARK: The patient, wherever the report names them

    /// A doctor's letter to the patient's home: the practice, the address
    /// block under "Herrn", the letter's subject, a sentence about the
    /// patient, the date of birth, and the doctor who signs.
    private let letter = [
        "Praxis Dr. med. Klaus Weber",
        "Facharzt für Innere Medizin",
        "Herrn",
        "Max Mustermann",
        "Musterweg 5",
        "12345 Berlin",
        "Arztbrief",
        "Betreff: Max Mustermann, geb. 01.02.1960",
        "Sehr geehrter Herr Mustermann,",
        "wir berichten über Ihren Patienten Max Mustermann nach der Untersuchung.",
        "Diagnose: Gastritis",
        "Mit freundlichen Grüßen",
        "Klaus Weber",
        "Facharzt für Innere Medizin",
    ]

    func testEveryPlaceThePatientIsNamedIsCovered() {
        let found = protect(letter, [.patientNames])
        let named = found.hits.filter { letter[$0.line].contains("Mustermann") }.map(\.line)
        XCTAssertEqual(Set(named), [3, 7, 8, 9], "the address, the subject, the greeting and the sentence: \(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Weber") }, "the doctor stays: \(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Berlin") || $0.contains("1960") || $0.contains("Gastritis") },
                       "patient names alone cover no address, date or diagnosis: \(found.covered)")
        XCTAssertTrue(found.possible.allSatisfy { !$0.contains("Mustermann") }, "never left as a suggestion")
    }

    func testThePatientIsCoveredWhereverTheyAreNamedWithAllNames() {
        let found = protect(letter, PrivateDetail.allNames)
        for line in [0, 3, 7, 8, 9, 12] {
            XCTAssertTrue(found.hits.contains { $0.line == line }, "line \(line): \(letter[line]) in \(found.covered)")
        }
        XCTAssertEqual(found.checked, [], "with everyone's names there is nothing to check")
    }

    func testANameBeforeItsDateOfBirthIsThePatient() {
        let lines = ["Laborbefund", "Mustermann Max 01.02.1960", "Hämoglobin 13,5 g/dl", "Befundet von Dr. Anna Schmidt"]
        let found = protect(lines, [.patientNames])
        XCTAssertTrue(found.covered.contains { $0.contains("Mustermann Max") }, "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Schmidt") }, "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("1960") }, "the date is a date: \(found.covered)")
    }

    func testANameUnderATableHeaderIsCovered() {
        let lines = ["Befundbericht", "Name, Vorname        Geb.-Datum", "Mustermann, Max      01.02.1960",
                     "Untersuchung: MRT Knie"]
        let found = protect(lines, [.patientNames])
        XCTAssertTrue(found.covered.contains { $0.contains("Mustermann, Max") }, "\(found.covered)")
    }

    func testAMisreadRepeatIsStillThePatient() {
        let lines = ["Arztbrief", "Patient: Max Mustermann", "Herr Mustermamn klagt über Schmerzen.",
                     "Überweisender Arzt: Dr. Klaus Weber"]
        let found = protect(lines, [.patientNames])
        XCTAssertTrue(found.covered.contains { $0.contains("Mustermamn") }, "a letter misread: \(found.covered)")
        XCTAssertFalse(found.checked.contains { $0.contains("Mustermamn") }, "known as the patient: \(found.checked)")
        XCTAssertFalse(found.covered.contains { $0.contains("Weber") }, "\(found.covered)")
    }

    func testAnInitialGoesWithTheName() {
        let lines = ["Patient: Max Mustermann", "Befund für M. Mustermann vom 3. März"]
        let found = protect(lines, [.patientNames])
        XCTAssertTrue(found.covered.contains { $0.contains("M. Mustermann") }, "\(found.covered)")
    }

    func testTheSigningDoctorIsADoctor() {
        let lines = ["Befund", "Patientin: Lena Weber", "Mit freundlichen Grüßen", "Anna Schmidt"]
        XCTAssertFalse(protect(lines, [.patientNames]).covered.contains("Anna Schmidt"))
        XCTAssertTrue(protect(lines, [.otherPeople]).covered.contains("Anna Schmidt"))
    }

    func testPatientNamesAloneLeaveEveryOtherKind() {
        let lines = ["Arztbrief", "Patient: Max Mustermann", "Tel. 040 1234567", "max@example.com",
                     "Musterweg 5, 12345 Berlin"]
        let found = protect(lines, [.patientNames])
        XCTAssertEqual(found.covered, ["Max Mustermann"])
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == .names })
    }

    /// The fault the owner saw, made up: Names on alone, and their own name
    /// saved. A letter about them covers their name, and leaves the doctor
    /// and the colleague it greets; the greeting's "Herr" is never covered.
    func testNamesAloneWithTheOwnNameLeaveTheDoctorsAndTheGreeting() {
        let lines = ["Dr. med. Paul Beispiel", "Sehr geehrter Herr Kollege Beispiel,",
                     "vielen Dank für die freundliche Überweisung Ihres Patienten:",
                     "Herr Zorvak Musteryan, geb. am 05.03.1990", "Befund: Flach linkskonvexe Skoliose."]
        let found = protect(lines, [.names], rules: [OwnRule(text: "Zorvak Musteryan", kind: .name)])
        XCTAssertTrue(found.covered.contains("Zorvak Musteryan"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Beispiel") || $0.contains("Herr") }, "\(found.covered)")
        let everyone = protect(lines, PrivateDetail.allNames)
        XCTAssertTrue(Set(everyone.covered).isSuperset(of: ["Paul Beispiel", "Beispiel", "Zorvak Musteryan"]),
                      "\(everyone.covered)")
        XCTAssertFalse(everyone.covered.contains { $0.contains("Herr") }, "\(everyone.covered)")
    }

    func testAPlaceFoundTwiceIsCountedOnce() {
        let found = protect(["Patient: Herr Max Mustermann"], PrivateDetail.allNames)
        XCTAssertEqual(found.hits.count, 1, "\(found.covered)")
    }

    // MARK: Forms: each field covered as what its label says, and only that

    /// The made-up certificate of incapacity for work, laid out as read.
    private let sickNote = FormFieldsTests.sickNote

    func testEveryonesNamesCoverTheNamesOnTheFormAndNothingElse() {
        let found = protect(form: sickNote, PrivateDetail.allNames)
        XCTAssertEqual(Set(found.covered), ["Mustermann", "Erika", "Paul Beispiel"], "\(found.covered)")
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == .names })
        XCTAssertTrue(found.checked.isEmpty, "every name here is sure: \(found.checked)")
    }

    func testPatientNamesAloneCoverTheInsuredPersonNotTheDoctor() {
        XCTAssertEqual(Set(protect(form: sickNote, [.patientNames]).covered), ["Mustermann", "Erika"])
        XCTAssertEqual(Set(protect(form: sickNote, [.otherPeople]).covered), ["Paul Beispiel"])
    }

    func testHealthAloneCoversTheIllnessAndItsDaysNotTheDateTheNoteWasWritten() {
        let found = protect(form: sickNote, [.health])
        XCTAssertEqual(Set(found.covered), ["02.10.26", "09.10.26", "05.10.26", "J06.9 G",
                                            "Akute Infektion der oberen Atemwege"], "\(found.covered)")
        let written = sickNote.firstIndex { $0.text == "05.10.26" && $0.row == 10 }!
        XCTAssertFalse(found.hits.contains { $0.line == written }, "the note's own date is no health detail")
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == .health })
    }

    func testIDsAloneCoverTheNumbersNotTheStatusCode() {
        let found = protect(form: sickNote, [.ids])
        XCTAssertEqual(Set(found.covered), ["101234567", "X987654321", "998877665", "112233445"], "\(found.covered)")
    }

    func testAddressesAloneCoverTheAddressesNotTheNames() {
        let found = protect(form: sickNote, [.addresses])
        XCTAssertTrue(found.covered.contains("Beispielweg 7"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains("54321 Musterstadt"), "\(found.covered)")
        for kept in ["Mustermann", "Erika", "Paul", "1985", "BKK", "J06"] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(found.covered)")
        }
    }

    func testDatesAloneCoverTheDatesOnly() {
        let found = protect(form: sickNote, [.dates])
        for date in ["12.03.1985", "02.10.26", "09.10.26", "05.10.26"] {
            XCTAssertTrue(found.covered.contains(date), "\(date) in \(found.covered)")
        }
        XCTAssertTrue(found.covered.allSatisfy { $0.range(of: #"^\d{1,2}\.\d{1,2}\.\d{2,4}$"#, options: .regularExpression) != nil },
                      "\(found.covered)")
    }

    func testAFieldsNumberIsNeverTakenForAnotherKind() {
        let found = protect(form: sickNote, [.phones, .tracking, .orders, .bank, .codes])
        for number in ["101234567", "X987654321", "998877665", "112233445", "5000001"] {
            XCTAssertFalse(found.covered.contains { $0.contains(number) }, "\(number): \(found.covered)")
        }
    }

    func testEveryKindTogetherCoversEveryValueAndNoLabel() {
        let found = protect(form: sickNote, Set(PrivateDetail.allCases))
        for value in ["Muster BKK", "Mustermann", "Erika", "12.03.1985", "Beispielweg 7", "54321 Musterstadt",
                      "101234567", "X987654321", "998877665", "112233445", "J06.9 G"] {
            XCTAssertTrue(found.covered.contains { $0.contains(value) }, "\(value) in \(found.covered)")
        }
        for label in ["Name, Vorname", "Versicherten-Nr", "Kostenträger", "geb. am", "Arzt-Nr", "Diagnose",
                      "Arbeitsunfähig seit", "festgestellt am", "Status", "Datum"] {
            XCTAssertFalse(found.covered.contains { $0.contains(label) }, "\(label) is printed by the form: \(found.covered)")
        }
    }

    /// How well the sick note is covered, kind by kind: every value its
    /// labels announce and nothing else, measured as precision and recall.
    func testPrecisionAndRecallOnTheSickNote() {
        let truth: [PrivateDetail: Set<String>] = [
            .names: ["Mustermann", "Erika", "Paul Beispiel"],
            .health: ["02.10.26", "09.10.26", "05.10.26", "J06.9 G", "Akute Infektion der oberen Atemwege"],
            .ids: ["101234567", "X987654321", "998877665", "112233445"],
        ]
        for (kind, expected) in truth {
            // Names are everyone's here: Names and its two parts.
            let covered = Set(protect(form: sickNote, kind == .names ? PrivateDetail.allNames : [kind]).covered)
            let right = covered.intersection(expected).count
            let precision = covered.isEmpty ? 1 : Double(right) / Double(covered.count)
            let recall = Double(right) / Double(expected.count)
            XCTAssertEqual(precision, 1, "\(kind): false positives \(covered.subtracting(expected))")
            XCTAssertEqual(recall, 1, "\(kind): missed \(expected.subtracting(covered))")
        }
    }

    /// A referral with a name on one line, the insured person and the
    /// doctor, and a diagnosis named after a person.
    private let referral: [FormFieldsTests.Piece] = [
        ("Überweisungsschein", 0.05, 0),
        ("Name, Vorname des Versicherten", 0.05, 1),
        ("Beispiel-Muster, Hans Peter", 0.05, 2),
        ("Lindenallee 12", 0.05, 3),
        ("10115 Berlin", 0.05, 4),
        ("Diagnose: Morbus Bechterew", 0.05, 6),
        ("Behandelnder Arzt: Dr. med. Clara Probe", 0.05, 7),
    ]

    func testTheInsuredPersonAndTheDoctorAreToldApart() {
        XCTAssertEqual(protect(form: referral, [.patientNames]).covered, ["Beispiel-Muster, Hans Peter"])
        XCTAssertEqual(protect(form: referral, [.otherPeople]).covered, ["Clara Probe"])
        let names = protect(form: referral, PrivateDetail.allNames)
        XCTAssertFalse(names.covered.contains { $0.contains("Bechterew") }, "a disease is no name: \(names.covered)")
        XCTAssertEqual(protect(form: referral, [.health]).covered, ["Morbus Bechterew"])
    }

    func testANameReadPoorlyIsCoveredAndMarkedForChecking() {
        let found = protect(form: [("Name des Versicherten", 0.05, 0), ("mustermann erika", 0.05, 1)],
                            PrivateDetail.allNames)
        XCTAssertEqual(found.covered, ["mustermann erika"])
        XCTAssertEqual(found.checked, ["mustermann erika"])
    }

    func testANameOnTheFormIsCoveredWhereverItComesAgain() {
        let pieces = sickNote + [("Frau Mustermann ist arbeitsunfähig.", 0.05, 24)]
        let found = protect(form: pieces, [.patientNames])
        XCTAssertTrue(found.hits.contains { $0.line == pieces.count - 1 }, "\(found.covered)")
    }

    // MARK: A letter

    /// A made-up radiology letter: the practice's header in the right
    /// column, the patient's name and address in the window, the subject
    /// with the date of birth, three doctors, and the bank's details.
    private let radiologyLetter: [FormFieldsTests.Piece] = [
        ("RADIOLOGIE NORDHAFEN", 0.72, 1), ("HAFENPLATZ · KAISERKAI", 0.72, 2),
        ("RADIOLOGIE NORDHAFEN Hafenplatz 2, Kaiserkai 9, 20457 Hamburg", 0.06, 4), ("MRT-DIAGNOSTIK", 0.72, 4),
        ("Erika Mustermann", 0.06, 5), ("CT-DIAGNOSTIK", 0.72, 5),
        ("Lindenberg 12", 0.06, 6),
        ("23456 Musterstadt", 0.06, 7), ("Hafenplatz 2", 0.72, 7),
        ("20457 Hamburg", 0.72, 8),
        ("Hamburg, den 05.06.2026", 0.52, 9), ("Telefon 040 1234567-0", 0.72, 9),
        ("Unser Zeichen: 7654321", 0.06, 10), ("info@radiologie-nordhafen.de", 0.72, 10),
        ("Mustermann, Erika", 0.08, 11), ("geb. 12.03.1985", 0.58, 11),
        ("Lindenberg 12,23456 Musterstadt", 0.08, 12),
        ("MRT der Lendenwirbelsäule nativ vom 05.06.2026.", 0.06, 14),
        ("Bilderportal: bilder.radiologie-nordhafen.de Referenznummer: XYZ123456", 0.06, 15),
        ("Ärzte für Radiologie", 0.72, 15),
        ("Klinik und Fragestellung:", 0.06, 16), ("Dr. med. Jonas Feldmann", 0.72, 16),
        ("Lumboischialgie links", 0.06, 17), ("Dr. med. Clara Wendt", 0.72, 17),
        ("Befund:", 0.06, 18), ("Dr. med. Paul Hagedorn MBA", 0.72, 18),
        ("Zum Vergleich liegt keine Untersuchung vor.", 0.06, 19),
        ("Im Segment LWK 5/SWK 1 zeigt sich ein Signalverlust der Bandscheibe.", 0.06, 20),
        ("Beurteilung:", 0.06, 22), ("Dt. Apotheker- u. Ärztebank", 0.72, 22),
        ("1. Mediale Bandscheibenextrusion LWK 5/SWK 1.", 0.06, 23), ("DE89 3704 0044 0532 0130 00", 0.72, 23),
        ("2. Bandscheibendegeneration LWK 5/SWK 1.", 0.06, 24), ("DAAEDEDDXXX", 0.72, 24),
        ("Mit freundlichen Grüßen", 0.06, 26),
        ("Dr. med. Jonas Feldmann", 0.06, 28), ("Dr. med. Clara Wendt", 0.33, 28), ("Dr. med. Paul Hagedorn", 0.55, 28),
    ]

    func testTheAddressUnderThePatientsNameIsTheirs() {
        let found = protect(form: radiologyLetter, [.addresses])
        let patients = zip(found.covered, found.hits).filter { $0.1.role?.role == .patient }.map(\.0)
        XCTAssertEqual(Set(patients), ["Lindenberg 12", "23456 Musterstadt", "Lindenberg 12,23456 Musterstadt"])
        XCTAssertFalse(found.covered.contains { $0.contains("Dr.") }, "\(found.covered)")
    }

    func testALettersDateOfBirthReferencesAndBankDetails() {
        let found = protect(form: radiologyLetter, [.birthDates, .ids, .bank])
        XCTAssertEqual(Set(found.covered),
                       ["12.03.1985", "7654321", "XYZ123456", "DE89 3704 0044 0532 0130 00", "DAAEDEDDXXX"])
        for (text, hit) in zip(found.covered, found.hits) where hit.kind != .bank {
            XCTAssertEqual(hit.role?.role, .patient, text)
        }
        // A date of birth is no other date, and the letter's reference no order.
        let more = protect(form: radiologyLetter, [.dates, .birthDates, .orders, .ids])
        for (text, hit) in zip(more.covered, more.hits) where ["12.03.1985", "7654321", "XYZ123456"].contains(text) {
            XCTAssertTrue(hit.kind == .birthDates || hit.kind == .ids, "\(text) is \(String(describing: hit.kind))")
        }
    }

    func testThePatientAndTheDoctorsOfALetterAreToldApart() {
        let found = protect(form: radiologyLetter, PrivateDetail.allNames)
        func roles(of name: String) -> Set<PersonRole?> {
            Set(zip(found.covered, found.hits).filter { $0.0.contains(name) }.map { $0.1.role?.role })
        }
        XCTAssertEqual(roles(of: "Mustermann"), [.patient], "\(found.covered)")
        for doctor in ["Feldmann", "Wendt", "Hagedorn"] {
            XCTAssertEqual(roles(of: doctor), [.doctor], "\(doctor) in \(found.covered)")
        }
        let patient = protect(form: radiologyLetter, [.patientNames]).covered
        XCTAssertTrue(patient.contains { $0.contains("Mustermann") }, "\(patient)")
        XCTAssertFalse(patient.contains { $0.contains("Feldmann") || $0.contains("Wendt") || $0.contains("Hagedorn") },
                       "\(patient)")
    }

    /// What a model names is covered only where it fits: the name it found
    /// part of, whole; never a street or a segment of the spine it calls a
    /// name (see `CategoryFidelityTests` for every kind).
    func testAModelsAnswerIsCoveredOnlyWhereItFits() {
        let lines = ["Patient: Mustermann, Max", "Hauptstraße 12, 20095 Hamburg", "Befund: Protrusion LWK 4/5"]
        let pieces = [Finder.IntelligentPiece(line: 0, kind: .names, words: "Max"),
                      Finder.IntelligentPiece(line: 1, kind: .names, words: "Hauptstraße"),
                      Finder.IntelligentPiece(line: 2, kind: .names, words: "LWK 4/5")]
        let found = Finder.vetted(pieces, in: lines, [.names])
        let covered = found.hits.map { hit in
            hit.range.flatMap { Range($0, in: lines[hit.line]) }.map { String(lines[hit.line][$0]) } ?? lines[hit.line]
        }
        XCTAssertEqual(covered, ["Mustermann, Max"])
        XCTAssertTrue(found.possible.isEmpty, "\(found.possible)")
    }

    func testTheOwnersNameOverTwoLinesIsCoveredWhereAnotherColumnIsReadBetween() {
        // The body's lines on the left, a letterhead's line on the right read
        // between them; a given name this short is no name alone.
        let lines = ["in unserer Praxis. Die Akte lautet auf Tim", "Dr. med. Tom Muster",
                     "Brandtner. Rückfragen bitte an die Praxis."]
        let boxes = [CGRect(x: 0.08, y: 0.50, width: 0.5, height: 0.015),
                     CGRect(x: 0.70, y: 0.49, width: 0.2, height: 0.012),
                     CGRect(x: 0.08, y: 0.48, width: 0.5, height: 0.015)]
        func part(_ index: Int, _ range: Range<String.Index>) -> CGRect? {
            let line = lines[index], share = boxes[index].width / CGFloat(line.count)
            let start = CGFloat(line.distance(from: line.startIndex, to: range.lowerBound))
            return CGRect(x: boxes[index].minX + start * share, y: boxes[index].minY,
                          width: CGFloat(line.distance(from: range.lowerBound, to: range.upperBound)) * share,
                          height: boxes[index].height)
        }
        let name = OwnRule(text: OwnDetails.nameText(given: "Tim", surname: "Brandtner"), kind: .name)
        let found = Finder.findings(lines, boxes: boxes, part: part, [], rules: [name])
        let covered = found.hits.map { hit in
            hit.range.flatMap { Range($0, in: lines[hit.line]) }.map { String(lines[hit.line][$0]) } ?? lines[hit.line]
        }
        XCTAssertEqual(Set(covered), ["Tim", "Brandtner"], "\(covered)")
        XCTAssertFalse(found.hits.contains { $0.line == 1 }, "the letterhead's line is no part of it")
    }

    // MARK: What an invoice charges for

    /// The made-up invoice as Vision read it on a Mac: "Druckpatronen
    /// Schwarz" in the column under "Pos Beschreibung", its price on its
    /// row, is what the invoice charges for, two words that only look like
    /// a name; Erika Mustermann, over her street, is the customer.
    func testAnInvoicesItemIsOfferedNotCoveredAsAName() {
        let found = protect(read: ScanReadingVisionTests.invoice, PrivateDetail.allNames)
        let report = "covered \(found.covered), checked \(found.checked), offered \(found.possible)"
        XCTAssertFalse(found.covered.contains { $0.contains("Druckpatronen") || $0.contains("Schwarz") }, report)
        XCTAssertTrue(found.possible.contains("Druckpatronen Schwarz"), "one tap from covered: \(report)")
        XCTAssertTrue(found.covered.contains("Erika Mustermann"), report)
        for kept in ["Beratung", "Versandpauschale", "Beschreibung", "24,90", "Musterfirma"] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(report)")
        }
    }

    /// A course's invoice: the people taking part, each in a column of
    /// their own beside the course's price, are names, not what is sold.
    func testAColumnOfPeopleStaysCoveredBesideItsPrices() {
        let course: [FormFieldsTests.Piece] = [
            ("Musterakademie GmbH", 0.05, 0),
            ("Rechnung Nr. 2026-0815", 0.05, 2), ("Datum 20.10.2026", 0.60, 2),
            ("Pos", 0.05, 4), ("Teilnehmer", 0.10, 4), ("Kurs", 0.40, 4), ("Betrag", 0.80, 4),
            ("1", 0.05, 5), ("Lena Weber", 0.10, 5), ("Tabellen", 0.40, 5), ("199,00 €", 0.80, 5),
            ("2", 0.05, 6), ("Jonas Brandt", 0.10, 6), ("Tabellen", 0.40, 6), ("199,00 €", 0.80, 6),
            ("Netto", 0.62, 8), ("398,00 €", 0.80, 8),
            ("Gesamt", 0.62, 9), ("473,62 €", 0.80, 9),
        ]
        let found = protect(form: course, PrivateDetail.allNames)
        for name in ["Lena Weber", "Jonas Brandt"] {
            XCTAssertTrue(found.covered.contains(name), "\(name): covered \(found.covered), offered \(found.possible)")
        }
    }

    /// The rule alone, without the Natural Language framework: a line is
    /// an item with its price on its row, under the nearest header up its
    /// column, when that header names what is sold and no people.
    func testAnItemIsARowOfAColumnOfItemsBesideItsPrice() {
        func items(_ pieces: [FormFieldsTests.Piece]) -> [String] {
            let made = FormFieldsTests.layout(pieces)
            return made.strings.indices.filter { Finder.isItem($0, strings: made.strings, boxes: made.boxes) }
                .map { made.strings[$0] }
        }
        let header: [FormFieldsTests.Piece] = [("Pos", 0.05, 4), ("Beschreibung", 0.10, 4), ("Menge", 0.50, 4),
                                               ("Betrag", 0.80, 4)]
        XCTAssertEqual(items(header + [("Druckpatronen Schwarz", 0.10, 5), ("2", 0.50, 5), ("49,80 €", 0.80, 5),
                                       ("Kabel Blau", 0.10, 6), ("1", 0.50, 6), ("5,90 €", 0.80, 6)]),
                       ["Druckpatronen Schwarz", "Kabel Blau"])
        // The header read as one line, a compound, and in English.
        XCTAssertEqual(items([("Pos Artikelbezeichnung Menge Preis", 0.05, 4), ("Druckpatronen Schwarz", 0.10, 5),
                              ("EUR 24,90", 0.80, 5)]), ["Druckpatronen Schwarz"])
        XCTAssertEqual(items([("Item", 0.10, 4), ("Qty", 0.50, 4), ("Amount", 0.80, 4), ("Ink Cartridge", 0.10, 5),
                              ("$12.99", 0.80, 5)]), ["Ink Cartridge"])
        // Without a price on its row: a line an item's words wrap onto, or
        // the customer's name beside the date.
        XCTAssertEqual(items(header + [("Druckpatronen Schwarz", 0.10, 5), ("2", 0.50, 5)]), [])
        XCTAssertEqual(items([("Erika Mustermann", 0.05, 4), ("14.10.2026", 0.80, 4)]), [])
        // A column of people, or a header naming people beside what is sold.
        XCTAssertEqual(items([("Teilnehmer", 0.10, 4), ("Betrag", 0.80, 4), ("Lena Weber", 0.10, 5),
                              ("199,00 €", 0.80, 5)]), [])
        XCTAssertEqual(items([("Pos Name Beschreibung Betrag", 0.05, 4), ("Lena Weber", 0.10, 5),
                              ("199,00 €", 0.80, 5)]), [])
        // A sentence about what is charged for heads no column; a header
        // a new section away heads none here.
        XCTAssertEqual(items([("Für unsere Leistungen berechnen wir:", 0.05, 3), ("Lena Weber", 0.10, 4),
                              ("199,00 €", 0.80, 4)]), [])
        XCTAssertEqual(items([("Beschreibung", 0.10, 0), ("Betrag", 0.80, 0), ("Lena Weber", 0.10, 8),
                              ("199,00 €", 0.80, 8)]), [])
    }

    func testAPriceIsAnAmountNotAQuantityADateOrANumber() {
        for price in ["24,90 €", "€ 5.90", "1.234,56", "EUR 5,90", "$12.99", "5 €", "49,80"] {
            XCTAssertTrue(Finder.isPrice(price), price)
        }
        for other in ["2", "14.10.2026", "RE-2026-0417", "MwSt. 19%", "Telefon: 030 1234567", "Kundennr. 48213",
                      "IBAN: DE89 3704 0044 0532 0130 00"] {
            XCTAssertFalse(Finder.isPrice(other), other)
        }
    }

    // MARK: Other languages and chats, from CoverAccuracyTests

    func testAChatsWritersAreCoveredByTheNameBeforeTheirMessages() {
        let chat = ["Lena: Hallo Jonas!", "Jonas: Ruf mich bitte an unter +49 30 1234567", "Lena: Bis morgen",
                    "Jonas: Gut"]
        let found = protect(chat, PrivateDetail.recommended)
        for name in ["Lena", "Jonas"] {
            XCTAssertGreaterThanOrEqual(found.covered.filter { $0.contains(name) }.count, 2, "\(name): \(found.covered)")
        }
        let arabic = protect(["خالد: مرحبا", "سارة: أهلا", "خالد: كيف حالك؟", "سارة: بخير"], PrivateDetail.recommended)
        XCTAssertTrue(arabic.covered.contains("خالد") && arabic.covered.contains("سارة"), "\(arabic.covered)")
    }

    func testALogsErrorAndWarningLinesAreNoPeople() {
        let log = ["Error: file not found", "Warning: disk almost full", "Error: retry failed", "Warning: slow"]
        let found = protect(log, PrivateDetail.recommended)
        XCTAssertFalse(found.covered.contains { $0.contains("Error") || $0.contains("Warning") }, "\(found.covered)")
    }

    func testLabelsInOtherLanguagesAnnounceTheirNames() {
        let lines = ["Ordenante: Diego Navarro", "Beneficiario: Elena Martínez", "Bénéficiaire: Léa Bernard",
                     "Favorecido: Pedro Silva", "Müşteri: Emre Şahin", "Personel: Zeynep Kaya"]
        for line in lines {
            let name = String(line[line.index(after: line.firstIndex(of: ":")!)...].dropFirst())
            let found = protect([line], PrivateDetail.recommended)
            XCTAssertTrue(found.covered.contains { $0.contains(name) }, "\(line): \(found.covered)")
        }
    }

    func testVerificationCodesInOtherLanguagesButNoPostcode() {
        for (line, code) in [("Tu código de verificación es 202886", "202886"), ("Doğrulama kodun 271030", "271030"),
                             ("Seu código de verificação é 413190", "413190"),
                             ("رمز التحقق الخاص بك هو 042088", "042088")] {
            XCTAssertTrue(protect([line], [.codes]).covered.contains(code), line)
        }
        for line in ["Código postal 28013", "Posta kodu 34710"] {
            XCTAssertFalse(protect([line], [.codes]).hits.contains { $0.kind == .codes }, line)
        }
    }

    func testStreetsAndTownsAsTurkishAndArabicLettersWriteThem() {
        for street in ["Atatürk Caddesi No: 61", "Gül Sokak No: 109", "Atatürk Caddesi No: 10, 06420 Çankaya/Ankara",
                       "شارع التحلية 44", "شارع التحلية 44, جدة 21577"] {
            XCTAssertTrue(Finder.isStreetLine(street), street)
        }
        for town in ["34710 Kadıköy/İstanbul", "الرياض 12271"] {
            XCTAssertTrue(Finder.isTownLine(town), town)
        }
        for other in ["مصباح مكتب 19.26 ر.س", "ورق طباعة A4 20.71 ر.س", "رقم الفاتورة 12345", "Druckerpapier A4 63,44 €"] {
            XCTAssertFalse(Finder.isStreetLine(other) || Finder.isTownLine(other), other)
        }
    }

    func testDatesOfBirthAndIDNumbersByTheirLabelsInOtherLanguages() {
        for (line, born) in [("Paciente: Sergio Ruiz, Fecha de nacimiento: 14/03/1987", "14/03/1987"),
                             ("Doğum tarihi: 14.03.1987", "14.03.1987"),
                             ("Data de nascimento: 14/03/1987", "14/03/1987")] {
            XCTAssertTrue(protect([line], PrivateDetail.recommended).covered.contains { $0.contains(born) }, line)
        }
        for (line, id) in [("DNI: 12345678Z", "12345678Z"), ("CPF: 123.456.789-09", "123.456.789-09"),
                           ("T.C. Kimlik No: 10000000146", "10000000146")] {
            XCTAssertTrue(protect([line], [.ids]).covered.contains { $0.contains(id) }, line)
        }
    }

    func testANameInAnEmailsHeaderIsCoveredInItsGreetingAndSignature() {
        for (email, name) in [(["Kime: Mehmet Yılmaz <mehmet.yilmaz@example.com>", "Merhaba Mehmet,"], "Mehmet"),
                              (["Para: Juliana Souza <juliana.souza@example.com>", "Oi Juliana,"], "Juliana"),
                              (["إلى: مريم الحسن <maryam@example.com>", "مرحبا مريم,"], "مريم")] {
            let found = protect(email, PrivateDetail.recommended)
            XCTAssertEqual(found.covered.filter { $0.contains(name) }.count, 2, "\(email): \(found.covered)")
        }
        // An Arabic signature: the sender's name, and the address under it.
        let arabic = protect(["من: أحمد الخطيب <ahmad@example.com>", "مع خالص التحية", "أحمد الخطيب",
                              "طريق الملك عبدالله 132, الدمام 32241"], PrivateDetail.recommended)
        XCTAssertGreaterThanOrEqual(arabic.covered.filter { $0.contains("الخطيب") }.count, 2, "\(arabic.covered)")
        XCTAssertTrue(arabic.covered.contains { $0.contains("132") }, "\(arabic.covered)")
        XCTAssertFalse(arabic.covered.contains { $0.contains("التحية") }, "\(arabic.covered)")
    }

    func testAnAddressInsideAMessageInTurkishAndArabic() {
        for (line, address) in [("Emre: Şu adrese gönder Atatürk Caddesi No: 61, 06420 Çankaya/Ankara", "Çankaya/Ankara"),
                                ("Bağdat Caddesi No: 46 de buluşalım", "Bağdat Caddesi No: 46"),
                                ("خالد: أرسله إلى شارع العليا 76, الرياض 12271", "شارع العليا 76")] {
            XCTAssertTrue(protect([line], [.addresses]).covered.contains { $0.contains(address) }, line)
        }
        // "عن طريق" is "by way of", no street.
        XCTAssertTrue(protect(["أرسلها عن طريق البريد 3 مرات"], [.addresses]).covered.isEmpty)
    }

    // MARK: Helpers

    /// What the engine covers on a page as Vision read it, as
    /// `ScanReadingVisionTests` keeps it: a line each, its box round its
    /// words.
    private func protect(read dump: String, _ chosen: Set<PrivateDetail>)
        -> (covered: [String], checked: [String], possible: [String], hits: [Finder.Hit]) {
        var lines: [String] = [], boxes: [CGRect] = []
        for row in dump.split(separator: "\n").dropFirst() {
            let words = row.split(separator: " ").dropFirst().compactMap { part -> (text: String, box: CGRect)? in
                guard let at = part.lastIndex(of: "@") else { return nil }
                let box = part[part.index(after: at)...].split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
                guard box.count == 4 else { return nil }
                return (String(part[..<at]), CGRect(x: box[0], y: box[1], width: box[2], height: box[3]))
            }
            guard let first = words.first else { continue }
            lines.append(words.map(\.text).joined(separator: " "))
            boxes.append(words.dropFirst().reduce(first.box) { $0.union($1.box) })
        }
        func part(_ index: Int, _ range: Range<String.Index>) -> CGRect? {
            let line = lines[index], share = boxes[index].width / CGFloat(line.count)
            let start = CGFloat(line.distance(from: line.startIndex, to: range.lowerBound))
            return CGRect(x: boxes[index].minX + start * share, y: boxes[index].minY,
                          width: CGFloat(line.distance(from: range.lowerBound, to: range.upperBound)) * share,
                          height: boxes[index].height)
        }
        let found = Finder.findings(lines, boxes: boxes, part: part, chosen)
        func text(_ hit: Finder.Hit) -> String {
            let line = lines[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
        return (found.hits.map(text), found.hits.filter(\.check).map(text), found.possible.map(text), found.hits)
    }

    /// What the engine covers on a made-up page laid out in rows and
    /// columns, as `protect` does for one line per row.
    private func protect(form pieces: [FormFieldsTests.Piece], _ chosen: Set<PrivateDetail>)
        -> (covered: [String], checked: [String], possible: [String], hits: [Finder.Hit]) {
        let made = FormFieldsTests.layout(pieces)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, chosen)
        func text(_ hit: Finder.Hit) -> String {
            let line = made.strings[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
        return (found.hits.map(text), found.hits.filter(\.check).map(text), found.possible.map(text), found.hits)
    }

    /// What the engine covers, what it marks for checking and what it only
    /// offers, as text, with the lines laid out down a page.
    private func protect(_ lines: [String], _ chosen: Set<PrivateDetail>, rules: [OwnRule] = [])
        -> (covered: [String], checked: [String], possible: [String], hits: [Finder.Hit]) {
        let boxes = lines.indices.map { i in
            CGRect(x: 0.1, y: 0.9 - CGFloat(i) * 0.03, width: CGFloat(lines[i].count) * 0.01, height: 0.02)
        }
        func part(_ index: Int, _ range: Range<String.Index>) -> CGRect? {
            let line = lines[index]
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let count = line.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: boxes[index].minX + CGFloat(start) * 0.01, y: boxes[index].minY,
                          width: CGFloat(count) * 0.01, height: boxes[index].height)
        }
        let found = Finder.findings(lines, boxes: boxes, part: part, chosen, rules: rules)
        func text(_ hit: Finder.Hit) -> String {
            let line = lines[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
        return (found.hits.map(text), found.hits.filter(\.check).map(text), found.possible.map(text), found.hits)
    }
}
