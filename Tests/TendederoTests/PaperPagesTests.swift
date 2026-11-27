import XCTest
@testable import Tendedero

/// A whole page on sheets of paper for Make PDF: how large it is drawn,
/// how many rows fill a sheet, and where they are cut.
final class PaperPagesTests: XCTestCase {
    func testASheetOfA4HoldsWhatFitsItsShape() {
        // 2880 pixels across 538.58 points: 4198 rows down 785.19 points.
        XCTAssertEqual(PaperPages.rowsPerPage(width: 2880, paper: PaperSize.a4Size), 4198)
        XCTAssertEqual(PaperPages.rowsPerPage(width: 1440, paper: PaperSize.letterSize), 1906)
        XCTAssertEqual(PaperPages.room(on: PaperSize.a4Size).minX, PaperSize.margin, accuracy: 0.001)
    }

    func testANarrowPictureIsNotBlownUp() {
        // A window 400 pixels wide stays a point a pixel, in the middle.
        XCTAssertEqual(PaperPages.scale(width: 400, paper: PaperSize.a4Size), 1)
        XCTAssertEqual(PaperPages.rowsPerPage(width: 400, paper: PaperSize.a4Size), 785)
        XCTAssertEqual(PaperPages.scale(width: 2880, paper: PaperSize.a4Size), 538.58 / 2880, accuracy: 0.0001)
    }

    func testEveryRowIsOnExactlyOneSheet() {
        let quiet = (0..<10_000).map { $0 % 37 == 0 }
        let pages = PaperPages.cuts(quiet: quiet, perPage: 1000)
        XCTAssertEqual(pages.first?.lowerBound, 0)
        XCTAssertEqual(pages.last?.upperBound, 10_000)
        for (a, b) in zip(pages, pages.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        XCTAssertTrue(pages.allSatisfy { $0.count <= 1000 && !$0.isEmpty })
    }

    func testASheetEndsBetweenTwoLines() {
        // Text everywhere but a gap at rows 930 to 940.
        var quiet = [Bool](repeating: false, count: 3000)
        for r in 930..<940 { quiet[r] = true }
        let pages = PaperPages.cuts(quiet: quiet, perPage: 1000)
        XCTAssertEqual(pages.first, 0..<939)
        // No gap in the last fifth of the next sheets: they are full.
        XCTAssertEqual(Array(pages.dropFirst()), [939..<1939, 1939..<2939, 2939..<3000])
    }

    func testAShortPictureIsOneSheet() {
        XCTAssertEqual(PaperPages.cuts(quiet: [Bool](repeating: false, count: 500), perPage: 1000), [0..<500])
        XCTAssertEqual(PaperPages.cuts(quiet: [], perPage: 1000), [])
    }

    func testOnlyRowsLikeTheirNeighboursAreQuiet() {
        let blank = [UInt8](repeating: 250, count: 8)
        let text: [UInt8] = [250, 30, 250, 40, 250, 250, 20, 250]
        let rows = [blank, blank, text, text.map { $0 == 250 ? 250 : $0 + 30 }, blank, blank, blank]
        XCTAssertEqual(PaperPages.quiet(rows), [true, false, false, false, false, true, true])
    }
}
