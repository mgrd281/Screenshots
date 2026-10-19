import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Draw on Photo: marks drawn on what leaves the line, the part kept, and
/// how a mark is found, moved and reshaped in the window.
final class DrawingTests: XCTestCase {
    private let white = (r: UInt8(255), g: UInt8(255), b: UInt8(255))
    private let blue = (r: UInt8(20), g: UInt8(60), b: UInt8(200))

    private func mark(_ kind: Drawing.Mark.Kind, _ from: CGPoint, _ to: CGPoint,
                      ink: Drawing.Ink = .red, size: Drawing.Size = .medium, text: String = "") -> Drawing.Mark {
        Drawing.Mark(kind: kind, from: from, to: to, ink: ink, size: size, text: text)
    }

    // MARK: The part kept

    func testTheCropIsCountedInPixelsFromTheTop() {
        let crop = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        XCTAssertEqual(Drawing.pixels(of: crop, width: 400, height: 200), CGRect(x: 100, y: 50, width: 200, height: 50))
        // All of it, or more, keeps all of it.
        XCTAssertNil(Drawing.pixels(of: CGRect(x: 0, y: 0, width: 1, height: 1), width: 400, height: 200))
        XCTAssertNil(Drawing.pixels(of: CGRect(x: -0.2, y: -0.1, width: 1.5, height: 1.3), width: 400, height: 200))
    }

    func testTheCopyIsCutToThePartKept() throws {
        // Blue across the top half, white below.
        let picture = try image(width: 400, height: 300) { context in
            context.setFillColor(self.cg(self.blue))
            context.fill(CGRect(x: 0, y: 150, width: 400, height: 150))
        }
        var drawing = Drawing()
        drawing.crop = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        let drawn = try XCTUnwrap(Drawing.render(picture, drawing))
        XCTAssertEqual(drawn.width, 200)
        XCTAssertEqual(drawn.height, 150)
        let pixels = try rgba(drawn)
        XCTAssertEqual(pixel(pixels, drawn, x: 100, row: 75).b, blue.b)
        XCTAssertEqual(pixel(pixels, drawn, x: 199, row: 149).r, blue.r)
    }

    // MARK: Marks

    func testAnArrowIsDrawnInItsInk() throws {
        let picture = try image(width: 800, height: 600)
        let drawing = Drawing(marks: [mark(.arrow, CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5), size: .thick)])
        let drawn = try XCTUnwrap(Drawing.render(picture, drawing))
        let pixels = try rgba(drawn)
        let middle = pixel(pixels, drawn, x: 400, row: 300)
        XCTAssertEqual(middle.r, 255)
        XCTAssertLessThan(middle.g, 80)
        XCTAssertLessThan(middle.b, 80)
        // Away from it the picture is as it was.
        XCTAssertEqual(pixel(pixels, drawn, x: 400, row: 100).g, 255)
    }

    func testACircleIsDrawnRoundWhatItPointsAt() throws {
        let picture = try image(width: 800, height: 600)
        let drawing = Drawing(marks: [mark(.circle, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9), size: .thick)])
        let drawn = try XCTUnwrap(Drawing.render(picture, drawing))
        let pixels = try rgba(drawn)
        // On its line, at the bottom and on the right, in its ink.
        for (x, row) in [(400, 540), (718, 300)] {
            let line = pixel(pixels, drawn, x: x, row: row)
            XCTAssertEqual(line.r, 255)
            XCTAssertLessThan(line.g, 80)
            XCTAssertLessThan(line.b, 80)
        }
        // What it is drawn round, and what lies outside it, are as they were.
        XCTAssertEqual(pixel(pixels, drawn, x: 400, row: 300).g, 255)
        XCTAssertEqual(pixel(pixels, drawn, x: 20, row: 20).g, 255)
    }

    func testAHighlightLeavesTheWordsUnderItAsDarkAsTheyWere() throws {
        // A black word on white paper.
        let picture = try image(width: 400, height: 200) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 100, y: 90, width: 60, height: 20))
        }
        let drawing = Drawing(marks: [mark(.highlight, CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.9, y: 0.7), ink: .yellow)])
        let drawn = try XCTUnwrap(Drawing.render(picture, drawing))
        let pixels = try rgba(drawn)
        let paper = pixel(pixels, drawn, x: 300, row: 100)
        XCTAssertEqual(paper.r, 255)
        XCTAssertLessThan(paper.b, 170)
        XCTAssertGreaterThan(paper.b, 120)
        let word = pixel(pixels, drawn, x: 130, row: 100)
        XCTAssertLessThan(word.r, 4)
        XCTAssertLessThan(word.g, 4)
    }

    func testStepsAreNumberedInTheOrderDrawn() {
        let first = mark(.step, CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.2, y: 0.2))
        let arrow = mark(.arrow, CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.6, y: 0.6))
        let second = mark(.step, CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.7, y: 0.7))
        var drawing = Drawing(marks: [first, arrow, second])
        XCTAssertEqual(drawing.number(of: first), 1)
        XCTAssertEqual(drawing.number(of: second), 2)
        XCTAssertNil(drawing.number(of: arrow))
        // Taking one away numbers the rest again.
        drawing.marks.removeFirst()
        XCTAssertEqual(drawing.number(of: second), 1)
    }

    func testWordsLeftEmptyGo() {
        let words = mark(.text, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5), text: "Hier klicken")
        let empty = mark(.text, CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.2, y: 0.2), text: "  ")
        let box = mark(.box, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4))
        XCTAssertEqual(Drawing(marks: [words, empty, box]).tidied.marks, [words, box])
    }

    func testTheKeyChangesWithTheDrawing() {
        XCTAssertEqual(Drawing().key, "")
        var drawing = Drawing(marks: [mark(.box, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4))])
        let drawn = drawing.key
        XCTAssertFalse(drawn.isEmpty)
        drawing.marks[0].ink = .blue
        XCTAssertNotEqual(drawing.key, drawn)
        let inked = drawing.key
        drawing.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertNotEqual(drawing.key, inked)
    }

    // MARK: In the window

    func testAMarkMovesButStaysOnThePicture() {
        let box = mark(.box, CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.9, y: 0.9))
        let moved = Drawing.moved(box, by: CGVector(dx: 0.5, dy: -0.1))
        XCTAssertEqual(moved.from.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(moved.to.x, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.from.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(moved.to.y, 0.8, accuracy: 0.0001)
    }

    func testABoxIsReshapedFromTheCornerOpposite() {
        let box = mark(.box, CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.2, y: 0.2))
        // The top right corner, dragged up and out.
        let reshaped = Drawing.reshaped(box, handle: 2, to: CGPoint(x: 0.8, y: 0.9))
        XCTAssertEqual(reshaped.rect.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reshaped.rect.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reshaped.rect.width, 0.6, accuracy: 0.0001)
        XCTAssertEqual(reshaped.rect.height, 0.7, accuracy: 0.0001)
        let arrow = mark(.arrow, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(Drawing.reshaped(arrow, handle: 1, to: CGPoint(x: 1.4, y: 0.3)).to, CGPoint(x: 1, y: 0.3))
    }

    func testAMarkIsFoundOnItsLineOrEdge() {
        let size = CGSize(width: 1000, height: 1000)
        let arrow = mark(.arrow, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9))
        let box = mark(.box, CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8))
        XCTAssertTrue(Drawing.hits(arrow, at: CGPoint(x: 500, y: 502), size: size, unit: 1000, slack: 4))
        XCTAssertFalse(Drawing.hits(arrow, at: CGPoint(x: 500, y: 600), size: size, unit: 1000, slack: 4))
        XCTAssertTrue(Drawing.hits(box, at: CGPoint(x: 201, y: 500), size: size, unit: 1000, slack: 4))
        // A box is chosen by its edge, so what is inside it can be drawn on.
        XCTAssertFalse(Drawing.hits(box, at: CGPoint(x: 400, y: 450), size: size, unit: 1000, slack: 4))
        // Where both are, the last drawn is on top.
        let drawing = Drawing(marks: [box, arrow])
        XCTAssertEqual(drawing.mark(at: CGPoint(x: 200, y: 200), size: size, unit: 1000, slack: 4)?.id, arrow.id)
        XCTAssertNil(drawing.mark(at: CGPoint(x: 950, y: 100), size: size, unit: 1000, slack: 4))
    }

    func testACircleIsFoundOnItsLineAndReshapedByItsCorners() throws {
        let size = CGSize(width: 1000, height: 1000)
        let circle = mark(.circle, CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8))
        XCTAssertTrue(Drawing.hits(circle, at: CGPoint(x: 201, y: 500), size: size, unit: 1000, slack: 4))
        XCTAssertTrue(Drawing.hits(circle, at: CGPoint(x: 500, y: 797), size: size, unit: 1000, slack: 4))
        // Inside it stays free to draw on, and so do the box's corners outside it.
        XCTAssertFalse(Drawing.hits(circle, at: CGPoint(x: 500, y: 500), size: size, unit: 1000, slack: 4))
        XCTAssertFalse(Drawing.hits(circle, at: CGPoint(x: 210, y: 210), size: size, unit: 1000, slack: 4))
        XCTAssertEqual(Drawing.handles(of: circle).count, 4)
        let reshaped = Drawing.reshaped(circle, handle: 2, to: CGPoint(x: 0.9, y: 0.6))
        XCTAssertEqual(reshaped.rect.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reshaped.rect.width, 0.7, accuracy: 0.0001)
        XCTAssertEqual(reshaped.rect.height, 0.4, accuracy: 0.0001)
        // Kept with the photo under its own name.
        let kept = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(Drawing(marks: [circle])))
        XCTAssertEqual(kept.marks.first?.kind, .circle)
    }

    func testEveryToolHasAKeyOfItsOwn() {
        let keys = DrawTool.allCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(DrawTool.circle.kind, .circle)
    }

    @MainActor
    func testTheLastToolThatDrawsIsKeptForTheNextTime() {
        let key = "drawTool"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let window = { DrawModel(image: NSImage(size: NSSize(width: 40, height: 30)), pixels: CGSize(width: 40, height: 30),
                                 drawing: .empty, hand: []) }
        XCTAssertEqual(window().tool, .arrow)
        let model = window()
        model.tool = .circle
        XCTAssertEqual(window().tool, .circle)
        // Cropping or choosing is not kept: the next time starts drawing.
        model.tool = .crop
        model.tool = .select
        XCTAssertEqual(window().tool, .circle)
    }

    func testSizesFollowThePicture() {
        // A small screenshot draws as a larger one would, at its scale.
        XCTAssertEqual(Drawing.unit(width: 300, height: 200), 640)
        XCTAssertEqual(Drawing.unit(width: 2880, height: 1800), CGFloat(2880 * 1800).squareRoot(), accuracy: 0.001)
    }

    // MARK: Kept with the photo

    func testADrawingIsKeptAndForgottenWithThePhoto() throws {
        let key = "drawings"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        let url = URL(fileURLWithPath: "/tmp/Snapfly drawing test.png")
        var drawing = Drawing(marks: [mark(.text, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5), text: "Hier")])
        drawing.crop = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        Drawings.set(drawing, for: url)
        XCTAssertEqual(Drawings.saved(url), drawing)
        Drawings.keep(only: [url.path])
        XCTAssertEqual(Drawings.saved(url), drawing)
        Drawings.keep(only: [])
        XCTAssertTrue(Drawings.saved(url).isEmpty)
    }

    func testTheCoveredCopyIsDrawnOnAndCut() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Screenshot.png")
        let screenshot = try image(width: 320, height: 240)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, screenshot, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        var drawing = Drawing(marks: [mark(.box, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4))])
        drawing.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let made = try XCTUnwrap(Cover.covering(url, [], drawing: drawing))
        // Drawing explains; it is never counted as covered.
        XCTAssertTrue(made.report.isEmpty)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(made.url as CFURL, nil))
        let copy = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(copy.width, 160)
        XCTAssertEqual(copy.height, 120)
        // Nothing drawn and nothing to cover makes no copy.
        XCTAssertNil(Cover.covering(url, [], drawing: .empty))
    }

    func testASavedCopyIsNamedAfterTheOriginal() {
        // In the kind the copy is, whatever the original was.
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-10-17 at 14.05.32.png")
        XCTAssertEqual(Line.copyName(for: url, as: "jpg"),
                       String(format: L("%@ (edited)"), "Screenshot 2026-10-17 at 14.05.32") + ".jpg")
    }

    // MARK: Helpers

    private func cg(_ color: (r: UInt8, g: UInt8, b: UInt8)) -> CGColor {
        CGColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1)
    }

    /// White paper, with anything drawn on it, counted from the bottom left.
    private func image(width: Int, height: Int, _ draw: (CGContext) -> Void = { _ in }) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(cg(white))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
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
