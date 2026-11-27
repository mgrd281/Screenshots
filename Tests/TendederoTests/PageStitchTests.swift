import XCTest
@testable import Tendedero

/// Joining the views of a scrolled page: what stays put, how far the page
/// moved, and which rows make the whole page.
final class PageStitchTests: XCTestCase {
    /// A row of a long page, different from its neighbours.
    private func pageRow(_ i: Int) -> [UInt8] {
        row { j in (i * 131 + j * 17) % 200 }
    }

    private func row(_ value: (Int) -> Int) -> [UInt8] {
        var row: [UInt8] = []
        for j in 0..<PageStitch.samples { row.append(UInt8(value(j))) }
        return row
    }

    /// A row of the toolbar, the same in every view.
    private func barRow(_ i: Int) -> [UInt8] {
        row { j in 210 + (i * 7 + j) % 40 }
    }

    /// What the window shows with the page scrolled this far: a toolbar,
    /// then the page.
    private func view(at offset: Int, bar: Int = 30, height: Int = 400) -> PageStitch.Rows {
        let bars: PageStitch.Rows = (0..<bar).map(barRow)
        let rows: PageStitch.Rows = (0..<(height - bar)).map { pageRow(offset + $0) }
        return bars + rows
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
        var other: PageStitch.Rows = []
        for i in 0..<400 { other.append(row { j in (i * 53 + j * 29 + 11) % 197 }) }
        XCTAssertNil(PageStitch.step(from: view(at: 0), to: other, expected: 300))
    }

    func testPlainStretchFollowsTheScroll() throws {
        // Some text, then a long blank stretch, which lines up at any move:
        // the one asked for wins.
        let blank = [UInt8](repeating: 250, count: PageStitch.samples)
        let text: PageStitch.Rows = (0..<50).map(pageRow)
        let page: PageStitch.Rows = text + Array(repeating: blank, count: 950)
        let bars: PageStitch.Rows = (0..<30).map(barRow)
        let window: (Int) -> PageStitch.Rows = { offset in bars + Array(page[offset..<(offset + 370)]) }
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
        XCTAssertEqual(slices.map(\.rows), [0..<380, 180..<400])
    }

    func testEachSeamLeavesTheFreshRowsToTheNextView() {
        // The views share 370 - 200 = 170 rows: at most half go to the next.
        let steps = [PageStitch.Step(top: 30, bottom: 0, shift: 200), PageStitch.Step(top: 30, bottom: 0, shift: 300)]
        XCTAssertEqual(PageStitch.seam(after: steps[0], height: 400, fresh: 60), 340)
        XCTAssertEqual(PageStitch.seam(after: steps[0], height: 400, fresh: 500), 315)
        let slices = PageStitch.slices(height: 400, steps: steps, fresh: 60)
        XCTAssertEqual(slices.map(\.view), [0, 1, 2])
        XCTAssertEqual(slices.map(\.rows), [0..<340, 140..<365, 65..<400])
        // Nothing twice, nothing left out: the page from its top to row 370 + 500.
        XCTAssertEqual(slices.reduce(0) { $0 + $1.rows.count }, 400 + 200 + 300)
    }

    func testAMoveIsFoundPastFreshRowsThatChanged() throws {
        // The lowest rows of the view before were still loading.
        var before = view(at: 0)
        for i in 330..<400 { before[i] = [UInt8](repeating: 200, count: PageStitch.samples) }
        XCTAssertNil(PageStitch.step(from: before, to: view(at: 150), expected: 150))
        let step = try XCTUnwrap(PageStitch.step(from: before, to: view(at: 150), expected: 150, fresh: 70))
        XCTAssertEqual(step.shift, 150)
    }

    func testAMoveIsFollowedPastAColumnThatStays() throws {
        // The left third of the window stays put while the rest scrolls.
        func window(_ offset: Int) -> PageStitch.Rows {
            var rows = view(at: offset)
            for i in 30..<rows.count {
                for j in 0..<16 { rows[i][j] = UInt8((i * 37 + j * 11) % 200) }
            }
            return rows
        }
        XCTAssertNil(PageStitch.step(from: window(0), to: window(130), expected: 130))
        let step = try XCTUnwrap(PageStitch.follow(from: window(0), to: window(130), expected: 130))
        XCTAssertEqual(step.top, 30)
        XCTAssertEqual(step.shift, 130)
    }

    func testFollowFindsNoMoveOnAPageThatChangedByItself() {
        var other: PageStitch.Rows = []
        for i in 0..<400 { other.append(row { j in (i * 53 + j * 29 + 11) % 197 }) }
        XCTAssertNil(PageStitch.follow(from: view(at: 0), to: other, expected: 300))
    }

    func testOneViewIsTheWholePicture() {
        XCTAssertEqual(PageStitch.slices(height: 400, steps: []).map(\.rows), [0..<400])
    }

    func testTwoViewsOfTheSamePlaceAreAlikeDespiteAFewMovingRows() {
        var moving = view(at: 100)
        // A carousel of twenty rows changes by itself.
        for i in 200..<220 { moving[i] = pageRow(5000 + i) }
        XCTAssertTrue(PageStitch.alike(view(at: 100), moving))
        XCTAssertFalse(PageStitch.alike(view(at: 100), view(at: 150)))
        XCTAssertFalse(PageStitch.alike(view(at: 100), []))
    }

    func testStripsStackIntoTheWholePage() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 10))
        let image = try XCTUnwrap(context.makeImage())
        let top = try XCTUnwrap(PageStitch.strip(of: image, rows: 0..<8))
        let rest = try XCTUnwrap(PageStitch.strip(of: image, rows: 2..<10))
        XCTAssertEqual(top.height, 8)
        XCTAssertNil(PageStitch.strip(of: image, rows: 10..<12))
        let joined = try XCTUnwrap(PageStitch.stack([top, rest]))
        XCTAssertEqual(joined.height, 16)
        XCTAssertEqual(joined.width, 4)
    }
}
