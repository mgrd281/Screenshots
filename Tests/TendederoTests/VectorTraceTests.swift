import XCTest
@testable import Tendedero

/// Turning a picture into shapes: what the colours and edges come out as,
/// and the SVG they are written as.
final class VectorTraceTests: XCTestCase {
    private typealias Colour = (red: UInt8, green: UInt8, blue: UInt8)
    private let white: Colour = (255, 255, 255)
    private let blue: Colour = (30, 60, 200)

    /// A picture of `background` with `ink` over the part `coverage` says each
    /// pixel has: 0 for none of it and 1 for all of it, as a drawing program anti-aliases.
    private func picture(_ width: Int, _ height: Int, background: Colour, ink: Colour, alpha: UInt8 = 255,
                         coverage: (Int, Int) -> Double) -> VectorPixels {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        func mix(_ a: UInt8, _ b: UInt8, _ t: Double) -> UInt8 { UInt8((Double(a) * (1 - t) + Double(b) * t).rounded()) }
        for y in 0..<height {
            for x in 0..<width {
                let t = min(1, max(0, coverage(x, y)))
                let i = (y * width + x) * 4
                rgba[i] = mix(background.red, ink.red, t)
                rgba[i + 1] = mix(background.green, ink.green, t)
                rgba[i + 2] = mix(background.blue, ink.blue, t)
                rgba[i + 3] = alpha
            }
        }
        return VectorPixels(width: width, height: height, rgba: rgba)
    }

    /// Every point of a layer's outlines: the corners, and a few along each curve.
    private func points(of layer: VectorLayer) -> [VectorPoint] {
        var out: [VectorPoint] = []
        for contour in layer.contours {
            var from = contour.start
            out.append(from)
            for segment in contour.segments {
                switch segment {
                case .line(let end):
                    out.append(end)
                    from = end
                case .curve(let c1, let c2, let end):
                    for step in 1...8 {
                        let t = Double(step) / 8, m = 1 - t
                        out.append(VectorPoint(
                            m * m * m * from.x + 3 * m * m * t * c1.x + 3 * m * t * t * c2.x + t * t * t * end.x,
                            m * m * m * from.y + 3 * m * m * t * c1.y + 3 * m * t * t * c2.y + t * t * t * end.y))
                    }
                    from = end
                }
            }
        }
        return out
    }

    // MARK: Writing

    func testNumbersAreWrittenShort() {
        XCTAssertEqual(VectorImage.number(hundredths: 1234), "12.34")
        XCTAssertEqual(VectorImage.number(hundredths: 5), ".05")
        XCTAssertEqual(VectorImage.number(hundredths: -50), "-.5")
        XCTAssertEqual(VectorImage.number(hundredths: 0), "0")
        XCTAssertEqual(VectorImage.number(hundredths: 100), "1")
        XCTAssertEqual(VectorImage.number(hundredths: 120), "1.2")
        XCTAssertEqual(VectorImage.number(hundredths: -1205), "-12.05")
    }

    func testAColourIsWrittenAsHex() {
        XCTAssertEqual(VectorColor(red: 30, green: 60, blue: 200).hex, "#1e3cc8")
        XCTAssertEqual(VectorColor(red: 0, green: 0, blue: 0).hex, "#000000")
        XCTAssertEqual(VectorColor(red: 255, green: 255, blue: 255).hex, "#ffffff")
    }

    func testAPathIsWrittenFromTheStepBeforeIt() {
        let contour = VectorContour(start: VectorPoint(10, 10), segments: [
            .line(VectorPoint(20, 10)),
            .line(VectorPoint(20, 5.5)),
            .curve(VectorPoint(20, 2), VectorPoint(15, 0), VectorPoint(10, 0)),
        ])
        let image = VectorImage(width: 30, height: 30,
                                layers: [VectorLayer(color: VectorColor(red: 1, green: 2, blue: 3), contours: [contour])])
        XCTAssertEqual(image.svg(), "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"30\" height=\"30\" viewBox=\"0 0 30 30\">"
            + "<path fill=\"#010203\" fill-rule=\"evenodd\" d=\"M10 10l10 0 0-4.5c0-3.5-5-5.5-10-5.5z\"/></svg>")
    }

    func testASizeToShowItAtKeepsTheShapesInThePicturesOwnPixels() {
        let flat = VectorPixels(width: 100, height: 50, fill: (10, 20, 30, 255))
        let image = VectorTracer.trace(flat, settings: VectorSettings())
        let svg = image?.svg(size: (width: 400, height: 200)) ?? ""
        XCTAssertTrue(svg.contains("width=\"400\" height=\"200\" viewBox=\"0 0 100 50\""))
    }

    // MARK: Tracing

    func testAFlatPictureIsOneRectangle() throws {
        let flat = VectorPixels(width: 40, height: 30, fill: (200, 100, 50, 255))
        let image = try XCTUnwrap(VectorTracer.trace(flat, settings: VectorSettings()))
        XCTAssertEqual(image.layers.count, 1)
        XCTAssertTrue(image.layers[0].fillsPicture)
        XCTAssertEqual(image.contourCount, 0)
        XCTAssertTrue(image.svg().contains("<rect width=\"40\" height=\"30\" fill=\"#c86432\"/>"))
    }

    func testASquareOfPixelsComesOutAsFourExactLines() throws {
        let pixels = picture(100, 100, background: white, ink: blue) { x, y in
            (20..<80).contains(x) && (20..<80).contains(y) ? 1 : 0
        }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        XCTAssertEqual(image.svg(), "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">"
            + "<rect width=\"100\" height=\"100\" fill=\"#ffffff\"/>"
            + "<path fill=\"#1e3cc8\" fill-rule=\"evenodd\" d=\"M20 20l0 60 60 0 0-60z\"/></svg>")
    }

    func testAHoleIsAnOutlineInsideAnOutline() throws {
        let pixels = picture(100, 100, background: white, ink: blue) { x, y in
            let outer = (10..<90).contains(x) && (10..<90).contains(y)
            let inner = (30..<70).contains(x) && (30..<70).contains(y)
            return outer && !inner ? 1 : 0
        }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        let ring = try XCTUnwrap(image.layers.first { $0.color == VectorColor(red: 30, green: 60, blue: 200) })
        XCTAssertEqual(ring.contours.count, 2)
        // Painted with the even-odd rule, the inner outline cuts the hole.
        XCTAssertTrue(image.svg().contains("fill-rule=\"evenodd\""))
    }

    func testACircleIsAFewCurvesThatStayOnIt() throws {
        let centre = 50.0, radius = 30.0
        let pixels = picture(100, 100, background: white, ink: blue) { x, y in
            let d = ((Double(x) + 0.5 - centre) * (Double(x) + 0.5 - centre) + (Double(y) + 0.5 - centre) * (Double(y) + 0.5 - centre)).squareRoot()
            return radius + 0.5 - d
        }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        let disc = try XCTUnwrap(image.layers.first { !$0.fillsPicture })
        XCTAssertEqual(disc.contours.count, 1)
        XCTAssertLessThanOrEqual(disc.contours[0].segments.count, 16)
        for p in points(of: disc) {
            let d = ((p.x - centre) * (p.x - centre) + (p.y - centre) * (p.y - centre)).squareRoot()
            XCTAssertEqual(d, radius, accuracy: 0.5)
        }
    }

    func testAnEdgeBetweenPixelsIsPlacedBetweenThem() throws {
        // The ink starts 0.3 of the way into the pixel at 50, where it covers 0.7 of it.
        let pixels = picture(100, 40, background: white, ink: blue) { x, _ in Double(x) + 1 - 50.3 }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        let ink = try XCTUnwrap(image.layers.first { !$0.fillsPicture })
        let edge = points(of: ink).filter { $0.x < 55 }
        XCTAssertFalse(edge.isEmpty)
        for p in edge { XCTAssertEqual(p.x, 50.3, accuracy: 0.15) }
    }

    func testAPictureOnNothingLeavesNothingBehindIt() throws {
        let pixels = picture(60, 60, background: (0, 0, 0), ink: blue, alpha: 255) { _, _ in 1 }
        var clear = pixels
        for y in 0..<60 {
            for x in 0..<60 {
                let inside = (15..<45).contains(x) && (15..<45).contains(y)
                clear.rgba[(y * 60 + x) * 4 + 3] = inside ? 255 : 0
            }
        }
        let image = try XCTUnwrap(VectorTracer.trace(clear, settings: VectorPreset.screenshot.settings))
        XCTAssertEqual(image.layers.count, 1)
        XCTAssertFalse(image.layers[0].fillsPicture)
        XCTAssertFalse(image.svg().contains("<rect"))
        XCTAssertTrue(image.svg().contains("M15 15"))
    }

    func testBlackAndWhiteKeepsOnlyTheInkOnNothing() throws {
        let ink: Colour = (20, 20, 20)
        let pixels = picture(80, 80, background: white, ink: ink) { x, y in
            let d = ((Double(x) + 0.5 - 40) * (Double(x) + 0.5 - 40) + (Double(y) + 0.5 - 40) * (Double(y) + 0.5 - 40)).squareRoot()
            return 20.5 - d
        }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.blackAndWhite.settings))
        XCTAssertEqual(image.layers.count, 1)
        XCTAssertFalse(image.layers[0].fillsPicture)
        XCTAssertLessThan(Int(image.layers[0].color.red), 80)
    }

    func testFewerColoursMergeTheClosestOnes() throws {
        // Five stripes, each a clearly different colour.
        let colours: [Colour] = [(250, 250, 250), (220, 40, 40), (40, 160, 60), (40, 60, 220), (20, 20, 20)]
        var rgba: [UInt8] = []
        for _ in 0..<50 {
            for x in 0..<100 {
                let c = colours[x / 20]
                rgba += [c.red, c.green, c.blue, 255]
            }
        }
        let pixels = VectorPixels(width: 100, height: 50, rgba: rgba)
        var settings = VectorSettings()
        settings.colors = 24
        XCTAssertEqual(VectorTracer.trace(pixels, settings: settings)?.layers.count, 5)
        settings.colors = 3
        let fewer = try XCTUnwrap(VectorTracer.trace(pixels, settings: settings))
        XCTAssertLessThanOrEqual(fewer.layers.count, 3)
    }

    func testAStrayPixelIsLeftOut() throws {
        var pixels = VectorPixels(width: 50, height: 50, fill: (240, 240, 240, 255))
        let i = (25 * 50 + 25) * 4
        pixels.rgba[i] = 200
        pixels.rgba[i + 1] = 30
        pixels.rgba[i + 2] = 30
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        XCTAssertEqual(image.layers.count, 1)
        XCTAssertEqual(image.contourCount, 0)
    }

    func testCancellingStopsTheTracing() {
        let pixels = VectorPixels(width: 40, height: 40, fill: (10, 10, 10, 255))
        XCTAssertNil(VectorTracer.trace(pixels, settings: VectorSettings(), isCancelled: { true }))
    }

    func testEverySettingsPresetTracesAPicture() throws {
        let pixels = picture(64, 64, background: white, ink: blue) { x, y in (16..<48).contains(x) && (16..<48).contains(y) ? 1 : 0 }
        for preset in VectorPreset.allCases {
            XCTAssertNotNil(VectorTracer.trace(pixels, settings: preset.settings), "\(preset)")
        }
    }

    // MARK: Fitting

    func testAStraightEdgeStaysOneLineAndACornerStaysSharp() throws {
        // An L shape: six corners, all of them right angles.
        let pixels = picture(100, 100, background: white, ink: blue) { x, y in
            ((20..<40).contains(x) && (20..<80).contains(y)) || ((20..<80).contains(x) && (60..<80).contains(y)) ? 1 : 0
        }
        let image = try XCTUnwrap(VectorTracer.trace(pixels, settings: VectorPreset.screenshot.settings))
        let shape = try XCTUnwrap(image.layers.first { !$0.fillsPicture })
        XCTAssertEqual(shape.contours.count, 1)
        XCTAssertEqual(shape.contours[0].segments.count, 5)
        for segment in shape.contours[0].segments {
            if case .curve = segment { XCTFail("an edge of pixels is no curve") }
        }
    }

    func testMarchingSquaresClosesALoopRoundAPatch() {
        let width = 8, height = 8
        var field = [Float](repeating: 0, count: width * height)
        for y in 2..<6 { for x in 2..<6 { field[y * width + x] = 1 } }
        var squares = VectorMarchingSquares()
        let loops = squares.loops(of: field, width: width, height: height, originX: 0.5, originY: 0.5)
        XCTAssertEqual(loops.count, 1)
        // Half-way between the pixel centres of the patch and the ones outside it.
        XCTAssertEqual(loops[0].map(\.x).min(), 2)
        XCTAssertEqual(loops[0].map(\.x).max(), 6)
    }
}
