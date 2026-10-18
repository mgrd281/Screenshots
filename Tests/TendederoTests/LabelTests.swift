import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Tendedero

/// Labels that announce a name under them, laid out as a shop's order page
/// lays them out: a card's heading, like "Kunde", with a menu's dots on its
/// row, and the customer's name a little further down than the lines under
/// it are from each other.
final class LabelTests: XCTestCase {
    func testALabelIsKnownWithTheDotsOfAMenuOnItsRow() {
        for line in ["Kunde", "Kunde ⋯", "Kunde ...", "Kunde …", "Kunde •••", "Rechnungsadresse:", "KUNDE"] {
            XCTAssertTrue(Finder.isLabel(line), line)
        }
        for line in ["Christopher Kelly", "5 Bestellungen", "Keine Lieferadresse angegeben", "..."] {
            XCTAssertFalse(Finder.isLabel(line), line)
        }
    }

    /// Measured as Vision reads a Retina screenshot of one: "Kunde" has
    /// nothing below its baseline and is read shorter than the name.
    func testTheNameUnderAShortHeadingIsItsFirstLine() {
        let kunde = CGRect(x: 0.69, y: 0.770, width: 0.03, height: 0.011)
        let name = CGRect(x: 0.69, y: 0.731, width: 0.08, height: 0.015)
        let orders = CGRect(x: 0.69, y: 0.709, width: 0.07, height: 0.015)
        let boxes = [kunde, name, orders]
        // The gap is more than twice the heading's height, under twice the name's.
        XCTAssertGreaterThan(kunde.minY - name.maxY, kunde.height * 2)
        XCTAssertEqual(Finder.line(below: 0, in: boxes, gap: 2.5), 1)
        XCTAssertEqual(Finder.line(below: 1, in: boxes, gap: 1.1), 2)
        // A new section, further down, is not the heading's.
        let further = CGRect(x: 0.69, y: 0.70, width: 0.08, height: 0.015)
        XCTAssertNil(Finder.line(below: 0, in: [kunde, further], gap: 2.5))
        // Nor is a line in another column.
        let beside = CGRect(x: 0.10, y: 0.731, width: 0.08, height: 0.015)
        XCTAssertNil(Finder.line(below: 0, in: [kunde, beside], gap: 2.5))
    }

    /// Read from a picture, as the app does: the customer's name under
    /// "Kunde" is covered with Names on, and so is the name the bill goes
    /// to, though they differ. The rest stays.
    func testBothNamesOnAnOrderPageAreCovered() throws {
        let image = try orderPage()
        let lines = Finder.textLines(in: image).map { "\($0.string) \($0.box)" }
        let covered = Finder.coveredAreas(in: image, [.names], rules: [], intelligence: false)
        let texts = covered.compactMap(\.text)
        XCTAssertTrue(texts.contains { $0.contains("Christopher Kelly") }, "\(texts) in \(lines)")
        XCTAssertTrue(texts.contains { $0.contains("Chris Kelly") && !$0.contains("Christopher") }, "\(texts) in \(lines)")
        XCTAssertFalse(texts.contains { $0.contains("Bestellungen") || $0.contains("Deutschland") }, "\(texts)")
    }

    // MARK: Helpers

    /// The customer's card and the addresses beside an order, at Retina
    /// size: 13 pt text on 20 pt lines, headings in bold with their menu's
    /// dots at the far edge, and a heading 34 pt above its first line.
    private func orderPage() throws -> CGImage {
        let width = 2880, height = 1800
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ink = CGColor(gray: 0.1, alpha: 1)
        let link = CGColor(red: 0.17, green: 0.38, blue: 0.82, alpha: 1)
        let heading = CTFontCreateWithName("Helvetica-Bold" as CFString, 26, nil)
        let body = CTFontCreateWithName("Helvetica" as CFString, 26, nil)
        // From the top of the screen, as the page reads.
        let rows: [(text: String, top: CGFloat, font: CTFont, color: CGColor, dots: Bool)] = [
            ("Kunde", 400, heading, ink, true),
            ("Christopher Kelly", 468, body, link, false),
            ("5 Bestellungen", 508, body, ink, false),
            ("tazman21@gmx.de", 566, body, link, false),
            ("Lieferadresse", 684, heading, ink, true),
            ("Keine Lieferadresse angegeben", 752, body, ink, false),
            ("Rechnungsadresse", 868, heading, ink, false),
            ("Chris Kelly", 936, body, ink, false),
            ("Auenstraße 20", 976, body, ink, false),
            ("97456 Dittelbrunn", 1016, body, ink, false),
            ("Deutschland", 1056, body, ink, false),
        ]
        for row in rows {
            draw(row.text, at: CGPoint(x: 2000, y: CGFloat(height) - row.top), font: row.font, color: row.color, in: context)
            if row.dots {
                draw("⋯", at: CGPoint(x: 2540, y: CGFloat(height) - row.top), font: body,
                     color: CGColor(gray: 0.45, alpha: 1), in: context)
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func draw(_ string: String, at point: CGPoint, font: CTFont, color: CGColor, in context: CGContext) {
        let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
    }
}
