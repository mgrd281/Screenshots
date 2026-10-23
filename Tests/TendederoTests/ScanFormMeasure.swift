#if DEBUG && canImport(Vision) && canImport(CoreImage)
import CoreGraphics
import Foundation
@testable import Tendedero

/// The quality of a cleaned page of the made-up sick note (`ScanForm`),
/// measured as the brief's targets say: the paper's brightness, evenness and
/// colour away from everything printed; the print's darkness in the boxes
/// Vision reads; the signature's blue; how straight the long lines are and
/// whether the box's lines step at the fold; the background left at the
/// edges; and every word and number read again.
struct ScanFormMeasures: CustomStringConvertible {
    /// Of the paper's pixels, the share at 250 and brighter.
    var paperWhite = 0.0
    /// The most and least bright bands of paper rows, apart.
    var paperRows = 0
    /// The paper's mean saturation, from 0 to 1.
    var paperSaturation = 0.0
    /// The median of the darkest 5 % of pixels in the boxes of text read.
    var printDarkness = 255
    /// The signature's hue in degrees, how far it is from the ink's, and its saturation.
    var signatureHue = 0.0
    var signatureHueOff = 180.0
    var signatureSaturation = 0.0
    /// Each long line's spread up and down, at 300 dots an inch.
    var lineSpread: [Double] = []
    /// How far the box's upright lines step at the fold, at 300 dots an inch.
    var foldStep: Double?
    /// Background pixels in a band 1 % wide along the edges.
    var edgePixels = 0
    /// Words and numbers of the form not read, and read but not on it.
    var missing: [String] = []
    var added: [String] = []
    var size = (width: 0, height: 0)

    var description: String {
        let lines = lineSpread.map { String(format: "%.1f", $0) }.joined(separator: "/")
        let step = foldStep.map { String(format: "%.1f", $0) } ?? "–"
        return String(format: "%dx%d paper≥250 %.1f%% rows±%d sat %.3f print %d hue %.0f° (off %.0f°, sat %.2f) ",
                      size.width, size.height, paperWhite * 100, paperRows, paperSaturation, printDarkness, signatureHue,
                      signatureHueOff, signatureSaturation)
            + "lines \(lines) px step \(step) px edge \(edgePixels) missing \(missing) added \(added)"
    }
}

enum ScanFormMeasure {
    /// The ballpoint's hue as drawn, in degrees.
    static let inkHue = hue(0.13 * 255, 0.24 * 255, 0.66 * 255)

    /// Where the form has print, from its top left in its own pixels, the
    /// signature's sweep among it.
    static var printed: [CGRect] {
        var rects = [ScanForm.header, ScanForm.patch]
        for (top, bottom) in [(380, 1080), (ScanForm.foldBox.top, ScanForm.foldBox.bottom)] {
            rects.append(CGRect(x: 160, y: top, width: 2164, height: 4))
            rects.append(CGRect(x: 160, y: bottom, width: 2164, height: 4))
            rects.append(CGRect(x: 160, y: top, width: 4, height: bottom - top))
            rects.append(CGRect(x: 2320, y: top, width: 4, height: bottom - top))
        }
        rects.append(CGRect(x: 160, y: 760, width: 2160, height: 3))
        rects.append(CGRect(x: 1240, y: ScanForm.foldBox.top, width: 3, height: ScanForm.foldBox.bottom - ScanForm.foldBox.top))
        for top in ScanForm.ruledLines { rects.append(CGRect(x: 160, y: top, width: 2164, height: 4)) }
        rects.append(CGRect(x: 200, y: 2840, width: 1000, height: 3))
        rects.append(CGRect(x: 690, y: 2560, width: 880, height: 320))
        rects.append(CGRect(x: 200, y: 196, width: 1300, height: 90))
        for line in ScanForm.lines {
            let advance = line.typed ? line.size * 0.6 : line.size * 0.6
            rects.append(CGRect(x: CGFloat(line.x), y: CGFloat(line.top), width: CGFloat(line.text.count) * advance,
                                height: line.size * 1.3))
        }
        return rects
    }

    /// Measured on a cleaned page that shows `frame` of the form, in the
    /// form's own pixels from its top left: all of it, or less where its
    /// edges were cut away.
    static func measure(_ page: ScanBitmap, reading: [Finder.TextLine], variant: ScanForm.Variant,
                        frame: CGRect = CGRect(x: 0, y: 0, width: ScanForm.width, height: ScanForm.height)) -> ScanFormMeasures {
        var result = ScanFormMeasures()
        let w = page.width, h = page.height
        result.size = (w, h)
        let sx = Double(w) / frame.width, sy = Double(h) / frame.height
        let to300 = 1 / sx
        func px(_ x: Double) -> Double { (x - frame.minX) * sx }
        func py(_ y: Double) -> Double { (y - frame.minY) * sy }
        // The paper: away from all that is printed, typed or read, and from the edges.
        var paper = [Bool](repeating: true, count: w * h)
        func clear(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            let left = max(0, x0), right = min(w, x1), top = max(0, y0), bottom = min(h, y1)
            guard left < right, top < bottom else { return }
            for y in top..<bottom { for x in left..<right { paper[y * w + x] = false } }
        }
        for rect in printed {
            clear(Int(px(rect.minX - 40)), Int(py(rect.minY - 40)), Int(px(rect.maxX + 40).rounded(.up)),
                  Int(py(rect.maxY + 40).rounded(.up)))
        }
        for line in reading {
            let box = line.box
            clear(Int(box.minX * Double(w)) - 12, Int((1 - box.maxY) * Double(h)) - 12,
                  Int(box.maxX * Double(w)) + 12, Int((1 - box.minY) * Double(h)) + 12)
        }
        let band = (x: max(2, w / 66), y: max(2, h / 66))
        var white = 0, count = 0
        var saturation = 0.0
        var rowSums = [(sum: Int, count: Int)](repeating: (0, 0), count: h)
        for y in band.y..<(h - band.y) {
            for x in band.x..<(w - band.x) where paper[y * w + x] {
                let (r, g, b) = page.color(x: x, y: y)
                let value = Int(ScanClean.brightness(r, g, b))
                if value >= 250 { white += 1 }
                count += 1
                let high = Double(max(r, g, b)), low = Double(min(r, g, b))
                saturation += high > 0 ? (high - low) / high : 0
                rowSums[y].sum += value
                rowSums[y].count += 1
            }
        }
        result.paperWhite = Double(white) / Double(max(1, count))
        result.paperSaturation = saturation / Double(max(1, count))
        // Rows in bands of 1 % of the height, each with paper across a fifth of the page.
        let rowBand = max(1, h / 100)
        var means: [Double] = []
        for start in stride(from: band.y, to: h - band.y - rowBand, by: rowBand) {
            let part = rowSums[start..<(start + rowBand)]
            let n = part.reduce(0) { $0 + $1.count }
            guard n >= rowBand * w / 5 else { continue }
            means.append(Double(part.reduce(0) { $0 + $1.sum }) / Double(n))
        }
        result.paperRows = Int(((means.max() ?? 0) - (means.min() ?? 0)).rounded())
        result.printDarkness = darkestPrint(page, reading: reading)
        (result.signatureHue, result.signatureHueOff, result.signatureSaturation) =
            signature(page, x: Int(px(690)), y: Int(py(2560)), right: Int(px(1570)), bottom: Int(py(2880)))
        result.lineSpread = ScanForm.ruledLines.compactMap { line in
            spread(page, y: py(Double(line)), window: 80 * sy, from: px(260), to: px(2220)).map { $0 * to300 }
        }
        if variant.folds.count == 1 {
            let fold = py(variant.folds[0].at * Double(ScanForm.height))
            let steps = [160.0, 1240, 2320].compactMap { x in step(page, x: px(x), fold: fold, scale: sy) }
            result.foldStep = steps.max().map { $0 * to300 }
        }
        result.edgePixels = edges(page)
        (result.missing, result.added) = tokens(reading)
        return result
    }

    /// For each box of text read, the median of its darkest 5 % of
    /// pixels; then the median of those over the boxes.
    static func darkestPrint(_ page: ScanBitmap, reading: [Finder.TextLine]) -> Int {
        let w = page.width, h = page.height
        var values: [Int] = []
        for line in reading {
            let box = line.box
            let x0 = max(0, Int(box.minX * Double(w))), x1 = min(w, Int(box.maxX * Double(w)))
            let y0 = max(0, Int((1 - box.maxY) * Double(h))), y1 = min(h, Int((1 - box.minY) * Double(h)))
            guard x1 - x0 > 4, y1 - y0 > 4 else { continue }
            var pixels: [UInt8] = []
            for y in y0..<y1 { for x in x0..<x1 { pixels.append(page.brightness(x: x, y: y)) } }
            pixels.sort()
            let darkest = pixels.prefix(max(1, pixels.count / 20))
            values.append(Int(darkest[darkest.startIndex + darkest.count / 2]))
        }
        guard !values.isEmpty else { return 255 }
        return values.sorted()[values.count / 2]
    }

    /// The blue of the signature in a rectangle of the page: its strokes'
    /// mean hue, how far that is from the ink's, and their mean saturation.
    static func signature(_ page: ScanBitmap, x: Int, y: Int, right: Int, bottom: Int) -> (Double, Double, Double) {
        var sinSum = 0.0, cosSum = 0.0, saturation = 0.0, count = 0
        for yy in max(0, y)..<min(page.height, bottom) {
            for xx in max(0, x)..<min(page.width, right) {
                let (r, g, b) = page.color(x: xx, y: yy)
                let high = Double(max(r, g, b)), low = Double(min(r, g, b))
                guard high > 0, high < 235 else { continue }
                let s = (high - low) / high
                guard s > 0.3 else { continue }
                let angle = hue(Double(r), Double(g), Double(b)) * .pi / 180
                sinSum += sin(angle)
                cosSum += cos(angle)
                saturation += s
                count += 1
            }
        }
        guard count > 50 else { return (0, 180, 0) }
        var mean = atan2(sinSum, cosSum) * 180 / .pi
        if mean < 0 { mean += 360 }
        let off = abs(((mean - inkHue + 540).truncatingRemainder(dividingBy: 360)) - 180)
        return (mean, off, saturation / Double(count))
    }

    static func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard span > 0 else { return 0 }
        var hue: Double
        if high == r { hue = (g - b) / span } else if high == g { hue = 2 + (b - r) / span } else { hue = 4 + (r - g) / span }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    /// Pixels in a band 1 % wide along each edge dark enough to be what the
    /// sheet lay on rather than the sheet: the form prints nothing that
    /// close to its edges, and its own shadow there is lighter than this.
    static func edges(_ page: ScanBitmap) -> Int {
        let w = page.width, h = page.height
        let bx = max(1, w / 100), by = max(1, h / 100)
        var count = 0
        for y in 0..<h {
            for x in 0..<w where x < bx || x >= w - bx || y < by || y >= h - by {
                if page.brightness(x: x, y: y) < 170 { count += 1 }
            }
        }
        return count
    }

    /// A part of the form on a cleaned page, in the form's own pixels: the
    /// mean brightness of its pixels, and how far they spread, so a grey
    /// kept grey is still a shade with its own texture, not black or white.
    static func shade(_ page: ScanBitmap, of rect: CGRect,
                      frame: CGRect = CGRect(x: 0, y: 0, width: ScanForm.width, height: ScanForm.height))
        -> (mean: Double, spread: Double) {
        let sx = Double(page.width) / frame.width, sy = Double(page.height) / frame.height
        let x0 = max(0, Int((rect.minX - frame.minX) * sx)), x1 = min(page.width, Int((rect.maxX - frame.minX) * sx))
        let y0 = max(0, Int((rect.minY - frame.minY) * sy)), y1 = min(page.height, Int((rect.maxY - frame.minY) * sy))
        guard x0 < x1, y0 < y1 else { return (0, 0) }
        var values: [Double] = []
        for y in y0..<y1 {
            for x in x0..<x1 { values.append(Double(page.brightness(x: x, y: y))) }
        }
        values.sort()
        let mean = values.reduce(0, +) / Double(values.count)
        let low = values[values.count / 20], high = values[values.count - values.count / 20]
        return (mean, high - low)
    }

    /// A line's words and numbers, without the punctuation round them.
    static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: ",;:()·"))
        }.filter { !$0.isEmpty }
    }

    /// The form's words and numbers not read, and those read that are not on it.
    static func tokens(_ reading: [Finder.TextLine]) -> (missing: [String], added: [String]) {
        var known: [String: Int] = [:]
        for line in ScanForm.text { for token in tokens(of: line) { known[token, default: 0] += 1 } }
        var read: [String: Int] = [:]
        for line in reading { for token in tokens(of: line.string) { read[token, default: 0] += 1 } }
        let missing = known.flatMap { token, count in Array(repeating: token, count: max(0, count - (read[token] ?? 0))) }
        let added = read.keys.filter { known[$0] == nil }
        return (missing.sorted(), added.sorted())
    }

    /// Where a dark line crosses a column, within `window` of `around`:
    /// the middle of its darkness; nil where nothing is dark there.
    static func crossing(_ page: ScanBitmap, x: Int, around: Double, window: Double) -> Double? {
        let y0 = max(0, Int(around - window)), y1 = min(page.height - 1, Int(around + window))
        guard y0 < y1, x >= 1, x < page.width - 1 else { return nil }
        var best = y0, darkest = 255
        for y in y0...y1 {
            let a = Int(page.brightness(x: x - 1, y: y)), b = Int(page.brightness(x: x, y: y))
            let value = (a + b + Int(page.brightness(x: x + 1, y: y))) / 3
            if value < darkest {
                darkest = value
                best = y
            }
        }
        guard darkest < 170 else { return nil }
        return centre(of: (max(0, best - 5)...min(page.height - 1, best + 5)).map { y in (Double(y), page.brightness(x: x, y: y)) })
    }

    /// The darkness-weighted middle of a few pixels.
    static func centre(of pixels: [(Double, UInt8)]) -> Double? {
        var sum = 0.0, weight = 0.0
        for (at, value) in pixels {
            let dark = max(0, 200 - Double(value))
            sum += dark * at
            weight += dark
        }
        return weight > 0 ? sum / weight : nil
    }

    /// A long line followed from the middle out, column by column: how far
    /// it wanders up and down; nil where it is not found. The line is the
    /// row near `y` that runs darkest across the page, since a rule is dark
    /// the whole way while a line of print is dark here and there.
    static func spread(_ page: ScanBitmap, y: Double, window: Double, from: Double, to: Double) -> Double? {
        var rule: Double?
        var darkest = 0.0
        var row = (y - window).rounded(.down)
        while row <= y + window {
            guard row >= 0, row < Double(page.height) else { row += 1; continue }
            var dark = 0.0
            var x = from
            while x < to {
                if page.brightness(x: Int(x), y: Int(row)) < 170 { dark += 1 }
                x += 8
            }
            if dark > darkest { darkest = dark; rule = row }
            row += 1
        }
        // A rule runs dark across most of the page.
        guard darkest >= (to - from) / 8 / 2, let rule else { return nil }
        var found: [Double] = []
        var x = from
        while x < to {
            if let at = crossing(page, x: Int(x), around: rule, window: 6) { found.append(at) }
            x += 8
        }
        guard found.count > 20 else { return nil }
        // The columns where print above or below the line is darker, or the
        // line is broken, are left out: a twentieth at each end.
        found.sort()
        let trim = found.count / 20
        return (found[found.count - 1 - trim]) - found[trim]
    }

    /// An upright line near `x`, found a little above the fold and a little
    /// below it, each its middle over a few rows: how far the two stand
    /// apart there.
    static func step(_ page: ScanBitmap, x: Double, fold: Double, scale: Double) -> Double? {
        func column(at y: Int) -> Double? {
            let x0 = max(1, Int(x - 26 * scale)), x1 = min(page.width - 2, Int(x + 26 * scale))
            guard x0 < x1, y >= 0, y < page.height else { return nil }
            var best = x0, darkest = 255
            for xx in x0...x1 where Int(page.brightness(x: xx, y: y)) < darkest {
                darkest = Int(page.brightness(x: xx, y: y))
                best = xx
            }
            guard darkest < 170 else { return nil }
            return centre(of: (max(0, best - 5)...min(page.width - 1, best + 5)).map { (Double($0), page.brightness(x: $0, y: y)) })
        }
        func middle(_ rows: [Int]) -> Double? {
            let found = rows.compactMap { column(at: $0) }.sorted()
            guard found.count >= rows.count / 2 else { return nil }
            return found[found.count / 2]
        }
        let reach = 4 * scale
        let above = Array(stride(from: Int(fold - 34 * scale), to: Int(fold - reach), by: 2))
        let below = Array(stride(from: Int(fold + reach), to: Int(fold + 34 * scale), by: 2))
        guard let top = middle(above), let low = middle(below) else { return nil }
        return abs(top - low)
    }
}
#endif
