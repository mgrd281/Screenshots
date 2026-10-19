import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// What is covered of a whole document, kind by kind, without a picture:
/// finding, telling what each find is, and covering only what the owner
/// chose are kept apart. With Names on, a person's name is covered and
/// nothing else: not a company, a phone number, an address, a date, an
/// amount or a diagnosis. With Patient names alone, the doctors' names
/// stay, and every place the patient is named is covered. The documents are
/// made up for the tests; none is a real one, and none is the screenshot a
/// fault was first seen in.
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

    func testNamesAloneCoverThePeopleAndNothingElse() {
        let found = protect(report, [.names])
        for name in ["Anna Schmidt", "Mustermann, Max", "Klaus Weber", "Max Mustermann"] {
            XCTAssertTrue(found.covered.contains(name), "\(name) in \(found.covered)")
        }
        for kept in ["GmbH", "Radiologie", "Hauptstraße", "Hamburg", "040", "1960", "Fraktur", "Befund", "Dr.", "geb."] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(found.covered)")
        }
        XCTAssertTrue(found.hits.allSatisfy { $0.kind == .names }, "only names, with Names alone")
    }

    func testNamesAloneLeaveTheShopTheAddressAndTheMoney() {
        let found = protect(invoice, [.names])
        XCTAssertTrue(found.covered.contains("Lena Weber"), "\(found.covered)")
        for kept in ["Muster Versand", "Musterweg", "Berlin", "1234567", "49,90", "DE89", "Sparkasse", "2024"] {
            XCTAssertFalse(found.covered.contains { $0.contains(kept) }, "\(kept) stays: \(found.covered)")
        }
    }

    func testCompaniesAreCoveredOnlyAsCompanies() {
        let names = protect(invoice, [.names])
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
        // With everyone's names covered, there is nothing to check.
        XCTAssertTrue(protect(lines, [.names]).checked.isEmpty)
    }

    func testTheDiagnosisIsHealthNotAName() {
        let found = protect(["Patientin: Weber, Lena", "Diagnose: Morbus Crohn"], [.health])
        XCTAssertTrue(found.covered.contains("Morbus Crohn"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Lena") }, "\(found.covered)")
        let names = protect(["Patientin: Weber, Lena", "Diagnose: Morbus Crohn"], [.names])
        XCTAssertEqual(names.covered.filter { $0.contains("Crohn") }, [], "a disease named after a person is no name")
    }

    func testANameIsCoveredWithoutItsTitleOrWhatFollowsIt() {
        let found = protect(["Arztbrief", "Behandelnder Arzt: Dr. med. Klaus Weber",
                             "Kunde: Frau Lena Weber (Kundennr. 4711)"], [.names])
        XCTAssertTrue(found.covered.contains("Klaus Weber"), "\(found.covered)")
        XCTAssertTrue(found.covered.contains("Lena Weber"), "\(found.covered)")
        XCTAssertFalse(found.covered.contains { $0.contains("Dr.") || $0.contains("Frau") || $0.contains("4711") },
                       "\(found.covered)")
    }

    func testEveryKindChosenIsCoveredAsItself() {
        let found = protect(invoice, [.names, .addresses, .phones, .amounts, .bank, .organizations, .orders])
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
        let found = protect(letter, [.names])
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

    func testAPlaceFoundTwiceIsCountedOnce() {
        let found = protect(["Patient: Herr Max Mustermann"], [.names])
        XCTAssertEqual(found.hits.count, 1, "\(found.covered)")
    }

    // MARK: Helpers

    /// What the engine covers, what it marks for checking and what it only
    /// offers, as text, with the lines laid out down a page.
    private func protect(_ lines: [String], _ chosen: Set<PrivateDetail>)
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
        let found = Finder.findings(lines, boxes: boxes, part: part, chosen)
        func text(_ hit: Finder.Hit) -> String {
            let line = lines[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
        return (found.hits.map(text), found.hits.filter(\.check).map(text), found.possible.map(text), found.hits)
    }
}
