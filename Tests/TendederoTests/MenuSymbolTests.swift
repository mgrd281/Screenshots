import AppKit
import XCTest
@testable import Tendedero

/// The menu bar menu's symbols: each one the Mac has, and no two lines alike
/// but the stop that stands for what is running.
final class MenuSymbolTests: XCTestCase {
    func testEverySymbolIsOneTheMacHas() {
        for name in MenuSymbol.all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testEachIsDrawnAsAPictureTheMenuShows() throws {
        for name in MenuSymbol.all {
            let image = try XCTUnwrap(MenuSymbol.image(name), name)
            XCTAssertTrue(image.isTemplate, name)
            XCTAssertEqual(image.size, MenuSymbol.box, name)
            // A picture, not a symbol, which macOS 27 hides in menus.
            XCTAssertFalse(image.representations.contains { String(describing: type(of: $0)).contains("Symbol") }, name)
            // And something is drawn in it.
            var rect = NSRect(origin: .zero, size: MenuSymbol.box)
            let drawn = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil), name)
            XCTAssertGreaterThan(Self.inked(drawn), 8, name)
        }
    }

    /// How many pixels of a picture hold anything.
    private static func inked(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 40 }.count
    }

    func testNoTwoLinesShareASymbol() {
        XCTAssertEqual(Set(MenuSymbol.all).count, MenuSymbol.all.count)
    }
}
