import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// What was sent where, kept as facts and handed on as a table for a
/// spreadsheet.
final class SendLogTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    @MainActor
    private func sent(_ name: String, to: String, covered: [String], message: String? = nil) -> SendLog.Sent {
        SendLog.Sent(date: Date(timeIntervalSince1970: 1_792_234_567), name: name, to: to, covered: covered, message: message)
    }

    @MainActor
    func testTheTableHasHeadingsThenOneRowASend() {
        let table = SendLog.table([sent("Rechnung 1024.png", to: "WhatsApp", covered: ["names", "bank"])],
                                  separator: ",", timeZone: utc)
        let rows = table.components(separatedBy: "\r\n")
        XCTAssertEqual(rows.count, 3, table)
        XCTAssertEqual(rows[0], [L("Date"), L("Photo"), L("Sent to"), L("Covered"), L("Message")].joined(separator: ","))
        let covered = [PrivateDetail.names.title, PrivateDetail.bank.title].joined(separator: ", ")
        XCTAssertEqual(rows[1], "2026-10-17 10:56:07,Rechnung 1024.png,WhatsApp,\"\(covered)\",")
        XCTAssertEqual(rows[2], "")
    }

    @MainActor
    func testASemicolonSeparatesWhereNumbersUseADecimalComma() {
        let table = SendLog.table([sent("Shot.png", to: "chatgpt.com", covered: [], message: "Hier, bitte")],
                                  separator: ";", timeZone: utc)
        XCTAssertEqual(table.components(separatedBy: "\r\n")[1], "2026-10-17 10:56:07;Shot.png;chatgpt.com;;Hier, bitte")
    }

    func testFieldsAreQuotedWhereNeededAndFormulasStayText() {
        XCTAssertEqual(SendLog.field("plain", separator: ","), "plain")
        XCTAssertEqual(SendLog.field("say \"hi\"", separator: ","), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(SendLog.field("a;b", separator: ";"), "\"a;b\"")
        XCTAssertEqual(SendLog.field("a;b", separator: ","), "a;b")
        XCTAssertEqual(SendLog.field("two\nlines", separator: ","), "\"two\nlines\"")
        XCTAssertEqual(SendLog.field("=SUM(A1)", separator: ","), "'=SUM(A1)")
        XCTAssertEqual(SendLog.field("+49 30 1234", separator: ","), "'+49 30 1234")
    }

    func testWhatWasCoveredIsKeptByNameAndReadBackInWords() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
        let report = CoverReport([Finder.Area(rect: box, kind: .barcodes), Finder.Area(rect: box, kind: .names),
                                  Finder.Area(rect: box, kind: nil)], hand: 1)
        XCTAssertEqual(report.keys, ["names", "barcodes", "rules", "hand"])
        XCTAssertEqual(CoverReport.titles(of: report.keys),
                       [PrivateDetail.names.title, PrivateDetail.barcodes.title, L("Your details and rules"), L("Hidden by hand")])
        XCTAssertEqual(CoverReport.titles(of: ["gone"]), [])
    }

    @MainActor
    func testTheLongestHistoryChoicesReadAsWords() {
        XCTAssertEqual(History.dayChoices.last, History.forever)
        XCTAssertEqual(History.title(days: History.forever), L("Forever"))
        XCTAssertEqual(History.title(days: 365), L("1 year"))
        XCTAssertEqual(History.title(days: 30), String(format: L("%d days"), 30))
    }
}
