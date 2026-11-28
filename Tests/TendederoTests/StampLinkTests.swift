import AppKit
import PDFKit
import XCTest
@testable import Tendedero

/// The time stamp's address as a link: in the PDF saved beside the stamped
/// copy, in the PDF of a proof of time, and on the photo as it hangs.
final class StampLinkTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let english = Locale(identifier: "en_US")
    // October 16, 2026, 23:30 in UTC.
    private let taken = Date(timeIntervalSince1970: 1_792_193_400)
    private let address = "https://example.com/review/42"

    private func mark(page: String? = "https://example.com/review/42") -> TimeStamp.Mark {
        TimeStamp.mark(TimeStamp.Record(taken: taken, atomic: true, page: page, fingerprint: "ab12"),
                       text: "", locale: english, timeZone: utc, rightToLeft: false)
    }

    private func picture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func temporary(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("stamp-link-\(UUID().uuidString)").appendingPathExtension(ext)
    }

    /// Where each link of a PDF's page leads.
    private func links(on page: PDFPage) -> [(url: URL, bounds: CGRect)] {
        page.annotations.compactMap { annotation in
            (annotation.url ?? (annotation.action as? PDFActionURL)?.url).map { (url: $0, bounds: annotation.bounds) }
        }
    }

    // MARK: The stamped copy as a PDF

    func testATopLeftPlaceIsCountedFromTheFootOnAPage() {
        let rect = TimeStamp.pageRect(CGRect(x: 10, y: 20, width: 100, height: 30), height: 500)
        XCTAssertEqual(rect, CGRect(x: 10, y: 450, width: 100, height: 30))
    }

    func testTheStampedCopysPDFIsThePictureWithItsAddressALink() throws {
        let stamped = try XCTUnwrap(TimeStamp.stamped(try picture(width: 1600, height: 900), mark()))
        let link = try XCTUnwrap(stamped.links.first)
        let file = temporary("pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(TimeStamp.writePDF(stamped, title: "Screenshot with time stamp", subject: "words", to: file))

        let document = try XCTUnwrap(PDFDocument(url: file))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        // A point for each pixel.
        let box = page.bounds(for: .mediaBox)
        XCTAssertEqual(box.width, CGFloat(stamped.image.width), accuracy: 0.5)
        XCTAssertEqual(box.height, CGFloat(stamped.image.height), accuracy: 0.5)
        let found = links(on: page)
        XCTAssertEqual(found.map { $0.url }, [URL(string: address)!])
        // In the band at the top, where the address is drawn.
        let expected = TimeStamp.pageRect(link.rect, height: box.height)
        let bounds = try XCTUnwrap(found.first?.bounds)
        XCTAssertEqual(bounds.minX, expected.minX, accuracy: 1)
        XCTAssertEqual(bounds.minY, expected.minY, accuracy: 1)
        XCTAssertEqual(bounds.height, expected.height, accuracy: 1)
        XCTAssertGreaterThan(bounds.minY, CGFloat(900))
    }

    func testTheCopyTakesANameFreeAsAPictureAndAsAPDF() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(TimeStamp.freeName("Shot with time stamp", in: folder), "Shot with time stamp")
        try Data().write(to: folder.appendingPathComponent("Shot with time stamp.png"))
        XCTAssertEqual(TimeStamp.freeName("Shot with time stamp", in: folder), "Shot with time stamp 2")
        // A PDF alone takes the name too.
        try Data().write(to: folder.appendingPathComponent("Shot with time stamp 2.pdf"))
        XCTAssertEqual(TimeStamp.freeName("Shot with time stamp", in: folder), "Shot with time stamp 3")
    }

    // MARK: The proof of time as a PDF

    private func proof() -> TimeProof.Record {
        TimeProof.Record(fingerprint: "ab12", signed: taken, accuracy: 1, authority: "Sectigo (Europe) SL",
                         qualified: true, serial: "EA6B", response: Data([0x30, 0x00]), began: taken, atomic: true,
                         duration: 42)
    }

    func testTheTextPageIsTheParagraphs() {
        let paragraphs = TimeProof.paragraphs(proof(), file: "a.mov", locale: english, timeZone: utc)
        let page = TimeProof.page(proof(), file: "a.mov", locale: english, timeZone: utc)
        XCTAssertEqual(page, paragraphs.map(\.text).joined(separator: "\n") + "\n")
        XCTAssertEqual(paragraphs.first?.kind, .title)
        XCTAssertEqual(paragraphs.filter { $0.kind == .code }.map(\.text).first?.hasPrefix("openssl ts -reply"), true)
    }

    func testAMomentReadsAsAPlayerShowsIt() {
        XCTAssertEqual(TimeProof.moment(0), "0:00")
        XCTAssertEqual(TimeProof.moment(12.7), "0:12")
        XCTAssertEqual(TimeProof.moment(725), "12:05")
        XCTAssertEqual(TimeProof.moment(3723), "1:02:03")
        XCTAssertEqual(TimeProof.moment(-3), "0:00")
        XCTAssertEqual(TimeProof.moment(.nan), "0:00")
    }

    func testARecordingsPagesAreTheWebsitesFromWhenEachWasOpened() {
        let record = VideoStamp.Record(began: taken, atomic: true, pages: [
            VideoStamp.Page(at: 0, address: "https://a.example/one"),
            VideoStamp.Page(at: 5, address: nil),
            VideoStamp.Page(at: 9, address: "https://a.example/one"),
            VideoStamp.Page(at: 12, address: "https://b.example/two"),
            VideoStamp.Page(at: 12.5, address: "https://b.example/two"),
            VideoStamp.Page(at: 20, address: "file:///Users/me/secret.pdf"),
        ])
        XCTAssertEqual(TimeProof.pages(in: record), [
            TimeProof.Seen.Page(at: 0, address: "https://a.example/one"),
            TimeProof.Seen.Page(at: 9, address: "https://a.example/one"),
            TimeProof.Seen.Page(at: 12, address: "https://b.example/two"),
        ])
    }

    func testARecordingsPagesComeWithTheirMomentsAsLinks() {
        let seen = TimeProof.Seen(pages: [TimeProof.Seen.Page(at: 0, address: "https://a.example/one"),
                                          TimeProof.Seen.Page(at: 12, address: "https://b.example/two")])
        let blocks = TimeProof.blocks(TimeProof.paragraphs(proof(), file: "a.mov", locale: english, timeZone: utc),
                                      seen: seen, recording: true)
        let words = blocks.compactMap { block -> TimeProof.Paragraph? in
            if case .words(let paragraph) = block { return paragraph }
            return nil
        }
        let moments = words.filter { $0.kind == .strong }.map(\.text)
        XCTAssertEqual(moments, ["From 0:00", "From 0:12"])
        let links = words.filter { $0.kind == .link }
        XCTAssertEqual(links.map(\.url), [URL(string: "https://a.example/one"), URL(string: "https://b.example/two")])
        // The moment comes right before its address.
        let second = words.firstIndex { $0.text == "From 0:12" }
        XCTAssertEqual(second.map { words[$0 + 1].text }, "https://b.example/two")
    }

    func testAScreenshotsPageHasNoMoment() {
        let seen = TimeProof.Seen(pages: [TimeProof.Seen.Page(at: nil, address: address)], stamp: mark())
        let blocks = TimeProof.blocks(TimeProof.paragraphs(proof(), file: "a.png", locale: english, timeZone: utc),
                                      seen: seen, recording: false)
        let words = blocks.compactMap { block -> TimeProof.Paragraph? in
            if case .words(let paragraph) = block { return paragraph }
            return nil
        }
        XCTAssertFalse(words.contains { $0.kind == .strong })
        XCTAssertEqual(words.filter { $0.kind == .link }.map(\.url), [URL(string: address)])
    }

    func testTheProofsPDFHasThePagesAsLinksOnA4() throws {
        let long = "https://example.com/orders/" + String(repeating: "abcdefghij", count: 20)
        let seen = TimeProof.Seen(pages: [TimeProof.Seen.Page(at: 0, address: "https://a.example/one"),
                                          TimeProof.Seen.Page(at: 12, address: long)])
        let blocks = TimeProof.blocks(TimeProof.paragraphs(proof(), file: "a.mov", locale: english, timeZone: utc),
                                      seen: seen, recording: true)
        let file = temporary("pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(TimeProof.writePDF(blocks, title: "Proof of Time", rightToLeft: false, to: file))

        let document = try XCTUnwrap(PDFDocument(url: file))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, TimeProof.pageSize.width, accuracy: 0.5)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, TimeProof.pageSize.height, accuracy: 0.5)
        let found = (0..<document.pageCount).compactMap(document.page(at:)).flatMap(links(on:))
        XCTAssertTrue(found.contains { $0.url == URL(string: "https://a.example/one") })
        // A long address goes on over lines, each of them a link.
        XCTAssertGreaterThan(found.filter { $0.url == URL(string: long) }.count, 1)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Proof of Time"))
        XCTAssertTrue(text.contains("From 0:12"))
        XCTAssertTrue(text.contains("openssl ts -verify"))
    }

    func testALongProofGoesOnOverMorePages() throws {
        let paragraph = TimeProof.Paragraph(text: String(repeating: "A line of the page that explains the proof. ", count: 12),
                                            kind: .text)
        let blocks = Array(repeating: TimeProof.Block.words(paragraph), count: 40)
        let placed = TimeProof.layOut(blocks, rightToLeft: false)
        let pages = (placed.map(\.page).max() ?? 0) + 1
        XCTAssertGreaterThan(pages, 1)
        // Nothing is set below the margin or above the page.
        for item in placed {
            XCTAssertGreaterThanOrEqual(item.rect.minY, 0)
            XCTAssertLessThanOrEqual(item.rect.maxY, TimeProof.pageSize.height)
        }
        let file = temporary("pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(TimeProof.writePDF(blocks, title: "Proof of Time", rightToLeft: false, to: file))
        XCTAssertEqual(PDFDocument(url: file)?.pageCount, pages)
    }

    func testTheStampedPictureKeepsItsLinkOnThePage() throws {
        let stamped = try XCTUnwrap(TimeStamp.stamped(try picture(width: 2000, height: 1200), mark()))
        let blocks: [TimeProof.Block] = [.picture(stamped.image, links: stamped.links,
                                                  largest: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))]
        let placed = TimeProof.layOut(blocks, rightToLeft: false)
        let item = try XCTUnwrap(placed.first)
        // As wide as the page's room, never wider.
        XCTAssertLessThanOrEqual(item.rect.width, TimeProof.pageSize.width)
        let link = try XCTUnwrap(item.links.first)
        XCTAssertEqual(link.url, URL(string: address))
        // In the band, at the picture's top.
        XCTAssertTrue(item.rect.contains(CGPoint(x: link.rect.midX, y: link.rect.midY)))
        XCTAssertGreaterThan(link.rect.minY, item.rect.midY)
    }

    // MARK: On the line

    func testTheBandsLinkIsAStripAcrossItsTop() throws {
        let band = try XCTUnwrap(TimeStamp.band(mark(), width: 1600))
        let link = try XCTUnwrap(band.links.first)
        let links = try XCTUnwrap(BandLinks.screenshot(mark(), width: 1600, height: 1000, backdrop: nil))
        let tall = CGFloat(1000 + band.image.height)
        XCTAssertEqual(links.band.minY, 0)
        XCTAssertEqual(links.band.height, CGFloat(band.image.height) / tall, accuracy: 0.0001)
        let strip = try XCTUnwrap(links.strips.first)
        XCTAssertEqual(links.strips.count, 1)
        XCTAssertEqual(strip.url, URL(string: address))
        // Across the band, at the address's lines.
        XCTAssertEqual(strip.rect.minX, 0)
        XCTAssertEqual(strip.rect.width, 1, accuracy: 0.0001)
        XCTAssertEqual(strip.rect.minY, link.rect.minY / tall, accuracy: 0.0001)
        XCTAssertEqual(strip.rect.height, link.rect.height / tall, accuracy: 0.0001)
        // The photo shows it with its band, not as it was before.
        XCTAssertTrue(links.fits(CGSize(width: 320, height: (320 * tall / 1600).rounded())))
        XCTAssertFalse(links.fits(CGSize(width: 320, height: 200)))
    }

    func testALongAddressIsOneStripOverItsLines() throws {
        let long = "https://example.com/orders/" + String(repeating: "abcdefghij", count: 30)
        let band = try XCTUnwrap(TimeStamp.band(mark(page: long), width: 1200))
        XCTAssertGreaterThan(band.links.count, 1)
        let links = try XCTUnwrap(BandLinks.screenshot(mark(page: long), width: 1200, height: 800, backdrop: nil))
        let strip = try XCTUnwrap(links.strips.first)
        XCTAssertEqual(links.strips.count, 1)
        let tall = CGFloat(800 + band.image.height)
        let top = band.links.map(\.rect.minY).min() ?? 0, bottom = band.links.map(\.rect.maxY).max() ?? 0
        XCTAssertEqual(strip.rect.minY, top / tall, accuracy: 0.0001)
        XCTAssertEqual(strip.rect.maxY, bottom / tall, accuracy: 0.0001)
    }

    func testOnABackdropTheBandIsWhereThePictureIs() throws {
        let backdrop = Backdrop(padding: 0.1, shadow: false)
        let band = try XCTUnwrap(TimeStamp.band(mark(), width: 1600))
        let layout = backdrop.layout(width: 1600, height: 1000 + band.image.height)
        let links = try XCTUnwrap(BandLinks.screenshot(mark(), width: 1600, height: 1000, backdrop: backdrop))
        let canvas = layout.canvas
        XCTAssertEqual(links.band.minX, layout.picture.minX / canvas.width, accuracy: 0.0001)
        XCTAssertEqual(links.band.minY, (canvas.height - layout.picture.maxY) / canvas.height, accuracy: 0.0001)
        XCTAssertEqual(links.aspect, canvas.width / canvas.height, accuracy: 0.0001)
        let strip = try XCTUnwrap(links.strips.first)
        XCTAssertGreaterThan(strip.rect.minY, links.band.minY)
        XCTAssertLessThan(strip.rect.maxY, links.band.maxY)
    }

    func testNoPageNoLinks() {
        XCTAssertNil(BandLinks.screenshot(mark(page: nil), width: 1600, height: 1000, backdrop: nil))
        XCTAssertNil(BandLinks.make([], band: CGRect(x: 0, y: 0, width: 10, height: 10), canvas: CGSize(width: 10, height: 20)))
    }

    func testASmallBandStillHasALinkToClick() throws {
        let links = try XCTUnwrap(BandLinks.screenshot(mark(), width: 3024, height: 1964, backdrop: nil))
        let photo = CGSize(width: 136, height: 136 / links.aspect)
        let band = CGRect(x: 0, y: links.band.minY * photo.height, width: photo.width, height: links.band.height * photo.height)
        let strip = try XCTUnwrap(links.places(on: photo, least: 6).first)
        // At least the least height, where the band has it, and on the band.
        XCTAssertEqual(strip.rect.height, min(6, band.height), accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(strip.rect.minY, band.minY - 0.001)
        XCTAssertLessThanOrEqual(strip.rect.maxY, band.maxY + 0.001)
        XCTAssertEqual(strip.rect.width, photo.width, accuracy: 0.001)
        // Large enough already, a strip stays as it is.
        let large = try XCTUnwrap(links.places(on: CGSize(width: 3024, height: 3024 / links.aspect), least: 6).first)
        XCTAssertEqual(large.rect.height, (links.strips.first?.rect.height ?? 0) * 3024 / links.aspect, accuracy: 0.01)
    }
}
