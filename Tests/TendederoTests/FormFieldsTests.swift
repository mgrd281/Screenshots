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

    /// The insured person's copy of a made-up certificate of incapacity for
    /// work: the header's boxes at the left, the checkboxes' captions and the
    /// doctor's stamp at the right, the stamp repeating the practice's and the
    /// doctor's numbers. No real person's details.
    static let insuredCopy: [Piece] = [
        ("Krankenkasse bzw. Kostenträger", 0.05, 0), ("Arbeitsunfähigkeitsbescheinigung", 0.62, 0),
        ("Muster BKK", 0.05, 1), ("Erstbescheinigung", 0.62, 1),
        ("Name, Vorname des Versicherten", 0.05, 2), ("Arbeitsunfall, Arbeitsunfallfolgen, Berufskrankheit", 0.62, 2),
        ("Beispielyan", 0.05, 3), ("geb. am", 0.45, 3), ("dem Durchgangsarzt zugewiesen", 0.62, 3),
        ("Nare", 0.05, 4), ("14.03.1987", 0.45, 4),
        ("Sonnenhang 9", 0.05, 5),
        ("D 12345 Musterstadt", 0.05, 6),
        ("Kostenträgerkennung   Versicherten-Nr.   Status", 0.05, 7),
        ("101234567             X987654321         5000001", 0.05, 8),
        ("Betriebsstätten-Nr.", 0.05, 9), ("Arzt-Nr.", 0.25, 9), ("Datum", 0.40, 9),
        ("021234560", 0.05, 10), ("345678812", 0.25, 10), ("05.10.26", 0.40, 10),
        ("Arbeitsunfähig seit", 0.05, 12), ("02.10.26", 0.40, 12),
        ("festgestellt am", 0.05, 14), ("05.10.26", 0.40, 14),
        ("AU-begründende Diagnose(n) (ICD-10)", 0.05, 16),
        ("M54.5 G", 0.05, 17),
        ("sonstiger Unfall, Unfallfolgen", 0.05, 19), ("Versorgungsleiden (BVG)", 0.40, 19),
        // The doctor's stamp.
        ("021234560", 0.62, 12), ("Lindenallee 12", 0.62, 13), ("20999 Musterstadt", 0.62, 14),
        ("Tel. 040 1234567", 0.62, 15), ("Fax 040 1234568", 0.62, 16),
        ("Dr. med. Hanna Beispiel", 0.62, 17), ("Fachärztin", 0.62, 18), ("für Chirurgie /", 0.73, 18),
        ("Proktologie", 0.62, 19), ("345678812", 0.62, 20),
        ("Vertragsarztstempel / Unterschrift des Arztes", 0.62, 21),
        ("Ausfertigung für Versicherte", 0.05, 23),
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

    // MARK: A scanned certificate

    /// The insured person's copy of a made-up certificate of incapacity for
    /// work, scanned: its labels in small print, some read a letter off; a
    /// checkbox's words at the right between the name's label and the
    /// surname; "geb. am" between the surname and the given name, which is
    /// read as one line with the date of birth at its right; the boxes'
    /// borders read as strokes; and the doctor's stamp at the right,
    /// repeating the practice's and the doctor's numbers.
    static let scannedSickNote: [[Printed]] = [
        [("Krankenkasse bzw. Kostenträger", 0.05, 0, true)],
        [("AOK Musterland", 0.05, 1, false)],
        [("Name, Vomame des Versicherlen", 0.05, 2, true)],
        [("Arbeitsunfall, Arbeitsunfallfolgen, Berufskrankheit", 0.60, 2.4, true)],
        [("| Beispielyan", 0.04, 3, false)],
        [("geb. am", 0.40, 3.5, true)],
        [("Nare", 0.05, 4, false), ("14.03.1987", 0.40, 4, false)],
        [("Sonnenhang 9 |", 0.05, 5, false)],
        [("D 12345 Musterstadt", 0.05, 6, false)],
        [("Kostentrâgerkennung", 0.05, 7, true), ("Versicherlen-Nr.", 0.25, 7, true), ("Status", 0.45, 7, true)],
        [("101234567", 0.05, 8, false), ("|", 0.23, 8, false), ("X123456789", 0.25, 8, false), ("I", 0.43, 8, false),
         ("5000001", 0.45, 8, false)],
        [("Betriebsstätlen-Nr.", 0.05, 9, true), ("Arzt-Nr.", 0.25, 9, true), ("Datum", 0.45, 9, true)],
        [("021234560", 0.05, 10, false)], [("l345678812", 0.24, 10, false)], [("05.10.2026ł", 0.45, 10, false)],
        [("arbeitsunfähig seit", 0.05, 12, true), ("02.10.2026", 0.30, 12, false)],
        [("festgestellt am", 0.05, 14, true), ("05.10.2026", 0.30, 14, false)],
        [("021234560", 0.60, 11, false)], [("Lindenallee 12", 0.60, 12, false)],
        [("20999 Musterstadt", 0.60, 13, false)], [("Tel.: 040-1234567", 0.60, 14, false)],
        [("Fax: 040-1234568", 0.60, 15, false)], [("Dr. med. Hanna Beispiel", 0.60, 16, false)],
        [("Fachärztin für Chirurgie /", 0.60, 17, false)], [("Proktologie", 0.60, 18, false)],
        [("345678812", 0.60, 19, false)],
        [("Vertragsarztstempel / Unterschrift des Arztes", 0.60, 20, true)],
        [("AU-begründende Diagnose(n) (ICD-10)", 0.05, 17, true)],
        [("M54.5 G", 0.05, 18, false)],
        [("sonstiger Unfall, Unfallfolgen", 0.05, 19, true), ("Versorgungsleiden (BVG)", 0.30, 19, true)],
    ]

    func testAScannedSickNoteIsReadAsItsLabelsSay() {
        let read = Self.read(scan: Self.scannedSickNote).values
        let expected: [(String, FormFields.Entity, PersonRole?)] = [
            ("AOK Musterland", .institution, nil),
            ("Beispielyan", .personName, .patient), ("Nare", .personName, .patient),
            ("Sonnenhang 9", .address, .patient), ("D 12345 Musterstadt", .address, .patient),
            ("14.03.1987", .dateOfBirth, nil),
            ("101234567", .institutionNumber, nil), ("X123456789", .healthInsuranceNumber, .patient),
            ("5000001", .formCode, nil),
            ("021234560", .institutionNumber, nil), ("345678812", .identificationNumber, .doctor),
            ("02.10.2026", .medicalDate, nil), ("M54.5 G", .medicalDiagnosis, nil),
        ]
        for (text, entity, role) in expected {
            let value = read.first { $0.text == text }
            XCTAssertEqual(value?.entity, entity, "\(text) in \(read)")
            XCTAssertEqual(value?.role, role, "\(text) in \(read)")
        }
        // The note's date is a date; the day the illness was found, a health detail.
        XCTAssertEqual(Set(read.filter { $0.text == "05.10.2026" }.map(\.entity)), [.date, .medicalDate], "\(read)")
        // What the form prints, and the doctor's stamp but its numbers, is no field's value.
        for printed in ["Arbeitsunfall", "Berufskrankheit", "Proktologie", "sonstiger", "Versorgungsleiden",
                        "Kostent", "Versicher", "geb. am", "Lindenallee", "Tel", "Fax", "Hanna", "|"] {
            XCTAssertFalse(read.contains { $0.text.contains(printed) }, "\(printed) is no field's value: \(read)")
        }
    }

    func testAScannedSickNotesLabelsAreKnownAsLabels() {
        let (_, reading, strings) = Self.read(scan: Self.scannedSickNote)
        for start in ["Name, Vomame", "Kostentrâgerkennung", "Betriebsstätlen", "Arbeitsunfall,", "sonstiger Unfall"] {
            let line = strings.firstIndex { $0.hasPrefix(start) }!
            XCTAssertTrue(reading.isLabel(nil, in: line, of: strings[line]), strings[line])
        }
    }

    func testATinyLabelReadALetterOffIsStillItsLabel() {
        let read = Self.read([("Name, Vomame des Versicherlen", 0.05, 0), ("Beispielyan", 0.05, 1),
                              ("Betriebsstätlen-Nr.", 0.05, 3), ("998877665", 0.05, 4)]).values
        XCTAssertEqual(read.map(\.text), ["Beispielyan", "998877665"])
        XCTAssertEqual(read.map(\.entity), [.personName, .institutionNumber])
        XCTAssertEqual(read.first?.role, .patient)
    }

    func testAnotherWordALetterFromALabelIsNoLabel() {
        // "Nachnahme" is cash on delivery, "arbeitsfähig" the opposite of the label's word.
        let read = Self.read([("Nachnahme", 0.05, 0), ("Beispielyan", 0.05, 1),
                              ("arbeitsfähig seit 02.10.2026", 0.05, 3)]).values
        XCTAssertEqual(read.map(\.text), [], "\(read)")
    }

    func testAMisreadWordIsALabelsWordReadALetterOff() {
        for (read, meant) in [("Vomame", "Vorname"), ("Versicherlen", "Versicherten"),
                              ("Kostentrâgerkennung", "Kostenträgerkennung"), ("Betriebsstätlen", "Betriebsstätten"),
                              ("einschlieBlich", "einschließlich")] {
            XCTAssertTrue(FormFields.reads(read, as: meant), "\(read) is \(meant) misread")
        }
        // A letter more or less, two letters off in a word of twelve, or one in a short word: another word.
        for (read, meant) in [("Nachnahme", "Nachname"), ("arbeitsfähig", "arbeitsunfähig"),
                              ("Kartennummer", "Kassennummer"), ("Name", "Nase")] {
            XCTAssertFalse(FormFields.reads(read, as: meant), "\(read) is no \(meant)")
        }
    }

    func testABoxsBordersAreNoPartOfItsValue() {
        let read = Self.read([("Name des Versicherten", 0.05, 0), ("| Beispielyan", 0.04, 1), ("Nare |", 0.05, 2),
                              ("Arzt-Nr.", 0.05, 4), ("l345678812", 0.045, 5),
                              ("Datum", 0.05, 6), ("05.10.2026ł", 0.05, 7)]).values
        XCTAssertEqual(read.map(\.text), ["Beispielyan", "Nare", "345678812", "05.10.2026"])
        XCTAssertEqual(read.map(\.entity), [.personName, .personName, .identificationNumber, .date])
    }

    func testABoxsBorderStuckToANumberIsNotPartOfIt() {
        for number in ["345678812ł", "l345678812", "345678812l", "|345678812", "345678812 |"] {
            let read = Self.read([("Betriebsstätten-Nr.", 0.05, 0), ("Arzt-Nr.", 0.30, 0), ("Datum", 0.50, 0),
                                  ("021234560", 0.05, 1), (number, 0.30, 1), ("05.10.26ł", 0.50, 1)]).values
            XCTAssertEqual(read.first { $0.text == "345678812" }?.entity, .identificationNumber, "\(number): \(read)")
            XCTAssertEqual(read.first { $0.text == "021234560" }?.entity, .institutionNumber, "\(number): \(read)")
            XCTAssertEqual(read.first { $0.text == "05.10.26" }?.entity, .date, "\(number): \(read)")
        }
        // A border, or a comma, read after the label is no value: the number under it is.
        for label in ["Arzt-Nr.ł", "Arzt-Nr.,", "Arzt-Nr. |"] {
            let read = Self.read([(label, 0.30, 0), ("345678812", 0.30, 1)]).values
            XCTAssertEqual(read.map(\.text), ["345678812"], label)
        }
        // A capital letter before the digits may be the number's own.
        XCTAssertEqual(Self.read([("Versicherten-Nr.", 0.05, 0), ("X987654321", 0.05, 1)]).values.map(\.text),
                       ["X987654321"])
    }

    func testALabelReadOnTheGivenNamesLineEndsOnlyItsPart() {
        // "geb. am" between the surname and the given name, read with the given name's line.
        let read = Self.read(scan: [
            [("Name, Vorname des Versicherten", 0.05, 0, true)],
            [("Beispielyan", 0.05, 1, false)],
            [("Nare", 0.05, 2, false), ("geb. am", 0.40, 1.6, true), ("14.03.1987", 0.40, 2, false)],
            [("Sonnenhang 9", 0.05, 3, false)], [("D 12345 Musterstadt", 0.05, 4, false)],
        ]).values
        XCTAssertEqual(read.map(\.text), ["Beispielyan", "Nare", "Sonnenhang 9", "D 12345 Musterstadt", "14.03.1987"])
        XCTAssertEqual(read.map(\.entity), [.personName, .personName, .address, .address, .dateOfBirth])
        // On a line of its own between the two, it ends nothing.
        let alone = Self.read(scan: [
            [("Name, Vorname des Versicherten", 0.05, 0, true)],
            [("Beispielyan", 0.05, 1, false)], [("geb. am", 0.40, 1.6, true)],
            [("14.03.1987", 0.40, 2, false)], [("Nare", 0.05, 2, false)],
            [("Sonnenhang 9", 0.05, 3, false)], [("D 12345 Musterstadt", 0.05, 4, false)],
        ]).values
        XCTAssertEqual(Set(alone.map(\.text)), ["Beispielyan", "Nare", "Sonnenhang 9", "D 12345 Musterstadt", "14.03.1987"])
        XCTAssertEqual(alone.first { $0.text == "Nare" }?.entity, .personName)
        // Printed nearly on the surname's row and read with the given name's
        // line, it does not lift that line onto the surname's.
        let high = Self.read(scan: [
            [("Name, Vorname des Versicherten", 0.05, 0, true)],
            [("Beispielyan", 0.05, 1, false)],
            [("Nare", 0.05, 1.8, false), ("geb. am", 0.40, 1.15, true), ("14.03.1987", 0.40, 1.8, false)],
            [("Sonnenhang 9", 0.05, 2.8, false)], [("D 12345 Musterstadt", 0.05, 3.8, false)],
        ]).values
        XCTAssertEqual(high.map(\.text), ["Beispielyan", "Nare", "Sonnenhang 9", "D 12345 Musterstadt", "14.03.1987"])
    }

    func testARowOfBoxesReadAsOneLineUnderALabelAloneOnItsRow() {
        // The label before "Arzt-Nr." was not read, so it stands alone on its row.
        let read = Self.read([("Arzt-Nr.", 0.25, 0), ("998877665         112233445", 0.05, 1)]).values
        XCTAssertEqual(read.map(\.text), ["112233445"])
        XCTAssertEqual(read.first?.entity, .identificationNumber)
        // A sentence's words under a label are not a box's value.
        XCTAssertEqual(Self.read([("Datum", 0.30, 0), ("Wir bitten um Rückmeldung bis 05.10.2026", 0.05, 1)]).values.map(\.text), [])
    }

    func testWordsAcrossThePageAreNoValueOfALabel() {
        let read = Self.read(scan: [
            [("Name, Vorname des Versicherten", 0.05, 0, true), ("Ausfertigung für Versicherte", 0.60, 0, true)],
            [("Bitte dem Arbeitgeber vorlegen", 0.60, 0.4, true)],
            [("Beispielyan", 0.05, 1, false)], [("Nare", 0.05, 2, false)],
        ]).values
        XCTAssertEqual(read.map(\.text), ["Beispielyan", "Nare"], "\(read)")
    }

    func testTheLastLabelOfARowTakesNoLineFromABlockToItsRight() {
        // The name's label has no label to its right on its row, so its column
        // reaches across the page; the stamp's first line, at the right and a
        // little higher than the surname, is no part of the name.
        let read = Self.read(boxed: [
            ("Name, Vorname des Versicherten", CGRect(x: 0.05, y: 0.840, width: 0.18, height: 0.012)),
            ("021234560", CGRect(x: 0.62, y: 0.825, width: 0.072, height: 0.012)),
            ("Beispielyan", CGRect(x: 0.05, y: 0.810, width: 0.11, height: 0.02)),
            ("Nare", CGRect(x: 0.05, y: 0.780, width: 0.04, height: 0.02)),
            ("Sonnenhang 9", CGRect(x: 0.05, y: 0.750, width: 0.12, height: 0.02)),
            ("D 12345 Musterstadt", CGRect(x: 0.05, y: 0.720, width: 0.19, height: 0.02)),
        ]).values
        XCTAssertEqual(read.map(\.text), ["Beispielyan", "Nare", "Sonnenhang 9", "D 12345 Musterstadt"], "\(read)")
        XCTAssertEqual(read.map(\.entity), [.personName, .personName, .address, .address])
    }

    func testANumberALabelAnnouncesIsThatFieldWhereverItIsPrintedAgain() {
        let read = Self.read([("Betriebsstätten-Nr.   Arzt-Nr.", 0.05, 0), ("998877665             112233445", 0.05, 1),
                              ("998877665", 0.60, 3), ("Tel.: 040-1234567", 0.60, 4), ("112233445", 0.60, 5),
                              ("Ref. 4499887766554", 0.60, 6)]).values
        XCTAssertEqual(read.filter { $0.text == "998877665" }.map(\.entity), [.institutionNumber, .institutionNumber])
        XCTAssertEqual(read.filter { $0.text == "112233445" }.map(\.role), [.doctor, .doctor])
        XCTAssertFalse(read.contains { $0.text.contains("040") || $0.text.contains("4499") }, "\(read)")
    }

    func testACheckboxsWordsEndTheValueAboveThem() {
        let read = Self.read([("Diagnose", 0.05, 0), ("M54.5 G", 0.05, 1), ("sonstiger Unfall, Unfallfolgen", 0.05, 2)]).values
        XCTAssertEqual(read.map(\.text), ["M54.5 G"])
    }

    func testTheInsuredCopyIsReadAsItsLabelsSay() {
        let read = Self.read(Self.insuredCopy).values
        let expected: [(String, FormFields.Entity, PersonRole?)] = [
            ("Muster BKK", .institution, nil),
            ("Beispielyan", .personName, .patient), ("Nare", .personName, .patient),
            ("Sonnenhang 9", .address, .patient), ("D 12345 Musterstadt", .address, .patient),
            ("14.03.1987", .dateOfBirth, nil),
            ("X987654321", .healthInsuranceNumber, .patient), ("5000001", .formCode, nil),
            ("02.10.26", .medicalDate, nil),
        ]
        for (text, entity, role) in expected {
            let value = read.first { $0.text == text }
            XCTAssertEqual(value?.entity, entity, "\(text) in \(read)")
            XCTAssertEqual(value?.role, role, "\(text) in \(read)")
        }
        // The practice's and the doctor's numbers, in the boxes and again in the stamp.
        XCTAssertEqual(read.filter { $0.text == "101234567" }.map(\.entity), [.institutionNumber])
        XCTAssertEqual(read.filter { $0.text == "021234560" }.map(\.entity), [.institutionNumber, .institutionNumber])
        XCTAssertEqual(read.filter { $0.text == "345678812" }.map(\.entity), [.identificationNumber, .identificationNumber])
        XCTAssertEqual(read.filter { $0.text == "345678812" }.map(\.role), [.doctor, .doctor])
        // The note's date is a date; the day the illness was found, a health detail.
        XCTAssertEqual(Set(read.filter { $0.text == "05.10.26" }.map(\.entity)), [.date, .medicalDate], "\(read)")
        // The stamp's line on the diagnosis label's row is no diagnosis: the code under the label is.
        XCTAssertEqual(read.filter { $0.entity == .medicalDiagnosis }.map(\.text), ["M54.5 G"])
        for printed in ["Arbeitsunfall", "Durchgangsarzt", "Erstbescheinigung", "Fax", "Tel", "Lindenallee", "Fachärztin",
                        "Proktologie", "Vertragsarztstempel", "sonstiger", "Versorgungsleiden"] {
            XCTAssertFalse(read.contains { $0.text.contains(printed) }, "\(printed) is no field's value: \(read)")
        }
    }

    func testACaptionBesideTheNameFieldLeavesTheNameUnderIt() {
        // The checkbox's caption printed a little lower, between the name's
        // label and the surname, so no longer on the label's row.
        let made = Self.layout(Self.insuredCopy)
        let caption = Self.insuredCopy.firstIndex { $0.text.hasPrefix("Arbeitsunfall,") }!
        var boxes = made.boxes
        boxes[caption].origin.y -= 0.019
        let read = Self.read(boxed: Array(zip(made.strings, boxes))).values
        XCTAssertEqual(read.filter { $0.entity == .personName }.map(\.text), ["Beispielyan", "Nare"], "\(read)")
        XCTAssertEqual(read.filter { $0.entity == .address }.count, 2, "\(read)")
    }

    func testLettersBesideALabelWithoutItsColonCountWhereNothingIsUnderIt() {
        // A shop's field and its value beside it, read poorly: nothing is under the label.
        let read = Self.read([("Bestellung 1024", 0.05, 0), ("Vorname", 0.05, 1), ("max", 0.30, 1)]).values
        XCTAssertEqual(read.map(\.text), ["max"])
        XCTAssertEqual(read.first?.confidence, .medium)
        // A name of two lines' field, with its value beside it and nothing under it.
        XCTAssertEqual(Self.read([("Name, Vorname", 0.05, 0), ("Beispiel, Hans", 0.30, 0)]).values.map(\.text),
                       ["Beispiel, Hans"])
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

    /// Lines with their boxes given, each part of a line placed by its
    /// share of the line's letters.
    static func read(boxed lines: [(text: String, box: CGRect)]) -> (values: [ReadValue], reading: FormFields.Reading) {
        let strings = lines.map(\.text), boxes = lines.map(\.box)
        let reading = FormFields.read(strings, boxes: boxes, part: { index, range in
            let line = strings[index], share = boxes[index].width / CGFloat(max(1, line.count))
            let start = CGFloat(line.distance(from: line.startIndex, to: range.lowerBound))
            return CGRect(x: boxes[index].minX + start * share, y: boxes[index].minY,
                          width: CGFloat(line.distance(from: range.lowerBound, to: range.upperBound)) * share,
                          height: boxes[index].height)
        })
        let values = reading.values.map { value in
            ReadValue(text: String(strings[value.line][value.range]), entity: value.entity, role: value.role,
                      confidence: value.confidence)
        }
        return (values, reading)
    }

    /// A part of a scanned line: its text, where it starts across the page,
    /// its row from the top, which may fall between two, and whether it is
    /// the form's small print.
    typealias Printed = (text: String, x: CGFloat, row: CGFloat, small: Bool)

    /// Lines as text recognition reads a scan: each the parts it joined,
    /// one space between them, every letter where it was printed. Typed
    /// values are a hundredth of the page wide for each letter, small print
    /// six thousandths and lower; rows are three hundredths apart.
    static func scan(_ lines: [[Printed]]) -> (strings: [String], boxes: [CGRect],
                                              part: (Int, Range<String.Index>) -> CGRect?) {
        var strings: [String] = [], boxes: [CGRect] = [], letters: [[CGRect?]] = []
        for parts in lines {
            var text = "", places: [CGRect?] = []
            for (n, piece) in parts.enumerated() {
                if n > 0 { text += " "; places.append(nil) }
                let width: CGFloat = piece.small ? 0.006 : 0.01, height: CGFloat = piece.small ? 0.012 : 0.02
                for (i, letter) in piece.text.enumerated() {
                    text.append(letter)
                    places.append(CGRect(x: piece.x + CGFloat(i) * width, y: 0.9 - piece.row * 0.03,
                                         width: width, height: height))
                }
            }
            strings.append(text)
            letters.append(places)
            boxes.append(places.compactMap { $0 }.reduce(CGRect.null) { $0.union($1) })
        }
        let part: (Int, Range<String.Index>) -> CGRect? = { index, range in
            let line = strings[index]
            let lower = line.distance(from: line.startIndex, to: range.lowerBound)
            let upper = line.distance(from: line.startIndex, to: range.upperBound)
            let found = letters[index][lower..<upper].compactMap { $0 }
            return found.first.map { first in found.dropFirst().reduce(first) { $0.union($1) } }
        }
        return (strings, boxes, part)
    }

    static func read(scan lines: [[Printed]]) -> (values: [ReadValue], reading: FormFields.Reading,
                                                strings: [String]) {
        let made = scan(lines)
        let reading = FormFields.read(made.strings, boxes: made.boxes, part: made.part)
        let values = reading.values.map { value in
            ReadValue(text: String(made.strings[value.line][value.range]), entity: value.entity, role: value.role,
                      confidence: value.confidence)
        }
        return (values, reading, made.strings)
    }
}
