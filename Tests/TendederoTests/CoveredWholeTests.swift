import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// What leaves when a picture or a PDF could not be read or covered: all of
/// it in the covers' ink, made without reading what it shows, never the
/// original. And a picture with nothing to change is told apart from one
/// whose copy could not be made.
final class CoveredWholeTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAPictureIsInkedWholeAtItsSize() throws {
        let original = folder.appendingPathComponent("Screenshot 2026-10-17 at 17.41.47.png")
        try write(stripes(width: 120, height: 80), to: original, type: .png)
        let inked = Cover.inked(original)
        XCTAssertNotEqual(inked, original)
        let image = try picture(at: inked)
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 80)
        let pixels = try rgba(of: image)
        XCTAssertEqual(Set(pixels).count, 1, "one colour, nothing of the stripes")
        XCTAssertLessThan(pixels[0] & 0xFF, 60, "the covers' ink")
    }

    func testAPhotoStoredTurnedIsInkedTheWayItShows() throws {
        // Stored 60 × 40 and turned a quarter, as phones store photos: 40 × 60 upright.
        let original = folder.appendingPathComponent("IMG_1024.jpg")
        try write(stripes(width: 60, height: 40), to: original, type: .jpeg,
                  properties: [kCGImagePropertyOrientation: 6])
        let image = try picture(at: Cover.inked(original))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 60)
    }

    func testAVeryLargePictureIsInkedSmaller() throws {
        let original = folder.appendingPathComponent("Wide.png")
        try write(stripes(width: 8192, height: 100), to: original, type: .png)
        let image = try picture(at: Cover.inked(original))
        XCTAssertEqual(image.width, 4096)
        XCTAssertEqual(image.height, 50)
    }

    /// What cannot be read as a picture still leaves as ink, never as itself.
    func testWhatCannotBeReadIsInkedToo() throws {
        let broken = folder.appendingPathComponent("Broken.png")
        try Data("IBAN DE89 3704 0044 0532 0130 00".utf8).write(to: broken)
        XCTAssertNil(Cover.covering(broken, [.bank]), "no copy, and no nothing-to-cover either")
        let image = try picture(at: Cover.inked(broken))
        XCTAssertEqual(Set(try rgba(of: image)).count, 1)
    }

    /// Nothing to hide, draw or stamp gives the screenshot itself, which is
    /// no failure: it leaves as a fresh file.
    func testNothingToChangeIsNoFailure() throws {
        let original = folder.appendingPathComponent("Plain.png")
        try write(stripes(width: 32, height: 32), to: original, type: .png)
        let made = try XCTUnwrap(Cover.covering(original, []))
        XCTAssertEqual(made.url, original)
        XCTAssertTrue(made.report.isEmpty)
    }

    /// A PDF whose covering failed leaves as its pages in ink: as many, as
    /// large, and with none of its text.
    func testAPDFIsInkedPageByPageWithoutItsText() throws {
        let pdf = folder.appendingPathComponent("Kontoauszug.pdf")
        try makePDF(at: pdf, pages: [CGSize(width: 595, height: 842), CGSize(width: 612, height: 792)],
                    line: "IBAN DE89 3704 0044 0532 0130 00")
        XCTAssertFalse(DocumentCover.isClean(pdf), "the original holds its text")

        let inked = DocumentCover.inked(pdf)
        let document = try XCTUnwrap(PDFDocument(url: inked))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        XCTAssertTrue(DocumentCover.isClean(inked))

        let page = try XCTUnwrap(document.page(at: 0).flatMap(DocumentCover.render))
        let pixels = try rgba(of: page)
        let middle = pixels[(page.height / 2) * page.width + page.width / 2]
        XCTAssertLessThan(middle & 0xFF, 60, "the covers' ink")
        XCTAssertGreaterThan(Double(pixels.filter { $0 == middle }.count) / Double(pixels.count), 0.99)
    }

    /// One whose pages cannot be told goes as one page of A4 in ink.
    func testAPDFThatCannotBeReadIsOnePageOfInk() throws {
        let broken = folder.appendingPathComponent("Broken.pdf")
        try Data("Rechnung 1024".utf8).write(to: broken)
        let document = try XCTUnwrap(PDFDocument(url: DocumentCover.inked(broken)))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
    }

    // MARK: Helpers

    /// Stripes of light and dark grey, so a copy of the picture would show.
    private func stripes(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<width {
            context.setFillColor(CGColor(gray: x % 2 == 0 ? 0.9 : 0.4, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func picture(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Every pixel, drawn the same way for each picture, red in the lowest byte.
    private func rgba(of image: CGImage) throws -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: image.width * image.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
        return pixels
    }

    /// A PDF of these pages, each with the line as real text, which PDFKit
    /// reads back.
    private func makePDF(at url: URL, pages: [CGSize], line text: String) throws {
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: nil, nil))
        for size in pages {
            var box = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &box)
            let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)
                                                            as CFAttributedString)
            context.textPosition = CGPoint(x: 72, y: size.height - 100)
            CTLineDraw(line, context)
            context.endPage()
        }
        context.closePDF()
    }
}
