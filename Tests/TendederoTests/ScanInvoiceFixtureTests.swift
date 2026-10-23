#if DEBUG && canImport(Vision) && canImport(CoreImage) && canImport(PDFKit) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Tendedero

/// The made-up invoice (`ScanInvoice`) with its words, printed and scanned
/// on a flatbed, then made ready as a picture chosen from Photos is: turned
/// level, cut in from its edges, cleaned in colour and read again. Measured
/// as `ScanInvoiceTests` measures the page in shapes, and every number read
/// before cleaning read after it. With SCAN_CAPTURES set, the scan is kept
/// with its page before and after and the numbers. Made-up data only.
final class ScanInvoiceFixtureTests: XCTestCase {
    private static var made: (scan: CGImage, prepared: ScanCleaner.Prepared, measures: ScanInvoiceMeasures, seconds: Double)?

    private func made() async throws
        -> (scan: CGImage, prepared: ScanCleaner.Prepared, measures: ScanInvoiceMeasures, seconds: Double) {
        if let made = Self.made { return made }
        let printed = try XCTUnwrap(Self.printed())
        let page = try XCTUnwrap(ScanCleaner.bitmap(printed))
        let scan = try XCTUnwrap(ScanCleaner.image(ScanInvoice.scanned(page, scale: 1), gray: false))
        let start = Date()
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(scan, quad: nil, mode: .color))
        let seconds = Date().timeIntervalSince(start)
        let cleaned = try XCTUnwrap(ScanCleaner.bitmap(prepared.cleaned))
        let w = Double(cleaned.width), h = Double(cleaned.height)
        let boxes = prepared.checked.reading.map { line -> (x0: Int, y0: Int, x1: Int, y1: Int) in
            (Int(line.box.minX * w), Int((1 - line.box.maxY) * h), Int(line.box.maxX * w), Int((1 - line.box.minY) * h))
        }
        // Turned level and cut in by a few dozen pixels: where the logo's
        // frame lies says how far, and each part is measured well inside.
        let cut = try XCTUnwrap(ScanInvoiceMeasure.offset(of: cleaned, scale: 1), "the logo's orange frame is seen")
        let measures = ScanInvoiceMeasure.measure(cleaned, scale: 1, left: cut.left, top: cut.top, margin: 60, textBoxes: boxes)
        Self.made = (scan, prepared, measures, seconds)
        ScanFixtureTests.keep(scan, "invoice-scan", longest: 1600)
        ScanFixtureTests.keep(prepared.straightened, "invoice-before", longest: 1600)
        ScanFixtureTests.keep(prepared.cleaned, "invoice-after", longest: 1600)
        ScanFixtureTests.write("invoice.txt", """
            invoice: scan \(scan.width)×\(scan.height), straightened \(prepared.straightened.width)×\(prepared.straightened.height), \
            cleaned \(prepared.cleaned.width)×\(prepared.cleaned.height), cut \(cut), skew \(String(format: "%.2f", prepared.skew * 180 / .pi))°, \
            \(String(format: "%.1f", seconds)) s on this Mac (debug build)
            \(measures)
            issues: \(prepared.checked.issues.map(\.kind.rawValue))

            """)
        print("INVOICE \(measures) issues \(prepared.checked.issues.map(\.kind.rawValue))")
        return (scan, prepared, measures, seconds)
    }

    /// The page as printed, at 300 dots an inch: the watermark, logo, seals
    /// and rules as `ScanInvoice` draws them, and its words in Helvetica.
    static func printed() -> CGImage? {
        let width = Int(ScanInvoice.width), height = Int(ScanInvoice.height)
        var page = ScanBitmap(width: width, height: height, red: 255, green: 255, blue: 255)
        ScanInvoice.background(&page, scale: 1)
        guard let base = ScanCleaner.image(page, gray: false), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        for line in ScanInvoice.lines {
            let colour = line.text == "MUSTERHANDEL" ? ScanInvoice.teal : ScanInvoice.ink
            let font = CTFontCreateWithName((line.bold ? "Helvetica-Bold" : "Helvetica") as CFString, CGFloat(line.size), nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: colour.red / 255, green: colour.green / 255, blue: colour.blue / 255, alpha: 1),
            ]
            let drawn = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
            context.textPosition = CGPoint(x: CGFloat(line.x), y: CGFloat(height) - CGFloat(line.top) - CTFontGetAscent(font))
            CTLineDraw(drawn, context)
        }
        return context.makeImage()
    }

    func testThePaperComesOutWhiteAndEvenWithItsCreaseGone() async throws {
        let measures = try await made().measures
        XCTAssertGreaterThanOrEqual(measures.paperWhite, 0.98, "the paper white")
        XCTAssertLessThanOrEqual(measures.paperRows, 3, "its rows even")
        XCTAssertLessThanOrEqual(measures.paperSaturation, 0.02, "its grey-blue cast gone")
        XCTAssertGreaterThanOrEqual(measures.crease, 248, "the crease gone from the margin it crossed")
    }

    func testThePrintComesOutDark() async throws {
        let measures = try await made().measures
        XCTAssertLessThanOrEqual(measures.printDarkness, 45, "print dark")
    }

    func testThePaleWatermarkKeepsItsTintAndShape() async throws {
        let measures = try await made().measures
        let printedBlue = Double(ScanClean.brightness(234, 242, 250))
        XCTAssertEqual(measures.blue.mean, printedBlue, accuracy: 8, "the blue as pale as printed, not white")
        XCTAssertEqual(measures.blueAtEdge, measures.blueInMiddle, accuracy: 4, "the same at the sheet's edge as in its middle")
        XCTAssertLessThanOrEqual(ScanColourSample.apart(measures.blue.hue, 210), 20, "and blue")
        XCTAssertLessThanOrEqual(measures.yellow.mean, 248, "the yellow kept")
    }

    func testTheLogoKeepsItsColourAndTheSealsTheirGrey() async throws {
        let measures = try await made().measures
        let orange = ScanColourSample.hue(ScanInvoice.orange.red, ScanInvoice.orange.green, ScanInvoice.orange.blue)
        XCTAssertLessThanOrEqual(ScanColourSample.apart(measures.orangeHue, orange), 10, "the logo's orange")
        XCTAssertGreaterThanOrEqual(measures.seal, 110, "the seal grey, not black")
        XCTAssertLessThanOrEqual(measures.seal, 200, "and not white")
    }

    func testNothingOfTheLidIsLeft() async throws {
        let measures = try await made().measures
        XCTAssertEqual(measures.edgePixels, 0, "nothing dark at the edges")
    }

    /// Every number read before cleaning is read after it, and no warning
    /// says text was lost.
    func testNoNumberIsLost() async throws {
        let prepared = try await made().prepared
        XCTAssertTrue(prepared.checked.textKept ?? false, "every line reads after cleaning")
        XCTAssertFalse(prepared.checked.issues.contains { $0.kind == .lessText }, "no text lost")
        // A number as its digits and marks: where Vision puts the euro sign,
        // before it or after, says nothing of the number.
        func numbers(_ lines: [Finder.TextLine]) -> Set<String> {
            Set(lines.flatMap { ScanFormMeasure.tokens(of: $0.string) }
                .map { $0.filter { $0.isNumber || $0.isLetter || ".,-/".contains($0) } }
                .filter { $0.contains(where: \.isNumber) })
        }
        let before = numbers(Finder.lines(in: prepared.straightened) ?? [])
        let after = numbers(prepared.checked.reading)
        XCTAssertFalse(before.isEmpty, "numbers read before")
        XCTAssertTrue(before.subtracting(after).isEmpty, "numbers lost \(before.subtracting(after))")
    }
}
#endif
