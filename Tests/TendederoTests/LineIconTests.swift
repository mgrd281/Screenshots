import AppKit
import XCTest
@testable import Tendedero

/// The mark in the menu bar is a template at menu bar size, and its filled
/// form covers clearly more than the outline.
final class LineIconTests: XCTestCase {
    func testTemplateAtMenuBarSize() {
        let icon = LineIcon.image(filled: false, description: "Snapfly")
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(icon.accessibilityDescription, "Snapfly")
    }

    func testFilledCoversMoreThanTheOutline() {
        let outline = inked(LineIcon.image(filled: false, description: ""))
        let filled = inked(LineIcon.image(filled: true, description: ""))
        XCTAssertGreaterThan(outline, 0)
        XCTAssertGreaterThan(Double(filled), Double(outline) * 1.2)
    }

    /// Counts the pixels the icon covers, drawn at twice its size.
    private func inked(_ image: NSImage) -> Int {
        let side = 36
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var count = 0
        for x in 0..<side {
            for y in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
        }
        return count
    }
}
