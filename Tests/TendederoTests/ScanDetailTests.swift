import XCTest
@testable import Tendedero

/// Small print taken again close up and laid onto its page (`ScanDetail`):
/// a made-up page whose small print came out soft, and a close-up of it 2.4
/// times as large, turned by 0.6° and lit a little darker. The close-up is
/// found on the page to well under a pixel, laid in, and the small print is
/// then closer to the printed page; a close-up of something else is not laid
/// at all. Drawn in shapes, so it is checked on any machine.
final class ScanDetailTests: XCTestCase {
    static let width = 480, height = 360
    static let area = CGRect(x: 150, y: 120, width: 140, height: 110)
    /// How the close-up was taken: a page pixel at p falls at
    /// scale · turn(angle) · (p − the small print's middle) + (dx, dy).
    static let truth = ScanDetail.Placement(scale: 2.4, angle: 0.6 * .pi / 180, dx: 214.3, dy: 161.7, match: 1)

    /// The page's ink at a point, from 0 (paper) to 1 (ink): rows of small
    /// letters of a few shapes, each letter's shape and width as a hash of
    /// its place picks them, so no two stretches of a line are alike, as in
    /// real text.
    static func ink(_ x: Double, _ y: Double) -> Double {
        let row = Int(((y - 30) / 26).rounded(.down))
        guard row >= 0, row < 12, x > 30, x < 450 else { return 0 }
        let inRow = y - 30 - Double(row) * 26
        guard inRow >= 0, inRow < 14 else { return 0 }
        // The letters of the row, each 6 to 11 pixels wide, a space now and then.
        var start = 30.0, n = 0
        var hash: UInt64 = 0
        while true {
            hash = UInt64(row * 1000 + n) &* 0x9E3779B97F4A7C15
            hash ^= hash >> 29
            let wide = 6 + Double(hash % 6)
            if x < start + wide { break }
            start += wide
            n += 1
        }
        let inLetter = x - start, shape = (hash >> 8) % 8
        guard shape != 7 else { return 0 }
        let stem = inLetter >= 1 && inLetter < 2.6
        let second = shape % 2 == 0 && inLetter >= 4 && inLetter < 5.6 && inRow >= 4
        let bar = shape % 3 == 0 && inRow >= 6 && inRow < 7.6 && inLetter < 5.5
        let top = shape == 4 && inRow < 1.6 && inLetter < 5
        let dot = shape == 5 && inRow < 2 && inLetter >= 3.5 && inLetter < 5.3
        let tall = shape == 1 || inRow >= 4
        return (stem && tall) || second || bar || top || dot ? 1 : 0
    }

    /// The page as the camera took it from afar: the small print soft (a
    /// Gaussian of `focus` pixels), with grain; or as printed.
    static func page(focus: Double = 1.6, grain: Double = 4, seed: UInt64 = 7) -> ScanBitmap {
        let w = width, h = height
        var values = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for sy in 0..<4 {
                    for sx in 0..<4 { sum += ink(Double(x) + (Double(sx) + 0.5) / 4, Double(y) + (Double(sy) + 0.5) / 4) }
                }
                values[y * w + x] = 232 - 132 * sum / 16
            }
        }
        values = ScanBurstTests.softened(values, width: w, height: h, sigma: focus)
        var seed = seed
        var bitmap = ScanBitmap(width: w, height: h, red: 255, green: 255, blue: 255)
        for i in 0..<(w * h) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = (Double((seed >> 11) & 0xFFFF) / Double(0xFFFF) - 0.5) * 2 * grain
            let v = UInt8(min(255, max(0, (values[i] + noise).rounded())))
            bitmap.pixels[i * 4] = v
            bitmap.pixels[i * 4 + 1] = v
            bitmap.pixels[i * 4 + 2] = v
        }
        return bitmap
    }

    /// The close-up, `size` pixels, of the page laid as `placement` says,
    /// sharp, its paper and ink a little darker, with grain; `ink` the page
    /// it shows.
    static func detail(_ placement: ScanDetail.Placement = truth, width w: Int = 440, height h: Int = 330,
                       ink: (Double, Double) -> Double = ScanDetailTests.ink, seed: UInt64 = 11) -> ScanBitmap {
        let centre = (x: Double(area.midX), y: Double(area.midY))
        let c = cos(-placement.angle) / placement.scale, s = sin(-placement.angle) / placement.scale
        var values = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let qx = Double(x) + (Double(sx) + 0.5) / 4 - 0.5 - placement.dx
                        let qy = Double(y) + (Double(sy) + 0.5) / 4 - 0.5 - placement.dy
                        // The page's pixel centres are at whole numbers; its ink is drawn from their corners.
                        sum += ink(centre.x + c * qx - s * qy + 0.5, centre.y + s * qx + c * qy + 0.5)
                    }
                }
                values[y * w + x] = 220 - 130 * sum / 16
            }
        }
        values = ScanBurstTests.softened(values, width: w, height: h, sigma: 0.9)
        var seed = seed
        var bitmap = ScanBitmap(width: w, height: h, red: 255, green: 255, blue: 255)
        for i in 0..<(w * h) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = (Double((seed >> 11) & 0xFFFF) / Double(0xFFFF) - 0.5) * 8
            let v = UInt8(min(255, max(0, (values[i] + noise).rounded())))
            bitmap.pixels[i * 4] = v
            bitmap.pixels[i * 4 + 1] = v
            bitmap.pixels[i * 4 + 2] = v
        }
        return bitmap
    }

    /// How far apart two placements put the small print's corners and
    /// middle, at most, in the page's pixels.
    static func apart(_ a: ScanDetail.Placement, _ b: ScanDetail.Placement) -> Double {
        let centre = (x: Double(area.midX), y: Double(area.midY))
        let corners = [(area.minX, area.minY), (area.maxX, area.minY), (area.minX, area.maxY),
                       (area.maxX, area.maxY), (area.midX, area.midY)]
        return corners.map { corner in
            let p = a.detailPoint(Double(corner.0), Double(corner.1), centre: centre)
            let q = b.detailPoint(Double(corner.0), Double(corner.1), centre: centre)
            return hypot(p.x - q.x, p.y - q.y) / b.scale
        }.max() ?? .infinity
    }

    /// How far the small print is from the page as printed, the root mean
    /// square inside its place.
    static func error(_ page: ScanBitmap, against printed: ScanBitmap) -> Double {
        var sum = 0.0, n = 0.0
        let inner = area.insetBy(dx: 16, dy: 16)
        for y in Int(inner.minY)..<Int(inner.maxY) {
            for x in Int(inner.minX)..<Int(inner.maxX) {
                let gap = Double(page.brightness(x: x, y: y)) - Double(printed.brightness(x: x, y: y))
                sum += gap * gap
                n += 1
            }
        }
        return (sum / n).squareRoot()
    }

    /// How steep the small print's edges are where the printed page's are
    /// steepest, its steepest twentieth inside the small print's place.
    static func steepness(_ page: ScanBitmap, against printed: ScanBitmap) -> Double {
        func turn(_ bitmap: ScanBitmap, _ x: Int, _ y: Int) -> Double {
            let across = Double(bitmap.brightness(x: x + 1, y: y)) - Double(bitmap.brightness(x: x - 1, y: y))
            let down = Double(bitmap.brightness(x: x, y: y + 1)) - Double(bitmap.brightness(x: x, y: y - 1))
            return (across * across + down * down).squareRoot()
        }
        let inner = area.insetBy(dx: 16, dy: 16)
        var places: [(turn: Double, x: Int, y: Int)] = []
        for y in Int(inner.minY)..<Int(inner.maxY) {
            for x in Int(inner.minX)..<Int(inner.maxX) { places.append((turn(printed, x, y), x, y)) }
        }
        places.sort { $0.turn > $1.turn }
        let steepest = places.prefix(places.count / 20)
        return steepest.reduce(0) { $0 + turn(page, $1.x, $1.y) } / Double(steepest.count)
    }

    func testTheCloseUpIsFoundToWellUnderAPixel() throws {
        let page = Self.page(), detail = Self.detail()
        let found = try XCTUnwrap(ScanDetail.placement(of: detail.brightness, width: detail.width, height: detail.height,
                                                       onto: page.brightness, width: page.width, height: page.height,
                                                       around: Self.area))
        let off = Self.apart(found, Self.truth)
        print(String(format: "DETAIL found scale %.4f angle %.3f° at %.2f %.2f, match %.3f; off by %.3f px",
                     found.scale, found.angle * 180 / .pi, found.dx, found.dy, found.match, off))
        XCTAssertLessThanOrEqual(off, 1, "within a pixel at the page's size")
        XCTAssertEqual(found.scale, Self.truth.scale, accuracy: 0.02)
    }

    func testTheSmallPrintLaidIsCloserToThePrintedPage() throws {
        let page = Self.page(), detail = Self.detail()
        let laid = try XCTUnwrap(ScanDetail.laid(detail, onto: page, around: Self.area))
        let printed = Self.page(focus: 0.8, grain: 0)
        let before = Self.error(page, against: printed), after = Self.error(laid.page, against: printed)
        let soft = Self.steepness(page, against: printed), sharp = Self.steepness(laid.page, against: printed)
        let asPrinted = Self.steepness(printed, against: printed)
        print(String(format: "DETAIL inside the small print: error before %.2f, laid %.2f; steepness before %.1f, laid %.1f, printed %.1f",
                     before, after, soft, sharp, asPrinted))
        XCTAssertLessThan(after, before * 0.9, "closer to the printed page")
        XCTAssertGreaterThan(sharp, soft * 1.3, "sharper")
        // Outside the small print's place the page is as it was.
        XCTAssertEqual(laid.page.color(x: 40, y: 40).red, page.color(x: 40, y: 40).red)
    }

    func testACloseUpOfSomethingElseIsNotLaid() {
        let page = Self.page()
        // The page's print mirrored and moved: other letters in other places.
        let other = Self.detail(ink: { x, y in ScanDetailTests.ink(480 - x, 400 - y) })
        XCTAssertNil(ScanDetail.laid(other, onto: page, around: Self.area))
    }

    func testItIsKeptOnlyWhereTheSmallPrintReadsMoreSurely() {
        let area = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.3)
        func line(_ text: String, _ y: Double, _ confidence: Float) -> ScanReadability.Line {
            ScanReadability.Line(text: text, box: CGRect(x: 0.25, y: y, width: 0.5, height: 0.02), confidence: confidence)
        }
        let before = [line("Musterstraße 12, 12345 Beispielstadt", 0.3, 0.6), line("Telefon 0123 456789", 0.35, 0.7)]
        let sharper = [line("Musterstraße 12, 12345 Beispielstadt", 0.3, 0.95), line("Telefon 0123 456789", 0.35, 0.9)]
        let lost = [line("Musterstraße 12, 12345 Beispielstadt", 0.3, 0.95)]
        let same = [line("Musterstraße 12, 12345 Beispielstadt", 0.3, 0.6), line("Telefon 0123 456789", 0.35, 0.71)]
        XCTAssertTrue(ScanDetail.better(before: before, after: sharper, area: area))
        XCTAssertFalse(ScanDetail.better(before: before, after: lost, area: area), "a line no longer read")
        XCTAssertFalse(ScanDetail.better(before: before, after: same, area: area), "no surer")
    }
}
