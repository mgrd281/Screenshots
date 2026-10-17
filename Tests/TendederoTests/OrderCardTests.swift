import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Tendedero

/// The order card: the order's parts read off a screenshot, each ready to
/// copy, and the whole order as a row for a spreadsheet.
final class OrderCardTests: XCTestCase {
    func testEachPartIsTheFirstFoundButTheTotalAndTheAddress() {
        let lines = ["Bestellung #1024", "17.10.2026", "Lena Hoffmann", "Musterstraße 5", "10115 Berlin",
                     "Zwischensumme 60,00 €", "Versand 14,00 €", "Gesamt 74,00 €", "lena@example.com"]
        let found: [(kind: PrivateDetail, text: String, line: Int)] = [
            (.orders, "1024", 0), (.dates, "17.10.2026", 1), (.names, "Lena Hoffmann", 2),
            (.addresses, "Musterstraße 5", 3), (.addresses, "10115 Berlin", 4),
            (.amounts, "60,00 €", 5), (.amounts, "14,00 €", 6), (.amounts, "74,00 €", 7), (.emails, "lena@example.com", 8),
        ]
        let fields = OrderCard.fields(from: found, lines: lines)
        XCTAssertEqual(fields.map(\.part), [.order, .date, .total, .name, .address, .email])
        XCTAssertEqual(fields.first { $0.part == .total }?.value, "74,00 €")
        XCTAssertEqual(fields.first { $0.part == .address }?.value, "Musterstraße 5, 10115 Berlin")
    }

    func testWithoutAWordForTheTotalTheLargestAmountIs() {
        let lines = ["Artikel 9,99 €", "Artikel 1.250,00 €", "Versand 4,90 €"]
        let found: [(kind: PrivateDetail, text: String, line: Int)] = [
            (.amounts, "9,99 €", 0), (.amounts, "1.250,00 €", 1), (.amounts, "4,90 €", 2),
        ]
        XCTAssertEqual(OrderCard.total(of: found, lines: lines), "1.250,00 €")
    }

    func testAmountsAreReadWithEitherDecimalMark() {
        XCTAssertEqual(OrderCard.value(of: "1.250,00 €"), 1250)
        XCTAssertEqual(OrderCard.value(of: "$1,250.00"), 1250)
        XCTAssertEqual(OrderCard.value(of: "EUR 12.50"), 12.5)
        XCTAssertEqual(OrderCard.value(of: "1.250 €"), 1250)
        XCTAssertEqual(OrderCard.value(of: "€ 5"), 5)
    }

    func testTheRowKeepsEveryColumnInItsPlace() {
        let fields = [OrderCard.Field(part: .order, value: "1024"), OrderCard.Field(part: .total, value: "74,00 €")]
        XCTAssertEqual(OrderCard.row(fields), "1024\t\t74,00 €\t\t\t\t\t\t")
        XCTAssertEqual(OrderCard.text(fields), "\(L("Order")): 1024\n\(L("Total")): 74,00 €")
    }

    func testACodeAddsWhatItSays() {
        let fields = OrderCard.fields(from: [], lines: [], codes: ["BCD\n002\n1\nSCT"])
        XCTAssertEqual(fields, [OrderCard.Field(part: .code, value: "BCD · 002 · 1 · SCT")])
    }

    /// Read from a picture, as the app does.
    func testAnOrderIsReadOffAPicture() throws {
        let image = try drawn(["Bestellung #1024", "lena.hoffmann@example.com", "Gesamt 74,00 €"])
        let lines = Finder.textLines(in: image)
        let fields = OrderCard.fields(from: Finder.details(in: lines), lines: lines.map(\.string))
        XCTAssertEqual(fields.first { $0.part == .order }?.value, "1024", "\(lines.map(\.string))")
        XCTAssertEqual(fields.first { $0.part == .email }?.value, "lena.hoffmann@example.com")
        XCTAssertEqual(fields.first { $0.part == .total }?.value, "74,00 €")
    }

    /// Lines of large black text on white, one under another.
    private func drawn(_ lines: [String]) throws -> CGImage {
        let width = 1400, height = 120 * lines.count + 80
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 100 - 120 * i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        return try XCTUnwrap(context.makeImage())
    }
}
