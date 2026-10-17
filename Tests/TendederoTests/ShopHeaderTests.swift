import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Send with Shop Header: a band above the covered screenshot, with the
/// logo leading in the reading direction, and the order and the day.
final class ShopHeaderTests: XCTestCase {
    private let october17 = Date(timeIntervalSince1970: 1_792_234_567)
    private let utc = TimeZone(identifier: "UTC")!
    private let blue = (r: UInt8(20), g: UInt8(60), b: UInt8(200))

    func testTheDetailSaysTheOrderAndTheDay() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ShopHeader.detail(order: "1024", day: october17, locale: english, timeZone: utc),
                       L("Order") + " 1024 · October 17, 2026")
        XCTAssertEqual(ShopHeader.detail(order: nil, day: october17, locale: english, timeZone: utc), "October 17, 2026")
        XCTAssertEqual(ShopHeader.detail(order: "", day: october17, locale: english, timeZone: utc), "October 17, 2026")
    }

    func testTheBandSitsAboveThePicture() throws {
        let picture = try solid(width: 400, height: 300, blue)
        let drawn = try XCTUnwrap(ShopHeader.render(picture, name: "Lena's Laden", logo: nil,
                                                    detail: "Order 1024", rightToLeft: false))
        let band = Int(ShopHeader.Metrics(width: 400).height.rounded(.up))
        XCTAssertEqual(drawn.width, 400)
        XCTAssertEqual(drawn.height, 300 + band)
        let pixels = try rgba(drawn)
        // The band is white at its far end, the picture as it was below it.
        XCTAssertEqual(pixel(pixels, drawn, x: 396, row: 2).r, 255)
        XCTAssertEqual(pixel(pixels, drawn, x: 396, row: 2).b, 255)
        let below = pixel(pixels, drawn, x: 200, row: drawn.height - 2)
        XCTAssertEqual(below.b, blue.b)
        XCTAssertEqual(below.r, blue.r)
    }

    func testTheLogoLeadsInTheReadingDirection() throws {
        let picture = try solid(width: 600, height: 200, blue)
        let logo = try solid(width: 64, height: 64, (r: 230, g: 20, b: 20))
        let m = ShopHeader.Metrics(width: 600)
        let band = Int(m.height.rounded(.up))
        let side = CGFloat(band) - m.padding * 2
        let row = band / 2
        let near = Int(m.padding + side / 2), far = 600 - near

        let leftToRight = try XCTUnwrap(ShopHeader.render(picture, name: "Shop", logo: logo, detail: "", rightToLeft: false))
        let ltr = try rgba(leftToRight)
        XCTAssertEqual(pixel(ltr, leftToRight, x: near, row: row).r, 230)
        XCTAssertEqual(pixel(ltr, leftToRight, x: far, row: row).g, 255)

        let rightToLeft = try XCTUnwrap(ShopHeader.render(picture, name: "Shop", logo: logo, detail: "", rightToLeft: true))
        let rtl = try rgba(rightToLeft)
        XCTAssertEqual(pixel(rtl, rightToLeft, x: far, row: row).r, 230)
        XCTAssertEqual(pixel(rtl, rightToLeft, x: near, row: row).g, 255)
    }

    func testTheCopyIsAPNGUnderTheBand() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Screenshot.png")
        let screenshot = try solid(width: 320, height: 240, blue)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, screenshot, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let logo = folder.appendingPathComponent("Logo.png")
        XCTAssertTrue(ShopHeader.keep(logo: url, at: logo))

        let copy = try XCTUnwrap(ShopHeader.copy(of: url, name: "Lena's Laden", logo: logo, order: "1024",
                                                 day: october17, rightToLeft: false))
        XCTAssertEqual(copy.pathExtension, "png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(copy as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 240 + Int(ShopHeader.Metrics(width: 320).height.rounded(.up)))
    }

    // MARK: Helpers

    private func solid(width: Int, height: Int, _ color: (r: UInt8, g: UInt8, b: UInt8)) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                                     blue: CGFloat(color.b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// The picture's pixels in sRGB, the top row first.
    private func rgba(_ image: CGImage) throws -> [UInt8] {
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

    private func pixel(_ bytes: [UInt8], _ image: CGImage, x: Int, row: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (row * image.width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
}
