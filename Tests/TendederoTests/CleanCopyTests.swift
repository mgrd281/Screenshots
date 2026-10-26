import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Pictures leave as fresh files: what they show, and none of the notes
/// their files carry on when, where and with what they were made.
final class CleanCopyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAScreenshotLeavesWithItsPixelsAndNothingElse() throws {
        let original = folder.appendingPathComponent("Screenshot 2026-10-17 at 17.41.47.png")
        try write(picture(width: 64, height: 48), to: original, type: .png, properties: [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "Lena Hoffmann, order 1024"],
        ])
        try setAttribute("com.apple.metadata:kMDItemWhereFroms", on: original)
        XCTAssertNotNil(png(original)[kCGImagePropertyPNGDescription])
        XCTAssertNotNil(attribute("com.apple.metadata:kMDItemWhereFroms", of: original))

        let copy = try XCTUnwrap(Cover.plain(original))
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(copy.lastPathComponent, original.lastPathComponent)
        XCTAssertNil(png(copy)[kCGImagePropertyPNGDescription])
        XCTAssertNil(attribute("com.apple.metadata:kMDItemWhereFroms", of: copy))
        XCTAssertEqual(try pixels(of: copy), try pixels(of: original))
    }

    func testAPhotoLeavesUprightAndWithoutWhereItWasTaken() throws {
        // Stored 60 × 40 and turned a quarter, as phones store photos: 40 × 60 upright.
        let original = folder.appendingPathComponent("IMG_1024.jpg")
        try write(picture(width: 60, height: 40), to: original, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 13.40, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Lena Hoffmann"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Lena's shop"],
        ])
        XCTAssertNotNil(properties(original)[kCGImagePropertyGPSDictionary])

        let copy = try XCTUnwrap(Cover.plain(original))
        XCTAssertEqual(copy.pathExtension, "jpg")
        let notes = properties(copy)
        XCTAssertNil(notes[kCGImagePropertyGPSDictionary])
        XCTAssertNil((notes[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFArtist])
        XCTAssertNil((notes[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        XCTAssertEqual(notes[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(notes[kCGImagePropertyPixelHeight] as? Int, 60)
        XCTAssertEqual((notes[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
    }

    /// A GIF goes as itself, so it keeps moving.
    func testAGIFGoesAsItself() throws {
        let gif = folder.appendingPathComponent("Moving.gif")
        let first = try picture(width: 20, height: 20)
        let second = try picture(width: 20, height: 20, shade: 0.3)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, first, nil)
        CGImageDestinationAddImage(destination, second, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertNil(Cover.plain(gif))
    }

    func testPlainNamesCallEveryPictureImage() throws {
        let original = folder.appendingPathComponent("Bildschirmfoto 2026-10-17 um 17.41.47.png")
        try write(picture(width: 32, height: 32), to: original, type: .png, properties: [:])
        let before = Cover.plainNames
        Cover.plainNames = true
        addTeardownBlock { Cover.plainNames = before }
        let copy = try XCTUnwrap(Cover.plain(original))
        XCTAssertEqual(copy.deletingPathExtension().lastPathComponent, L("Image"))
        XCTAssertEqual(copy.pathExtension, "png")
        // A covered PDF is called Document with them, whatever its title says.
        XCTAssertEqual(Cover.newCopy(of: folder.appendingPathComponent("Rechnung 1024.pdf"), ext: "pdf")?
            .deletingPathExtension().lastPathComponent, L("Document"))
    }

    /// A name that holds a detail being covered leaves as "Image" or
    /// "Document", plain names or not; any other name stays, a screenshot's
    /// date and time too while dates are not covered.
    func testANameHoldingACoveredDetailIsReplaced() throws {
        let before = Cover.plainNames
        Cover.plainNames = false
        addTeardownBlock { Cover.plainNames = before }
        let statement = folder.appendingPathComponent("Kontoauszug_DE89370400440532013000.pdf")
        XCTAssertEqual(Cover.newCopy(of: statement, ext: "pdf", covering: [.bank])?
            .deletingPathExtension().lastPathComponent, L("Document"))
        let invoice = folder.appendingPathComponent("Rechnung 1024.pdf")
        XCTAssertEqual(Cover.newCopy(of: invoice, ext: "pdf", covering: [.bank])?
            .deletingPathExtension().lastPathComponent, "Rechnung 1024")
        XCTAssertTrue(Cover.nameHolds("Rechnung lena.hoffmann@example.com", [.emails]))
        XCTAssertFalse(Cover.nameHolds("Rechnung lena.hoffmann@example.com", []), "nothing covered, nothing replaced")
        XCTAssertFalse(Cover.nameHolds("Screenshot 2026-10-17 at 17.41.47", PrivateDetail.recommended))
        XCTAssertTrue(Cover.nameHolds("Screenshot 2026-10-17 at 17.41.47", [.dates]))
    }

    // MARK: Helpers

    /// Stripes of grey with a coloured corner, so every pixel counts.
    private func picture(width: Int, height: Int, shade: CGFloat = 0.8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<width {
            context.setFillColor(CGColor(gray: x % 2 == 0 ? shade : 0.2, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 3))
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any]) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    private func png(_ url: URL) -> [CFString: Any] {
        properties(url)[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
    }

    /// The picture drawn the same way for both files, to compare.
    private func pixels(of url: URL) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
        return bytes
    }

    private func setAttribute(_ name: String, on url: URL) throws {
        let value = Data("https://shop.example.com/orders/1024".utf8)
        let result = url.withUnsafeFileSystemRepresentation { path in
            value.withUnsafeBytes { setxattr(path, name, $0.baseAddress, value.count, 0, 0) }
        }
        XCTAssertEqual(result, 0)
    }

    private func attribute(_ name: String, of url: URL) -> Int? {
        let size = url.withUnsafeFileSystemRepresentation { getxattr($0, name, nil, 0, 0, 0) }
        return size >= 0 ? size : nil
    }
}
