import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Scanned pages made into one PDF: a page of each picture's shape, in
/// order, with pictures alone, nothing to copy as text, and nothing said of
/// who made it but the app.
final class ScanPDFTests: XCTestCase {
    func testEachPictureIsAPageOfItsShapeInOrder() throws {
        let pdf = try XCTUnwrap(ScanPDF.make([Self.page(1000, 1414), Self.page(1400, 1000), Self.page(800, 3000)]))
        let document = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: pdf as CFData))))
        XCTAssertEqual(document.numberOfPages, 3)
        let letter = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(letter.width, ScanPDF.shortSide, accuracy: 0.01)
        XCTAssertEqual(letter.height, ScanPDF.shortSide * 1.414, accuracy: 0.5)
        let sideways = try XCTUnwrap(document.page(at: 2)).getBoxRect(.mediaBox)
        XCTAssertEqual(sideways.height, ScanPDF.shortSide, accuracy: 0.01)
        XCTAssertEqual(sideways.width, ScanPDF.shortSide * 1.4, accuracy: 0.5)
        let receipt = try XCTUnwrap(document.page(at: 3)).getBoxRect(.mediaBox)
        XCTAssertEqual(receipt.height, ScanPDF.shortSide * 3000 / 800, accuracy: 0.5)
    }

    func testThePagesHoldNoTextAndSayNothingOfWhoMadeThem() throws {
        let pdf = try XCTUnwrap(ScanPDF.make([Self.page(600, 800)]))
        let document = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: pdf as CFData))))
        if let info = document.info {
            for key in ["Title", "Author", "Subject", "Keywords"] {
                var value: CGPDFStringRef?
                XCTAssertFalse(CGPDFDictionaryGetString(info, key, &value), "\(key) is in the PDF")
            }
        }
        let page = try XCTUnwrap(try XCTUnwrap(document.page(at: 1)).dictionary)
        var resources: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(page, "Resources", &resources))
        let held = try XCTUnwrap(resources)
        var fonts: CGPDFDictionaryRef?
        XCTAssertFalse(CGPDFDictionaryGetDictionary(held, "Font", &fonts), "a page has fonts, so text")
    }

    func testALargePageIsMadeSmaller() throws {
        let made = try XCTUnwrap(ScanPDF.compressed(Self.page(4000, 6000), quality: 0.8))
        XCTAssertEqual(max(made.width, made.height), ScanPDF.longest)
        XCTAssertEqual(made.width, 2339)
    }

    func testNoPagesMakeNoPDF() {
        XCTAssertNil(ScanPDF.make([]))
    }

    /// A page of a light grey with a dark band across it, like a line of print.
    static func page(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: width / 10, y: height / 2, width: width * 8 / 10, height: max(1, height / 40)))
        return context.makeImage()!
    }
}
