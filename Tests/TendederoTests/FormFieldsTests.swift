import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Reading a printed form's fields as a person does: each label, and the
/// value beside it or under it in its column, told by what the label says it
/// is. The forms are made up for the tests, laid out as text recognition
/// reads one; no real person's details are in them, and none is the
/// document a fault was first seen in.
final class FormFieldsTests: XCTestCase {
    /// A line of a made-up page: its text, where it starts across the page,
    /// and its row from the top.
    typealias Piece = (text: String, x: CGFloat, row: Int)

    /// A certificate of incapacity for work, as a doctor's printer fills it
    /// in: separate pieces where the printer leaves space, one line where it
    /// does not, as row 7 and 8 are read.
    static let sickNote: [Piece] = [
        ("Krankenkasse bzw. Kostenträger", 0.05, 0),
        ("Muster BKK", 0.05, 1),
        ("Name, Vorname des Versicherten", 0.05, 2),
        ("Mustermann", 0.05, 3), ("geb. am", 0.45, 3),
        ("Erika", 0.05, 4), ("12.03.1985", 0.45, 4),
        ("Beispielweg 7", 0.05, 5),
        ("54321 Musterstadt", 0.05, 6),
        ("Kostenträgerkennung   Versicherten-Nr.   Status", 0.05, 7),
        ("101234567             X987654321         5000001", 0.05, 8),
        ("Betriebsstätten-Nr.", 0.05, 9), ("Arzt-Nr.", 0.30, 9), ("Datum", 0.50, 9),
        ("998877665", 0.05, 10), ("112233445", 0.30, 10), ("05.10.26", 0.50, 10),
        ("Arbeitsunfähigkeitsbescheinigung", 0.05, 11),
        ("Erstbescheinigung", 0.05, 12),
        ("Arbeitsunfähig seit", 0.05, 13), ("02.10.26", 0.45, 13),
        ("voraussichtlich arbeitsunfähig bis einschließlich", 0.05, 14), ("09.10.26", 0.60, 14),
        ("festgestellt am", 0.05, 15), ("05.10.26", 0.45, 15),
        ("AU-begründende Diagnose(n) (ICD-10)", 0.05, 16),
        ("J06.9 G", 0.05, 17),
        ("Akute Infektion der oberen Atemwege", 0.05, 18),
        ("Dr. med. Paul Beispiel", 0.05, 20),
        ("Praxisstraße 3, 54321 Musterstadt", 0.05, 21),
        ("Vertragsarztstempel / Unterschrift des Arztes", 0.05, 22),
    ]

    func testEachFieldOfTheSickNoteIsWhatItsLabelSays() {
        let read = Self.read(Self.sickNote)
        let expected: [(String, FormFields.Entity)] = [
            ("Muster BKK", .institution),
            ("Mustermann", .personName), ("Erika", .personName),
            ("Beispielweg 7", .address), ("54321 Musterstadt", .address),
            ("12.03.1985", .dateOfBirth),
            ("101234567", .institutionNumber), ("X987654321", .healthInsuranceNumber),
            ("998877665", .institutionNumber), ("112233445", .identificationNumber),
            ("02.10.26", .medicalDate), ("09.10.26", .medicalDate),
            ("J06.9 G", .medicalDiagnosis), ("Akute Infektion der oberen Atemwege", .medicalDiagnosis),
        ]
        for (text, entity) in expected {
            XCTAssertEqual(read.values.first { $0.text == text }?.entity, entity, "\(text) in \(read.values)")
        }
        // The date the note was written is a date, and the day it was found a health detail.
        XCTAssertEqual(Set(read.values.filter { $0.text == "05.10.26" }.map(\.entity)), [.date, .medicalDate])
        // The status the form prints is read as its code, so nothing takes it for a private number.
        XCTAssertEqual(read.values.first { $0.text == "5000001" }?.entity, .formCode)
        // What the form prints is no one's details.
        for kept in ["Arbeitsunfähigkeitsbescheinigung", "Erstbescheinigung", "Paul Beispiel",
                     "Praxisstraße 3, 54321 Musterstadt", "Vertragsarztstempel"] {
            XCTAssertFalse(read.values.contains { $0.text.contains(kept) }, "\(kept) is no field's value: \(read.values)")
        }
        XCTAssertTrue(read.values.allSatisfy { $0.confidence == .high }, "\(read.values)")
    }

    func testTheInsuredPersonIsThePatient() {
        let read = Self.read(Self.sickNote)
        XCTAssertEqual(read.values.first { $0.text == "Mustermann" }?.role, .patient)
        XCTAssertEqual(read.values.first { $0.text == "X987654321" }?.role, .patient)
        XCTAssertEqual(read.values.first { $0.text == "112233445" }?.role, .doctor)
    }

    func testTheLabelsAreKnownAsLabels() {
        let pieces = Self.sickNote
        let made = Self.layout(pieces)
        let reading = FormFields.read(made.strings, boxes: made.boxes, part: made.part)
        let header = pieces.firstIndex { $0.text.hasPrefix("Kostenträgerkennung") }!
        XCTAssertTrue(reading.isLabel(nil, in: header, of: made.strings[header]), "a row of labels alone")
        let name = pieces.firstIndex { $0.text.hasPrefix("Name, Vorname") }!
        XCTAssertTrue(reading.isLabel(nil, in: name, of: made.strings[name]))
        let surname = pieces.firstIndex { $0.text == "Mustermann" }!
        XCTAssertFalse(reading.isLabel(nil, in: surname, of: made.strings[surname]))
    }

    func testAMergedRowOfHeadingsSplitsItsValuesByColumn() {
        let read = Self.read([("Befundbericht", 0.05, 0),
                              ("Name        Vorname     Geburtsdatum", 0.05, 1),
                              ("Mustermann  Erika       12.03.1985", 0.05, 2)])
        XCTAssertEqual(read.values.map(\.text), ["Mustermann", "Erika", "12.03.1985"])
        XCTAssertEqual(read.values.map(\.entity), [.personName, .personName, .dateOfBirth])
    }

    func testAValueOnTheLabelsLine() {
        let read = Self.read([("Diagnose: Morbus Crohn", 0.05, 0), ("Arbeitsunfähig seit 02.10.2026", 0.05, 1),
                              ("Name, Vorname: Mustermann, Erika", 0.05, 2)])
        XCTAssertEqual(read.values.map(\.text), ["Morbus Crohn", "02.10.2026", "Mustermann, Erika"])
        XCTAssertEqual(read.values.map(\.entity), [.medicalDiagnosis, .medicalDate, .personName])
    }

    func testAWordOfALabelInASentenceAnnouncesNothing() {
        let read = Self.read([("Name und Anschrift bitte angeben", 0.05, 0), ("Erika Mustermann", 0.05, 1),
                              ("Die Diagnose wurde besprochen.", 0.05, 2), ("Gastritis", 0.05, 3)])
        XCTAssertEqual(read.values.map(\.text), [])
    }

    func testAStatusInASentenceIsNoField() {
        let read = Self.read([("Ihr Status 12345 ist aktiv", 0.05, 0), ("Status: 5000001", 0.05, 1)])
        XCTAssertEqual(read.values.map(\.text), ["5000001"])
    }

    func testALineUnderALabelMustStartInItsColumn() {
        let read = Self.read([("Datum", 0.50, 0), ("Wir bitten um Rückmeldung bis 05.10.2026", 0.05, 1)])
        XCTAssertEqual(read.values.map(\.text), [], "a sentence further left is not the date's value")
    }

    func testANumberTooShortIsOnlyOffered() {
        let read = Self.read([("Versicherten-Nr.: 1234", 0.05, 0)])
        XCTAssertEqual(read.values.map(\.text), ["1234"])
        XCTAssertEqual(read.values.first?.confidence, .low)
    }

    func testANameOfLettersButNoNamesShapeIsToBeChecked() {
        let read = Self.read([("Name des Versicherten", 0.05, 0), ("mustermann erika", 0.05, 1)])
        XCTAssertEqual(read.values.first?.text, "mustermann erika")
        XCTAssertEqual(read.values.first?.confidence, .medium)
    }

    func testAnAddressIsAStreetOrAPostcodeWithItsTown() {
        for text in ["Beispielweg 7", "Hauptstr. 12a", "54321 Musterstadt", "D-54321 Musterstadt"] {
            XCTAssertTrue(FormFields.isAddress(text[...]), text)
        }
        for text in ["Erika", "Mustermann, Erika", "J06.9 G", "12.03.1985"] {
            XCTAssertFalse(FormFields.isAddress(text[...]), text)
        }
    }

    // MARK: Helpers

    /// The pieces as text recognition gives them: a line each, a hundredth
    /// of the page wide for each letter, rows three hundredths apart.
    static func layout(_ pieces: [Piece]) -> (strings: [String], boxes: [CGRect],
                                              part: (Int, Range<String.Index>) -> CGRect?) {
        let strings = pieces.map(\.text)
        let boxes = pieces.map { piece in
            CGRect(x: piece.x, y: 0.9 - CGFloat(piece.row) * 0.03, width: CGFloat(piece.text.count) * 0.01, height: 0.02)
        }
        let part: (Int, Range<String.Index>) -> CGRect? = { index, range in
            let line = strings[index]
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let count = line.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: boxes[index].minX + CGFloat(start) * 0.01, y: boxes[index].minY,
                          width: CGFloat(count) * 0.01, height: boxes[index].height)
        }
        return (strings, boxes, part)
    }

    struct ReadValue: CustomStringConvertible {
        let text: String
        let entity: FormFields.Entity
        let role: PersonRole?
        let confidence: FormFields.Confidence
        var description: String { "\(text)=\(entity.rawValue)" }
    }

    static func read(_ pieces: [Piece]) -> (values: [ReadValue], reading: FormFields.Reading) {
        let made = layout(pieces)
        let reading = FormFields.read(made.strings, boxes: made.boxes, part: made.part)
        let values = reading.values.map { value in
            ReadValue(text: String(made.strings[value.line][value.range]), entity: value.entity, role: value.role,
                      confidence: value.confidence)
        }
        return (values, reading)
    }
}
