import Foundation
import XCTest
@testable import Tendedero

/// Reading a document as a person would, without a picture: which words
/// are a person and which a company, whose name a name is, and where a
/// label's value stops being a name. The documents are made up for the
/// tests; none is a real one.
final class DocumentSenseTests: XCTestCase {
    /// A made-up radiology report: a practice's header, the patient's block,
    /// the referring doctor, the findings, and the signing doctor.
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

    private func text(_ line: String, _ range: Range<String.Index>?) -> String {
        range.map { String(line[$0]) } ?? line
    }

    func testTheKindOfDocumentComesFromItsWords() {
        XCTAssertEqual(DocumentSense.kind(of: report), .medical)
        XCTAssertEqual(DocumentSense.kind(of: ["Rechnung Nr. 1024", "Kunde: Lena Weber", "Summe 49,90 €", "MwSt 19 %"]),
                       .invoice)
        XCTAssertEqual(DocumentSense.kind(of: ["Kontoauszug", "IBAN DE89 3704 0044 0532 0130 00", "Saldo 1.234,00 €"]),
                       .banking)
        XCTAssertEqual(DocumentSense.kind(of: ["Hi Lena", "See you tomorrow"]), .general)
    }

    func testCompaniesAreNotPeople() {
        for text in ["Radiologie Zentrum Nord GmbH", "Klinikum Dortmund", "Muster GmbH", "Sparkasse KölnBonn",
                     "Gemeinschaftspraxis Am Markt", "Universitätsklinikum Hamburg-Eppendorf", "Acme Inc.",
                     "Techniker Krankenkasse", "Labor Berlin"] {
            XCTAssertTrue(DocumentSense.isOrganization(text), text)
            XCTAssertNil(DocumentSense.nameWords(text), text)
        }
        for text in ["Max Mustermann", "Anna Schmidt", "Lena Weber-Krause", "Laborwerte im Normbereich"] {
            XCTAssertFalse(DocumentSense.isOrganization(text), text)
        }
        XCTAssertFalse(DocumentSense.isOrganizationWord("Datenbank"))
        XCTAssertFalse(DocumentSense.isOrganizationWord("insgesamt"))
        XCTAssertTrue(DocumentSense.isOrganizationWord("Volksbank"))
        XCTAssertTrue(DocumentSense.isOrganizationWord("Radiologiepraxis"))
    }

    func testAnOrganizationsNameIsItsRunOfCapitalizedWords() {
        let line = "Radiologie Zentrum Nord GmbH, Hauptstraße 12"
        XCTAssertEqual(DocumentSense.organizationRanges(in: line).map { String(line[$0]) },
                       ["Radiologie Zentrum Nord GmbH"])
        // A lone word in a sentence names no organization.
        let sentence = "Sie kam in unsere Praxis zur Kontrolle."
        XCTAssertEqual(DocumentSense.organizationRanges(in: sentence).count, 0)
        let bank = "Empfänger: Sparkasse KölnBonn"
        XCTAssertEqual(DocumentSense.organizationRanges(in: bank).map { String(bank[$0]) }, ["Sparkasse KölnBonn"])
    }

    func testANameIsReadSurnameFirstToo() {
        XCTAssertEqual(DocumentSense.nameWords("Mustermann, Max"), ["mustermann", "max"])
        XCTAssertEqual(DocumentSense.nameWords("Max Mustermann"), ["max", "mustermann"])
        XCTAssertEqual(DocumentSense.nameWords("Ludwig van Beethoven"), ["ludwig", "beethoven"])
        XCTAssertNil(DocumentSense.nameWords("Max, Mustermann, Hamburg"))
        XCTAssertNil(DocumentSense.nameWords("Befund und Beurteilung"))
        XCTAssertNil(DocumentSense.nameWords("Sehr geehrte Frau Kollegin"))
        XCTAssertNil(DocumentSense.nameWords("Max Mustermann 1960"))
        // Arabic has no capitals: a line alone is never taken for a name.
        XCTAssertNil(DocumentSense.nameWords("أحمد علي"))
    }

    func testALabelsValueIsCutWhereTheNameEnds() {
        func lead(_ line: String) -> String? {
            let start = line.firstIndex(of: ":").map { line.index(after: $0) } ?? line.startIndex
            return DocumentSense.leadingName(in: line, from: start).map { String(line[$0]) }
        }
        XCTAssertEqual(lead("Patient: Mustermann, Max, geb. 01.02.1960"), "Mustermann, Max")
        XCTAssertEqual(lead("Name: Max Mustermann, Musterstraße 5, 12345 Berlin"), "Max Mustermann")
        XCTAssertEqual(lead("Kunde: Frau Lena Weber (Kundennr. 4711)"), "Lena Weber")
        XCTAssertEqual(lead("Patientin: Weber"), "Weber")
        XCTAssertEqual(lead("Behandelnder Arzt: Dr. med. Klaus Weber"), "Klaus Weber")
        XCTAssertEqual(lead("المريض: أحمد علي"), "أحمد علي")
        XCTAssertNil(lead("Name: 4711"))
        XCTAssertNil(lead("Kunde: Muster GmbH"))
    }

    func testANameAfterATitleIsFoundInASentence() {
        let line = report[7]
        let found = DocumentSense.titledNames(in: line)
        XCTAssertEqual(found.map { String(line[$0.range]) }, ["Max Mustermann"])
        XCTAssertEqual(found.first?.title, "Herrn")
        let doctor = report[1]
        XCTAssertEqual(DocumentSense.titledNames(in: doctor).map { String(doctor[$0.range]) }, ["Anna Schmidt"])
        XCTAssertEqual(DocumentSense.titledNames(in: doctor).first?.title, "Dr. med.")
        // A salutation names nobody.
        XCTAssertTrue(DocumentSense.titledNames(in: "Sehr geehrte Frau Kollegin,").isEmpty)
        let title = "Sehr geehrte Frau Dr. Schmidt,"
        XCTAssertEqual(DocumentSense.titledNames(in: title).map { String(title[$0.range]) }, ["Schmidt"])
    }

    func testTitlesAreLeftOutOfAName() {
        func trimmed(_ line: String) -> String? {
            DocumentSense.trimmingTitles(line.startIndex..<line.endIndex, in: line).map { String(line[$0]) }
        }
        XCTAssertEqual(trimmed("Frau Dr. Lena Weber"), "Lena Weber")
        XCTAssertEqual(trimmed("Herrn Prof. Dr. med. Max Mustermann"), "Max Mustermann")
        XCTAssertEqual(trimmed("Lena Weber"), "Lena Weber")
        XCTAssertNil(trimmed("Frau Dr."))
        XCTAssertNil(DocumentSense.nameWords("Morbus Crohn"), "a disease, though named after a person")
    }

    func testThePatientAndTheDoctorsAreToldApart() {
        let kind = DocumentSense.kind(of: report)
        func role(_ index: Int, _ name: String, title: String? = nil) -> NameRole {
            let line = report[index]
            return DocumentSense.role(ofNameIn: index, at: line.range(of: name), title: title, lines: report, kind: kind)
        }
        XCTAssertEqual(role(4, "Mustermann, Max").role, .patient)
        XCTAssertTrue(role(4, "Mustermann, Max").isSure)
        XCTAssertEqual(role(5, "Klaus Weber", title: "Dr. med.").role, .doctor)
        XCTAssertEqual(role(1, "Anna Schmidt", title: "Dr. med.").role, .doctor)
        XCTAssertEqual(role(7, "Max Mustermann", title: "Herrn").role, .patient)
        // The name under the closing signs the letter.
        XCTAssertEqual(role(10, "Anna Schmidt").role, .doctor)
        XCTAssertTrue(role(10, "Anna Schmidt").isSure)
        // A doctor's title on a patient: the label wins.
        let lines = ["Arztbrief", "Patient: Dr. Hans Meier", "Diagnose: Gastritis"]
        let named = DocumentSense.role(ofNameIn: 1, at: lines[1].range(of: "Hans Meier"), title: "Dr.", lines: lines,
                                       kind: .medical)
        XCTAssertEqual(named.role, .patient)
        // A label further back in a sentence says nothing of the name.
        let sentence = ["Befund", "Der Patient wurde von Dr. med. Ulrich Bauer untersucht."]
        let doctor = DocumentSense.role(ofNameIn: 1, at: sentence[1].range(of: "Ulrich Bauer"), title: "Dr. med.",
                                        lines: sentence, kind: .medical)
        XCTAssertEqual(doctor.role, .doctor)
    }

    func testCustomersStaffAndAccountHoldersAreToldApart() {
        let invoice = ["Rechnung Nr. 1024", "Kundenname: Lena Weber", "Ihr Ansprechpartner: Jonas Kraft",
                       "Summe 49,90 €"]
        let kind = DocumentSense.kind(of: invoice)
        XCTAssertEqual(DocumentSense.role(ofNameIn: 1, at: invoice[1].range(of: "Lena Weber"), lines: invoice,
                                          kind: kind).role, .customer)
        XCTAssertEqual(DocumentSense.role(ofNameIn: 2, at: invoice[2].range(of: "Jonas Kraft"), lines: invoice,
                                          kind: kind).role, .employee)
        let bank = ["Kontoauszug", "Kontoinhaber: Max Mustermann", "IBAN DE89 3704 0044 0532 0130 00"]
        XCTAssertEqual(DocumentSense.role(ofNameIn: 1, at: bank[1].range(of: "Max Mustermann"), lines: bank,
                                          kind: .banking).role, .customer)
        // A label alone on the line above.
        let card = ["Kunde", "Lena Weber", "5 Bestellungen"]
        let named = DocumentSense.role(ofNameIn: 1, at: nil, lines: card, kind: .invoice)
        XCTAssertEqual(named.role, .customer)
        XCTAssertTrue(named.isSure)
        // Nothing round a name: no role, and not sure.
        XCTAssertFalse(DocumentSense.role(ofNameIn: 0, at: nil, lines: ["Lena Weber"], kind: .general).isSure)
        XCTAssertEqual(DocumentSense.role(ofLabel: "Behandelnder Arzt"), .doctor)
        XCTAssertNil(DocumentSense.role(ofLabel: "Name"))
        XCTAssertNil(DocumentSense.role(ofLabel: "Kundennummer"), "a number's label, not a person's")
        XCTAssertNil(DocumentSense.role(ofLabel: "Agentur für Arbeit"))
    }

    func testOnlyTheChosenPeopleAreCoveredAndUnsureOnesAreChecked() {
        let patients = NameScope(roles: [.patient])
        XCTAssertEqual(patients.decide(NameRole(role: .patient, confidence: 0.9, reason: "label")), .cover)
        XCTAssertEqual(patients.decide(NameRole(role: .doctor, confidence: 0.9, reason: "title")), .leave)
        XCTAssertEqual(patients.decide(.unknown), .coverAndCheck)
        XCTAssertEqual(NameScope.everyone.decide(NameRole(role: .doctor, confidence: 0.9, reason: "title")), .cover)
        XCTAssertEqual(NameScope.everyone.decide(.unknown), .cover)
    }

    func testTheScopeIsKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DocumentSenseTests"))
        defaults.removePersistentDomain(forName: "DocumentSenseTests")
        XCTAssertEqual(NameScope.load(from: defaults), .everyone)
        NameScope(roles: [.patient, .customer]).save(to: defaults)
        XCTAssertEqual(NameScope.load(from: defaults).roles, [.patient, .customer])
        NameScope.everyone.save(to: defaults)
        XCTAssertEqual(NameScope.load(from: defaults), .everyone)
    }
}
