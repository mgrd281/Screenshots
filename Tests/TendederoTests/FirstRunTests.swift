import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The iPhone's first run, without a screen: the sample invoice, the doctor's
/// letter and the bank statement are covered as the engine covers them, the
/// story keeps its times, and the categories chosen alone say what is
/// covered, however often they change.
final class FirstRunTests: XCTestCase {
    // MARK: The sample and the engine

    /// The invoice laid out as a page: the title, then each line.
    private func page(_ lines: [String]) -> (strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?) {
        FormFieldsTests.layout(lines.enumerated().map { (text: $0.element, x: CGFloat(0.06), row: $0.offset) })
    }

    /// What the engine covers on the invoice for some kinds, by field.
    private func covered(_ chosen: Set<PrivateDetail>, labels: [FirstRun.Field.ID: String]? = nil,
                         title: String = "Rechnung") -> [FirstRun.Field.ID: [String]] {
        let lines = labels.map { FirstRun.lines(title: title, labels: $0) } ?? FirstRun.lines(title: title)
        let made = page(lines)
        let found = Finder.findings(made.strings, boxes: made.boxes, part: made.part, chosen)
        var byField: [FirstRun.Field.ID: [String]] = [:]
        for hit in found.hits {
            // The title is line 0; the fields follow in order.
            XCTAssertGreaterThan(hit.line, 0, "nothing on the title: \(lines[hit.line])")
            guard hit.line > 0 else { continue }
            let line = made.strings[hit.line]
            let text = hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
            byField[FirstRun.fields(of: .invoice)[hit.line - 1].id, default: []].append(text)
        }
        return byField
    }

    /// The invoice's categories, which the statement shares.
    private let invoiceCategories = FirstRun.Category.allCases.filter { $0.document == .invoice }

    func testEachCategoryCoversItsOwnDetailAndNothingElse() {
        for category in invoiceCategories {
            let found = covered(category.details)
            let expected = FirstRun.fields(of: .invoice).filter { $0.category == category }
            XCTAssertEqual(Set(found.keys), Set(expected.map(\.id)), "\(category): \(found)")
            for field in expected {
                XCTAssertTrue(found[field.id]?.contains { $0.contains(field.value) || field.value.contains($0) } == true,
                              "\(category) covers \(field.value): \(found)")
            }
        }
    }

    func testTheAmountStaysReadableAndIsAnAmountToTheEngine() {
        let chosen = FirstRun.Category.allCases.reduce(into: Set<PrivateDetail>()) { $0.formUnion($1.details) }
        XCTAssertNil(covered(chosen)[.amount], "the amount stays readable")
        XCTAssertEqual(covered([.amounts])[.amount], ["149,90 €"])
    }

    func testTheSampleIsReadTheSameWithEnglishLabels() {
        let labels: [FirstRun.Field.ID: String] = [.name: "Name:", .email: "Email:", .iban: "IBAN:", .amount: "Amount:"]
        for category in invoiceCategories {
            let found = covered(category.details, labels: labels, title: "Invoice")
            XCTAssertEqual(Set(found.keys), Set(FirstRun.fields(of: .invoice).filter { $0.category == category }.map(\.id)),
                           "\(category): \(found)")
        }
    }

    /// Every word the doctor's letter prints, in German: the letterhead, the
    /// colleague it is for, the patient, the letter, the stamp and the
    /// signature.
    private let letterDE = [
        "Dr. med. Anna Schmidt", "Fachärztin für Innere Medizin",
        "Praxis Dr. Schmidt · Hauptstraße 12 · 20095 Hamburg",
        "Dr. med. Klaus Weber", "Hausarztpraxis", "Lindenweg 3", "22301 Hamburg",
        "Hamburg, 14.10.2026", "Arztbrief",
        "Patient: Erika Mustermann", "Geburtsdatum: 12.08.1964", "Diagnose: Arterielle Hypertonie (I10.90)",
        "Sehr geehrter Herr Kollege,",
        "wir berichten über die heutige Vorstellung unserer gemeinsamen Patientin.",
        "Der Blutdruck ist gut eingestellt; wir empfehlen eine Kontrolle in sechs Monaten.",
        "Mit freundlichen Grüßen",
        "Dr. med. Anna Schmidt", "Fachärztin für Innere Medizin", "Hauptstraße 12 · 20095 Hamburg",
        "Dr. med. Anna Schmidt", "Fachärztin für Innere Medizin",
        "Praxis Dr. Schmidt · Tel. 040 1234567 · www.example.com",
    ]

    /// The same letter in English.
    private let letterEN = [
        "Dr. med. Anna Schmidt", "Specialist in internal medicine",
        "Praxis Dr. Schmidt · Hauptstraße 12 · 20095 Hamburg",
        "Dr. med. Klaus Weber", "Family practice", "Lindenweg 3", "22301 Hamburg",
        "Hamburg, 14.10.2026", "Doctor's letter",
        "Patient: Erika Mustermann", "Date of birth: 12.08.1964", "Diagnosis: Hypertension (I10.90)",
        "Dear colleague,",
        "We report on our patient's visit today. Her blood pressure is well controlled;",
        "we advise a check-up in six months.",
        "Kind regards",
        "Dr. med. Anna Schmidt", "Specialist in internal medicine", "Hauptstraße 12 · 20095 Hamburg",
        "Dr. med. Anna Schmidt", "Specialist in internal medicine",
        "Praxis Dr. Schmidt · Tel. 040 1234567 · www.example.com",
    ]

    /// Every word the bank statement prints, in German and in English.
    private let statementDE = [
        "Musterbank", "www.example.com", "Kontoauszug 10/2026", "01.10.2026 – 31.10.2026",
        "Kontoinhaber: Erika Mustermann", "IBAN: DE89 3704 0044 0532 0130 00", "Datum Beschreibung Betrag",
        "01.10. Gehalt +2.450,00 €", "02.10. Miete −890,00 €", "05.10. Lebensmittel −64,37 €",
        "08.10. Strom −58,00 €", "14.10. Musterstudio RE-2026-0417 −149,90 €", "15.10. Mobilfunk −19,99 €",
        "20.10. Apotheke −12,50 €", "Neuer Kontostand 1.255,24 €", "Musterbank · www.example.com",
    ]
    private let statementEN = [
        "Example Bank", "www.example.com", "Account statement 10/2026", "01.10.2026 – 31.10.2026",
        "Account holder: Erika Mustermann", "IBAN: DE89 3704 0044 0532 0130 00", "Date Description Amount",
        "01.10. Salary +2.450,00 €", "02.10. Rent −890,00 €", "05.10. Groceries −64,37 €",
        "08.10. Electricity −58,00 €", "14.10. Example Studio RE-2026-0417 −149,90 €",
        "15.10. Mobile phone −19,99 €", "20.10. Pharmacy −12,50 €",
        "New balance 1.255,24 €", "Example Bank · www.example.com",
    ]

    /// What the engine covers on a page for some kinds, as the words covered.
    private func coveredWords(_ lines: [String], _ chosen: Set<PrivateDetail>) -> [String] {
        let made = page(lines)
        return Finder.findings(made.strings, boxes: made.boxes, part: made.part, chosen).hits.map { hit in
            let line = made.strings[hit.line]
            return hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
        }
    }

    func testTheLetterCoversThePatientAndLeavesTheDoctors() {
        for (letter, diagnosis) in [(letterDE, "Arterielle Hypertonie (I10.90)"), (letterEN, "Hypertension (I10.90)")] {
            let expected: [FirstRun.Category: String] = [
                .patients: FirstRun.field(.patient).value, .birthDates: FirstRun.field(.birthDate).value, .health: diagnosis,
            ]
            for (category, value) in expected {
                let found = coveredWords(letter, category.details)
                XCTAssertFalse(found.isEmpty, "\(category) finds \(value)")
                XCTAssertTrue(found.allSatisfy { $0 == value }, "\(category) covers only \(value): \(found)")
            }
            let all = coveredWords(letter, expected.keys.reduce(into: Set<PrivateDetail>()) { $0.formUnion($1.details) })
            XCTAssertFalse(all.contains { $0.contains("Schmidt") || $0.contains("Weber") }, "the doctors stay: \(all)")
        }
    }

    func testTheStatementCoversItsHolderAndAccountAsTheInvoiceDoes() {
        for statement in [statementDE, statementEN] {
            XCTAssertEqual(coveredWords(statement, FirstRun.Category.names.details), [FirstRun.field(.holder).value])
            XCTAssertEqual(coveredWords(statement, [.bank]), [FirstRun.field(.account).value])
            XCTAssertEqual(coveredWords(statement, [.emails]), [], "it has no email")
        }
    }

    // MARK: The story

    func testItOpensReadableAndIsProtectedWithinTwoSeconds() {
        let start = FirstRun.state(at: 0)
        XCTAssertEqual(start.scene, .reveal)
        XCTAssertEqual(start.phase, .initial)
        XCTAssertTrue(FirstRun.fields.allSatisfy { !start.isCovered($0) && !start.isFound($0) })

        let protected = FirstRun.state(at: 2)
        XCTAssertEqual(protected.phase, .protected)
        XCTAssertTrue(protected.showsShield)
        for field in FirstRun.fields(of: .invoice) {
            XCTAssertEqual(protected.isCovered(field), field.category != nil, field.value)
        }
    }

    func testTheDetailsAreFoundAsTheLineReachesThemThenCoveredInTurn() {
        let found = FirstRun.state(at: 1.2)
        XCTAssertEqual(found.phase, .highlighted)
        XCTAssertTrue(FirstRun.privateFields(of: .invoice).allSatisfy { found.isFound($0) && !found.isCovered($0) })
        let half = FirstRun.state(at: 1.31 + FirstRun.stagger)
        XCTAssertEqual(half.phase, .redacting)
        XCTAssertEqual(FirstRun.privateFields(of: .invoice).map(half.isCovered), [true, true, false])
    }

    func testTheScriptKeepsItsOrderAndEndsWithinFifteenSeconds() {
        let times = FirstRun.script.map(\.at)
        XCTAssertEqual(times, times.sorted())
        XCTAssertLessThanOrEqual(times.last ?? 0, 15)
        let scenes = FirstRun.script.compactMap { beat -> FirstRun.Scene? in
            if case .scene(let scene) = beat.event { return scene }
            return nil
        }
        XCTAssertEqual(scenes, [.control, .scan, .share, .complete])
        // The phases it goes through, each change once.
        var state = FirstRun.State()
        var phases = [state.phase]
        for beat in FirstRun.script {
            FirstRun.apply(beat.event, to: &state)
            if phases.last != state.phase { phases.append(state.phase) }
        }
        XCTAssertEqual(phases, [.initial, .detecting, .highlighted, .redacting, .protected, .revealing, .protected,
                                .redacting, .protected, .initial, .detecting, .highlighted, .redacting, .protected,
                                .complete])
    }

    func testTurningACategoryOffShowsItsDetailAndOnCoversItAgain() {
        var state = FirstRun.state(at: FirstRun.controlStart)
        let name = FirstRun.field(.name)
        XCTAssertTrue(state.isCovered(name))
        FirstRun.toggle(.names, in: &state)
        XCTAssertFalse(state.isCovered(name))
        XCTAssertFalse(state.isFound(name), "readable again, without its marks")
        XCTAssertEqual(state.phase, .revealing)
        XCTAssertTrue(state.isCovered(FirstRun.field(.email)), "the others stay covered")
        FirstRun.apply(.settle, to: &state)
        XCTAssertEqual(state.phase, .protected)
        FirstRun.toggle(.names, in: &state)
        XCTAssertTrue(state.isCovered(name))
        XCTAssertEqual(state.phase, .redacting)
    }

    func testRapidChangesEndWhereTheLastOneLeftIt() {
        var state = FirstRun.state(at: 2.5)
        for _ in 0..<7 { FirstRun.toggle(.bank, in: &state) }
        XCTAssertFalse(state.chosen.contains(.bank))
        XCTAssertFalse(state.isCovered(FirstRun.field(.iban)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.name)))
    }

    func testTheStoryLeavesTheOwnersChoiceAlone() {
        var state = FirstRun.state(at: 2.5)
        FirstRun.toggle(.emails, in: &state)
        for beat in FirstRun.script where beat.at > 2.5 {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.chosen, Set(FirstRun.Category.allCases).subtracting([.emails]),
                       "the story turned nothing for the owner")
        // At the end the invoice lies protected beside the letter, as chosen.
        let invoice = state.protected(.invoice)
        XCTAssertFalse(invoice.isCovered(FirstRun.field(.email)))
        XCTAssertTrue(invoice.isCovered(FirstRun.field(.name)))
        XCTAssertTrue(invoice.isCovered(FirstRun.field(.iban)))
        XCTAssertTrue(FirstRun.privateFields(of: .letter).allSatisfy(state.isCovered), "the letter is covered")
    }

    func testTheScannedLetterIsReadThenFoundThenCoveredAsChosen() {
        var state = FirstRun.state(at: FirstRun.scanStart)
        XCTAssertEqual(state.scan, .placed)
        XCTAssertEqual(state.document, .letter)
        XCTAssertTrue(FirstRun.fields.allSatisfy { !state.isCovered($0) }, "the page as printed")
        FirstRun.toggle(.birthDates, in: &state)
        for beat in FirstRun.script where beat.at > FirstRun.scanStart && beat.at <= 9.25 {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.scan, .reading)
        XCTAssertFalse(state.isFound(FirstRun.field(.birthDate)), "only what is chosen is marked")
        XCTAssertTrue(state.isFound(FirstRun.field(.patient)))
        XCTAssertTrue(state.isFound(FirstRun.field(.diagnosis)))
        for beat in FirstRun.script where beat.at > 9.25 && beat.at < FirstRun.shareStart {
            FirstRun.apply(beat.event, to: &state)
        }
        XCTAssertEqual(state.scan, .done)
        XCTAssertFalse(state.isCovered(FirstRun.field(.birthDate)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.patient)))
        XCTAssertTrue(state.isCovered(FirstRun.field(.diagnosis)))
        XCTAssertFalse(state.isCovered(FirstRun.field(.doctor)), "the doctor's name stays")
        XCTAssertTrue(state.showsShield)
    }

    func testWithNothingOfTheLetterChosenItsShieldStaysAway() {
        var state = FirstRun.state(at: 10)
        for category in FirstRun.Category.allCases where category.document == .letter {
            FirstRun.toggle(category, in: &state)
        }
        XCTAssertTrue(FirstRun.fields(of: .letter).allSatisfy { !state.isCovered($0) })
        XCTAssertFalse(state.showsShield, "nothing on the page in front is covered")
    }

    func testWhileTheStoryWaitsItSaysPausedAndTheEndStays() {
        XCTAssertEqual(FirstRun.state(at: 3).reported(held: true), .paused)
        XCTAssertEqual(FirstRun.state(at: 3).reported(held: false), FirstRun.state(at: 3).phase)
        var end = FirstRun.state(at: 14)
        XCTAssertEqual(end.reported(held: true), .complete)
        FirstRun.toggle(.names, in: &end)
        XCTAssertEqual(end.phase, .complete)
    }

    func testWithNothingChosenNothingIsCoveredAndNoShieldShows() {
        var state = FirstRun.state(at: 2.5)
        for category in FirstRun.Category.allCases { FirstRun.toggle(category, in: &state) }
        XCTAssertTrue(FirstRun.fields.allSatisfy { !state.isCovered($0) })
        XCTAssertFalse(state.showsShield)
    }

    // MARK: The scanner's perspective

    func testThePageIsStraightenedFromTippedToFlat() {
        XCTAssertEqual(FirstRun.corners(straightened: 0), FirstRun.tipped)
        XCTAssertEqual(FirstRun.corners(straightened: 1), FirstRun.flat)
        let size = CGSize(width: 300, height: 220)
        for progress in [0.0, 0.4, 1.0] {
            let corners = FirstRun.corners(straightened: progress).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let matrix = FirstRun.homography(size, to: corners)
            let rectangle = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                             CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
            for (point, corner) in zip(rectangle, corners) {
                let projected = FirstRun.project(point, by: matrix)
                XCTAssertEqual(projected.x, corner.x, accuracy: 0.001)
                XCTAssertEqual(projected.y, corner.y, accuracy: 0.001)
            }
        }
        // Straight, it changes nothing.
        let flat = FirstRun.homography(size, to: [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0),
                                                  CGPoint(x: 300, y: 220), CGPoint(x: 0, y: 220)])
        for (value, identity) in zip(flat, [1.0, 0, 0, 0, 1, 0, 0, 0, 1]) {
            XCTAssertEqual(value, identity, accuracy: 1e-9)
        }
    }

    func testTheBarsFillSceneByScene() {
        XCTAssertEqual(FirstRun.progress(at: 0), [0, 0, 0, 0])
        XCTAssertEqual(FirstRun.progress(at: FirstRun.controlStart / 2)[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(FirstRun.progress(at: FirstRun.controlStart), [1, 0, 0, 0])
        let scanning = FirstRun.progress(at: (FirstRun.scanStart + FirstRun.shareStart) / 2)
        XCTAssertEqual(scanning[0], 1)
        XCTAssertEqual(scanning[1], 1)
        XCTAssertEqual(scanning[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(scanning[3], 0)
        // At its end every bar is full, and stays so.
        XCTAssertEqual(FirstRun.progress(at: FirstRun.completeStart), [1, 1, 1, 1])
        XCTAssertEqual(FirstRun.progress(at: 60), [1, 1, 1, 1])
        XCTAssertEqual(FirstRun.progress(at: -1), [0, 0, 0, 0])
    }
}
