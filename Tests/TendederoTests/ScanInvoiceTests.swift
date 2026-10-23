import XCTest
@testable import Tendedero

/// A printed invoice scanned on a flatbed (`ScanInvoice`), cleaned as a good
/// scanner leaves it: the paper white and even with its crease gone, a pale
/// watermark kept in its own tint and shape, its blue reaching the sheet's
/// edge as printed, the logo's colour and the seals' grey kept, the print
/// dark, and nothing of the lid's shadow left. Then the crease alone: found
/// where the sheet was folded, and never on lined paper or a printed rule.
/// Made-up data only.
final class ScanInvoiceTests: XCTestCase {
    /// Half of 300 dots an inch: enough for every part, quick in a debug build.
    private static let scale = 0.5
    private static var made: (page: ScanBitmap, cut: (left: Int, top: Int, right: Int, bottom: Int),
                              measures: ScanInvoiceMeasures)?

    /// The invoice scanned, cut in from its edges as the Scan tab does, and
    /// cleaned in colour; once for all the tests.
    private func made() -> (page: ScanBitmap, cut: (left: Int, top: Int, right: Int, bottom: Int), measures: ScanInvoiceMeasures) {
        if let made = Self.made { return made }
        let scan = ScanInvoice.scanned(ScanInvoice.page(scale: Self.scale), scale: Self.scale)
        let cut = ScanSheet.inset(of: scan)
        let cleaned = ScanSheet.edgeCleaned(ScanClean.clean(ScanSheet.cropped(scan, cut), .color))
        let measures = ScanInvoiceMeasure.measure(cleaned, scale: Self.scale, left: cut.left, top: cut.top)
        print("INVOICE \(cleaned.width)×\(cleaned.height), cut \(cut), as the logo says \(String(describing: ScanInvoiceMeasure.offset(of: cleaned, scale: Self.scale))): \(measures)")
        Self.made = (cleaned, cut, measures)
        return (cleaned, cut, measures)
    }

    func testThePaperComesOutWhiteAndEvenWithItsCreaseGone() {
        let measures = made().measures
        XCTAssertGreaterThanOrEqual(measures.paperWhite, 0.98, "the paper white")
        XCTAssertLessThanOrEqual(measures.paperRows, 3, "its rows even")
        XCTAssertLessThanOrEqual(measures.paperSaturation, 0.02, "its grey-blue cast gone")
        XCTAssertGreaterThanOrEqual(measures.crease, 250, "the crease gone from the margin it crossed")
    }

    func testThePrintComesOutDark() {
        let measures = made().measures
        XCTAssertLessThanOrEqual(measures.printDarkness, 45, "the soft toner comes out dark")
    }

    /// The watermark keeps the shade and tint it was printed in, alike at
    /// the sheet's edge and in its middle, where it used to go white with
    /// the paper there and stay tinted elsewhere.
    func testThePaleWatermarkKeepsItsTintAndShape() {
        let measures = made().measures
        let printedBlue = Double(ScanClean.brightness(234, 242, 250))
        XCTAssertEqual(measures.blue.mean, printedBlue, accuracy: 6, "the blue as pale as printed, not white")
        XCTAssertLessThanOrEqual(measures.blue.spread, 10, "and even")
        XCTAssertEqual(measures.blueAtEdge, measures.blueInMiddle, accuracy: 3, "the same at the sheet's edge as in its middle")
        XCTAssertLessThanOrEqual(ScanColourSample.apart(measures.blue.hue, 210), 15, "and blue")
        XCTAssertLessThanOrEqual(measures.yellow.mean, 248, "the yellow kept")
        XCTAssertLessThanOrEqual(ScanColourSample.apart(measures.yellow.hue, ScanColourSample.hue(255, 244, 205)), 15,
                                 "and yellow")
    }

    func testTheLogoKeepsItsColourAndTheSealsTheirGrey() {
        let measures = made().measures
        let orange = ScanColourSample.hue(ScanInvoice.orange.red, ScanInvoice.orange.green, ScanInvoice.orange.blue)
        XCTAssertLessThanOrEqual(ScanColourSample.apart(measures.orangeHue, orange), 10, "the logo's orange")
        XCTAssertGreaterThanOrEqual(measures.seal, 110, "the seal grey, not black")
        XCTAssertLessThanOrEqual(measures.seal, 200, "and not white")
    }

    /// The lid's shadow along the top and the right, and the glass at the
    /// corners where the sheet lay crooked, are cut away.
    func testNothingOfTheLidIsLeft() {
        let (page, cut, measures) = made()
        XCTAssertGreaterThanOrEqual(Double(cut.top), ScanInvoice.lidTop * Self.scale, "the lid's shadow along the top")
        XCTAssertGreaterThanOrEqual(Double(cut.right), ScanInvoice.lidRight * Self.scale, "and the right")
        XCTAssertEqual(measures.edgePixels, 0, "nothing dark at the edges of \(page.width)×\(page.height)")
    }

    // MARK: The crease alone

    /// A plain page with lines of print, as `evened` leaves it: its paper at 255.
    private func printedPage(width: Int = 900, height: Int = 1200) -> ScanBitmap {
        var page = ScanBitmap(width: width, height: height, red: 255, green: 255, blue: 255)
        for top in stride(from: 100, to: height - 100, by: 60) {
            for x in stride(from: 90, to: width - 90, by: 14) {
                for y in top..<(top + 22) { for k in 0..<3 { page.pixels[(y * width + x) * 4 + k] = 30 } }
            }
        }
        return page
    }

    /// A line across the whole page, `rows` thick, slanting by `slope`, its
    /// pixels multiplied by `share` per colour.
    private func line(on page: inout ScanBitmap, at y0: Double, slope: Double = 0, rows: Int = 3, from: Int = 0, to: Int? = nil,
                      share: (Double, Double, Double)) {
        for x in from..<(to ?? page.width) {
            let middle = Int((y0 + slope * Double(x)).rounded())
            for y in (middle - rows / 2)...(middle + rows / 2) where y >= 0 && y < page.height {
                let i = (y * page.width + x) * 4
                page.pixels[i] = UInt8(Double(page.pixels[i]) * share.0)
                page.pixels[i + 1] = UInt8(Double(page.pixels[i + 1]) * share.1)
                page.pixels[i + 2] = UInt8(Double(page.pixels[i + 2]) * share.2)
            }
        }
    }

    func testACreaseIsFoundWhereTheSheetWasFoldedAndEvenedOut() throws {
        var page = printedPage()
        line(on: &page, at: 640, slope: 0.006, share: (0.88, 0.88, 0.88))
        let found = ScanClean.creases(in: page, across: true)
        XCTAssertEqual(found.count, 1, "one crease")
        let crease = try XCTUnwrap(found.first)
        XCTAssertEqual(crease.line(at: 0), 640, accuracy: 2, "where it starts")
        XCTAssertEqual(crease.line(at: 899), 640 + 0.006 * 899, accuracy: 2, "and ends")
        XCTAssertTrue(ScanClean.creases(in: page, across: false).isEmpty, "none down the page")
        let flat = ScanClean.uncreased(page)
        for x in [10, 450, 880] {
            let y = Int((640 + 0.006 * Double(x)).rounded())
            XCTAssertGreaterThanOrEqual(flat.brightness(x: x, y: y), 252, "the margin and the paper white again at \(x)")
        }
        // Print on the crease comes back as dark as it was printed, not lighter.
        XCTAssertEqual(Double(flat.brightness(x: 90, y: 641)), 30, accuracy: 6, "print on the crease as printed")
    }

    func testLinedPaperKeepsItsLines() {
        var page = printedPage()
        for y in stride(from: 80.0, to: 1150, by: 70) { line(on: &page, at: y, rows: 2, share: (0.85, 0.85, 0.85)) }
        XCTAssertTrue(ScanClean.creases(in: page, across: true).isEmpty, "a page of lines is lined, not creased")
        XCTAssertLessThan(ScanClean.uncreased(page).brightness(x: 10, y: 150), 230, "its lines stay")
    }

    func testAColouredLineIsNotACrease() {
        var page = printedPage()
        line(on: &page, at: 640, share: (0.75, 0.85, 1.0))
        XCTAssertTrue(ScanClean.creases(in: page, across: true).isEmpty, "a blue line is printed, not light")
    }

    func testAPrintedRuleIsNotACrease() {
        var page = printedPage()
        // Faint enough, but it stops at the margins, as printed rules do.
        line(on: &page, at: 640, from: 60, to: 840, share: (0.88, 0.88, 0.88))
        XCTAssertTrue(ScanClean.creases(in: page, across: true).isEmpty, "a rule within the margins is print")
        // And a dark one, though it reaches both edges.
        var dark = printedPage()
        line(on: &dark, at: 640, share: (0.3, 0.3, 0.3))
        XCTAssertTrue(ScanClean.creases(in: dark, across: true).isEmpty, "a dark line is print")
    }

    /// A pale fill on a page lit unevenly, brighter at its top left, is
    /// kept whole and even, as pale as printed, while the paper round it
    /// comes out white.
    func testAPaleFillUnderUnevenLightIsKeptWhole() {
        let w = 900, h = 1270
        var page = printedPage(width: w, height: h)
        var seed: UInt32 = 3
        for y in 0..<h {
            for x in 0..<w {
                let light = 1 - 0.12 * (Double(x) / Double(w) + Double(y) / Double(h)) / 2
                let fill = x >= 140 && x < 640 && y >= 720 && y < 1020 ? 0.955 : 1
                for k in 0..<3 {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let grain = Double(seed >> 24) / 255 * 4 - 2
                    let i = (y * w + x) * 4 + k
                    page.pixels[i] = UInt8(max(0, min(255, (Double(page.pixels[i]) * 0.92 * light * fill + grain).rounded())))
                }
            }
        }
        let cleaned = ScanClean.clean(page, .color)
        var inside: [Double] = []
        for y in stride(from: 760, to: 980, by: 4) {
            for x in stride(from: 180, to: 600, by: 4) where cleaned.brightness(x: x, y: y) > 200 {
                inside.append(Double(cleaned.brightness(x: x, y: y)))
            }
        }
        inside.sort()
        let mean = inside.reduce(0, +) / Double(inside.count)
        XCTAssertEqual(mean, 0.955 * 255, accuracy: 4, "the fill as pale as printed, all of it")
        XCTAssertLessThanOrEqual(inside[inside.count * 19 / 20] - inside[inside.count / 20], 8, "and even, dim corner and bright")
        for (x, y) in [(40, 40), (860, 1230), (860, 40), (40, 1230), (450, 700)] {
            XCTAssertGreaterThanOrEqual(cleaned.brightness(x: x, y: y), 250, "the paper white at \(x), \(y)")
        }
    }

    /// A pale fill with a soft edge is light, as a shadow is: still evened
    /// to white, while one with a sharp edge keeps its shade.
    func testAPaleSoftShadowIsEvenedAndAPaleSharpFillIsKept() {
        let w = 900, h = 1200
        var page = printedPage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x - 250) / 120, dy = Double(y - 400) / 120
                var share = 1 - 0.06 * exp(-(dx * dx + dy * dy))
                if x >= 500, x < 800, y >= 700, y < 1000 { share *= 0.94 }
                for k in 0..<3 {
                    let i = (y * w + x) * 4 + k
                    page.pixels[i] = UInt8((Double(page.pixels[i]) * share * 0.9).rounded())
                }
            }
        }
        let cleaned = ScanClean.clean(page, .color)
        XCTAssertGreaterThanOrEqual(cleaned.brightness(x: 250, y: 430), 250, "the soft shadow's middle is paper")
        XCTAssertLessThanOrEqual(cleaned.brightness(x: 657, y: 800), 245, "the sharp pale fill keeps its shade")
        XCTAssertGreaterThanOrEqual(cleaned.brightness(x: 657, y: 800), 230, "and stays pale")
    }
}
