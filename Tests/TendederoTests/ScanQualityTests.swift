import XCTest
@testable import Tendedero

/// How well a page reads as it was taken: a sharp page passes, a page
/// blurred at the bottom says so for the bottom, one blurred all over for
/// all of it; a reflection on a dull page is found, white paper is not; a
/// small page is small. The words say where, outside the page.
final class ScanQualityTests: XCTestCase {
    func testASharpPageHasNothingWrong() {
        let page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        XCTAssertEqual(ScanQuality.issues(in: page, dpi: 200), [])
    }

    func testAPageBlurredAtTheBottomSaysSo() throws {
        var page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        page = Self.blurred(page, rows: (page.height * 7 / 10)..<page.height, passes: 3, radius: 2)
        let issues = ScanQuality.issues(in: page, dpi: 200)
        let blur = try XCTUnwrap(issues.first { $0.kind == .blurred })
        XCTAssertEqual(blur.part, .bottom, "\(String(describing: blur.area))")
        XCTAssertEqual(blur.message(in: .color), "At the bottom the text is blurred. Take it again for a clear result.")
        XCTAssertTrue(blur.asksForRetake)
    }

    func testAPageBlurredPastItsEdgesStillSaysSo() throws {
        // So blurred that its print has no edges left, with the camera's grain over it.
        var page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        page = Self.blurred(page, rows: (page.height * 7 / 10)..<page.height, passes: 4, radius: 4)
        page = Self.grained(page, by: 3)
        let blur = try XCTUnwrap(ScanQuality.issues(in: page, dpi: 200).first { $0.kind == .blurred })
        XCTAssertEqual(blur.part, .bottom, "\(String(describing: blur.area))")
    }

    func testASoftShadowIsNotBlur() {
        var page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        // The phone's shadow over the bottom right, darkening softly into its corner.
        for y in 0..<page.height {
            for x in 0..<page.width {
                let into: Int = x + y - page.width / 2 - page.height * 3 / 4
                guard into > 0 else { continue }
                let reach: Float = min(Float(into) / 160, 1)
                let kept: Float = 1 - 0.3 * reach
                let (red, green, blue) = page.color(x: x, y: y)
                page.set(x: x, y: y, Self.dimmed(red, kept), Self.dimmed(green, kept), Self.dimmed(blue, kept))
            }
        }
        page = Self.grained(page, by: 3)
        XCTAssertFalse(ScanQuality.issues(in: page, dpi: 200).contains { $0.kind == .blurred })
    }

    func testAPageBlurredAllOverSaysSoForAllOfIt() throws {
        var page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        page = Self.blurred(page, rows: 0..<page.height, passes: 3, radius: 2)
        let blur = try XCTUnwrap(ScanQuality.issues(in: page, dpi: 200).first { $0.kind == .blurred })
        XCTAssertNil(blur.area)
        XCTAssertEqual(blur.part, .whole)
    }

    func testSharpnessFallsAsTheBlurGrows() {
        let page = ScanPaperFixture.page(width: 1100, printTo: 0.95).bitmap
        var last = Float.infinity
        for passes in [0, 1, 2, 3] {
            let blurred = passes == 0 ? page : Self.blurred(page, rows: 0..<page.height, passes: passes, radius: 1)
            let sharpness = ScanQuality.tiles(of: blurred).tiles.filter(\.hasPrint).map(\.sharpness).sorted()
            let middle = sharpness[sharpness.count / 2]
            XCTAssertLessThan(middle, last, "\(passes) passes")
            last = middle
        }
    }

    func testAReflectionOnADullPageIsFoundAndWhitePaperIsNot() throws {
        var page = ScanBitmap(width: 1000, height: 1400, red: 205, green: 200, blue: 190)
        // A bright patch, white out, at the top right.
        for y in 150..<420 { for x in 600..<900 { page.set(x: x, y: y, 255, 255, 255) } }
        let glare = try XCTUnwrap(ScanQuality.issues(in: page, dpi: 200).first { $0.kind == .glare })
        XCTAssertEqual(glare.part, .top)
        let area = try XCTUnwrap(glare.area)
        XCTAssertGreaterThan(area.minX, 0.5)
        let white = ScanBitmap(width: 1000, height: 1400, red: 254, green: 254, blue: 254)
        XCTAssertFalse(ScanQuality.issues(in: white, dpi: 200).contains { $0.kind == .glare })
    }

    func testASmallPageIsSmall() {
        let page = ScanBitmap(width: 600, height: 848, red: 250, green: 250, blue: 250)
        XCTAssertEqual(ScanQuality.issues(in: page, dpi: 90).map(\.kind), [.small])
        XCTAssertEqual(ScanQuality.issues(in: page, dpi: 150), [])
    }

    func testThePartOfThePageIsItsMiddlesThird() {
        XCTAssertEqual(ScanIssue(.blurred, area: CGRect(x: 0, y: 0.75, width: 1, height: 0.2)).part, .top)
        XCTAssertEqual(ScanIssue(.blurred, area: CGRect(x: 0, y: 0.4, width: 1, height: 0.2)).part, .middle)
        XCTAssertEqual(ScanIssue(.blurred, area: CGRect(x: 0, y: 0, width: 1, height: 0.3)).part, .bottom)
        XCTAssertEqual(ScanIssue(.blurred, area: CGRect(x: 0, y: 0.1, width: 1, height: 0.8)).part, .whole)
        XCTAssertEqual(ScanIssue(.smudge).part, .whole)
    }

    func testTheMostImportantComesFirst() {
        let issues = [ScanIssue(.small), ScanIssue(.blurred), ScanIssue(.lessText, area: .zero), ScanIssue(.glare)]
        XCTAssertEqual(ScanIssue.ordered(issues).map(\.kind), [.lessText, .glare, .blurred, .small])
    }

    func testLessTextSaysWhatToDoInEachLook() {
        let issue = ScanIssue(.lessText, area: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05))
        XCTAssertFalse(issue.asksForRetake)
        XCTAssertNotEqual(issue.message(in: .blackAndWhite), issue.message(in: .color))
        XCTAssertEqual(issue.message(in: .gray), issue.message(in: .color))
    }

    /// The page with a camera's grain: each channel up to `amount` lighter or darker.
    static func grained(_ page: ScanBitmap, by amount: Int) -> ScanBitmap {
        var out = page
        var seed: UInt32 = 5
        let spread: Int = 2 * amount + 1
        for i in 0..<out.pixels.count where i % 4 != 3 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let high: UInt32 = seed >> 16
            let shift: Int = Int(high) % spread - amount
            let value: Int = Int(out.pixels[i]) + shift
            let kept: Int = min(max(value, 0), 255)
            out.pixels[i] = UInt8(kept)
        }
        return out
    }

    /// A channel darkened to `share` of itself.
    static func dimmed(_ value: UInt8, _ share: Float) -> UInt8 {
        let darker: Float = Float(value) * share
        return UInt8(darker)
    }

    /// The rows given blurred: brightness boxed `passes` times, in grey.
    static func blurred(_ page: ScanBitmap, rows: Range<Int>, passes: Int, radius: Int) -> ScanBitmap {
        var plane = page.brightness
        for _ in 0..<passes { plane = ScanClean.blurred(plane, width: page.width, height: page.height, radius: radius) }
        var out = page
        for y in rows {
            for x in 0..<page.width {
                let value = plane[y * page.width + x]
                out.set(x: x, y: y, value, value, value)
            }
        }
        return out
    }
}
