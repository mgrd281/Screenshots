import CoreGraphics
import Foundation

/// Light print, line by line: a column of small grey print, as a
/// practice's letterhead runs down the side of a letter, made as dark and
/// plain as the body's, with every mark of it kept: an umlaut's dots, an
/// accent, a comma, an @. Each line of text read is measured on its own,
/// in windows along it, so the light across the page never counts: its
/// paper and its darkest ink, how grainy the paper is, and whether the ink
/// is coloured. A light grey line's ink is then taken to the body's
/// darkness, and each pixel by the same share of how far under the paper
/// it lies, so a faint dot is darkened as much as the stroke beside it and
/// keeps its place, size and shape; the paper's grain, and nothing darker,
/// turns white. Dark print, coloured print and print on a fill are left to
/// the page's own curve. Nothing is drawn or moved: each pixel is only
/// made darker or lighter, as `ScanClean` does everywhere. A thin light
/// face is taken a little further, so the body of its strokes, not only
/// their middles, comes out dark: it reads a little bolder, as dark as the
/// body beside it.
extension ScanClean {
    /// A line of text read, in the page's pixels, grown by 30 % of its
    /// height on every side, as far as its marks reach: an accent over a
    /// capital, a descender's tail.
    struct PrintLine: Equatable {
        let x0: Int
        let y0: Int
        let x1: Int
        let y1: Int
        /// The line's own height, before it was grown.
        let height: Int
    }

    /// The lines of text read, from 0 to 1 from the bottom left as Vision
    /// gives them, in pixels from the top left, grown.
    static func printLines(_ boxes: [CGRect], width w: Int, height h: Int, grow share: Double = 0.3) -> [PrintLine] {
        boxes.compactMap { box in
            let lineHeight = Double(box.height) * Double(h)
            let grow = share * lineHeight
            let x0 = max(0, Int((Double(box.minX) * Double(w) - grow).rounded(.down)))
            let x1 = min(w, Int((Double(box.maxX) * Double(w) + grow).rounded(.up)))
            let y0 = max(0, Int(((1 - Double(box.maxY)) * Double(h) - grow).rounded(.down)))
            let y1 = min(h, Int(((1 - Double(box.minY)) * Double(h) + grow).rounded(.up)))
            guard x1 - x0 > 4, y1 - y0 > 4 else { return nil }
            return PrintLine(x0: x0, y0: y0, x1: x1, y1: y1, height: max(1, Int(lineHeight.rounded())))
        }
    }

    /// The boxes of text whose print is light and neutral, as the photo has
    /// it: its darkest lighter than `lightInk` would be on white paper, and
    /// lighter than the page's own dark print by `lightApart`, a grey
    /// column beside black text, not black text a soft photo left grey (on
    /// a faded page, whose darkest print is lighter than `lightInkFull`,
    /// all of it); and as grey as the paper is, its colour divided out. Only these are
    /// toned (`toned`), evened at the paper's own level and smoothed less
    /// (`textHeadroom`, `textGrain`), so their faintest marks keep their
    /// contrast; dark print and coloured print, a form's among them, are
    /// cleaned as before.
    static func lightPrint(_ boxes: [CGRect], in page: ScanBitmap, tuning: Tuning = .standard) -> [CGRect] {
        let w = page.width, h = page.height
        // Each box's darkest print as on white paper, and whether it is grey.
        let measured: [(box: CGRect, ink: Float, neutral: Bool)] = boxes.compactMap { box in
            let x0 = max(0, Int(Double(box.minX) * Double(w))), x1 = min(w, Int(Double(box.maxX) * Double(w)))
            let y0 = max(0, Int((1 - Double(box.maxY)) * Double(h))), y1 = min(h, Int((1 - Double(box.minY)) * Double(h)))
            guard x1 - x0 > 2, y1 - y0 > 2 else { return nil }
            var values: [UInt8] = [], reds: [UInt8] = [], greens: [UInt8] = [], blues: [UInt8] = []
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * w + x) * 4
                    reds.append(page.pixels[i])
                    greens.append(page.pixels[i + 1])
                    blues.append(page.pixels[i + 2])
                    values.append(brightness(page.pixels[i], page.pixels[i + 1], page.pixels[i + 2]))
                }
            }
            func level(_ list: [UInt8], _ share: Double) -> Float {
                let sorted = list.sorted()
                return Float(sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))])
            }
            let paper = level(values, 0.9), ink = level(values, 0.01)
            guard paper > 0 else { return nil }
            // How coloured the darkest of it is once the paper's own colour is divided out.
            let paperRed = max(1, level(reds, 0.9)), paperGreen = max(1, level(greens, 0.9)), paperBlue = max(1, level(blues, 0.9))
            let darkest = ink + 0.3 * (paper - ink)
            var colour: Float = 0
            var inked = 0
            for (n, value) in values.enumerated() where Float(value) <= darkest {
                let r = Float(reds[n]) / paperRed, g = Float(greens[n]) / paperGreen, b = Float(blues[n]) / paperBlue
                let top = max(r, g, b)
                colour += top > 0 ? (top - min(r, g, b)) / top : 0
                inked += 1
            }
            return (box, min(255, ink * 255 / paper), inked > 0 && colour / Float(inked) < tuning.colourAbove)
        }
        guard !measured.isEmpty else { return [] }
        // The page's own dark print: the darkest quarter of its lines. Where
        // even that is light, a faded page, all of its print is.
        let inks = measured.map(\.ink).sorted()
        let dark = inks[inks.count / 4]
        let allLight = dark >= tuning.lightInkFull
        return measured.filter { line in
            line.neutral && line.ink >= tuning.lightInk && (allLight || line.ink - dark >= tuning.lightApart)
        }.map(\.box)
    }

    /// How a stretch of a line is toned: its paper, its darkest ink and the
    /// paper's grain, of 255, and how much of the toning it takes, from 0,
    /// left to the page's curve, to 1.
    struct Tone: Equatable {
        var paper: Float
        var ink: Float
        var grain: Float
        var strength: Float

        /// How much darker than its paper each level is made.
        func gain(_ tuning: Tuning) -> Float {
            let contrast = paper - ink - grain
            guard contrast > 1 else { return 1 }
            return min(tuning.lineGain, max(1, (255 - tuning.lineInk) / contrast))
        }

        /// A pixel's brightness toned: white within the grain of the paper,
        /// the ink at the line's darkness, the levels between as the page's
        /// curve has them, a little lighter, so a soft edge does not make
        /// the stroke bolder.
        func value(_ brightness: Float, tuning: Tuning) -> Float {
            let under = max(0, paper - brightness - grain)
            let depth = 255 - tuning.lineInk
            let share = min(1, under * gain(tuning) * tuning.lineDrive / depth)
            return 255 - depth * powf(share, tuning.gamma)
        }
    }

    /// The tone of a window of a line, from its pixels' brightness and
    /// colour: none (strength 0) where it holds no print, where its paper is
    /// a fill rather than paper, where its ink is coloured, or where its ink
    /// is dark already.
    static func tone(of plane: [UInt8], _ page: ScanBitmap, x0: Int, x1: Int, y0: Int, y1: Int, noise: Float,
                     tuning: Tuning, everyInk: Bool = false) -> Tone {
        let w = page.width
        var counts = [Int](repeating: 0, count: 256)
        var n = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                counts[Int(plane[y * w + x])] += 1
                n += 1
            }
        }
        func level(_ share: Double) -> Float {
            let wanted = max(1, Int(Double(n) * share))
            var seen = 0
            for value in 0..<256 {
                seen += counts[value]
                if seen >= wanted { return Float(value) }
            }
            return 255
        }
        let paper = level(0.9), ink = level(0.01)
        let grain = min(16, max(2, tuning.lineGrain * noise))
        var tone = Tone(paper: paper, ink: ink, grain: grain, strength: 0)
        // No print, or print on a fill: left as the page's curve has it.
        guard paper - ink >= 3 * grain, paper - ink >= 12, paper >= tuning.linePaper else { return tone }
        // Light ink only, but where a line is cleaned again: dark print reads as it is.
        let light = everyInk ? 1 : (ink - tuning.lightInk) / max(1, tuning.lightInkFull - tuning.lightInk)
        guard light > 0 else { return tone }
        // Coloured ink, as a blue heading's, keeps its colour and shade.
        let darkest = ink + 0.3 * (paper - ink)
        var colour: Float = 0
        var inked = 0
        page.pixels.withUnsafeBufferPointer { px in
            for y in y0..<y1 {
                for x in x0..<x1 where Float(plane[y * w + x]) <= darkest {
                    let i = (y * w + x) * 4
                    let r = Float(px[i]), g = Float(px[i + 1]), b = Float(px[i + 2])
                    let top = max(r, g, b)
                    colour += top > 0 ? (top - min(r, g, b)) / top : 0
                    inked += 1
                }
            }
        }
        let saturation = inked > 0 ? colour / Float(inked) : 0
        let neutral = 1 - (saturation - tuning.neutralBelow) / max(1e-6, tuning.colourAbove - tuning.neutralBelow)
        tone.strength = min(1, light) * min(1, max(0, neutral))
        return tone
    }

    /// How much further than its darkest ink a line is toned, from 1 to
    /// `lineDrive`: enough for the body of its ink, its darkest `lineBody`
    /// share, to come out `lineDark` or darker, not only the middles of its
    /// strokes. A thin light face then reads as dark as the body text beside
    /// it; a soft one, its ink spread wide already, is toned as it is.
    static func drive(of plane: [UInt8], width w: Int, line: PrintLine, noise: Float, tuning: Tuning) -> Float {
        guard tuning.lineDrive > 1 else { return 1 }
        var counts = [Int](repeating: 0, count: 256)
        var n = 0
        for y in line.y0..<line.y1 {
            for x in line.x0..<line.x1 {
                counts[Int(plane[y * w + x])] += 1
                n += 1
            }
        }
        func level(_ share: Float) -> Float {
            let wanted = max(1, Int(Float(n) * share))
            var seen = 0
            for value in 0..<256 {
                seen += counts[value]
                if seen >= wanted { return Float(value) }
            }
            return 255
        }
        let grain = min(16, max(2, tuning.lineGrain * noise))
        let tone = Tone(paper: level(0.9), ink: level(0.01), grain: grain, strength: 1)
        let body = tone.paper - level(tuning.lineBody) - grain
        guard body > 1 else { return 1 }
        let depth = 255 - tuning.lineInk
        let share = powf((255 - tuning.lineDark) / depth, 1 / tuning.gamma)
        return min(tuning.lineDrive, max(1, share * depth / (body * tone.gain(tuning))))
    }

    /// How grainy a line's paper is: the spread of its pixels where no
    /// print is near, none of the eight round them darker than the paper
    /// by 30 levels and more. Its paper is white once evened, so only the
    /// darker half of the grain shows; the spread is taken as if both did.
    static func grain(of plane: [UInt8], width w: Int, height h: Int, line: PrintLine) -> Float {
        var sum: Float = 0
        var n = 0
        for y in max(1, line.y0)..<min(h - 1, line.y1) {
            for x in max(1, line.x0)..<min(w - 1, line.x1) {
                var lowest = 255
                for yy in (y - 1)...(y + 1) {
                    for xx in (x - 1)...(x + 1) { lowest = min(lowest, Int(plane[yy * w + xx])) }
                }
                guard lowest >= 225 else { continue }
                let under = Float(255 - Int(plane[y * w + x]))
                sum += under * under
                n += 1
            }
        }
        return n > 20 ? (2 * sum / Float(n)).squareRoot() : 4
    }

    /// The lines of light print in `base`, the page evened and smoothed but
    /// not yet curved, toned (`Tone`) into `page`, the page curved: each
    /// line in windows `lineWindow` times its height wide, half a window
    /// apart, its tone changing smoothly between their middles, and
    /// blended in over the line's edge, so no seam shows. Its smallest
    /// marks are first made as clear as its strokes, `lineSharpen` times
    /// what a pixel stands out from the eight round it.
    static func toned(_ base: ScanBitmap, into page: inout ScanBitmap, lines: [PrintLine], tuning: Tuning = .standard,
                      everyInk: Bool = false) {
        guard tuning.lineGain > 1, base.width == page.width, base.height == page.height else { return }
        let w = base.width, h = base.height
        let plane = base.brightness
        for line in lines {
            let noise = grain(of: plane, width: w, height: h, line: line)
            var tuning = tuning
            tuning.lineDrive = drive(of: plane, width: w, line: line, noise: noise, tuning: tuning)
            let window = max(12, Int((Float(line.height) * tuning.lineWindow).rounded()))
            let step = max(6, window / 2)
            var middles: [Float] = []
            var tones: [Tone] = []
            var start = line.x0
            while true {
                let end = min(line.x1, start + window)
                tones.append(tone(of: plane, base, x0: start, x1: end, y0: line.y0, y1: line.y1, noise: noise,
                                  tuning: tuning, everyInk: everyInk))
                middles.append(Float(start + end) / 2)
                if end >= line.x1 { break }
                start += step
            }
            guard tones.contains(where: { $0.strength > 0 }) else { continue }
            page.pixels.withUnsafeMutableBufferPointer { px in
                var k = 0
                for x in line.x0..<line.x1 {
                    // The two windows round this column, and how far between them.
                    while k + 1 < middles.count, middles[k + 1] <= Float(x) { k += 1 }
                    let a = tones[k], b = tones[min(k + 1, tones.count - 1)]
                    let along: Float = k + 1 < middles.count
                        ? min(1, max(0, (Float(x) - middles[k]) / max(1, middles[k + 1] - middles[k]))) : 0
                    let here = Tone(paper: a.paper + (b.paper - a.paper) * along, ink: a.ink + (b.ink - a.ink) * along,
                                    grain: a.grain + (b.grain - a.grain) * along,
                                    strength: a.strength + (b.strength - a.strength) * along)
                    guard here.strength > 0 else { continue }
                    let fromSide = min(x - line.x0, line.x1 - 1 - x)
                    for y in line.y0..<line.y1 {
                        let edge = min(fromSide, min(y - line.y0, line.y1 - 1 - y))
                        let weight = here.strength * min(1, Float(edge + 1) / 3)
                        let p = y * w + x
                        // What the pixel stands out from the eight round it, made a little more.
                        var around = 0, count = 0
                        for yy in max(0, y - 1)...min(h - 1, y + 1) {
                            for xx in max(0, x - 1)...min(w - 1, x + 1) {
                                around += Int(plane[yy * w + xx])
                                count += 1
                            }
                        }
                        let value = Float(plane[p])
                        let mean = Float(around) / Float(count)
                        // Close to the paper, the mean of the nine, so the paper's
                        // grain is not taken darker with the print; a mark,
                        // however faint, is wider than a pixel and stays.
                        let clearer = value > here.paper - 2 * here.grain ? mean
                            : value + tuning.lineSharpen * (value - mean)
                        let toned = here.value(clearer, tuning: tuning)
                        let i = p * 4
                        let current = Float(Self.brightness(px[i], px[i + 1], px[i + 2]))
                        let change = (toned - current) * weight
                        for c in 0..<3 {
                            px[i + c] = UInt8(min(255, max(0, Float(px[i + c]) + change)).rounded())
                        }
                    }
                }
            }
        }
    }

    // MARK: Cleaned again

    /// How a line is cleaned again where cleaning changed what it says
    /// (`ScanContent.changed`): toned gently from the base, dark print too,
    /// at most twice as dark, nothing sharpened; or kept as the base has it,
    /// its light evened and its paper white, nothing more.
    enum Again {
        case gentle
        case kept
    }

    /// `page` with the line in `box` cleaned again from `base`, the page
    /// before its print was toned (`Cleaned.base`), as `again` says, in the
    /// page's colours. Black and white keeps the line in greys, so nothing
    /// of it is lost to a threshold.
    static func redone(_ base: ScanBitmap, into page: inout ScanBitmap, box: CGRect, _ again: Again, mode: ScanColor,
                       grow: Double = 0.3, tuning: Tuning = .standard) {
        guard base.width == page.width, base.height == page.height,
              let line = printLines([box], width: base.width, height: base.height, grow: grow).first else { return }
        let w = base.width
        switch again {
        case .gentle:
            var gentle = tuning
            gentle.lineSharpen = 0
            gentle.lineGain = 2
            gentle.lineDrive = 1
            toned(base, into: &page, lines: [line], tuning: gentle, everyInk: true)
        case .kept:
            page.pixels.withUnsafeMutableBufferPointer { px in
                base.pixels.withUnsafeBufferPointer { src in
                    for y in line.y0..<line.y1 {
                        for x in line.x0..<line.x1 {
                            let edge = min(min(x - line.x0, line.x1 - 1 - x), min(y - line.y0, line.y1 - 1 - y))
                            let weight = min(1, Float(edge + 1) / 3)
                            let i = (y * w + x) * 4
                            for c in 0..<3 {
                                let mixed = Float(px[i + c]) + (Float(src[i + c]) - Float(px[i + c])) * weight
                                px[i + c] = UInt8(min(255, max(0, mixed)).rounded())
                            }
                        }
                    }
                }
            }
        }
        guard mode != .color else { return }
        // In greys, the line's pixels each as bright as their colour.
        page.pixels.withUnsafeMutableBufferPointer { px in
            for y in line.y0..<line.y1 {
                for x in line.x0..<line.x1 {
                    let i = (y * w + x) * 4
                    let value = Self.brightness(px[i], px[i + 1], px[i + 2])
                    px[i] = value
                    px[i + 1] = value
                    px[i + 2] = value
                }
            }
        }
    }
}
