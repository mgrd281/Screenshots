import XCTest
@testable import Tendedero

/// Several photos of one page merged into one (`ScanBurst`): a made-up page
/// of small print, taken four times by a hand that moves a little between
/// frames, each with the camera's grain, one blurred by a shake, one with a
/// reflection passing over. Laid over each other to a fraction of a pixel,
/// the shaken frame left out, the merged page is quieter than the sharpest
/// frame and as sharp, and the reflection is gone. Drawn in shapes, so it is
/// checked on any machine.
final class ScanBurstTests: XCTestCase {
    /// How a frame was taken: where the page lay, a shake, a reflection, the grain.
    struct Take {
        var dx = 0.0
        var dy = 0.0
        var angle = 0.0
        var shake = 0
        /// The lens's softness, a Gaussian of this many pixels; more is out of focus.
        var focus = 0.8
        var reflection = false
        var grain = 5.0
        var seed: UInt64 = 1
    }

    static let width = 480, height = 360

    /// The page's ink at a point, from 0 (paper) to 1 (ink): rows of small
    /// letters, stems and bars, as a column of 7 pt print is at 300 dpi.
    static func ink(_ x: Double, _ y: Double) -> Double {
        let row = Int((y - 30) / 26)
        guard row >= 0, row < 12, x > 30, x < 450 else { return 0 }
        let top = 30 + Double(row) * 26, inRow = y - top
        guard inRow >= 0, inRow < 14 else { return 0 }
        let letter = Int((x - 30) / 9), inLetter = x - 30 - Double(letter) * 9
        guard (letter + row) % 7 != 6 else { return 0 }
        let stem = inLetter >= 1 && inLetter < 2.6
        let bar = (letter % 3 == 0) && inRow >= 6 && inRow < 7.6 && inLetter < 6.5
        let dot = (letter % 4 == 1) && inRow < 2 && inLetter >= 4 && inLetter < 5.8
        return stem || bar || dot ? 1 : 0
    }

    /// A frame as the camera takes it: each pixel the page's ink averaged
    /// over a 4 × 4 grid inside it, the page laid as `take` says; softened
    /// as a lens does, by a Gaussian of `focus` pixels; then the shake, the
    /// reflection and the grain.
    static func frame(_ take: Take) -> ScanBitmap {
        let w = width, h = height
        let cx = Double(w) / 2, cy = Double(h) / 2
        let cosine = cos(take.angle), sine = sin(take.angle)
        var values = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        // The frame's pixel, where it falls on the page.
                        let fx = Double(x) + (Double(sx) + 0.5) / 4 - take.dx - cx
                        let fy = Double(y) + (Double(sy) + 0.5) / 4 - take.dy - cy
                        let px = cx + cosine * fx + sine * fy, py = cy - sine * fx + cosine * fy
                        sum += ink(px, py)
                    }
                }
                values[y * w + x] = 232 - 132 * sum / 16
            }
        }
        values = Self.softened(values, width: w, height: h, sigma: take.focus)
        if take.shake > 0 {
            var shaken = values
            for y in 0..<h {
                for x in 0..<w {
                    var sum = 0.0, n = 0.0
                    for s in -take.shake...take.shake where x + s >= 0 && x + s < w {
                        sum += values[y * w + x + s]
                        n += 1
                    }
                    shaken[y * w + x] = sum / n
                }
            }
            values = shaken
        }
        var seed = take.seed
        func gaussian() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u1 = Double((seed >> 11) & 0xFFFFF) / Double(0x100000) + 1e-9
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u2 = Double((seed >> 11) & 0xFFFFF) / Double(0x100000)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        var bitmap = ScanBitmap(width: w, height: h, red: 255, green: 255, blue: 255)
        for y in 0..<h {
            for x in 0..<w {
                var value = values[y * w + x]
                if take.reflection {
                    let d = hypot(Double(x) - 300, Double(y) - 150)
                    value += max(0, 120 * (1 - d / 60))
                }
                value += take.grain * gaussian()
                let v = UInt8(min(255, max(0, value.rounded())))
                let i = (y * w + x) * 4
                bitmap.pixels[i] = v
                bitmap.pixels[i + 1] = v
                bitmap.pixels[i + 2] = v
            }
        }
        return bitmap
    }

    /// How steep a page's edges are where the printed page's are steepest,
    /// its steepest twentieth: the mean of the turn across and down there.
    static func steepness(_ page: ScanBitmap, against take: Take) -> Double {
        var clean = take
        clean.grain = 0
        clean.shake = 0
        clean.reflection = false
        let truth = frame(clean)
        func turn(_ bitmap: ScanBitmap, _ x: Int, _ y: Int) -> Double {
            let across = Double(bitmap.brightness(x: x + 1, y: y)) - Double(bitmap.brightness(x: x - 1, y: y))
            let down = Double(bitmap.brightness(x: x, y: y + 1)) - Double(bitmap.brightness(x: x, y: y - 1))
            return (across * across + down * down).squareRoot()
        }
        var places: [(turn: Double, x: Int, y: Int)] = []
        for y in 20..<(height - 20) {
            for x in 20..<(width - 20) { places.append((turn(truth, x, y), x, y)) }
        }
        places.sort { $0.turn > $1.turn }
        let steepest = places.prefix(places.count / 20)
        return steepest.reduce(0) { $0 + turn(page, $1.x, $1.y) } / Double(steepest.count)
    }

    /// Each value the mean of its neighbours, weighted by a Gaussian of
    /// `sigma` pixels, across then down.
    static func softened(_ values: [Double], width w: Int, height h: Int, sigma: Double) -> [Double] {
        let reach = Int((sigma * 3).rounded(.up))
        let kernel = (-reach...reach).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        var across = values, out = values
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for k in -reach...reach { sum += values[y * w + min(w - 1, max(0, x + k))] * kernel[k + reach] }
                across[y * w + x] = sum / total
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for k in -reach...reach { sum += across[min(h - 1, max(0, y + k)) * w + x] * kernel[k + reach] }
                out[y * w + x] = sum / total
            }
        }
        return out
    }

    /// How far a page is from the page as printed, laid as `take` says,
    /// without grain: the root mean square, away from the edges.
    static func error(_ page: ScanBitmap, against take: Take) -> Double {
        var clean = take
        clean.grain = 0
        clean.shake = 0
        clean.reflection = false
        let truth = frame(clean)
        var sum = 0.0, n = 0.0
        for y in 20..<(height - 20) {
            for x in 20..<(width - 20) {
                let gap = Double(page.brightness(x: x, y: y)) - Double(truth.brightness(x: x, y: y))
                sum += gap * gap
                n += 1
            }
        }
        return (sum / n).squareRoot()
    }

    private let takes = [
        Take(dx: 0, dy: 0, angle: 0, seed: 1),
        Take(dx: 3.4, dy: -2.3, angle: 0.004, seed: 2),
        Take(dx: -2.6, dy: 1.7, angle: -0.003, seed: 3),
        Take(dx: 1.2, dy: 3.1, angle: 0.002, seed: 4),
    ]

    func testFramesAreLaidOverEachOtherToAFractionOfAPixel() {
        let reference = Self.frame(takes[0])
        let points = ScanBurst.edgePoints(reference.brightness, width: Self.width, height: Self.height, tuning: .init())
        for take in takes.dropFirst() {
            let placement = ScanBurst.placement(of: Self.frame(take).brightness, onto: reference.brightness,
                                                width: Self.width, height: Self.height, points: points, tuning: .init())
            XCTAssertEqual(placement.dx, take.dx, accuracy: 0.25, "across")
            XCTAssertEqual(placement.dy, take.dy, accuracy: 0.25, "down")
            XCTAssertEqual(placement.angle, take.angle, accuracy: 0.001, "turned")
        }
    }

    func testTheMergedPageIsQuieterThanTheSharpestFrameAndAsSharp() throws {
        let frames = takes.map(Self.frame)
        let merged = try XCTUnwrap(ScanBurst.merged(frames))
        let reference = takes[merged.reference]
        let single = Self.error(frames[merged.reference], against: reference)
        let together = Self.error(merged.page, against: reference)
        let sharpSingle = Self.steepness(frames[merged.reference], against: reference)
        let sharpTogether = Self.steepness(merged.page, against: reference)
        var printed = reference
        printed.grain = 0
        let sharpPrinted = Self.steepness(Self.frame(printed), against: reference)
        print("BURST steepness as printed \(sharpPrinted)")
        print("BURST error: single \(single), merged \(together); sharpness: single \(sharpSingle), merged \(sharpTogether); "
            + "placements \(merged.placements.map { String(format: "%.2f %.2f %.4f", $0.dx, $0.dy, $0.angle) })")
        XCTAssertEqual(merged.used.count, 4, "every frame used")
        XCTAssertLessThan(together, single * 0.8, "quieter")
        XCTAssertGreaterThanOrEqual(sharpTogether, sharpSingle * 0.97, "as sharp")
    }

    func testAShakenFrameIsLeftOutAndAReflectionInOneFrameIsGone() throws {
        var takes = self.takes
        takes[2].shake = 3
        takes[3].reflection = true
        let frames = takes.map(Self.frame)
        let merged = try XCTUnwrap(ScanBurst.merged(frames))
        XCTAssertFalse(merged.used.contains(2), "the shaken frame left out: \(merged.used), \(merged.sharpness)")
        // Where the reflection was, the merged page is as the others had it.
        var whiter = 0
        for y in 120..<180 {
            for x in 270..<330 where merged.page.brightness(x: x, y: y) > 245 { whiter += 1 }
        }
        XCTAssertLessThan(whiter, 30, "no reflection left: used \(merged.used), sharpest \(merged.reference)")
    }

    func testOneFrameIsItself() throws {
        let frame = Self.frame(takes[0])
        let merged = try XCTUnwrap(ScanBurst.merged([frame]))
        XCTAssertEqual(merged.page, frame)
        XCTAssertNil(ScanBurst.merged([]))
    }
}
