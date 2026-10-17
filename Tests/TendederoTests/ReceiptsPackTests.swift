import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// The monthly pack: the folder's table read back as it is written, the sum
/// of its totals, and one PDF with the list and a page a receipt.
final class ReceiptsPackTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let october17 = Date(timeIntervalSince1970: 1_792_234_567)
    private let october20 = Date(timeIntervalSince1970: 1_792_493_767)
    private let september27 = Date(timeIntervalSince1970: 1_790_506_567)

    /// The table as Bookkeeping writes it, with either separator.
    private func table(_ separator: Character) -> String {
        "\u{FEFF}" + Bookkeeping.headings(separator: separator)
            + Bookkeeping.line(day: october17, file: "2026-10-17 Order 1024 74,00 €.png",
                               fields: [OrderCard.Field(part: .order, value: "1024"),
                                        OrderCard.Field(part: .total, value: "74,00 €")],
                               covering: [], separator: separator, timeZone: utc)
            + Bookkeeping.line(day: september27, file: "2026-09-27.png", fields: [], covering: [],
                               separator: separator, timeZone: utc)
            + Bookkeeping.line(day: october20, file: "Refund; \"A\", 2.png",
                               fields: [OrderCard.Field(part: .total, value: "-5,00 €")],
                               covering: [.orders], separator: separator, timeZone: utc)
    }

    func testTheTableIsReadBackAsItIsWritten() {
        for separator: Character in [";", ","] {
            XCTAssertEqual(ReceiptsPack.separator(of: String(table(separator).dropFirst())), separator)
            XCTAssertEqual(ReceiptsPack.rows(fromTable: table(separator)), [
                ReceiptsPack.Row(day: "2026-10-17", file: "2026-10-17 Order 1024 74,00 €.png", order: "1024", total: "74,00 €"),
                ReceiptsPack.Row(day: "2026-09-27", file: "2026-09-27.png"),
                ReceiptsPack.Row(day: "2026-10-20", file: "Refund; \"A\", 2.png", total: "-5,00 €"),
            ], "separator \(separator)")
        }
    }

    func testMonthsNewestFirst() {
        XCTAssertEqual(ReceiptsPack.months(in: ReceiptsPack.rows(fromTable: table(";"))), ["2026-10", "2026-09"])
        XCTAssertEqual(ReceiptsPack.months(in: []), [])
    }

    func testLinesWithoutADayAreLeftOut() {
        let text = "Datum;Datei;Bestellung;Summe\n\nnot a day;x.png\n2026-1-5;y.png\n2026-10-05;z.png"
        XCTAssertEqual(ReceiptsPack.rows(fromTable: text), [ReceiptsPack.Row(day: "2026-10-05", file: "z.png")])
    }

    func testTheSumIsWrittenLikeTheTotals() {
        XCTAssertEqual(ReceiptsPack.sum(of: ["74,00 €", "1.250,00 €", "-5,00 €"]), "1.319,00 €")
        XCTAssertEqual(ReceiptsPack.sum(of: ["$1,250.00", "$5.50"]), "$1,255.50")
        XCTAssertEqual(ReceiptsPack.sum(of: ["EUR 12.50", "", "EUR 1.25"]), "EUR 13.75")
        // Mixed currencies have no sum, nor does nothing.
        XCTAssertNil(ReceiptsPack.sum(of: ["74,00 €", "$5.00"]))
        XCTAssertNil(ReceiptsPack.sum(of: ["", " "]))
    }

    func testTheMonthByName() {
        XCTAssertEqual(ReceiptsPack.title(month: "2026-10", locale: Locale(identifier: "en_US")), "October 2026")
        XCTAssertEqual(ReceiptsPack.title(month: "2026-10", locale: Locale(identifier: "de_DE")), "Oktober 2026")
        XCTAssertEqual(ReceiptsPack.title(month: "not a month"), "not a month")
    }

    func testTheListTakesAsManyPagesAsItNeeds() {
        XCTAssertEqual(ReceiptsPack.listPages(for: 1), 1)
        XCTAssertEqual(ReceiptsPack.listPages(for: ReceiptsPack.rowsOnFirstPage), 1)
        XCTAssertEqual(ReceiptsPack.listPages(for: ReceiptsPack.rowsOnFirstPage + 1), 2)
        XCTAssertEqual(ReceiptsPack.listPages(for: ReceiptsPack.rowsOnFirstPage + ReceiptsPack.rowsPerPage), 2)
        XCTAssertEqual(ReceiptsPack.listPages(for: ReceiptsPack.rowsOnFirstPage + ReceiptsPack.rowsPerPage + 1), 3)
    }

    /// October's receipts, one of them missing from the folder, and one from
    /// September that stays out.
    func testThePackListsTheMonthAndGivesEachReceiptAPage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try receipt(at: folder.appendingPathComponent("2026-10-17 Order 1024 74,00 €.png"))
        try receipt(at: folder.appendingPathComponent("2026-10-20.png"))
        try receipt(at: folder.appendingPathComponent("2026-09-27 Order 9988.png"))
        let rows = [
            ReceiptsPack.Row(day: "2026-10-17", file: "2026-10-17 Order 1024 74,00 €.png", order: "1024", total: "74,00 €"),
            ReceiptsPack.Row(day: "2026-09-27", file: "2026-09-27 Order 9988.png", order: "9988", total: "9,00 €"),
            ReceiptsPack.Row(day: "2026-10-18", file: "Gone.png", order: "1031", total: "20,00 €"),
            ReceiptsPack.Row(day: "2026-10-20", file: "2026-10-20.png", total: "-5,00 €"),
        ]
        let english = Locale(identifier: "en_US")
        let pack = try XCTUnwrap(ReceiptsPack.make(month: "2026-10", rows: rows, in: folder, made: october20, locale: english))
        XCTAssertEqual(pack.lastPathComponent, String(format: L("Receipts %@"), "2026-10") + ".pdf")

        let document = try XCTUnwrap(PDFDocument(url: pack))
        // The list, then the two receipts found.
        XCTAssertEqual(document.pageCount, 3)
        let list = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(list.contains("October 2026"), list)
        XCTAssertTrue(list.contains("1024"), list)
        XCTAssertTrue(list.contains("1031"), list)
        XCTAssertFalse(list.contains("9988"), list)
        XCTAssertTrue(list.contains("89,00 €"), list)
        XCTAssertTrue(list.contains("3"), list)
        let first = try XCTUnwrap(document.page(at: 1)?.string)
        XCTAssertTrue(first.contains("2026-10-17"), first)

        // Made again, it does not overwrite the first.
        let again = try XCTUnwrap(ReceiptsPack.make(month: "2026-10", rows: rows, in: folder, made: october20, locale: english))
        XCTAssertNotEqual(again, pack)
        XCTAssertNil(ReceiptsPack.make(month: "2026-08", rows: rows, in: folder))
    }

    // MARK: Helpers

    private func receipt(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 20, y: 300, width: 200, height: 20))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
