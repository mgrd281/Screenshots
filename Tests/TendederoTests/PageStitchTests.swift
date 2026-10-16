import XCTest
@testable import Tendedero

/// Joining the views of a scrolled page: what stays put, how far the page
/// moved, and which rows make the whole page.
final class PageStitchTests: XCTestCase {
    /// A row of a long page, different from its neighbours.
    private func pageRow(_ i: Int) -> [UInt8] {
        (0..<PageStitch.samples).map { UInt8((i * 131 + $0 * 17) % 200) }
    }

    /// A row of the toolbar, the same in every view.
    private func barRow(_ i: Int) -> [UInt8] {
        (0..<PageStitch.samples).map { UInt8(210 + (i * 7 + $0) % 40) }
    }

    /// What the window shows with the page scrolled this far: a toolbar,
    /// then the page.
    private func view(at offset: Int, bar: Int = 30, height: Int = 400) -> PageStitch.Rows {
        (0..<bar).map(barRow) + (0..<(height - bar)).map { pageRow(offset + $0) }
    }

    func testFindsHowFarThePageMoved() throws {
        let step = try XCTUnwrap(PageStitch.step(from: view(at: 0), to: view(at: 290), expected: 300))
        XCTAssertEqual(step.top, 30)
        XCTAssertEqual(step.bottom, 0)
        XCTAssertEqual(step.shift, 290)
    }

    func testTheEndOfThePageMovesNothing() {
        XCTAssertEqual(PageStitch.step(from: view(at: 500), to: view(at: 500), expected: 300)?.shift, 0)
    }

    func testAPageThatChangedByItselfDoesNotFit() {
        let other = (0..<400).map { i in (0..<PageStitch.samples).map { UInt8((i * 53 + $0 * 29 + 11) % 197) } }
        XCTAssertNil(PageStitch.step(from: view(at: 0), to: other, expected: 300))
    }

    func testPlainStretchFollowsTheScroll() throws {
        // Some text, then a long blank stretch, which lines up at any move:
        // the one asked for wins.
        let blank = [UInt8](repeating: 250, count: PageStitch.samples)
        let page = (0..<50).map(pageRow) + Array(repeating: blank, count: 950)
        let window = { (offset: Int) in (0..<30).map(self.barRow) + page[offset..<(offset + 370)] }
        let step = try XCTUnwrap(PageStitch.step(from: window(0), to: window(120), expected: 120))
        XCTAssertEqual(step.top, 30)
        XCTAssertEqual(step.shift, 120)
    }

    func testSlicesKeepTheToolbarOnce() {
        let steps = [PageStitch.Step(top: 30, bottom: 0, shift: 290), PageStitch.Step(top: 30, bottom: 0, shift: 100),
                     PageStitch.Step(top: 0, bottom: 0, shift: 0)]
        let slices = PageStitch.slices(height: 400, steps: steps)
        XCTAssertEqual(slices.map(\.view), [0, 1, 2])
        XCTAssertEqual(slices.map(\.rows), [0..<400, 110..<400, 300..<400])
        // The toolbar, then the page from its top to row 370 + 290 + 100.
        XCTAssertEqual(slices.reduce(0) { $0 + $1.rows.count }, 400 + 290 + 100)
    }

    func testSlicesKeepABottomBarAtTheEnd() {
        let steps = [PageStitch.Step(top: 30, bottom: 20, shift: 200)]
        let slices = PageStitch.slices(height: 400, steps: steps)
        XCTAssertEqual(slices.map(\.rows), [0..<380, 180..<380, 380..<400])
    }

    func testOneViewIsTheWholePicture() {
        XCTAssertEqual(PageStitch.slices(height: 400, steps: []).map(\.rows), [0..<400])
    }

    func testComposeStacksTheRows() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 10))
        let image = try XCTUnwrap(context.makeImage())
        let joined = try XCTUnwrap(PageStitch.compose([image, image], steps: [.init(top: 2, bottom: 0, shift: 6)]))
        XCTAssertEqual(joined.height, 16)
        XCTAssertEqual(joined.width, 4)
    }
}
