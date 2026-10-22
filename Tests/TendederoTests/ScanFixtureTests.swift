#if DEBUG && canImport(Vision) && canImport(CoreImage) && canImport(PDFKit)
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// The scan through Vision and Core Image, as on an iPhone, on made-up
/// photos of a made-up invoice (`ScanSample`): the page found where it
/// lies, made flat in A4's shape and turned upright, and levelled again
/// when it is cut again; cleaned with every number still read and every
/// detail still found; each look keeping what it should; blur and a
/// reflection said for the right part; and what leaves: covers in the
/// PDF's pixels and not in its text, greys where the PDF says greys,
/// nothing said of who made it but Snapfly, PNGs without notes, and a page
/// as the camera gives it going through as before. With SCAN_CAPTURES set
/// to a folder, it keeps the pictures before and after, with their
/// numbers. Each photo is taken, and each page made ready, once for all the
/// tests that look at it.
final class ScanFixtureTests: XCTestCase {
    private static let page = ScanSample.page()
    private static var photos: [String: ScanSample.Photo] = [:]
    private static var made: [String: ScanCleaner.Prepared] = [:]

    private var page: CGImage { get throws { try XCTUnwrap(Self.page) } }

    private func photo(_ flaw: ScanSample.Flaw = .none, turns: Int = 0) throws -> ScanSample.Photo {
        let key = "\(flaw.rawValue)-\(turns)"
        if let photo = Self.photos[key] { return photo }
        let photo = try XCTUnwrap(ScanSample.photographed(try page, flaw: flaw, quarterTurns: turns))
        Self.photos[key] = photo
        return photo
    }

    /// The photo's page made flat, upright, cleaned in `mode` and checked.
    private func cleaned(_ flaw: ScanSample.Flaw = .none, turns: Int = 0, mode: ScanColor = .color) async throws
        -> ScanCleaner.Prepared {
        let key = "\(flaw.rawValue)-\(turns)-\(mode.rawValue)"
        if let prepared = Self.made[key] { return prepared }
        let photo = try photo(flaw, turns: turns)
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: mode))
        Self.made[key] = prepared
        return prepared
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
        let shape: Double = Double(flat.width) / Double(flat.height)
        let a4: Double = 1 / 2.0.squareRoot()
        XCTAssertEqual(shape, a4, accuracy: 0.002)
        XCTAssertGreaterThan(flat.height, 2800, "as many pixels as the photo has for the page")
        Self.keep(flat, "flat")
    }

    func testAPhotoTakenSidewaysIsTurnedUpright() async throws {
        let prepared = try await cleaned(turns: 1)
        XCTAssertEqual(prepared.turns, 3, "a quarter turn back")
        XCTAssertLessThan(prepared.straightened.width, prepared.straightened.height, "upright")
    }

    func testCuttingAgainMeasuresTheLeanAgain() throws {
        let photo = try photo()
        // The page's corners turned 2° about its middle, in the photo's pixels: the cut leans.
        let width = CGFloat(photo.image.width), height = CGFloat(photo.image.height)
        let angle: CGFloat = 2 * .pi / 180
        let turnCos: CGFloat = cos(angle), turnSin: CGFloat = sin(angle)
        let corners = photo.quad.corners
        let acrossSum: CGFloat = corners.map(\.x).reduce(0, +), downSum: CGFloat = corners.map(\.y).reduce(0, +)
        let middle = CGPoint(x: acrossSum / 4, y: downSum / 4)
        var leaning = photo.quad
        leaning.corners = corners.map { corner -> CGPoint in
            let x: CGFloat = (corner.x - middle.x) * width, y: CGFloat = (corner.y - middle.y) * height
            let turnedX: CGFloat = x * turnCos - y * turnSin
            let turnedY: CGFloat = x * turnSin + y * turnCos
            let movedX: CGFloat = middle.x + turnedX / width, movedY: CGFloat = middle.y + turnedY / height
            return CGPoint(x: movedX, y: movedY)
        }
        let lean = Double(angle)
        let kept = try XCTUnwrap(ScanCleaner.flattened(photo.image, quad: leaning, way: (0, 0)))
        XCTAssertGreaterThan(abs(ScanCleaner.lean(of: kept.image)), lean / 2, "the cut leans")
        let again = try XCTUnwrap(ScanCleaner.flattened(photo.image, quad: leaning, way: (0, nil)))
        XCTAssertEqual(again.turns, 0, "the quarter turns stay")
        XCTAssertGreaterThan(abs(again.skew), lean / 2, "its lean is measured again")
        XCTAssertLessThan(abs(ScanCleaner.lean(of: again.image)), lean / 4, "and taken away")
    }

    func testCleaningKeepsEveryNumberAndTheTextReadsTheSame() async throws {
        let photo = try photo()
        let prepared = try await cleaned()
        XCTAssertEqual(prepared.checked.textKept, true)
        XCTAssertEqual(prepared.checked.issues, [], "nothing wrong with a sharp photo")
        let read = prepared.checked.reading.map(\.string).joined(separator: " ")
        for amount in ScanSample.amounts { XCTAssertTrue(read.contains(amount), "\(amount) is read after cleaning") }
        // Grey print, as the labels and the address under the company are, still reads.
        for word in ["Rechnungsnr", "Kundennr", "Beispielweg"] {
            XCTAssertTrue(read.contains(word), "\(word), printed in grey, is read after cleaning")
        }
        Self.keep(photo.image, "photo", longest: 1600)
        // The photo whole, for Photos on the simulator, where the scan is made from it.
        Self.keep(photo.image, "photo-full", longest: 4032)
        Self.keep(prepared.straightened, "before")
        Self.keep(prepared.cleaned, "after-color")
        Self.note("color", prepared)
    }

    func testTheSameDetailsAreFoundOnTheCleanedPageAsOnThePrintedOne() async throws {
        let chosen = PrivateDetail.recommended
        let printed = Finder.analysis(in: try page, chosen, rules: [], intelligence: false).areas
        let prepared = try await cleaned()
        let found = Finder.analysis(in: prepared.cleaned, chosen, rules: [], intelligence: false).areas
        func counts(_ areas: [Finder.Area]) -> [String: Int] {
            Dictionary(grouping: areas, by: { $0.kind?.rawValue ?? "rule" }).mapValues(\.count)
        }
        let printedCounts = counts(printed), foundCounts = counts(found)
        XCTAssertFalse(printed.isEmpty, "the invoice has private details")
        for (kind, count) in printedCounts {
            XCTAssertGreaterThanOrEqual(foundCounts[kind] ?? 0, count, "\(kind): printed \(printedCounts), cleaned \(foundCounts)")
        }
        let printedList = printedCounts.sorted { $0.key < $1.key }, foundList = foundCounts.sorted { $0.key < $1.key }
        Self.write("detection.txt", "Printed page: \(printedList)\nCleaned photo: \(foundList)\n")
    }

    func testEachLookKeepsWhatItShould() async throws {
        let gray = try await cleaned(mode: .gray)
        XCTAssertEqual(gray.cleaned.colorSpace?.model, .monochrome)
        XCTAssertEqual(gray.checked.textKept, true)
        let black = try await cleaned(mode: .blackAndWhite)
        let bitmap = try XCTUnwrap(ScanCleaner.bitmap(black.cleaned))
        XCTAssertEqual(Set(bitmap.brightness), [0, 255])
        Self.keep(gray.cleaned, "after-gray")
        Self.keep(black.cleaned, "after-black-and-white")
        Self.note("gray", gray)
        Self.note("black-and-white", black)
    }

    func testColorKeepsTheLogosColor() async throws {
        let color = try await cleaned()
        let bitmap = try XCTUnwrap(ScanCleaner.bitmap(color.cleaned))
        // Inside the teal logo, left of its letter, on the page as printed.
        let x = 133 * bitmap.width / ScanSample.width, y = 164 * bitmap.height / ScanSample.height
        var sums = (red: 0, green: 0, blue: 0)
        for dy in -2...2 {
            for dx in -2...2 {
                let pixel = bitmap.color(x: x + dx, y: y + dy)
                sums.red += Int(pixel.red)
                sums.green += Int(pixel.green)
                sums.blue += Int(pixel.blue)
            }
        }
        let mean = (red: sums.red / 25, green: sums.green / 25, blue: sums.blue / 25)
        XCTAssertGreaterThan(mean.green - mean.red, 40, "the logo stays teal: \(mean)")
        XCTAssertGreaterThan(mean.blue - mean.red, 30, "the logo stays teal: \(mean)")
    }

    func testAResultPushedTooFarIsCaught() async throws {
        let prepared = try await cleaned()
        // The totals gone white, as too harsh a cleaning leaves faint print.
        var bitmap = try XCTUnwrap(ScanCleaner.bitmap(prepared.cleaned))
        let left = bitmap.width * 6 / 10, top = bitmap.height * 44 / 100, bottom = bitmap.height * 52 / 100
        for y in top..<bottom {
            for x in left..<bitmap.width {
                let i = (y * bitmap.width + x) * 4
                bitmap.pixels[i] = 255
                bitmap.pixels[i + 1] = 255
                bitmap.pixels[i + 2] = 255
            }
        }
        let whitened = try XCTUnwrap(ScanCleaner.image(bitmap, gray: false))
        let checked = await ScanCleaner.check(before: prepared.straightened, after: whitened, mode: .color, photo: nil)
        XCTAssertEqual(checked.textKept, false)
        let lost = try XCTUnwrap(checked.issues.first { $0.kind == .lessText }, "\(checked.issues)")
        let area = try XCTUnwrap(lost.area)
        // From 0 to 1 from the bottom left: where the totals were.
        XCTAssertTrue(area.intersects(CGRect(x: 0.6, y: 0.48, width: 0.4, height: 0.08)), "\(area)")
    }

    func testABlurredBottomAndAReflectionAreSaidForWhereTheyAre() async throws {
        let blurred = try photo(.blurredBottom)
        let soft = try await cleaned(.blurredBottom)
        let blur = try XCTUnwrap(soft.checked.issues.first { $0.kind == .blurred }, "\(soft.checked.issues)")
        XCTAssertEqual(blur.part, .bottom)
        let shiny = try photo(.glare)
        let lit = try await cleaned(.glare)
        let glare = try XCTUnwrap(lit.checked.issues.first { $0.kind == .glare }, "\(lit.checked.issues)")
        XCTAssertEqual(glare.part, .top)
        Self.keep(blurred.image, "photo-blurred-bottom", longest: 1600)
        Self.keep(blurred.image, "photo-blurred-full", longest: 4032)
        Self.keep(shiny.image, "photo-reflection", longest: 1600)
        Self.note("blurred bottom", soft)
        Self.note("reflection", lit)
    }

    func testThePDFHasItsCoversInItsPixelsAndNotInItsText() async throws {
        let prepared = try await cleaned()
        let covered = try XCTUnwrapAsync(await CoveredCopy.make(prepared.cleaned, PrivateDetail.recommended, rules: [],
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
        let across: CGFloat = iban.midX * CGFloat(bitmap.width)
        let down: CGFloat = (1 - iban.midY) * CGFloat(bitmap.height)
        let x = Int(across), y = Int(down)
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

    func testAPageDrawnInColorIsInGraysInAGrayPDF() throws {
        // A covered page is drawn in colour; at 300 to 600 dots an inch it is not drawn again in size.
        let width = 2600, height = 3677
        XCTAssertEqual(ScanGeometry.printScale(width: width, height: height), 1)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 300, y: 3000, width: 1400, height: 120))
        let covered = try XCTUnwrap(context.makeImage())
        let page = try XCTUnwrap(ScanCleaner.pdfPage(covered, mode: .gray, words: []))
        guard case .jpeg(let jpeg, _, _, let gray) = page.picture else { return XCTFail("a JPEG") }
        XCTAssertTrue(gray)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.colorSpace?.model, .monochrome, "one channel, as the PDF says")
        XCTAssertNotNil(Self.rendered(try XCTUnwrap(ScanPDF.make([page]))))
    }

    func testBlackAndWhiteMakesTheSmallestPDF() async throws {
        var sizes: [ScanColor: Int] = [:]
        for mode in ScanColor.allCases {
            let prepared = try await cleaned(mode: mode)
            let page = try XCTUnwrap(ScanCleaner.pdfPage(prepared.cleaned, mode: mode, words: []))
            let data = try XCTUnwrap(ScanPDF.make([page]))
            XCTAssertNotNil(Self.rendered(data), "\(mode) reads")
            sizes[mode] = data.count
        }
        XCTAssertLessThan(sizes[.blackAndWhite] ?? .max, sizes[.gray] ?? 0)
        XCTAssertLessThan(sizes[.gray] ?? .max, sizes[.color] ?? 0)
        let lines: [String] = sizes.map { size -> String in "\(size.key.rawValue): \(size.value / 1024) KB" }
        Self.write("pdf-sizes.txt", lines.sorted().joined(separator: "\n"))
    }

    func testPNGsSayNothingAboutThemselves() throws {
        let png = try XCTUnwrap(CoveredCopy.png(try page))
        let chunks = Self.chunks(of: png)
        XCTAssertEqual(chunks.first, "IHDR")
        XCTAssertEqual(chunks.last, "IEND")
        for chunk in ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"] { XCTAssertFalse(chunks.contains(chunk), "\(chunk) in \(chunks)") }
    }

    func testAPNGsNotesAreLeftOutAndItsPictureKept() {
        func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
            let shifts: [Int] = [24, 16, 8, 0]
            let length: [UInt8] = shifts.map { shift -> UInt8 in UInt8(truncatingIfNeeded: body.count >> shift) }
            var out = length
            out += Array(name.utf8)
            out += body
            out += [1, 2, 3, 4]
            return out
        }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let head = chunk("IHDR", [UInt8](repeating: 7, count: 13)), color = chunk("sRGB", [0])
        let picture = chunk("IDAT", [UInt8](repeating: 9, count: 300)), end = chunk("IEND", [])
        let notes: [[UInt8]] = [chunk("eXIf", Array("MM\0*".utf8)), chunk("tEXt", Array("Software\0Camera".utf8)),
                                chunk("tIME", [7, 234, 10, 21, 12, 0, 0])]
        var parts: [[UInt8]] = [signature, head, color]
        parts += notes
        parts += [picture, end]
        let png = Data(parts.joined())
        let plain = CoveredCopy.plain(png)
        XCTAssertEqual(plain, Data([signature, head, color, picture, end].joined()))
        XCTAssertEqual(Self.chunks(of: plain), ["IHDR", "sRGB", "IDAT", "IEND"])
        XCTAssertEqual(CoveredCopy.plain(Data([1, 2, 3])), Data([1, 2, 3]), "not a PNG: as it was")
        let cut = png.prefix(png.count - 3)
        XCTAssertEqual(CoveredCopy.plain(cut), cut, "cut short: as it was")
    }

    func testAPageAsTheCameraGivesItGoesThroughAsBefore() async throws {
        let page = try page
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(page, quad: nil, mode: .color))
        XCTAssertEqual(prepared.turns, 0)
        XCTAssertEqual(prepared.skew, 0)
        XCTAssertEqual(prepared.straightened.width, page.width)
        XCTAssertEqual(prepared.straightened.height, page.height)
        XCTAssertEqual(prepared.checked.textKept, true)
        let covered = try XCTUnwrapAsync(await CoveredCopy.make(prepared.cleaned, PrivateDetail.recommended, rules: [],
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
        let wide: CGFloat = box.width * 150 / 72, high: CGFloat = box.height * 150 / 72
        let width = Int(wide), height = Int(high)
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
            var length = 0
            for byte in bytes[i..<(i + 4)] {
                let value: Int = Int(byte)
                length = length << 8 | value
            }
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
        let width = prepared.straightened.width, height = prepared.straightened.height
        let dpi = Int(ScanGeometry.dpi(width: width, height: height))
        let degrees: Double = prepared.skew * 180 / Double.pi
        let skew = String(format: "%.2f", degrees)
        let kept: String = prepared.checked.textKept.map { kept -> String in kept ? "yes" : "no" } ?? "no text"
        let found: String = issues.isEmpty ? "none" : issues
        let parts = ["\(name): \(width)×\(height) px", "\(dpi) dpi on A4", "turns \(prepared.turns)", "skew \(skew)°",
                     "text kept: \(kept)", "lines read after: \(prepared.checked.reading.count)", "issues: \(found)"]
        let line = parts.joined(separator: ", ") + "\n"
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? Data((old + line).utf8).write(to: url)
    }
}

/// `XCTUnwrap` for a value an async call gave.
func XCTUnwrapAsync<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, message, file: file, line: line)
}
#endif
