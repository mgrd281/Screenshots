import XCTest
@testable import Tendedero

/// Light print, line by line (`ScanClean.toned`): small grey letters with
/// dots over them, soft and grainy as a phone takes them, come out as dark
/// as the body, every dot kept and dark, the paper round them white;
/// dark print, coloured print and print on a grey fill are left as the
/// page's curve has them; and a line cleaned again is toned gently or kept
/// as evened (`ScanClean.redone`). Drawn in shapes, so it is checked on any
/// machine.
final class ScanPrintTests: XCTestCase {
    /// Paper a little warm and dim, as a phone takes it.
    private let paper: UInt8 = 228

    /// A line of letters: stems `stroke` wide and `size` high, a dot over
    /// every other one, in `ink`, from `x` along `top`.
    private func letters(_ page: inout ScanBitmap, top: Int, x: Int = 40, count: Int = 24, size: Int = 14, stroke: Int = 2,
                         ink: (UInt8, UInt8, UInt8)) -> [(x: Int, y: Int)] {
        var dots: [(x: Int, y: Int)] = []
        for n in 0..<count {
            let left = x + n * 9
            for y in top..<(top + size) { for xx in left..<(left + stroke) { set(&page, xx, y, ink) } }
            if n % 2 == 0 {
                // A dot over it, as an umlaut's: two pixels by two, four over the stem.
                for y in (top - 5)..<(top - 3) { for xx in left..<(left + 2) { set(&page, xx, y, ink) } }
                dots.append((left, top - 5))
            }
        }
        return dots
    }

    private func set(_ page: inout ScanBitmap, _ x: Int, _ y: Int, _ value: (UInt8, UInt8, UInt8)) {
        let i = (y * page.width + x) * 4
        page.pixels[i] = value.0
        page.pixels[i + 1] = value.1
        page.pixels[i + 2] = value.2
    }

    /// The page as a phone takes it: soft, each pixel the mean of the nine
    /// round it, and grainy, the same grain each time.
    private func photographed(_ page: ScanBitmap) -> ScanBitmap {
        var out = page
        var seed: UInt32 = 12345
        for y in 1..<(page.height - 1) {
            for x in 1..<(page.width - 1) {
                for c in 0..<3 {
                    var sum = 0
                    for dy in -1...1 { for dx in -1...1 { sum += Int(page.pixels[((y + dy) * page.width + x + dx) * 4 + c]) } }
                    seed = seed &* 1_103_515_245 &+ 12345
                    let grain = Int((seed >> 16) % 7) - 3
                    out.pixels[(y * page.width + x) * 4 + c] = UInt8(min(255, max(0, sum / 9 + grain)))
                }
            }
        }
        return out
    }

    /// A line's box as Vision gives it: from 0 to 1, from the bottom left.
    private func box(top: Int, x: Int = 40, count: Int = 24, size: Int = 14, in page: ScanBitmap) -> CGRect {
        let w = Double(page.width), h = Double(page.height)
        let up = Double(top - 6), down = Double(top + size + 1)
        return CGRect(x: Double(x - 2) / w, y: 1 - down / h, width: Double(count * 9 + 2) / w, height: (down - up) / h)
    }

    private func blank() -> ScanBitmap {
        ScanBitmap(width: 400, height: 260, red: paper, green: paper - 3, blue: paper - 10)
    }

    func testLightGreyPrintComesOutDarkWithEveryDot() throws {
        var printed = blank()
        let dots = letters(&printed, top: 60, ink: (165, 163, 160))
        let page = photographed(printed)
        let cleaned = ScanClean.clean(page, .color, printBoxes: [box(top: 60, in: page)])
        // The stems' middles dark, as the body's are.
        var stems: [Int] = []
        for n in 0..<24 { stems.append(Int(cleaned.brightness(x: 40 + n * 9, y: 67))) }
        XCTAssertLessThanOrEqual(stems.sorted()[stems.count / 2], 70, "the strokes dark: \(stems)")
        // Every dot kept, and darker than the paper by most of what a stroke is.
        for dot in dots {
            let darkest = (dot.y - 1...dot.y + 2).flatMap { y in (dot.x - 1...dot.x + 2).map { cleaned.brightness(x: $0, y: y) } }.min()!
            XCTAssertLessThanOrEqual(darkest, 150, "the dot at \(dot.x) kept, \(darkest)")
        }
        // The paper round the letters white, none of its grain taken darker.
        var paperPixels = 0, grey = 0
        for y in 20..<40 {
            for x in 30..<260 {
                paperPixels += 1
                if cleaned.brightness(x: x, y: y) < 245 { grey += 1 }
            }
        }
        XCTAssertLessThanOrEqual(Double(grey) / Double(paperPixels), 0.01, "the paper over the line white")
    }

    func testTheOldCurveLeftTheDotsPaleWhichTheToningDoesNot() throws {
        var printed = blank()
        let dots = letters(&printed, top: 60, ink: (165, 163, 160))
        let page = photographed(printed)
        let boxes = [box(top: 60, in: page)]
        var untoned = ScanClean.Tuning.standard
        untoned.lineGain = 1
        let before = ScanClean.clean(page, .color, tuning: untoned, printBoxes: boxes)
        let after = ScanClean.clean(page, .color, printBoxes: boxes)
        func darkest(_ bitmap: ScanBitmap, _ dot: (x: Int, y: Int)) -> UInt8 {
            (dot.y - 1...dot.y + 2).flatMap { y in (dot.x - 1...dot.x + 2).map { bitmap.brightness(x: $0, y: y) } }.min()!
        }
        for dot in dots { XCTAssertLessThan(darkest(after, dot), darkest(before, dot), "the dot at \(dot.x) darker") }
    }

    func testDarkPrintIsLeftToThePageCurve() {
        var printed = blank()
        _ = letters(&printed, top: 60, stroke: 3, ink: (30, 30, 32))
        let page = photographed(printed)
        let boxes = [box(top: 60, in: page)]
        var untoned = ScanClean.Tuning.standard
        untoned.lineGain = 1
        XCTAssertEqual(ScanClean.clean(page, .color, printBoxes: boxes),
                       ScanClean.clean(page, .color, tuning: untoned, printBoxes: boxes), "dark print as the curve has it")
    }

    func testColouredPrintKeepsItsColour() {
        var printed = blank()
        _ = letters(&printed, top: 60, ink: (110, 160, 225))
        let page = photographed(printed)
        let boxes = [box(top: 60, in: page)]
        var untoned = ScanClean.Tuning.standard
        untoned.lineGain = 1
        XCTAssertEqual(ScanClean.clean(page, .color, printBoxes: boxes),
                       ScanClean.clean(page, .color, tuning: untoned, printBoxes: boxes), "a blue heading as the curve has it")
    }

    func testPrintOnAGreyFillKeepsTheFill() {
        var printed = blank()
        // A table's header, filled grey, with its words in grey on it.
        for y in 46..<84 { for x in 30..<170 { set(&printed, x, y, (190, 190, 190)) } }
        _ = letters(&printed, top: 60, count: 14, ink: (120, 120, 120))
        let page = photographed(printed)
        let boxes = [box(top: 60, count: 14, in: page)]
        var untoned = ScanClean.Tuning.standard
        untoned.lineGain = 1
        let cleaned = ScanClean.clean(page, .color, printBoxes: boxes)
        let curved = ScanClean.clean(page, .color, tuning: untoned, printBoxes: boxes)
        XCTAssertLessThanOrEqual(curved.brightness(x: 160, y: 50), 235, "the curve keeps the fill grey")
        XCTAssertEqual(cleaned.brightness(x: 160, y: 50), curved.brightness(x: 160, y: 50), "and so does the toning")
    }

    func testALineCleanedAgainIsGentleOrKeptAsEvened() {
        var printed = blank()
        _ = letters(&printed, top: 60, ink: (165, 163, 160))
        let page = photographed(printed)
        let line = box(top: 60, in: page)
        let made = ScanClean.cleaned(page, .color, printBoxes: [line])
        var kept = made.page
        ScanClean.redone(made.base, into: &kept, box: line, .kept, mode: .color)
        XCTAssertEqual(kept.brightness(x: 40, y: 67), made.base.brightness(x: 40, y: 67), "kept as evened")
        var gentle = made.page
        ScanClean.redone(made.base, into: &gentle, box: line, .gentle, mode: .color)
        let base = made.base.brightness(x: 40, y: 67), toned = made.page.brightness(x: 40, y: 67)
        let again = gentle.brightness(x: 40, y: 67)
        XCTAssertLessThan(again, base, "gently darker than evened")
        XCTAssertGreaterThan(again, toned, "and lighter than toned")
        var grey = made.page
        ScanClean.redone(made.base, into: &grey, box: line, .kept, mode: .gray)
        let i = (67 * grey.width + 40) * 4
        XCTAssertEqual(grey.pixels[i], grey.pixels[i + 2], "in greys, grey")
    }
}
