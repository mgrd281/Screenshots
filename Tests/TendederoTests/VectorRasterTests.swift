import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// A picture read for the tracer, and the shapes drawn back as pixels.
final class VectorRasterTests: XCTestCase {
    private func square(_ from: Double, _ to: Double) -> VectorImage {
        let contour = VectorContour(start: VectorPoint(from, from), segments: [
            .line(VectorPoint(from, to)), .line(VectorPoint(to, to)), .line(VectorPoint(to, from)),
        ])
        return VectorImage(width: 100, height: 100,
                           layers: [VectorLayer(color: VectorColor(red: 30, green: 60, blue: 200), contours: [contour])])
    }

    private func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func png(_ image: CGImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vector-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testAHalfClearPixelKeepsItsColourAndItsAlpha() throws {
        let canvas = try XCTUnwrap(context(4, 4))
        canvas.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
        canvas.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let pixels = try XCTUnwrap(VectorRaster.pixels(of: try XCTUnwrap(canvas.makeImage())))
        XCTAssertEqual(pixels.width, 4)
        XCTAssertEqual(pixels.height, 4)
        // Straight colour: the red is not halved along with the alpha.
        XCTAssertEqual(Int(pixels.rgba[0]), 255, accuracy: 2)
        XCTAssertEqual(Int(pixels.rgba[1]), 0, accuracy: 1)
        XCTAssertEqual(Int(pixels.rgba[3]), 128, accuracy: 1)
    }

    func testShapesAreDrawnWhereTheyLieAndNothingElse() throws {
        let drawn = try XCTUnwrap(VectorRaster.render(square(20, 80), width: 100))
        XCTAssertEqual(drawn.width, 100)
        XCTAssertEqual(drawn.height, 100)
        let pixels = try XCTUnwrap(VectorRaster.pixels(of: drawn))
        func pixel(_ x: Int, _ y: Int) -> [Int] { (0..<4).map { Int(pixels.rgba[(y * 100 + x) * 4 + $0]) } }
        XCTAssertEqual(pixel(50, 50)[0], 30, accuracy: 2)
        XCTAssertEqual(pixel(50, 50)[1], 60, accuracy: 2)
        XCTAssertEqual(pixel(50, 50)[2], 200, accuracy: 2)
        XCTAssertEqual(pixel(50, 50)[3], 255, accuracy: 2)
        XCTAssertEqual(pixel(20, 20)[3], 255, accuracy: 2)
        XCTAssertEqual(pixel(79, 79)[3], 255, accuracy: 2)
        // Outside the square there is nothing, not white.
        XCTAssertEqual(pixel(10, 10)[3], 0)
        XCTAssertEqual(pixel(19, 50)[3], 0, accuracy: 2)
        XCTAssertEqual(pixel(80, 50)[3], 0, accuracy: 2)
    }

    func testTheShapesCanBeDrawnLargerAsTheyAreVectors() throws {
        let drawn = try XCTUnwrap(VectorRaster.render(square(20, 80), width: 300))
        XCTAssertEqual(drawn.width, 300)
        XCTAssertEqual(drawn.height, 300)
    }

    func testAPictureIsReadAsItIsAndAHugeOneIsShrunk() throws {
        let canvas = try XCTUnwrap(context(200, 100))
        canvas.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let url = try png(try XCTUnwrap(canvas.makeImage()))
        defer { try? FileManager.default.removeItem(at: url) }
        let whole = try XCTUnwrap(VectorRaster.pixels(of: url))
        XCTAssertEqual(whole.width, 200)
        XCTAssertEqual(whole.height, 100)
        let shrunk = try XCTUnwrap(VectorRaster.pixels(of: url, limit: 5_000))
        XCTAssertLessThanOrEqual(shrunk.width * shrunk.height, 5_000)
        // The sides keep their proportion.
        XCTAssertEqual(Double(shrunk.width) / Double(shrunk.height), 2, accuracy: 0.1)
    }

    func testSomethingThatIsNoPictureIsNotRead() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vector-\(UUID().uuidString).txt")
        try? "not a picture".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(VectorRaster.pixels(of: url))
    }
}
