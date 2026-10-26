#if DEBUG && canImport(PDFKit) && canImport(Vision) && canImport(CryptoKit)
import CoreGraphics
import CryptoKit
import Foundation
import PDFKit
import XCTest
@testable import Tendedero

/// PDFs and photos put together on this Mac as on an iPhone, from made-up
/// files (`PDFFixtures`): the words a PDF holds read straight from it where
/// they are on the page, turned with it; a locked PDF opened only with its
/// password, which is never kept; a signed one known as signed; 300 pages
/// drawn small quickly enough to scroll; the original file never changed;
/// and the PDF made of them with every page in its order and shape, the
/// covers found from the text. With PDF_CAPTURES set to a folder, it keeps
/// the numbers.
final class PDFFixtureTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-fixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ data: Data, _ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func source(_ data: Data, _ name: String = "Rechnung.pdf") throws -> PDFSource {
        try XCTUnwrap(PDFSource(url: try file(data, name)))
    }

    private static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// Where the page is dark, as a share of a part of it from 0 to 1 from the bottom left.
    private static func ink(_ image: CGImage, in part: CGRect) -> Double {
        guard let bitmap = ScanCleaner.bitmap(image) else { return 0 }
        // Made once: each reading of it makes the whole plane again.
        let brightness = bitmap.brightness
        let x0 = Int(part.minX * CGFloat(bitmap.width)), x1 = Int(part.maxX * CGFloat(bitmap.width))
        let y0 = Int((1 - part.maxY) * CGFloat(bitmap.height)), y1 = Int((1 - part.minY) * CGFloat(bitmap.height))
        var dark = 0, all = 0
        for y in max(0, y0)..<min(bitmap.height, y1) {
            for x in max(0, x0)..<min(bitmap.width, x1) {
                all += 1
                if brightness[y * bitmap.width + x] < 128 { dark += 1 }
            }
        }
        return all == 0 ? 0 : Double(dark) / Double(all)
    }

    private func keep(_ name: String, _ text: String) {
        guard let path = ProcessInfo.processInfo.environment["PDF_CAPTURES"] else { return }
        try? text.write(to: URL(fileURLWithPath: path).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testTheWordsAreReadFromTheTextWhereTheyAre() throws {
        let invoice = try source(PDFFixtures.invoice())
        XCTAssertEqual(invoice.pageCount, 3)
        XCTAssertFalse(invoice.isLocked)
        XCTAssertFalse(invoice.isSigned)
        let lines = try XCTUnwrap(invoice.lines(0, turns: 0))
        let customer = try XCTUnwrap(lines.first { $0.string.contains(PDFFixtures.customer) })
        // 56 points from the left, 150 down an A4 page.
        XCTAssertEqual(customer.box.minX, 56 / 595.28, accuracy: 0.01)
        XCTAssertEqual(customer.box.maxY, 1 - 150 / 841.89, accuracy: 0.015)
        XCTAssertTrue(lines.contains { $0.string.contains(PDFFixtures.iban) }, "the IBAN as written")
        let words = customer.words.compactMap { Range($0.range, in: customer.string).map { String(customer.string[$0]) } }
        XCTAssertEqual(words, ["Erika", "Mustermann"])
        // Every word where it stands, after the line breaks PDFKit's text adds and the ligature in
        // "Musterfirma": the name one row high, the invoice's number beside it where it starts, the last word in.
        XCTAssertLessThan(customer.box.height, 0.02, "one row: \(customer.box)")
        let number = try XCTUnwrap(lines.first { $0.string.hasPrefix("Rechnungsnr.") })
        XCTAssertEqual(number.box.minX, 360 / 595.28, accuracy: 0.01)
        XCTAssertLessThan(number.box.height, 0.02, "one row: \(number.box)")
        XCTAssertTrue(lines.contains { $0.string.hasSuffix("BIC COBADEFFXXX") }, lines.map(\.string).joined(separator: "\n"))
        // Turned a quarter clockwise, the line stands at the top right.
        let turned = try XCTUnwrap(invoice.lines(0, turns: 1)?.first { $0.string.contains(PDFFixtures.customer) })
        XCTAssertGreaterThan(turned.box.minX, 0.7)
        XCTAssertGreaterThan(turned.box.height, turned.box.width)
    }

    func testALockedPDFOpensOnlyWithItsPassword() throws {
        let locked = try source(PDFFixtures.locked())
        XCTAssertTrue(locked.isLocked)
        XCTAssertNil(locked.render(0, turns: 0, dpi: 72, longest: 600))
        XCTAssertNil(locked.lines(0, turns: 0))
        XCTAssertFalse(locked.unlock("falsch"))
        XCTAssertTrue(locked.isLocked)
        XCTAssertTrue(locked.unlock(PDFFixtures.password))
        XCTAssertFalse(locked.isLocked)
        XCTAssertNotNil(locked.render(0, turns: 0, dpi: 72, longest: 600))
        XCTAssertTrue(try XCTUnwrap(locked.lines(1, turns: 0)).contains { $0.string.contains(PDFFixtures.customer) })
        // Opened again from its file, it asks again: nothing of the password was kept.
        XCTAssertTrue(try XCTUnwrap(PDFSource(url: locked.url)).isLocked)
    }

    func testASignedPDFIsKnownAsSigned() throws {
        let signed = try source(PDFFixtures.signed(), "Vertrag.pdf")
        XCTAssertTrue(signed.isSigned)
        XCTAssertEqual(signed.pageCount, 1)
        XCTAssertTrue(try XCTUnwrap(signed.lines(0, turns: 0)).contains { $0.string.contains("Mietvertrag") })
    }

    func testTurnedPagesAreDrawnTurned() throws {
        let invoice = try source(PDFFixtures.invoice())
        let upright = try XCTUnwrap(invoice.render(0, turns: 0, dpi: 72, longest: 4000))
        XCTAssertEqual(upright.width, 595)
        XCTAssertEqual(upright.height, 842)
        let turned = try XCTUnwrap(invoice.render(0, turns: 1, dpi: 144, longest: 4000))
        XCTAssertEqual(turned.width, 1684)
        XCTAssertEqual(turned.height, 1191)
        XCTAssertEqual(try XCTUnwrap(invoice.size(of: 0, turns: 3)).width, 841.89, accuracy: 0.01)
        // The company's name, top left upright, is at the top right once turned.
        let corner = CGRect(x: 0.05, y: 0.88, width: 0.4, height: 0.1)
        XCTAssertGreaterThan(Self.ink(upright, in: corner), 0.02)
        XCTAssertGreaterThan(Self.ink(turned, in: PDFPageGeometry.turned(corner, quarters: 1)), 0.02)
        XCTAssertLessThan(Self.ink(turned, in: corner), 0.005)
        // A picture turns the same way.
        let receipt = try XCTUnwrap(PDFFixtures.receipt())
        let lying = try XCTUnwrap(PictureTools.turned(receipt, quarters: 1))
        XCTAssertEqual(lying.width, receipt.height)
        XCTAssertEqual(lying.height, receipt.width)
    }

    func testThreeHundredPagesAreDrawnSmallQuickly() throws {
        let long = try source(PDFFixtures.long(), "Protokoll.pdf")
        XCTAssertEqual(long.pageCount, 300)
        var times: [Double] = []
        for index in 0..<long.pageCount {
            let start = Date()
            let thumbnail = try XCTUnwrap(long.render(index, turns: 0, dpi: 72, longest: 360))
            times.append(Date().timeIntervalSince(start))
            XCTAssertEqual(max(thumbnail.width, thumbnail.height), 360)
        }
        let sorted = times.sorted()
        let average = times.reduce(0, +) / Double(times.count)
        let worst = sorted.last ?? 0, p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let numbers = String(format: "300 pages drawn small (360 px): average %.1f ms, 95th percentile %.1f ms, slowest %.1f ms",
                             average * 1000, p95 * 1000, worst * 1000)
        print(numbers)
        // Reordering 300 pages, one page at a time from the end to the front.
        var project = PDFProject(name: "Protokoll")
        let file = ProjectFile(kind: .pdf, name: "Protokoll.pdf", stored: "a.pdf", pageCount: 300, digest: "")
        project.files = [file]
        project.insert(file.pages(origin: .file))
        var history = ProjectHistory()
        let start = Date()
        for _ in 0..<300 {
            history.record(project.pages)
            project.move(from: project.pages.count - 1, to: 0)
        }
        let moving = Date().timeIntervalSince(start)
        XCTAssertEqual(project.pages.map(\.source), file.pages(origin: .file).map(\.source), "round once, as it was")
        let reorder = String(format: "300 moves with undo kept: %.1f ms in all", moving * 1000)
        print(reorder)
        keep("pdf-300-pages.txt", numbers + "\n" + reorder + "\n")
        XCTAssertLessThan(average, 0.25, "drawn small fast enough to scroll")
        XCTAssertTrue(try XCTUnwrap(long.lines(299, turns: 0)).contains { $0.string.contains("Seite 300 von 300") })
    }

    func testTheOriginalNeverChanges() throws {
        let url = try file(PDFFixtures.invoice(), "Rechnung.pdf")
        let before = try Self.digest(url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let invoice = try XCTUnwrap(PDFSource(url: url))
        for index in 0..<invoice.pageCount {
            _ = invoice.render(index, turns: index, dpi: 150, longest: 3000)
            _ = invoice.lines(index, turns: index)
        }
        let kept = (0..<invoice.pageCount).compactMap { invoice.copy($0, turns: 1).map(PDFComposer.Either.kept) }
        XCTAssertNotNil(PDFComposer.make(kept))
        XCTAssertEqual(try Self.digest(url), before, "the file is as it came")
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
    }

    func testThePDFKeepsEveryPageInItsOrderAndShape() throws {
        let invoice = try source(PDFFixtures.invoice())
        let receipt = try XCTUnwrap(PDFFixtures.receipt())
        let sideways = try XCTUnwrap(PDFFixtures.sideways())
        // The receipt on A4, never stretched; the sideways page on a page its own shape.
        let onA4 = try XCTUnwrap(PDFComposer.page(receipt, ownPage: nil, paper: .a4, quality: .medium, words: []))
        let frame = try XCTUnwrap(onA4.frame)
        XCTAssertEqual(frame.page, PaperSize.a4Size)
        XCTAssertEqual(Double(frame.picture.width / frame.picture.height), Double(receipt.width) / Double(receipt.height),
                       accuracy: 0.001)
        let own = try XCTUnwrap(PDFComposer.page(sideways, ownPage: nil, paper: .original, quality: .small, words: []))
        XCTAssertEqual(try XCTUnwrap(own.frame).page.width, 841.89, accuracy: 0.01)
        // Never more pixels than the receipt has.
        if case .jpeg(_, let width, let height, _) = onA4.picture {
            XCTAssertLessThanOrEqual(width, receipt.width)
            XCTAssertLessThanOrEqual(height, receipt.height)
        } else {
            XCTFail("a JPEG")
        }
        // The invoice's first page kept, the receipt, the sideways page, an
        // empty Letter page, and the invoice's last page turned.
        let pages: [PDFComposer.Either] = [
            .kept(try XCTUnwrap(invoice.copy(0, turns: 0))), .made(onA4), .made(own),
            .made(PDFComposer.blank(PaperSize.letterSize)), .kept(try XCTUnwrap(invoice.copy(2, turns: 1))),
        ]
        let made = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(PDFComposer.make(pages))))
        XCTAssertEqual(made.pageCount, 5)
        func shown(_ index: Int) -> CGSize {
            guard let page = made.page(at: index) else { return .zero }
            return PDFPageGeometry.shown(page.bounds(for: .mediaBox), rotation: page.rotation)
        }
        XCTAssertEqual(shown(0).width, 595.28, accuracy: 0.5)
        XCTAssertEqual(shown(1).height, 841.89, accuracy: 0.5)
        XCTAssertEqual(shown(2).width, 841.89, accuracy: 0.5)
        XCTAssertEqual(shown(3).width, 612, accuracy: 0.5)
        XCTAssertEqual(shown(4).width, 841.89, accuracy: 0.5, "turned a quarter")
        // A kept page keeps its own text.
        XCTAssertTrue(made.page(at: 0)?.string?.contains(PDFFixtures.iban) == true)
        // Pictures only: written by Snapfly alone, each page its own size.
        let drawn = try XCTUnwrap(PDFComposer.make([.made(onA4), .made(own)]))
        let pictures = try XCTUnwrap(PDFDocument(data: drawn))
        XCTAssertEqual(pictures.pageCount, 2)
        XCTAssertEqual(pictures.page(at: 1)?.bounds(for: .mediaBox).width ?? 0, 841.89, accuracy: 0.5)
        XCTAssertNil(drawn.range(of: Data("Mustermann".utf8)), "no word of the picture as text")
    }

    func testCoversAreFoundFromThePDFsText() async throws {
        let invoice = try source(PDFFixtures.invoice())
        let page = try XCTUnwrap(invoice.render(0, turns: 0, dpi: 200, longest: 2400))
        let lines = try XCTUnwrap(invoice.lines(0, turns: 0))
        Finder.remember(lines, for: page)
        let made = try XCTUnwrapAsync(await CoveredCopy.make(page, Set(PrivateDetail.allCases), rules: [], style: .ink,
                                                             intelligence: false))
        XCTAssertFalse(made.report.places.isEmpty)
        // Read again as anyone could read the covered page: the IBAN and the name are gone.
        let read = (Finder.lines(in: made.image) ?? []).map(\.string).joined(separator: "\n")
        XCTAssertFalse(read.contains("0532"), read)
        XCTAssertFalse(read.contains("Mustermann"), read)
        // And the PDF's page with its words read from the covered page, none from under a cover.
        let words = ScanCleaner.words(in: Finder.lines(in: made.image) ?? [], hiding: made.report.places,
                                      aspect: ScanCleaner.aspect(of: made.image))
        let covered = try XCTUnwrap(PDFComposer.page(made.image, ownPage: try XCTUnwrap(invoice.size(of: 0, turns: 0)),
                                                     paper: .original, quality: .high, words: words))
        let file = try XCTUnwrap(ScanPDF.make([covered]))
        let text = PDFDocument(data: file)?.string ?? ""
        XCTAssertFalse(text.contains("Mustermann"))
        XCTAssertFalse(text.contains("0532"))
        keep("pdf-covered-text.txt", text)
    }

    /// The invoice's first page covered as the iPhone covers a PDF's page
    /// (`ProjectStore.prepareReading`): its words from the file, and what
    /// the picture shows that the file does not hold. The name, the address
    /// under it and the IBAN are covered, each word whole; the invoice's
    /// number and date beside the address, on the same rows, are not, nor
    /// their labels; and the covered PDF holds the words left uncovered.
    /// Where each letter of the file's text is, what was read and where each
    /// cover lies are kept for review (`pdf-covers.txt`).
    func testTheNumberAndDateBesideTheAddressStayUncovered() async throws {
        let invoice = try source(PDFFixtures.invoice())
        let page = try XCTUnwrap(invoice.render(0, turns: 0, dpi: 200, longest: 2400))
        let layer = try XCTUnwrap(invoice.lines(0, turns: 0))
        let read = Finder.lines(in: page) ?? []
        let extra = PDFTextLayer.added(read: read.map(\.box), over: layer.map(\.box)).map { read[$0] }
        Finder.remember(layer + extra, for: page)
        let made = try XCTUnwrapAsync(await CoveredCopy.make(page, PrivateDetail.recommended, rules: [], style: .ink,
                                                             intelligence: false))
        let places = made.report.places
        let again = Finder.lines(in: made.image) ?? []
        let words = ScanCleaner.words(in: again, hiding: places, aspect: ScanCleaner.aspect(of: made.image))
        let covered = try XCTUnwrap(PDFComposer.page(made.image, ownPage: try XCTUnwrap(invoice.size(of: 0, turns: 0)),
                                                     paper: .original, quality: .high, words: words))
        let text = PDFDocument(data: try XCTUnwrap(ScanPDF.make([covered])))?.string ?? ""
        func shown(_ rect: CGRect) -> String {
            String(format: "x %.3f to %.3f, y %.3f to %.3f", rect.minX, rect.maxX, rect.minY, rect.maxY)
        }
        func wordsShown(_ line: Finder.TextLine) -> String {
            line.words.compactMap { word in
                Range(word.range, in: line.string).map { "\(line.string[$0]) (\(shown(word.box)))" }
            }.joined(separator: ", ")
        }
        // Each letter of the page's text, the character PDFKit counts it as and where that is, in points.
        let file = try XCTUnwrap(PDFDocument(data: PDFFixtures.invoice())?.page(at: 0))
        let letters = (file.string ?? "") as NSString
        let pieces = (0..<file.numberOfCharacters).map { file.selection(for: NSRange(location: $0, length: 1)) }
        let characters = PDFTextLayer.characters(of: letters as String, count: pieces.count) { pieces[$0]?.string }
        let placed = (0..<letters.length).map { unit -> String in
            let letter = letters.substring(with: NSRange(location: unit, length: 1))
            guard let character = characters[unit], let place = pieces[character]?.bounds(for: file) else {
                return "\(unit) \(letter.debugDescription) none"
            }
            return "\(unit) \(letter.debugDescription) \(character) "
                + String(format: "x %.1f y %.1f w %.1f h %.1f", place.minX, place.minY, place.width, place.height)
        }
        let first = placed.prefix(140).joined(separator: "\n")
        var lines = ["PDFKit counts \(file.numberOfCharacters) characters, the text holds \(letters.length) units.", first,
                     "From the file, line by line:"]
        lines += layer.map { "\($0.string) | \(shown($0.box)) | \(wordsShown($0))" }
        lines.append("Read from the picture besides:")
        lines += extra.map { "\($0.string) | \(shown($0.box))" }
        lines.append("Covered:")
        lines += places.map(shown)
        lines.append("Read from the covered picture:")
        lines += again.map { "\($0.string) | \(shown($0.box))" }
        lines += ["The covered PDF's text:", text]
        let report = lines.joined(separator: "\n")
        keep("pdf-covers.txt", ([report, "Each letter of the file's text:"] + placed).joined(separator: "\n"))
        print("PDF-COVERS\n\(report)\nPDF-COVERS-END")
        // Covered: the customer's name and address, and the IBAN.
        for wanted in [PDFFixtures.customer, PDFFixtures.street, PDFFixtures.town, "DE89"] {
            let line = try XCTUnwrap(layer.first { $0.string.contains(wanted) }, "\(wanted) in the file's text")
            XCTAssertTrue(places.contains { $0.intersects(line.box) }, "\(wanted) is covered")
        }
        // Not covered: the number and the date beside the address, word by word.
        let beside = ["Rechnungsnr.", "RE-2026-0412", "Datum", "21.10.2026"]
        let found = layer.flatMap { line in
            line.words.compactMap { word -> (text: String, box: CGRect)? in
                guard let range = Range(word.range, in: line.string), beside.contains(String(line.string[range]))
                else { return nil }
                return (String(line.string[range]), word.box)
            }
        }
        XCTAssertEqual(found.map { $0.text }.sorted(), beside.sorted())
        for word in found {
            XCTAssertFalse(places.contains { $0.intersects(word.box) }, "\(word.text) is not covered")
        }
        // The covered PDF's text: what is left, and nothing from under a cover.
        for left in ["Musterfirma", "Rechnung", "Einrichtung", "380,68", "RE-2026-0412", "21.10.2026"] {
            XCTAssertTrue(text.contains(left), "\(left) in the covered PDF's text")
        }
        for hidden in ["Mustermann", "0532"] {
            XCTAssertFalse(text.contains(hidden), "\(hidden) is not in the covered PDF's text")
        }
    }

    /// The invoice's first page read by Vision and put in reading order
    /// (`ScanReading`): the shop, the customer's address line by line, the
    /// invoice's number and date beside it after it, then the items row by
    /// row, each with its price, and the total; covered, the customer is a
    /// mark where the name was, and never the name.
    func testTheInvoiceReadsInOrderRowByRow() async throws {
        let invoice = try source(PDFFixtures.invoice())
        let page = try XCTUnwrap(invoice.render(0, turns: 0, dpi: 200, longest: 2400))
        let lines = try XCTUnwrap(Finder.lines(in: page))
        let text = ScanReading.text(ScanCleaner.page(lines, aspect: ScanCleaner.aspect(of: page)))
        keep("reading-invoice.txt", text)
        print("READING\n\(text)")
        let order = ["Musterfirma GmbH", PDFFixtures.customer, "Musterstraße 12", "20095 Hamburg", "Rechnung", "Beratung",
                     "Einrichtung", "Lizenz", "Gesamt", "Bitte bis"]
        var from = text.startIndex
        for words in order {
            let found = try XCTUnwrap(text.range(of: words, range: from..<text.endIndex), "\(words) after what came before: \(text)")
            from = found.upperBound
        }
        let rows = text.split(separator: "\n")
        for (item, price) in [("Beratung", "180,00"), ("Einrichtung", "90,00"), ("Lizenz", "49,90")] {
            XCTAssertTrue(rows.contains { $0.contains(item) && $0.contains(price) }, "\(item) and its price on one line: \(text)")
        }
        // Covered: a mark where the name was.
        let name = try XCTUnwrap(lines.first { $0.string.contains(PDFFixtures.customer) }).box
        let covered = ScanReading.text(ScanCleaner.page(lines, hiding: [name], aspect: ScanCleaner.aspect(of: page)))
        XCTAssertFalse(covered.contains("Mustermann"), covered)
        XCTAssertTrue(covered.contains("\(ScanReading.mark)\nMusterstraße 12"), covered)
    }
}
#endif
