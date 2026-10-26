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
    func testACoverStopsAtTheLineUnderItThatStaysToBeRead() {
        // A name under "Rechnungsadresse:", the street under it, the label on
        // its row, a line above it, and another column to the right.
        let name = CGRect(x: 0.5, y: 0.80, width: 0.1, height: 0.02)
        let boxes = [name,
                     CGRect(x: 0.5, y: 0.77, width: 0.12, height: 0.02),
                     CGRect(x: 0.3, y: 0.80, width: 0.1, height: 0.02),
                     CGRect(x: 0.8, y: 0.775, width: 0.1, height: 0.02),
                     CGRect(x: 0.5, y: 0.83, width: 0.1, height: 0.02)]
        // Only the name is covered: its cover reaches to the street and to the line above, no further.
        let room = Finder.room(around: name, line: 0, in: boxes, covered: [0])
        XCTAssertEqual(room.lowerBound, 0.79, accuracy: 0.0001)
        XCTAssertEqual(room.upperBound, 0.83, accuracy: 0.0001)
        // With the street covered too, the two covers may meet.
        XCTAssertEqual(Finder.room(around: name, line: 0, in: boxes, covered: [0, 1]).lowerBound, 0)
        // Nothing round it: it may reach as far as it likes.
        XCTAssertEqual(Finder.room(around: name, line: 0, in: [name], covered: [0]), 0...1)
        // A line pressed against it leaves it its own box, never less.
        let touching = CGRect(x: 0.5, y: 0.785, width: 0.1, height: 0.02)
        XCTAssertEqual(Finder.room(around: name, line: 0, in: [name, touching], covered: [0]).lowerBound, 0.8, accuracy: 0.0001)
    }

    /// A PDF cropped in Preview keeps the text cut off, its lines beyond the
    /// page: a line there, over another, leaves no room, and nothing traps.
    func testLinesBeyondThePageLeaveNoRoomAndNothingTraps() {
        let above = CGRect(x: 0.1, y: 1.3, width: 0.3, height: 0.02)
        let under = CGRect(x: 0.1, y: 1.2, width: 0.3, height: 0.02)
        let room = Finder.room(around: above, line: 0, in: [above, under], covered: [0])
        XCTAssertLessThanOrEqual(room.lowerBound, room.upperBound)
        let below = CGRect(x: 0.1, y: -0.3, width: 0.3, height: 0.02)
        let over = CGRect(x: 0.1, y: -0.2, width: 0.3, height: 0.02)
        let low = Finder.room(around: below, line: 0, in: [below, over], covered: [0])
        XCTAssertLessThanOrEqual(low.lowerBound, low.upperBound)
    }

    func testALabelIsKnownWithTheDotsOfAMenuOnItsRow() {
        for line in ["Kunde", "Kunde ⋯", "Kunde ...", "Kunde …", "Kunde •••", "Rechnungsadresse:", "KUNDE"] {
            XCTAssertTrue(Finder.isLabel(line), line)
        }
        for line in ["Christopher Kelly", "5 Bestellungen", "Keine Lieferadresse angegeben", "..."] {
            XCTAssertFalse(Finder.isLabel(line), line)
        }
    }

    func testTheLabelsOfAFormAreKnown() {
        for line in ["Vorname:", "Nachname:", "PLZ:", "Stadt:", "Straße", "First name", "Last name", "Zip code",
                     "Versendet mit:", "الاسم الأول"] {
            XCTAssertTrue(Finder.isLabel(line), line)
        }
        for line in ["Martin", "Deutschland", "Privatadresse"] {
            XCTAssertFalse(Finder.isLabel(line), line)
        }
    }

    /// A shop's order page lists its labels in one column and the values
    /// in the next, on the same rows.
    func testTheValueBesideALabelIsOnItsRow() {
        let vorname = CGRect(x: 0.76, y: 0.62, width: 0.03, height: 0.010)
        let martin = CGRect(x: 0.86, y: 0.619, width: 0.025, height: 0.012)
        let nachname = CGRect(x: 0.76, y: 0.60, width: 0.035, height: 0.010)
        let dorozala = CGRect(x: 0.86, y: 0.599, width: 0.03, height: 0.012)
        let boxes = [vorname, martin, nachname, dorozala]
        XCTAssertEqual(Finder.line(beside: 0, in: boxes), 1)
        XCTAssertEqual(Finder.line(beside: 2, in: boxes), 3)
        // Nothing to the right of a value, and nothing beside to the left.
        XCTAssertNil(Finder.line(beside: 1, in: boxes))
        // Far across the page is another part of it, not the value.
        let left = CGRect(x: 0.10, y: 0.62, width: 0.03, height: 0.010)
        XCTAssertNil(Finder.line(beside: 0, in: [left, CGRect(x: 0.60, y: 0.62, width: 0.03, height: 0.010)]))
        XCTAssertNil(Finder.line(beside: 0, in: [vorname, left]))
        // Nor is a line on another row.
        XCTAssertNil(Finder.line(beside: 0, in: [vorname, dorozala]))
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

    /// A marketplace's order page, as Vision reads it: the labels in one
    /// column, each value its own line beside its label, and the bill's name
    /// beside its label with the address under it.
    private let form: [(String, CGRect)] = [
        ("Vorname:", CGRect(x: 0.66, y: 0.772, width: 0.04, height: 0.012)),
        ("Martin", CGRect(x: 0.795, y: 0.772, width: 0.03, height: 0.012)),
        ("Nachname:", CGRect(x: 0.66, y: 0.748, width: 0.045, height: 0.012)),
        ("Dorozala", CGRect(x: 0.795, y: 0.748, width: 0.035, height: 0.012)),
        ("Adresse:", CGRect(x: 0.66, y: 0.724, width: 0.04, height: 0.012)),
        ("Oistinger Feld 41", CGRect(x: 0.795, y: 0.724, width: 0.07, height: 0.012)),
        ("PLZ:", CGRect(x: 0.66, y: 0.700, width: 0.02, height: 0.012)),
        ("59510", CGRect(x: 0.795, y: 0.700, width: 0.03, height: 0.012)),
        ("Stadt:", CGRect(x: 0.66, y: 0.676, width: 0.025, height: 0.012)),
        ("Lippetal", CGRect(x: 0.795, y: 0.676, width: 0.035, height: 0.012)),
        ("Rechnungsadresse:", CGRect(x: 0.66, y: 0.610, width: 0.08, height: 0.012)),
        ("Martin Dorozala", CGRect(x: 0.795, y: 0.610, width: 0.07, height: 0.012)),
        ("Oistinger Feld 41", CGRect(x: 0.795, y: 0.588, width: 0.07, height: 0.012)),
        ("59510 Lippetal", CGRect(x: 0.795, y: 0.566, width: 0.06, height: 0.012)),
        ("Rechnung:", CGRect(x: 0.66, y: 0.522, width: 0.04, height: 0.012)),
        ("Rechnung_F5.pdf", CGRect(x: 0.795, y: 0.522, width: 0.06, height: 0.012)),
    ]

    private func covered(_ lines: [(String, CGRect)], _ chosen: Set<PrivateDetail>,
                         value: CGRect? = nil) -> (lines: Set<Int>, learned: Set<String>, hits: [Finder.Hit]) {
        var learned = Set<String>()
        let hits = Finder.labelled(lines.map { $0.0 }, boxes: lines.map { $0.1 }, part: { _, _ in value }, chosen,
                                   learned: &learned)
        return (Set(hits.map(\.line)), learned, hits)
    }

    func testTheValuesBesideTheLabelsOfAnOrderAreCovered() {
        // Names: the first and last name on their rows, and the bill's name.
        let names = covered(form, [.names])
        XCTAssertEqual(names.lines, [1, 3, 11])
        XCTAssertTrue(names.hits.allSatisfy { $0.range == nil && $0.kind == .names })
        // Each name on its own is looked for in the full name elsewhere.
        XCTAssertTrue(names.learned.isSuperset(of: ["martin", "dorozala"]), "\(names.learned)")
        // Addresses: the street, postcode and town on their rows, and the
        // address under the bill's name, up to the next label's row; the
        // street's block stops at the row of PLZ, and the bill's file stays.
        XCTAssertEqual(covered(form, [.addresses]).lines, [5, 7, 9, 12, 13])
    }

    /// Vision may read a label and its value as one line: the rest of the
    /// block still follows under the value, in its column.
    func testTheAddressFollowsUnderAValueReadWithItsLabel() {
        let lines: [(String, CGRect)] = [
            ("Rechnungsadresse: Martin Dorozala", CGRect(x: 0.66, y: 0.610, width: 0.205, height: 0.012)),
            ("Oistinger Feld 41", CGRect(x: 0.795, y: 0.588, width: 0.07, height: 0.012)),
            ("59510 Lippetal", CGRect(x: 0.795, y: 0.566, width: 0.06, height: 0.012)),
            ("Rechnung:", CGRect(x: 0.66, y: 0.522, width: 0.04, height: 0.012)),
            ("Rechnung_F5.pdf", CGRect(x: 0.795, y: 0.522, width: 0.06, height: 0.012)),
        ]
        let value = CGRect(x: 0.795, y: 0.610, width: 0.07, height: 0.012)
        let names = covered(lines, [.names], value: value)
        XCTAssertEqual(names.lines, [0])
        let line = lines[0].0 as NSString
        XCTAssertEqual(names.hits.first?.range ?? nil, line.range(of: "Martin Dorozala"))
        XCTAssertEqual(covered(lines, [.addresses], value: value).lines, [1, 2])
    }

    /// Three small lines in a colour, read by Vision as one sign, like "三":
    /// read again, line by line. A sign on a line of its own, or words,
    /// stay as they are.
    func testABlockReadAsOneSignIsReadAgain() {
        XCTAssertTrue(Finder.isBlockReadAsSign("三", height: 0.133, usual: 0.015))
        XCTAssertFalse(Finder.isBlockReadAsSign("三", height: 0.016, usual: 0.015))
        XCTAssertFalse(Finder.isBlockReadAsSign("Christopher Kelly", height: 0.05, usual: 0.015))
    }

    /// Read from a picture, as the app does: the customer's name under
    /// "Kunde", in blue with two more lines under it, is covered with
    /// everyone's names on, and so is the name the bill goes to, though they
    /// differ. The rest stays.
    func testBothNamesOnAnOrderPageAreCovered() throws {
        let image = try orderPage()
        let lines = Finder.textLines(in: image).map { "\($0.string) \($0.box)" }
        let covered = Finder.coveredAreas(in: image, PrivateDetail.allNames, rules: [], intelligence: false)
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
