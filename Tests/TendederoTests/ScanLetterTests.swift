import XCTest
@testable import Tendedero

/// A doctor's letter photographed with a phone (`ScanLetter`), straightened
/// and cleaned as the Scan tab does: its lines lie straight, none bent into
/// a wave by text read as a rule, and the dark text no bolder than printed.
/// Then the long lines alone. Made-up data only.
final class ScanLetterTests: XCTestCase {
    private static var made: ScanLetterMeasures?

    private func made() -> ScanLetterMeasures {
        if let made = Self.made { return made }
        let printed = ScanLetter.page()
        let cleaned = ScanClean.clean(ScanBend.undeformed(ScanLetter.photographed(printed)), .color)
        let measures = ScanLetterMeasures.measure(cleaned, printed: printed)
        print("LETTER \(measures)")
        Self.made = measures
        return measures
    }

    func testTheCurlIsTakenOutAndNoWaveIsPutIn() {
        let measures = made()
        XCTAssertLessThanOrEqual(measures.wander, 1.5, "every line straight")
        XCTAssertLessThanOrEqual(measures.wanderUnderRule, 1.5, "the line just under the box's rule too")
    }

    func testTheDarkTextIsNoBolderThanPrinted() {
        XCTAssertLessThanOrEqual(made().bodyArea, 1.2, "strokes as thick as printed")
    }

    // MARK: The long lines alone

    /// A white page with lines of dense text, `rows` of them from `top`.
    private func textPage(width: Int = 1200, height: Int = 1600, top: Int = 200, rows: Int = 20) -> ScanBitmap {
        var page = ScanBitmap(width: width, height: height, red: 255, green: 255, blue: 255)
        for row in 0..<rows {
            let y0 = top + row * 40
            var x = 80
            while x < width - 80 {
                // A letter: a stem and a bar along its foot.
                for y in y0..<(y0 + 18) { for xx in x..<(x + 3) { set(&page, xx, y, 30) } }
                for y in (y0 + 15)..<(y0 + 18) { for xx in x..<(x + 8) { set(&page, xx, y, 30) } }
                x += x % 7 == 0 ? 20 : 11
            }
        }
        return page
    }

    private func set(_ page: inout ScanBitmap, _ x: Int, _ y: Int, _ value: UInt8) {
        guard x >= 0, y >= 0, x < page.width, y < page.height else { return }
        let i = (y * page.width + x) * 4
        page.pixels[i] = value
        page.pixels[i + 1] = value
        page.pixels[i + 2] = value
    }

    /// A rule across the page, bowed down by `bow` in its middle.
    private func rule(on page: inout ScanBitmap, at y: Double, bow: Double) {
        for x in 0..<page.width {
            let middle = y + bow * sin(.pi * Double(x) / Double(page.width))
            for yy in Int(middle.rounded())..<(Int(middle.rounded()) + 3) { set(&page, x, yy, 40) }
        }
    }

    func testDenseTextIsNoLine() {
        let page = textPage()
        XCTAssertTrue(ScanBend.lines(in: page.brightness, width: page.width, height: page.height).isEmpty,
                      "rows of letters are text, not rules")
        XCTAssertEqual(ScanBend.undeformed(page), page, "and the page is left as it is")
    }

    func testABowedRuleIsLaidStraightWithTextCloseUnderIt() throws {
        var page = textPage(top: 612, rows: 3)
        rule(on: &page, at: 600, bow: 6)
        let lines = ScanBend.lines(in: page.brightness, width: page.width, height: page.height)
        XCTAssertEqual(lines.count, 1, "the rule alone")
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.heights[600] - line.heights[0], -6, accuracy: 1, "bowed down six pixels in the middle")
        let straight = ScanBend.undeformed(page)
        // The rule on one row from one side to the other.
        let rows = [10, 300, 600, 900, 1190].map { x in
            (590..<620).min { straight.brightness(x: x, y: $0) < straight.brightness(x: x, y: $1) }!
        }
        XCTAssertLessThanOrEqual(rows.max()! - rows.min()!, 1, "the rule straight: \(rows)")
    }
}
