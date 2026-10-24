import Foundation
@testable import Tendedero

/// A made-up doctor's letter photographed with a phone, as a real one
/// came: dense dark text on the left, a column of small light-grey print on
/// the right (an address, telephone numbers), a box ruled across the page
/// with its first line of text close under its top rule; the sheet curled,
/// so every line bows down in the middle, lit unevenly in a warm room, and
/// a little soft, as a phone's picture is. Its people and numbers are all
/// made up; never a real document.
///
/// Drawn in shapes, its letters as strokes of their size, so it is checked
/// on any machine.
enum ScanLetter {
    /// A4 at 200 dots an inch.
    static let width = 1654
    static let height = 2339

    /// A line of letters: where it starts and ends across, its top, its
    /// letters' height and stroke, and its ink, of 255.
    struct Line {
        let x0: Double
        let x1: Double
        let top: Double
        let size: Double
        let stroke: Double
        let ink: Double

        var bottom: Double { top + size }
    }

    /// The body: dense dark text, left.
    static let body: [Line] = {
        var lines: [Line] = []
        for row in 0..<7 { lines.append(Line(x0: 120, x1: 1040, top: 180 + Double(row) * 40, size: 18, stroke: 2.6, ink: 30)) }
        for row in 0..<9 { lines.append(Line(x0: 120, x1: 1530, top: 1240 + Double(row) * 40, size: 18, stroke: 2.6, ink: 30)) }
        return lines
    }()

    /// The small grey print, right: thin strokes, light ink.
    static let grey: [Line] = (0..<10).map { Line(x0: 1180, x1: 1530, top: 180 + Double($0) * 28, size: 12, stroke: 1.4, ink: 150) }

    /// The box's rules across, and its text: the first line six pixels under
    /// the top rule, the last as close over the bottom one.
    static let rules: [(top: Double, bottom: Double)] = [(700, 702.5), (1100, 1102.5)]
    static let ruleSpan = (x0: 90.0, x1: 1564.0)
    static let boxed: [Line] = (0..<9).map {
        Line(x0: 130, x1: 1520, top: 708.5 + Double($0) * 42, size: 18, stroke: 2.6, ink: 30)
    } + [Line(x0: 130, x1: 1520, top: 1074, size: 18, stroke: 2.6, ink: 30)]

    /// How far the curled sheet bows down at its middle, in pixels.
    static let bow = 7.0

    /// The bow at a column: none at the edges, `bow` in the middle.
    static func bowed(at x: Double) -> Double { bow * sin(.pi * x / Double(width)) }

    /// The letter as printed: white paper, its print as drawn.
    static func page() -> [Double] {
        var page = [Double](repeating: 255, count: width * height)
        func fill(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ ink: Double) {
            let ys = max(0, Int(y0.rounded(.down))), ye = min(height - 1, Int(y1.rounded(.up)))
            let xs = max(0, Int(x0.rounded(.down))), xe = min(width - 1, Int(x1.rounded(.up)))
            guard ys <= ye, xs <= xe else { return }
            for y in ys...ye {
                let cy = max(0, min(Double(y + 1), y1) - max(Double(y), y0))
                guard cy > 0 else { continue }
                for x in xs...xe {
                    let cx = max(0, min(Double(x + 1), x1) - max(Double(x), x0))
                    guard cx > 0 else { continue }
                    let i = y * width + x
                    page[i] = min(page[i], 255 - (255 - ink) * cx * cy)
                }
            }
        }
        for line in body + grey + boxed { letters(of: line, fill) }
        for rule in rules { fill(ruleSpan.x0, rule.top, ruleSpan.x1, rule.bottom, 40) }
        return page
    }

    /// A line's letters as strokes: each a stem or two, some taller, with
    /// a bar at its top, middle or foot, and a gap between words.
    static func letters(of line: Line, _ fill: (Double, Double, Double, Double, Double) -> Void) {
        let advance = line.size * 0.62
        var x = line.x0
        var seed: UInt32 = UInt32(truncatingIfNeeded: Int(line.top * 7 + line.x0))
        func next() -> UInt32 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return seed >> 16
        }
        while x + advance < line.x1 {
            let kind = next() % 9
            if kind == 0 { x += advance * 0.8; continue }
            let s = line.stroke, w = advance * 0.6
            let tall = kind % 3 == 0 ? line.size * 0.35 : 0
            let top = line.top - tall, bottom = line.top + line.size
            fill(x, top, x + s, bottom, line.ink)
            if kind % 2 == 0 { fill(x + w - s, line.top, x + w, bottom, line.ink) }
            switch kind % 4 {
            case 0: fill(x, line.top, x + w, line.top + s, line.ink)
            case 1: fill(x, line.top + line.size / 2 - s / 2, x + w, line.top + line.size / 2 + s / 2, line.ink)
            case 2: fill(x, bottom - s, x + w, bottom, line.ink)
            default: break
            }
            x += advance
        }
    }

    /// The letter photographed: curled, lit warm and unevenly, softened,
    /// with a little grain.
    static func photographed(_ page: [Double]) -> ScanBitmap {
        let w = width, h = height
        // The curl: each column's print moved down by its bow.
        var curled = [Double](repeating: 255, count: w * h)
        for x in 0..<w {
            let by = bowed(at: Double(x) + 0.5)
            for y in 0..<h {
                let from = Double(y) - by
                let y0 = Int(from.rounded(.down)), t = from - Double(y0)
                guard y0 >= 0, y0 + 1 < h else { continue }
                curled[y * w + x] = page[y0 * w + x] * (1 - t) + page[(y0 + 1) * w + x] * t
            }
        }
        // Soft: a small blur, across then down.
        let kernel: [Double] = [0.11, 0.22, 0.34, 0.22, 0.11]
        var across = curled
        for y in 0..<h {
            for x in 2..<(w - 2) {
                var sum = 0.0
                for k in 0..<5 { sum += curled[y * w + x + k - 2] * kernel[k] }
                across[y * w + x] = sum
            }
        }
        var soft = across
        for y in 2..<(h - 2) {
            for x in 0..<w {
                var sum = 0.0
                for k in 0..<5 { sum += across[(y + k - 2) * w + x] * kernel[k] }
                soft[y * w + x] = sum
            }
        }
        var out = ScanBitmap(width: w, height: h, red: 255, green: 255, blue: 255)
        var seed: UInt32 = 5
        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) / Double(w), v = Double(y) / Double(h)
                let light = 0.86 - 0.10 * u - 0.06 * v + 0.04 * (1 - (2 * u - 1) * (2 * u - 1))
                let share = soft[y * w + x] / 255
                let i = (y * w + x) * 4
                for (k, tint) in [1.0, 0.95, 0.84].enumerated() {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let grain = Double(seed >> 24) / 255 * 6 - 3
                    let value = (0.10 + 0.90 * share) * light * tint * 255 + grain
                    out.pixels[i + k] = UInt8(max(0, min(255, value.rounded())))
                }
            }
        }
        return out
    }
}

/// What a cleaned photo of the letter shows, against the letter as printed.
struct ScanLetterMeasures: CustomStringConvertible {
    /// How far each line's letters wander up and down across the page, in
    /// pixels, the most of any line: the curl taken out, or a wave put in.
    var wander: Double
    /// The same for the box's first line, under its rule.
    var wanderUnderRule: Double
    /// The dark text's ink against the ink printed: over 1 is bolder.
    var bodyInk: Double
    /// The dark text's strokes, as the pixels darker than half, against
    /// those printed: over 1 is thicker.
    var bodyArea: Double
    /// The grey print's ink against the ink printed: under 1 is fainter.
    var greyInk: Double
    /// Of the grey print's letters, the share whose stem still reads as a
    /// stroke all the way down.
    var greyWhole: Double

    var description: String {
        String(format: "wander %.1f px (under the rule %.1f), body ink ×%.2f, strokes ×%.2f, grey ink ×%.2f, grey whole %.2f",
               wander, wanderUnderRule, bodyInk, bodyArea, greyInk, greyWhole)
    }

    /// The cleaned photo measured, with the printed page beside it. The
    /// cleaned page's rows are found again from the box's top rule, as
    /// straightening may move the page up or down by a pixel or two.
    static func measure(_ cleaned: ScanBitmap, printed: [Double]) -> ScanLetterMeasures {
        let w = cleaned.width, h = cleaned.height
        let plane = cleaned.brightness
        // Where the box's top rule lies now, at the middle.
        var offset = 0.0
        let mid = w / 2
        var best = 255.0
        for y in max(0, Int(ScanLetter.rules[0].top) - 20)..<min(h, Int(ScanLetter.rules[0].top) + 20) {
            var sum = 0.0
            for x in (mid - 40)..<(mid + 40) { sum += Double(plane[y * w + x]) }
            if sum / 80 < best { best = sum / 80; offset = Double(y) + 0.5 - (ScanLetter.rules[0].top + 1.25) }
        }
        // A line's ink: how much darker than white, summed, round where it lies.
        func ink(_ line: ScanLetter.Line, in values: (Int) -> Double, shift: Double) -> Double {
            var sum = 0.0
            let y0 = Int(line.top - line.size * 0.4 - 3 + shift), y1 = Int(line.bottom + 4 + shift)
            for y in max(0, y0)..<min(h, y1) {
                for x in Int(line.x0)..<Int(line.x1) { sum += 255 - values(y * w + x) }
            }
            return sum
        }
        let printedValue: (Int) -> Double = { printed[$0] }
        let cleanedValue: (Int) -> Double = { Double(plane[$0]) }
        // A line's letters' middle, down, in stretches across, against where
        // the printed page has it.
        func middles(_ line: ScanLetter.Line, in values: (Int) -> Double, shift: Double) -> [Double?] {
            var middles: [Double?] = []
            var x0 = Int(line.x0)
            while x0 + 80 <= Int(line.x1) {
                var sum = 0.0, weight = 0.0
                for y in Int(line.top - line.size * 0.4 - 3 + shift)..<Int(line.bottom + 4 + shift) where y >= 0 && y < h {
                    for x in x0..<(x0 + 80) {
                        let d = max(0, 200 - values(y * w + x))
                        sum += d * Double(y)
                        weight += d
                    }
                }
                middles.append(weight > 0 ? sum / weight : nil)
                x0 += 80
            }
            return middles
        }
        func wander(_ line: ScanLetter.Line) -> Double {
            let apart = zip(middles(line, in: cleanedValue, shift: offset), middles(line, in: printedValue, shift: 0))
                .compactMap { a, b -> Double? in
                    guard let a, let b else { return nil }
                    return a - b
                }
            return (apart.max() ?? 0) - (apart.min() ?? 0)
        }
        let bodyLines = ScanLetter.body + ScanLetter.boxed
        let bodyInk = bodyLines.reduce(0) { $0 + ink($1, in: cleanedValue, shift: offset) }
            / bodyLines.reduce(0) { $0 + ink($1, in: printedValue, shift: 0) }
        func area(_ line: ScanLetter.Line, in values: (Int) -> Double, shift: Double) -> Double {
            var count = 0.0
            let y0 = Int(line.top - line.size * 0.4 - 3 + shift), y1 = Int(line.bottom + 4 + shift)
            for y in max(0, y0)..<min(h, y1) {
                for x in Int(line.x0)..<Int(line.x1) where values(y * w + x) < 128 { count += 1 }
            }
            return count
        }
        let bodyArea = bodyLines.reduce(0) { $0 + area($1, in: cleanedValue, shift: offset) }
            / bodyLines.reduce(0) { $0 + area($1, in: printedValue, shift: 0) }
        let greyInk = ScanLetter.grey.reduce(0) { $0 + ink($1, in: cleanedValue, shift: offset) }
            / ScanLetter.grey.reduce(0) { $0 + ink($1, in: printedValue, shift: 0) }
        // Each grey stem: down its printed column, every row darker than the paper by a third of its ink.
        var stems = 0, whole = 0
        for line in ScanLetter.grey {
            var x = Int(line.x0)
            while x < Int(line.x1) {
                // A stem starts where the printed column is ink from the line's top to its foot.
                let column = (Int(line.top + 1)..<Int(line.bottom - 1)).allSatisfy { printed[$0 * w + x] < 230 }
                if column, x == 0 || !(Int(line.top + 1)..<Int(line.bottom - 1)).allSatisfy({ printed[$0 * w + x - 1] < 230 }) {
                    stems += 1
                    let shown = (Int(line.top + 2)..<Int(line.bottom - 2)).allSatisfy { y in
                        let yy = Int(Double(y) + offset)
                        return (max(0, x - 1)...min(w - 1, x + 2)).contains { plane[yy * w + $0] < 210 }
                    }
                    if shown { whole += 1 }
                }
                x += 1
            }
        }
        let wanders = (ScanLetter.body + ScanLetter.boxed).map(wander)
        return ScanLetterMeasures(wander: wanders.max() ?? 0, wanderUnderRule: wander(ScanLetter.boxed[0]),
                                  bodyInk: bodyInk, bodyArea: bodyArea, greyInk: greyInk,
                                  greyWhole: stems > 0 ? Double(whole) / Double(stems) : 0)
    }
}
