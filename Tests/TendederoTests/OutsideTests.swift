import AppKit
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Photos and PDFs brought in from anywhere on the Mac: what can hang, how a
/// PDF's pages are measured, covered and kept, and what a photo leaves
/// behind when it leaves the line.
final class OutsideTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testWhatCanHang() {
        XCTAssertTrue(Outside.accepts(URL(fileURLWithPath: "/tmp/Rechnung.pdf")))
        XCTAssertTrue(Outside.accepts(URL(fileURLWithPath: "/tmp/IMG_1234.HEIC")))
        XCTAssertTrue(Outside.accepts(URL(fileURLWithPath: "/tmp/Photo.JPG")))
        XCTAssertTrue(Outside.accepts(URL(fileURLWithPath: "/tmp/Scan.png")))
        XCTAssertFalse(Outside.accepts(URL(fileURLWithPath: "/tmp/Vertrag.docx")))
        XCTAssertFalse(Outside.accepts(URL(fileURLWithPath: "/tmp/Clip.mov")))
        XCTAssertFalse(Outside.accepts(URL(fileURLWithPath: "/tmp/Notes.txt")))
        XCTAssertFalse(Outside.accepts(URL(fileURLWithPath: "/tmp/Folder", isDirectory: true)))
    }

    func testFilesAreSortedOnce() throws {
        let pdf = folder.appendingPathComponent("Order.pdf")
        try makePDF(at: pdf)
        let sorted = Outside.sort([pdf, pdf, URL(fileURLWithPath: "/tmp/Vertrag.docx")])
        XCTAssertEqual(sorted.accepted, [pdf])
        XCTAssertEqual(sorted.refused.count, 1)
    }

    func testALockedPDFIsKeptOut() throws {
        let open = folder.appendingPathComponent("Open.pdf")
        try makePDF(at: open)
        let locked = folder.appendingPathComponent("Locked.pdf")
        let document = try XCTUnwrap(PDFDocument(url: open))
        XCTAssertTrue(document.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        XCTAssertTrue(DocumentCover.isLocked(locked))
        XCTAssertFalse(DocumentCover.isLocked(open))
        XCTAssertEqual(Outside.sort([locked]).locked, [locked])
    }

    /// A page turned a quarter is as tall as it was wide, and so is its copy.
    func testATurnedPageKeepsItsShape() throws {
        let flat = folder.appendingPathComponent("Flat.pdf")
        try makePDF(at: flat, size: CGSize(width: 300, height: 200))
        let document = try XCTUnwrap(PDFDocument(url: flat))
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = 90
        let turned = folder.appendingPathComponent("Turned.pdf")
        XCTAssertTrue(document.write(to: turned))
        let reread = try XCTUnwrap(PDFDocument(url: turned))
        let read = try XCTUnwrap(reread.page(at: 0))
        XCTAssertEqual(DocumentCover.pageSize(of: read), CGSize(width: 200, height: 300))

        let copy = try XCTUnwrap(DocumentCover.copy(of: turned, [], hand: [:]))
        let copied = try XCTUnwrap(PDFDocument(url: copy))
        XCTAssertEqual(copied.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 200, height: 300))
    }

    /// A page is drawn as it shows: upright, and turned when it is turned.
    /// PDF pages turn clockwise, so a turned page's top left corner shows at
    /// the top right.
    func testAPageIsDrawnAsItShows() throws {
        let pdf = folder.appendingPathComponent("Corner.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 140, width: 60, height: 60))
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(url: pdf))
        let page = try XCTUnwrap(document.page(at: 0))

        let upright = try XCTUnwrap(DocumentCover.render(page))
        XCTAssertGreaterThan(upright.width, upright.height)
        XCTAssertLessThan(lightness(of: upright, x: 0.1, y: 0.15), 0.2)
        XCTAssertGreaterThan(lightness(of: upright, x: 0.9, y: 0.15), 0.8)
        XCTAssertGreaterThan(lightness(of: upright, x: 0.1, y: 0.85), 0.8)

        page.rotation = 90
        let turned = try XCTUnwrap(DocumentCover.render(page))
        XCTAssertGreaterThan(turned.height, turned.width)
        XCTAssertLessThan(lightness(of: turned, x: 0.85, y: 0.1), 0.2)
        XCTAssertGreaterThan(lightness(of: turned, x: 0.15, y: 0.1), 0.8)
        XCTAssertGreaterThan(lightness(of: turned, x: 0.85, y: 0.9), 0.8)
        XCTAssertGreaterThan(lightness(of: turned, x: 0.15, y: 0.9), 0.8)
    }

    /// A page cut down to part of its sheet shows only that part, from its
    /// own top left corner, as a PDF reader shows it.
    func testACroppedPageShowsOnlyItsPart() throws {
        let pdf = folder.appendingPathComponent("Cropped.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 100, y: 120, width: 30, height: 30))
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(url: pdf))
        let page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(x: 100, y: 50, width: 150, height: 100), for: .cropBox)

        XCTAssertEqual(DocumentCover.pageSize(of: page), CGSize(width: 150, height: 100))
        let image = try XCTUnwrap(DocumentCover.render(page))
        XCTAssertLessThan(lightness(of: image, x: 0.1, y: 0.15), 0.2)
        XCTAssertGreaterThan(lightness(of: image, x: 0.9, y: 0.15), 0.8)
        XCTAssertGreaterThan(lightness(of: image, x: 0.1, y: 0.85), 0.8)
        XCTAssertGreaterThan(lightness(of: image, x: 0.9, y: 0.85), 0.8)
    }

    /// The protected copy has every page, under the same name, and no text
    /// left to copy out from under a cover.
    func testTheCopyIsDrawnNotWritten() throws {
        let pdf = folder.appendingPathComponent("Invoice.pdf")
        try makePDF(at: pdf, pages: 2)
        XCTAssertTrue(PDFDocument(url: pdf)?.string?.contains("IBAN") ?? false)

        let copy = try XCTUnwrap(DocumentCover.copy(of: pdf, [.bank], hand: [2: [CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2)]]))
        XCTAssertEqual(copy.lastPathComponent, "Invoice.pdf")
        let document = try XCTUnwrap(PDFDocument(url: copy))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // What was covered adds up over the pages: the IBANs, and the box by hand.
        let made = try XCTUnwrap(DocumentCover.covering(pdf, [.bank], hand: [2: [CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2)]]))
        XCTAssertEqual(made.report.hand, 1)
        XCTAssertGreaterThanOrEqual(made.report.kinds[.bank] ?? 0, 1, made.report.summary)
    }

    /// The copy leaves the original's details behind: its author and
    /// title, its notes, and its text.
    func testTheCopyLeavesTheDocumentsDetailsBehind() throws {
        let plain = folder.appendingPathComponent("Plain.pdf"), pdf = folder.appendingPathComponent("Note.pdf")
        try makePDF(at: plain, info: [kCGPDFContextAuthor: "Erika Mustermann", kCGPDFContextTitle: "Erika Mustermann"])
        let source = try XCTUnwrap(PDFDocument(url: plain))
        let note = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 20), forType: .freeText,
                                 withProperties: nil)
        note.contents = "Erika Mustermann"
        source.page(at: 0)?.addAnnotation(note)
        XCTAssertTrue(source.write(to: pdf))
        XCTAssertFalse(DocumentCover.isClean(pdf), "the original carries them")

        let copy = try XCTUnwrap(DocumentCover.copy(of: pdf, [.names], hand: [:]))
        XCTAssertTrue(DocumentCover.isClean(copy))
        let document = try XCTUnwrap(PDFDocument(url: copy))
        XCTAssertTrue(document.page(at: 0)?.annotations.isEmpty ?? false)
        XCTAssertNil(document.documentAttributes?[PDFDocumentAttribute.authorAttribute])
    }

    func testHandBoxesOfPagesBelongToTheirFile() {
        let url = URL(fileURLWithPath: "/tmp/Rechnung #4.pdf")
        let key = PrivateDetails.pageKey(url, 3)
        XCTAssertEqual(key, "/tmp/Rechnung #4.pdf#3")
        XCTAssertEqual(PrivateDetails.owner(ofHandKey: key), "/tmp/Rechnung #4.pdf")
        XCTAssertEqual(PrivateDetails.owner(ofHandKey: "/tmp/Rechnung #4.pdf"), "/tmp/Rechnung #4.pdf")
        XCTAssertEqual(PrivateDetails.owner(ofHandKey: "/tmp/Shot.png"), "/tmp/Shot.png")
    }

    /// What was hidden by hand goes with its file into the History and back,
    /// a PDF's pages too, so it leaves covered from there, and is forgotten
    /// with it; no other file's goes along.
    @MainActor
    func testHandBoxesGoWithTheirFileAndAreForgottenWithIt() {
        let key = "handCovers"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let shot = URL(fileURLWithPath: "/tmp/Snapfly hand test/Screenshot.png")
        let pdf = URL(fileURLWithPath: "/tmp/Snapfly hand test/Rechnung.pdf")
        let other = URL(fileURLWithPath: "/tmp/Snapfly hand test/Screenshot 2.png")
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        PrivateDetails.setHand([box], for: shot)
        PrivateDetails.setHand([box], for: pdf, page: 2)
        PrivateDetails.setHand([box], for: other)

        let kept = URL(fileURLWithPath: "/tmp/Snapfly hand test/History/Screenshot.png")
        let keptPDF = URL(fileURLWithPath: "/tmp/Snapfly hand test/History/Rechnung.pdf")
        PrivateDetails.moveHand(from: shot, to: kept)
        PrivateDetails.moveHand(from: pdf, to: keptPDF)
        XCTAssertEqual(PrivateDetails.hand(kept), [box])
        XCTAssertEqual(PrivateDetails.hand(keptPDF, page: 2), [box])
        XCTAssertTrue(PrivateDetails.hand(shot).isEmpty)
        XCTAssertTrue(PrivateDetails.handPages(pdf).isEmpty)
        XCTAssertEqual(PrivateDetails.hand(other), [box], "a file beside it keeps its own")

        PrivateDetails.forgetHand(keptPDF)
        XCTAssertTrue(PrivateDetails.handPages(keptPDF).isEmpty)
        XCTAssertEqual(PrivateDetails.hand(kept), [box])
    }

    /// A photo from a phone says where it was taken; what leaves the line
    /// does not. A screenshot carries nothing of the kind.
    func testAPhotoLeavesWithoutWhereItWasTaken() throws {
        let photo = folder.appendingPathComponent("IMG_0001.jpg")
        try makeImage(at: photo, type: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 13.40, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
        ])
        let screenshot = folder.appendingPathComponent("Screenshot.png")
        try makeImage(at: screenshot, type: .png, properties: [:])
        XCTAssertTrue(Cover.strips(photo))
        XCTAssertFalse(Cover.strips(screenshot))

        let clean = try XCTUnwrap(Cover.copy(of: photo, [], clean: true))
        XCTAssertEqual(clean.pathExtension, "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(clean as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertFalse(Cover.strips(clean))
        // Nothing to cover and nothing to take out: no copy, the screenshot itself.
        XCTAssertEqual(Cover.copy(of: screenshot, []), screenshot)
    }

    /// A photo stored turned, with a note to turn it back, is read upright.
    func testAPhotoIsReadUpright() throws {
        let photo = folder.appendingPathComponent("Turned.jpg")
        try makeImage(at: photo, type: .jpeg, size: CGSize(width: 40, height: 20),
                      properties: [kCGImagePropertyOrientation: 6])
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(photo as CFURL, nil))
        let image = try XCTUnwrap(Cover.upright(source))
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 40)
    }

    /// The copy takes the original's name with a mark, so it is never mistaken
    /// for the original, and keeps the kind of the photo or PDF.
    func testACopyIsNamedBesideTheOriginal() {
        XCTAssertEqual(SaveCopy.suggestedName(for: URL(fileURLWithPath: "/tmp/IMG_1.HEIC")),
                       String(format: L("%@ (covered)"), "IMG_1") + ".jpg")
        XCTAssertEqual(SaveCopy.suggestedName(for: URL(fileURLWithPath: "/tmp/Scan.png")),
                       String(format: L("%@ (covered)"), "Scan") + ".png")
        XCTAssertEqual(SaveCopy.suggestedName(for: URL(fileURLWithPath: "/tmp/Rechnung.pdf")),
                       String(format: L("%@ (covered)"), "Rechnung") + ".pdf")
        XCTAssertEqual(SaveCopy.fileType(for: URL(fileURLWithPath: "/tmp/IMG_1.HEIC")), .jpeg)
        XCTAssertEqual(SaveCopy.fileType(for: URL(fileURLWithPath: "/tmp/Scan.png")), .png)
        XCTAssertEqual(SaveCopy.fileType(for: URL(fileURLWithPath: "/tmp/Rechnung.pdf")), .pdf)
    }

    /// A photo's copy covers what is chosen and what is hidden by hand, and
    /// comes out without where or with what it was taken.
    func testAPhotoCopyCoversWhatIsChosenAndKeepsNoPlace() throws {
        let photo = folder.appendingPathComponent("IMG_0002.jpg")
        try makeImage(at: photo, type: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 13.40, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
        ])
        let target = folder.appendingPathComponent(SaveCopy.suggestedName(for: photo))
        let report = try XCTUnwrap(SaveCopy.write(photo, [], hand: [CGRect(x: 0, y: 0, width: 0.5, height: 1)],
                                                  pages: [:], to: target))
        // What was covered comes back, so the note says "covered" only then.
        XCTAssertEqual(report.hand, 1)
        XCTAssertEqual(target.lastPathComponent, String(format: L("%@ (covered)"), "IMG_0002") + ".jpg")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(target as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFModel])
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // The left half is covered in ink; the right half keeps its colour.
        XCTAssertLessThan(lightness(of: image, x: 0.25, y: 0.5), 0.25)
        XCTAssertGreaterThan(lightness(of: image, x: 0.75, y: 0.5), 0.35)
    }

    /// A PDF's copy has every page, with the page's boxes covered, and is
    /// written to the place it was asked for.
    func testAPDFCopyIsWrittenWhereAsked() throws {
        let pdf = folder.appendingPathComponent("Invoice.pdf")
        try makePDF(at: pdf, pages: 2)
        let target = folder.appendingPathComponent(SaveCopy.suggestedName(for: pdf))
        let report = try XCTUnwrap(SaveCopy.write(pdf, [], hand: [], pages: [2: [CGRect(x: 0, y: 0, width: 1, height: 1)]],
                                                  to: target))
        XCTAssertEqual(report.hand, 1)
        XCTAssertEqual(target.lastPathComponent, String(format: L("%@ (covered)"), "Invoice") + ".pdf")

        let copy = try XCTUnwrap(PDFDocument(url: target))
        XCTAssertEqual(copy.pageCount, 2)
        XCTAssertTrue((copy.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Helpers

    private func makePDF(at url: URL, size: CGSize = CGSize(width: 300, height: 200), pages: Int = 1,
                         info: [CFString: Any] = [:]) throws {
        var box = CGRect(origin: .zero, size: size)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, info.isEmpty ? nil : info as CFDictionary))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            let text = NSAttributedString(string: "IBAN DE89 3704 0044 0532 0130 00",
                                          attributes: [.font: NSFont.systemFont(ofSize: 14)])
            context.textPosition = CGPoint(x: 20, y: size.height / 2)
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// How light a picture is at a point, from 0 for black to 1 for white,
    /// with x and y from 0 to 1 from the top left.
    private func lightness(of image: CGImage, x: CGFloat, y: CGFloat) -> CGFloat {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return -1 }
        // The first row in memory is the top of the picture.
        let column = min(image.width - 1, Int(x * CGFloat(image.width)))
        let row = min(image.height - 1, Int(y * CGFloat(image.height)))
        let pixel = data.advanced(by: row * context.bytesPerRow + column * 4).assumingMemoryBound(to: UInt8.self)
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    private func makeImage(at url: URL, type: UTType, size: CGSize = CGSize(width: 64, height: 48),
                           properties: [CFString: Any]) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
