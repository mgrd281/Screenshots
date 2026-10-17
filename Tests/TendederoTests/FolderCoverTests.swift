import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Cover a folder: copies land apart from what is watched, under the file's
/// name, with what was found covered, and only once a file is written.
final class FolderCoverTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheFoldersMustBeApart() {
        let downloads = URL(fileURLWithPath: "/Users/lena/Downloads", isDirectory: true)
        XCTAssertFalse(FolderCover.areApart(downloads, downloads))
        XCTAssertFalse(FolderCover.areApart(downloads, downloads.appendingPathComponent("Covered")))
        XCTAssertFalse(FolderCover.areApart(downloads.appendingPathComponent("Covered"), downloads))
        XCTAssertTrue(FolderCover.areApart(downloads, URL(fileURLWithPath: "/Users/lena/Documents", isDirectory: true)))
        // A name that only starts the same is another folder.
        XCTAssertTrue(FolderCover.areApart(downloads, URL(fileURLWithPath: "/Users/lena/Downloads Covered", isDirectory: true)))
    }

    func testAPictureIsCoveredUnderItsName() throws {
        let invoice = folder.appendingPathComponent("Invoice 1024.jpg")
        try write(drawn(["lena.hoffmann@example.com", "Total 74,00 €"]), to: invoice, type: .jpeg)
        let out = folder.appendingPathComponent("Covered", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let made = try XCTUnwrap(FolderCover.coverCopy(of: invoice, [.emails], into: out))
        XCTAssertEqual(made.url.lastPathComponent, "Invoice 1024.png")
        XCTAssertNotNil(made.report.kinds[.emails])
        XCTAssertNil(made.report.kinds[.amounts])
        // A second with the same name does not replace the first.
        let again = try XCTUnwrap(FolderCover.coverCopy(of: invoice, [.emails], into: out))
        XCTAssertEqual(again.url.lastPathComponent, "Invoice 1024 2.png")
    }

    func testAPDFIsCoveredAsAPDF() throws {
        let pdf = folder.appendingPathComponent("Rechnung.pdf")
        try makePDF(at: pdf, lines: ["lena.hoffmann@example.com", "Bestellung #1024"])
        let out = folder.appendingPathComponent("Covered", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let made = try XCTUnwrap(FolderCover.coverCopy(of: pdf, [.emails], into: out))
        XCTAssertEqual(made.url.lastPathComponent, "Rechnung.pdf")
        XCTAssertEqual(PDFDocument(url: made.url)?.pageCount, 1)
        XCTAssertNotNil(made.report.kinds[.emails])
    }

    func testNothingFoundStillMakesACopy() throws {
        let photo = folder.appendingPathComponent("Plain.png")
        try write(drawn(["Hello"]), to: photo, type: .png)
        let made = try XCTUnwrap(FolderCover.coverCopy(of: photo, [.emails], into: folder))
        XCTAssertTrue(made.report.isEmpty)
        XCTAssertEqual(made.url.lastPathComponent, "Plain 2.png")
    }

    func testAWrittenFileIsReady() throws {
        let file = folder.appendingPathComponent("Done.png")
        try write(drawn(["Done"]), to: file, type: .png)
        XCTAssertTrue(FolderCover.waitUntilWritten(file))
    }

    func testNamesStayShort() {
        XCTAssertEqual(FolderCover.names(["a.pdf"]), "a.pdf")
        XCTAssertEqual(FolderCover.names(["a", "b", "c"]), "a, b, c")
        XCTAssertEqual(FolderCover.names(["a", "b", "c", "d"]), "a, b, c …")
    }

    // MARK: Helpers

    /// Lines of large black text on white.
    private func drawn(_ lines: [String]) throws -> CGImage {
        let width = 1400, height = 120 * lines.count + 80
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 100 - 120 * i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// A one-page PDF of the lines, drawn as text.
    private func makePDF(at url: URL, lines: [String]) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 48, y: 760 - 48 * CGFloat(i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        context.endPDFPage()
        context.closePDF()
    }
}
