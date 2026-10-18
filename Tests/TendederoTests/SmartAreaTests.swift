import CoreGraphics
import XCTest
@testable import Tendedero

/// Smart selection: the parts of a picture found by the empty space round
/// them, the edges a drag keeps to, and empty space trimmed off.
final class SmartAreaTests: XCTestCase {
    private let white: UInt32 = 0xFFFFFF
    private let grey: UInt32 = 0xFAF9F8
    private let ink: UInt32 = 0x1E1E1E

    /// A grid of one colour with rects of others painted on it, in order.
    private func grid(_ width: Int, _ height: Int, _ background: UInt32,
                      _ paint: [(CGRect, UInt32)] = []) -> PixelGrid {
        var pixels = [UInt32](repeating: background, count: width * height)
        for (rect, color) in paint {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) { pixels[y * width + x] = color }
            }
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }

    func testAPlainLineHasOneColourAndABusyOneNone() {
        let picture = grid(40, 10, white, [(CGRect(x: 20, y: 5, width: 1, height: 5), ink)])
        XCTAssertEqual(picture.rowColor(0, from: 0, to: 40), white)
        XCTAssertNil(picture.rowColor(6, from: 0, to: 40))
        XCTAssertEqual(picture.rowColor(6, from: 0, to: 20), white)
        XCTAssertNil(picture.columnColor(20, from: 0, to: 10))
        XCTAssertEqual(picture.columnColor(20, from: 0, to: 5), white)
        // Out of the grid, or empty, is no line.
        XCTAssertNil(picture.rowColor(10, from: 0, to: 40))
        XCTAssertNil(picture.rowColor(0, from: 5, to: 5))
    }

    func testGentleShadingIsStillPlainButAStepIsNot() {
        // A background shading from 230 to 245 across, as a window's does.
        var pixels: [UInt32] = []
        for _ in 0..<4 {
            for x in 0..<160 {
                let level = UInt32(230 + x * 15 / 159)
                pixels.append(level << 16 | level << 8 | level)
            }
        }
        let shaded = PixelGrid(width: 160, height: 4, pixels: pixels)
        XCTAssertNotNil(shaded.rowColor(0, from: 0, to: 160))
        // Grey beside white differs by a step, and is something.
        let tile = grid(20, 1, white, [(CGRect(x: 10, y: 0, width: 10, height: 1), grey)])
        XCTAssertNil(tile.rowColor(0, from: 0, to: 20))
        XCTAssertFalse(PixelGrid.same(white, grey))
        XCTAssertTrue(PixelGrid.same(white, 0xFDFEFF))
    }

    func testAFrameAtTheEndsOfALineIsLeftOut() {
        // A panel's frame, at both ends of a row of its background.
        let panel = grid(200, 3, white, [(CGRect(x: 0, y: 0, width: 2, height: 3), ink),
                                         (CGRect(x: 198, y: 0, width: 2, height: 3), ink)])
        XCTAssertNil(panel.rowColor(1, from: 0, to: 200))
        XCTAssertEqual(panel.rowColor(1, from: 0, to: 200, ends: SmartArea.ends), white)
    }

    /// Two grey tiles on white, each with a dark logo in its middle, as
    /// search results for pictures show them.
    private var tiles: PixelGrid {
        grid(200, 120, white, [(CGRect(x: 20, y: 20, width: 60, height: 60), grey),
                               (CGRect(x: 110, y: 20, width: 60, height: 60), grey),
                               (CGRect(x: 40, y: 40, width: 20, height: 20), ink),
                               (CGRect(x: 130, y: 40, width: 20, height: 20), ink)])
    }

    func testTheLogoTheTileAndTheWholeAreFoundUnderThePointer() {
        let tree = SmartArea.parts(of: tiles, in: CGRect(x: 0, y: 0, width: 200, height: 120))
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 50, y: 50)),
                       [CGRect(x: 40, y: 40, width: 20, height: 20), CGRect(x: 20, y: 20, width: 60, height: 60),
                        CGRect(x: 0, y: 0, width: 200, height: 120)])
        // On the grey round the logo, the tile.
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 25, y: 25)).first,
                       CGRect(x: 20, y: 20, width: 60, height: 60))
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 140, y: 50)).first,
                       CGRect(x: 130, y: 40, width: 20, height: 20))
        // On the white between, only the whole.
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 100, y: 100)),
                       [CGRect(x: 0, y: 0, width: 200, height: 120)])
        // Outside it, nothing.
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 300, y: 10)), [])
    }

    func testOnlyARectOfTheGridIsRead() {
        // The second tile alone, as a window would be.
        let tree = SmartArea.parts(of: tiles, in: CGRect(x: 100, y: 10, width: 80, height: 80))
        XCTAssertEqual(tree.rect, CGRect(x: 100, y: 10, width: 80, height: 80))
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 140, y: 50)).first,
                       CGRect(x: 130, y: 40, width: 20, height: 20))
        XCTAssertTrue(SmartArea.nested(in: tree, at: CGPoint(x: 50, y: 50)).isEmpty)
    }

    func testLinesOfTextCloseTogetherStayOneParagraph() {
        // Three lines of text, 4 apart, then a gap of 24 and a taller line.
        var paint: [(CGRect, UInt32)] = []
        for (top, height) in [(10, 12), (26, 12), (42, 12), (78, 16)] {
            for x in stride(from: 10, to: 150, by: 3) {
                paint.append((CGRect(x: x, y: top, width: 1, height: height), ink))
            }
        }
        let text = grid(160, 100, white, paint)
        let tree = SmartArea.parts(of: text, in: CGRect(x: 0, y: 0, width: 160, height: 100))
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 50, y: 30)),
                       [CGRect(x: 10, y: 10, width: 139, height: 44), CGRect(x: 0, y: 0, width: 160, height: 100)])
        XCTAssertEqual(SmartArea.nested(in: tree, at: CGPoint(x: 50, y: 80)).first,
                       CGRect(x: 10, y: 78, width: 139, height: 16))
    }

    func testTooSmallOrAlmostTheSameIsLeftOut() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 10, y: 10, width: 8, height: 30),
                     CGRect(x: 10, y: 10, width: 40, height: 40), CGRect(x: 8, y: 9, width: 43, height: 42)]
        XCTAssertEqual(SmartArea.merged(rects),
                       [CGRect(x: 10, y: 10, width: 40, height: 40), CGRect(x: 0, y: 0, width: 100, height: 100)])
    }

    func testADragKeepsToTheNearestEdgeWithinReach() {
        let edges: [CGFloat] = [20, 40, 80]
        XCTAssertEqual(SmartArea.snap(37, to: edges), 40)
        XCTAssertEqual(SmartArea.snap(22, to: edges), 20)
        XCTAssertEqual(SmartArea.snap(60, to: edges), 60)
        XCTAssertEqual(SmartArea.snap(60, to: edges, within: 25), 80)
        let tree = SmartArea.parts(of: tiles, in: CGRect(x: 0, y: 0, width: 200, height: 120))
        let found = SmartArea.edges(of: tree)
        for x: CGFloat in [20, 40, 60, 80, 110, 130, 150, 170] { XCTAssertTrue(found.across.contains(x), "\(x)") }
        for y: CGFloat in [20, 40, 60, 80] { XCTAssertTrue(found.down.contains(y), "\(y)") }
        XCTAssertEqual(found.across, found.across.sorted())
    }

    func testEmptySpaceRoundADragIsCutToAnEvenMargin() {
        let square = grid(100, 100, white, [(CGRect(x: 40, y: 40, width: 20, height: 20), ink)])
        XCTAssertEqual(SmartArea.trimmed(CGRect(x: 0, y: 0, width: 100, height: 100), in: square),
                       CGRect(x: 32, y: 32, width: 36, height: 36))
        // A margin already narrower stays as it was.
        XCTAssertEqual(SmartArea.trimmed(CGRect(x: 35, y: 35, width: 30, height: 30), in: square),
                       CGRect(x: 35, y: 35, width: 30, height: 30))
        // Uneven to begin with, even after.
        XCTAssertEqual(SmartArea.trimmed(CGRect(x: 10, y: 30, width: 90, height: 60), in: square),
                       CGRect(x: 32, y: 32, width: 36, height: 36))
        // Nothing in it: it stays.
        let blank = grid(50, 50, white)
        XCTAssertEqual(SmartArea.trimmed(CGRect(x: 0, y: 0, width: 50, height: 50), in: blank),
                       CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    func testTrimmingStopsAtAColourChange() {
        // A grey tile on white: the white goes, the tile's grey edge stays.
        XCTAssertEqual(SmartArea.trimmed(CGRect(x: 0, y: 0, width: 100, height: 100), in: tiles, margin: 0),
                       CGRect(x: 20, y: 20, width: 60, height: 60))
    }

    func testAPictureIsReadAtTheSizeAsked() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        // Red in the bottom half, as Core Graphics counts from the bottom.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        let image = try XCTUnwrap(context.makeImage())
        let picture = try XCTUnwrap(PixelGrid(image, width: 20, height: 10))
        XCTAssertEqual(picture.width, 20)
        XCTAssertEqual(picture.rowColor(1, from: 0, to: 20), white)
        let red = try XCTUnwrap(picture.rowColor(8, from: 0, to: 20))
        XCTAssertFalse(PixelGrid.same(red, white))
        XCTAssertNil(picture.columnColor(5, from: 0, to: 10))
    }
}
