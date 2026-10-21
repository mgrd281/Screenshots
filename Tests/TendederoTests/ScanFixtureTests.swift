#if canImport(Vision) && canImport(CoreImage) && canImport(PDFKit)
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// The scan through Vision and Core Image, as on an iPhone, on made-up
/// photos of a made-up invoice (`ScanSample`): the page found where it
/// lies, made flat in A4's shape and turned upright; cleaned with every
/// number still read and every detail still found; each look keeping what
/// it should; blur and a reflection said for the right part; and what
/// leaves: covers in the PDF's pixels and not in its text, nothing said of
/// who made it but Snapfly, PNGs without notes, and a page as the camera
/// gives it going through as before. With SCAN_CAPTURES set to a folder,
/// it keeps the pictures before and after, with their numbers.
final class ScanFixtureTests: XCTestCase {
    private static let page = ScanSample.page()

    private var page: CGImage { get throws { try XCTUnwrap(Self.page) } }

    private func photo(_ flaw: ScanSample.Flaw = .none, turns: Int = 0) throws -> ScanSample.Photo {
        try XCTUnwrap(ScanSample.photographed(try page, flaw: flaw, quarterTurns: turns))
    }

    func testThePageIsFoundWhereItLies() throws {
        let photo = try photo()
        let found = try XCTUnwrap(ScanCleaner.page(in: photo.image), "Vision finds the page")
        XCTAssertGreaterThan(found.confidence, 0.5)
        for (corner, truth) in zip(found.quad.corners, photo.quad.corners) {
            XCTAssertLessThan(hypot(corner.x - truth.x, corner.y - truth.y), 0.03, "\(corner) for \(truth)")
        }
    }

    func testTheFlatPageHasA4sShapeAndThePhotosPixels() throws {
        let photo = try photo()
        let flat = try XCTUnwrap(ScanCleaner.straightened(photo.image, quad: photo.quad))
        XCTAssertEqual(Double(flat.width) / Double(flat.height), 1 / 2.0.squareRoot(), accuracy: 0.002)
        XCTAssertGreaterThan(flat.height, 2800, "as many pixels as the photo has for the page")
        Self.keep(flat, "flat")
    }

    func testAPhotoTakenSidewaysIsTurnedUpright() async throws {
        let photo = try photo(turns: 1)
        let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        XCTAssertEqual(prepared.turns, 3, "a quarter turn back")
        XCTAssertLessThan(prepared.straightened.width, prepared.straightened.height, "upright")
    }

    func testCleaningKeepsEveryNumberAndTheTextReadsTheSame() async throws {
        let photo = try photo()
        let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        XCTAssertEqual(prepared.checked.textKept, true)
        XCTAssertEqual(prepared.checked.issues, [], "nothing wrong with a sharp photo")
        let read = prepared.checked.reading.map(\.string).joined(separator: " ")
        for amount in ScanSample.amounts { XCTAssertTrue(read.contains(amount), "\(amount) is read after cleaning") }
        Self.keep(photo.image, "photo", longest: 1600)
        Self.keep(prepared.straightened, "before")
        Self.keep(prepared.cleaned, "after-color")
        Self.note("color", prepared)
    }

    func testTheSameDetailsAreFoundOnTheCleanedPageAsOnThePrintedOne() async throws {
        let chosen = PrivateDetail.recommended
        let printed = Finder.analysis(in: try page, chosen, rules: [], intelligence: false).areas
        let photo = try photo()
        let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        let cleaned = Finder.analysis(in: prepared.cleaned, chosen, rules: [], intelligence: false).areas
        func counts(_ areas: [Finder.Area]) -> [String: Int] {
            Dictionary(grouping: areas, by: { $0.kind?.rawValue ?? "rule" }).mapValues(\.count)
        }
        XCTAssertFalse(printed.isEmpty, "the invoice has private details")
        for (kind, count) in counts(printed) {
            XCTAssertGreaterThanOrEqual(counts(cleaned)[kind] ?? 0, count, "\(kind): printed \(counts(printed)), cleaned \(counts(cleaned))")
        }
        Self.write("detection.txt", "Printed page: \(counts(printed).sorted { $0.key < $1.key })\n"
            + "Cleaned photo: \(counts(cleaned).sorted { $0.key < $1.key })\n")
    }

    func testEachLookKeepsWhatItShould() async throws {
        let photo = try photo()
        let gray = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .gray))
        XCTAssertEqual(gray.cleaned.colorSpace?.model, .monochrome)
        XCTAssertEqual(gray.checked.textKept, true)
        let black = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .blackAndWhite))
        let bitmap = try XCTUnwrap(ScanCleaner.bitmap(black.cleaned))
        XCTAssertEqual(Set(bitmap.brightness), [0, 255])
        Self.keep(gray.cleaned, "after-gray")
        Self.keep(black.cleaned, "after-black-and-white")
        Self.note("gray", gray)
        Self.note("black-and-white", black)
    }

    func testABlurredBottomAndAReflectionAreSaidForWhereTheyAre() async throws {
        let blurred = try photo(.blurredBottom)
        let soft = try await XCTUnwrapAsync(await ScanCleaner.prepare(blurred.image, quad: blurred.quad, mode: .color))
        let blur = try XCTUnwrap(soft.checked.issues.first { $0.kind == .blurred }, "\(soft.checked.issues)")
        XCTAssertEqual(blur.part, .bottom)
        let shiny = try photo(.glare)
        let lit = try await XCTUnwrapAsync(await ScanCleaner.prepare(shiny.image, quad: shiny.quad, mode: .color))
        let glare = try XCTUnwrap(lit.checked.issues.first { $0.kind == .glare }, "\(lit.checked.issues)")
        XCTAssertEqual(glare.part, .top)
        Self.keep(blurred.image, "photo-blurred-bottom", longest: 1600)
        Self.keep(shiny.image, "photo-reflection", longest: 1600)
        Self.note("blurred bottom", soft)
        Self.note("reflection", lit)
    }

    func testThePDFHasItsCoversInItsPixelsAndNotInItsText() async throws {
        let photo = try photo()
        let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        let covered = try await XCTUnwrapAsync(await CoveredCopy.make(prepared.cleaned, PrivateDetail.recommended, rules: [],
                                                                     style: .ink, intelligence: false))
        let places = covered.report.places
        XCTAssertFalse(places.isEmpty)
        let reading = Finder.lines(in: covered.image) ?? []
        let words = ScanCleaner.words(in: reading, hiding: places)
        let page = try XCTUnwrap(ScanCleaner.pdfPage(covered.image, mode: .color, words: words))
        let data = try XCTUnwrap(ScanPDF.make([page]))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(text.contains("Rechnung"), text)
        XCTAssertTrue(text.contains("369,73"), text)
        for hidden in ["Mustermann", "3704", "buchhaltung@"] {
            XCTAssertFalse(text.contains(hidden), "\(hidden) is in the covered PDF's text")
        }
        // The IBAN's place is dark in the page as it prints.
        let iban = try XCTUnwrap(places.first { place in
            reading.isEmpty || prepared.checked.reading.contains { $0.string.contains("IBAN") && $0.box.intersects(place) }
        })
        let rendered = try XCTUnwrap(Self.rendered(data))
        let bitmap = try XCTUnwrap(ScanCleaner.bitmap(rendered))
        let x = Int(iban.midX * CGFloat(bitmap.width)), y = Int((1 - iban.midY) * CGFloat(bitmap.height))
        XCTAssertLessThan(bitmap.brightness(x: x, y: y), 80, "covered in the pixels")
        // Without covers, every word is there.
        let open = try XCTUnwrap(ScanCleaner.pdfPage(prepared.cleaned, mode: .color,
                                                     words: ScanCleaner.words(in: prepared.checked.reading)))
        let openText = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(ScanPDF.make([open])))?.page(at: 0)?.string)
        XCTAssertTrue(openText.contains("Mustermann"), openText)
        // Nothing said of who made it but Snapfly.
        let attributes = pdf.documentAttributes ?? [:]
        XCTAssertEqual(attributes[PDFDocumentAttribute.producerAttribute] as? String, "Snapfly")
        for key in [PDFDocumentAttribute.titleAttribute, .authorAttribute, .creatorAttribute, .creationDateAttribute,
                    .modificationDateAttribute, .subjectAttribute, .keywordsAttribute] {
            XCTAssertNil(attributes[key], "\(key.rawValue) is in the PDF")
        }
        let box = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(box.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(box.height, 841.89, accuracy: 0.01)
        Self.keep(rendered, "pdf-covered")
        Self.write("covered-pdf-text.txt", text)
    }

    func testBlackAndWhiteMakesTheSmallestPDF() async throws {
        let photo = try photo()
        var sizes: [ScanColor: Int] = [:]
        for mode in ScanColor.allCases {
            let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: mode))
            let page = try XCTUnwrap(ScanCleaner.pdfPage(prepared.cleaned, mode: mode, words: []))
            let data = try XCTUnwrap(ScanPDF.make([page]))
            XCTAssertNotNil(Self.rendered(data), "\(mode) reads")
            sizes[mode] = data.count
        }
        XCTAssertLessThan(sizes[.blackAndWhite] ?? .max, sizes[.gray] ?? 0)
        XCTAssertLessThan(sizes[.gray] ?? .max, sizes[.color] ?? 0)
        Self.write("pdf-sizes.txt", sizes.map { "\($0.key.rawValue): \($0.value / 1024) KB" }.sorted().joined(separator: "\n"))
    }

    func testPNGsSayNothingAboutThemselves() throws {
        let png = try XCTUnwrap(CoveredCopy.png(try page))
        let chunks = Self.chunks(of: png)
        XCTAssertEqual(chunks.first, "IHDR")
        XCTAssertEqual(chunks.last, "IEND")
        for chunk in ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"] { XCTAssertFalse(chunks.contains(chunk), "\(chunk) in \(chunks)") }
    }

    func testAPageAsTheCameraGivesItGoesThroughAsBefore() async throws {
        let page = try page
        let prepared = try await XCTUnwrapAsync(await ScanCleaner.prepare(page, quad: nil, mode: .color))
        XCTAssertEqual(prepared.turns, 0)
        XCTAssertEqual(prepared.skew, 0)
        XCTAssertEqual(prepared.straightened.width, page.width)
        XCTAssertEqual(prepared.straightened.height, page.height)
        XCTAssertEqual(prepared.checked.textKept, true)
        let covered = try await XCTUnwrapAsync(await CoveredCopy.make(prepared.cleaned, PrivateDetail.recommended, rules: [],
                                                                     style: .ink, intelligence: false))
        let pages = try [covered.image, covered.image].map { try XCTUnwrap(ScanCleaner.pdfPage($0, mode: .color, words: [])) }
        let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(ScanPDF.make(pages))))
        XCTAssertEqual(pdf.pageCount, 2)
    }

    // MARK: Helpers

    /// The first page of a PDF as it prints, at 150 dots an inch.
    static func rendered(_ data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * 150 / 72), height = Int(box.height * 150 / 72)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 150 / 72, y: 150 / 72)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// A PNG's chunks by name, in order.
    static func chunks(of png: Data) -> [String] {
        let bytes = [UInt8](png)
        var names: [String] = []
        var i = 8
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            names.append(String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self))
            i += 12 + length
        }
        return names
    }

    // MARK: Captures

    private static var captures: URL? {
        guard let path = ProcessInfo.processInfo.environment["SCAN_CAPTURES"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A picture kept with the captures, no longer than `longest`.
    static func keep(_ image: CGImage, _ name: String, longest: Int = 2400) {
        guard let folder = captures, let small = ScanCleaner.smaller(image, longest: longest),
              let png = CoveredCopy.png(small) else { return }
        try? png.write(to: folder.appendingPathComponent("scan-\(name).png"))
    }

    static func write(_ name: String, _ text: String) {
        guard let folder = captures else { return }
        try? Data(text.utf8).write(to: folder.appendingPathComponent("scan-\(name)"))
    }

    /// What the checks found on a page, added to the captures' notes.
    static func note(_ name: String, _ prepared: ScanCleaner.Prepared) {
        guard let folder = captures else { return }
        let url = folder.appendingPathComponent("scan-numbers.txt")
        let issues = prepared.checked.issues.map { "\($0.kind.rawValue) (\($0.part))" }.joined(separator: ", ")
        let line = "\(name): \(prepared.straightened.width)×\(prepared.straightened.height) px, "
            + "\(Int(ScanGeometry.dpi(width: prepared.straightened.width, height: prepared.straightened.height))) dpi on A4, "
            + "turns \(prepared.turns), skew \(String(format: "%.2f", prepared.skew * 180 / .pi))°, "
            + "text kept: \(prepared.checked.textKept.map { $0 ? "yes" : "no" } ?? "no text"), "
            + "lines read after: \(prepared.checked.reading.count), issues: \(issues.isEmpty ? "none" : issues)\n"
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? Data((old + line).utf8).write(to: url)
    }
}

/// `XCTUnwrap` for a value an async call gave.
func XCTUnwrapAsync<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, message, file: file, line: line)
}
#endif
