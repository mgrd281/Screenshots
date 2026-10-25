import XCTest
@testable import Tendedero

/// The Scan tab's small pictures veiled (`ScanVeil`): nothing sharp is left
/// on a page of print, so no word can be read, while the page's shape and
/// colour stay. On this Mac, Vision reads a made-up invoice before it is
/// veiled and nothing after, as small as the tab shows it and drawn three
/// times larger; shown, its owner's saved name is covered.
final class ScanVeilTests: XCTestCase {
    /// A page of print: rows of strokes 1 to 4 px wide, as 7 to 24 pt print is at a thumbnail's size.
    private static func print(width: Int = 240, height: Int = 340) -> ScanBitmap {
        var page = ScanBitmap(width: width, height: height, red: 250, green: 248, blue: 244)
        for row in 0..<12 {
            let top = 12 + row * 20, stroke = 1 + row % 4
            for x in stride(from: 12, to: width - 12, by: 3 + stroke) {
                for y in top..<(top + 6 + stroke * 2) where y < height {
                    for dx in 0..<stroke where x + dx < width {
                        let i = (y * width + x + dx) * 4
                        page.pixels[i] = 20
                        page.pixels[i + 1] = 20
                        page.pixels[i + 2] = 20
                    }
                }
            }
        }
        return page
    }

    /// The steepest turn of brightness from one pixel to the next.
    private static func steepest(_ page: ScanBitmap) -> Int {
        let plane = page.brightness, w = page.width
        var most = 0
        for y in 0..<(page.height - 1) {
            for x in 0..<(w - 1) {
                let p = y * w + x
                most = max(most, abs(Int(plane[p + 1]) - Int(plane[p])), abs(Int(plane[p + w]) - Int(plane[p])))
            }
        }
        return most
    }

    func testNothingSharpIsLeftButThePagesShapeAndColourStay() {
        let page = Self.print()
        let veiled = ScanVeil.veiled(page)
        XCTAssertGreaterThan(Self.steepest(page), 200, "the print is sharp")
        XCTAssertLessThanOrEqual(Self.steepest(veiled), 12, "no edge a letter could be read by")
        // The paper's colour at the bottom, where nothing is printed, and the print's shade above it.
        let paper = veiled.color(x: 120, y: 336)
        XCTAssertGreaterThan(Int(paper.red), 230)
        XCTAssertGreaterThan(Int(paper.red) - Int(paper.blue), 2, "still warm")
        XCTAssertLessThan(Int(veiled.brightness(x: 120, y: 100)), 225, "the print's place is darker")
        XCTAssertEqual(veiled.width, page.width)
        XCTAssertEqual(veiled.height, page.height)
    }
}

#if DEBUG && canImport(PDFKit) && canImport(Vision) && canImport(CoreText)
import PDFKit
import Vision

extension ScanVeilTests {
    /// The words Vision reads, accurately, with language correction.
    private static func words(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) }
    }

    private static func drawn(_ bitmap: ScanBitmap, scale: Int) throws -> CGImage {
        let image = try XCTUnwrap(ScanCleaner.image(bitmap, gray: false))
        guard scale > 1 else { return image }
        let context = try XCTUnwrap(PictureTools.context(width: image.width * scale, height: image.height * scale))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale))
        return try XCTUnwrap(context.makeImage())
    }

    private static func invoice() throws -> CGImage {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("veil-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Rechnung.pdf")
        try PDFFixtures.invoice().write(to: url)
        let source = try XCTUnwrap(PDFSource(url: url))
        return try XCTUnwrap(source.render(0, turns: 0, dpi: 200, longest: 2400))
    }

    /// A made-up invoice with print from 10 to 22 pt: read whole before, and
    /// veiled as the tab shows it (480 px), not one word, as it is or drawn
    /// three times larger.
    func testNoWordIsReadOnAVeiledPageAtAnySize() throws {
        let page = try Self.invoice()
        let before = try Self.words(in: page)
        XCTAssertGreaterThan(before.count, 20, "the invoice reads before: \(before.prefix(8))")
        let small = try XCTUnwrap(ScanCleaner.smaller(page, longest: 480).flatMap(ScanCleaner.bitmap))
        let veiled = ScanVeil.veiled(small)
        for scale in [1, 3] {
            let read = try Self.words(in: try Self.drawn(veiled, scale: scale))
            print("VEIL at \(scale)×: \(read.count) words \(read)")
            XCTAssertEqual(read, [], "at \(scale)×")
        }
    }

    /// Shown, the small picture is the covered copy: the owner's saved name,
    /// kept in Always Hide, is read nowhere on it, even drawn three times larger.
    func testAShownPictureHidesTheSavedName() async throws {
        let page = try Self.invoice()
        XCTAssertTrue(try Self.words(in: page).contains("Mustermann"), "the name is on the page")
        let rules = [OwnRule(text: PDFFixtures.customer, kind: .name)]
        let made = try XCTUnwrapAsync(await CoveredCopy.make(page, [], rules: rules, style: .ink, intelligence: false))
        let small = try XCTUnwrap(ScanCleaner.smaller(made.image, longest: 480).flatMap(ScanCleaner.bitmap))
        for scale in [1, 3] {
            let read = try Self.words(in: try Self.drawn(small, scale: scale))
            XCTAssertFalse(read.contains { $0.contains("Mustermann") || $0.contains("Erika") }, "at \(scale)×: \(read)")
        }
    }
}
#endif
