import Foundation
@testable import Tendedero

/// A made-up shop's invoice, printed on an office printer and scanned on a
/// flatbed, as a real one came: a large pale watermark in two colours, its
/// blue reaching the sheet's left edge and its yellow in the streaks a worn
/// printer leaves; a coloured logo and two grey seals; toner a little soft;
/// the scanner's lamp leaving the paper grey-blue; a crease across the
/// middle where the sheet was folded; laid a little crooked on the glass,
/// with the lid's shadow along the top and the right. Its shop, people and
/// numbers are all made up; never a real document.
///
/// The page is drawn here in shapes, its lines of text as strokes the size
/// of letters, so it is checked on any machine; `ScanInvoiceFixtureTests`
/// draws the same page with its words, to be read by Vision.
enum ScanInvoice {
    /// A4 at 300 dots an inch; the page is drawn at `scale` of it.
    static let width = 2480.0
    static let height = 3508.0

    struct Colour {
        let red: Double
        let green: Double
        let blue: Double
    }

    static let ink = Colour(red: 20, green: 20, blue: 22)
    static let teal = Colour(red: 22, green: 70, blue: 88)
    static let orange = Colour(red: 240, green: 128, blue: 30)
    static let paleBlue = Colour(red: 234, green: 242, blue: 250)
    static let paleYellow = Colour(red: 255, green: 244, blue: 205)

    /// The watermark's blue: a block from the left edge with a round hole,
    /// as a large "2" is.
    static let blueBlock = (x0: 0.0, y0: 1980.0, x1: 1100.0, y1: 2900.0)
    static let blueHole = (cx: 550.0, cy: 2500.0, r: 400.0)
    /// The watermark's yellow: a slanted shape with a gap at its foot.
    static let yellowTop = 1950.0, yellowBottom = 3300.0
    static let yellowGap = (x0: 1250.0, y0: 2650.0, x1: 1450.0, y1: 3300.0)
    /// The logo's orange box, and the two grey seals, by their middles.
    static let logo = (x0: 1150.0, y0: 200.0, x1: 1330.0, y1: 400.0)
    static let seals = [(cx: 1980.0, cy: 300.0), (cx: 2230.0, cy: 300.0)]
    /// Where the sheet was folded, as a share of its height from the top.
    static let crease = 0.505
    /// How crooked it lay on the glass, in degrees, and the lid's shadow.
    static let tilt = 0.35
    static let lidTop = 28.0, lidRight = 22.0

    /// Rules, from the page's top left: ink, then orange.
    static let rules: [(x0: Double, y0: Double, x1: Double, y1: Double, orange: Bool)] = [
        (60, 470, 1600, 476, false), (1650, 468, 1820, 474, true), (200, 960, 450, 964, true),
        (200, 1720, 2320, 1724, false), (200, 1940, 1780, 1944, false), (1840, 1940, 2320, 1944, true),
        (170, 3180, 174, 3440, true), (730, 3180, 734, 3440, true), (1290, 3180, 1294, 3440, true),
        (1850, 3180, 1854, 3440, true),
    ]

    /// A line of text: what it says, where it starts, its top, its size in
    /// pixels at 300 dots an inch, and whether it is bold.
    struct Line {
        let text: String
        let x: Double
        let top: Double
        let size: Double
        let bold: Bool

        /// About where its letters lie.
        var box: (x0: Double, y0: Double, x1: Double, y1: Double) {
            (x, top, x + Double(text.count) * size * 0.55, top + size * 1.05)
        }
    }

    static let lines: [Line] = {
        var lines: [Line] = []
        func add(_ text: String, _ x: Double, _ top: Double, _ size: Double = 44, bold: Bool = false) {
            lines.append(Line(text: text, x: x, top: top, size: size, bold: bold))
        }
        add("MUSTERHANDEL", 200, 230, 120, bold: true)
        add("Musterhandel24 GmbH", 1880, 520, 42, bold: true)
        for (index, text) in ["Beispielallee 9", "12345 Musterstadt", "", "Tel.: 0800 12 345 67",
                              "info@musterhandel.example", "www.musterhandel.example", "",
                              "Kunden-Nr.: 200123456", "USt-IdNr.: DE123456789", "Bestell-Nr.: 765432",
                              "Datum: 12.06.2026"].enumerated() where !text.isEmpty {
            add(text, 1880, 575 + Double(index) * 55, 40)
        }
        add("Rechnung", 200, 690, 110, bold: true)
        add("Musterhandel24 GmbH - Beispielallee 9 - 12345 Musterstadt", 200, 900, 38)
        for (index, text) in ["Erika Mustermann", "Musterweg 1", "12345 Musterstadt", "GERMANY"].enumerated() {
            add(text, 200, 1000 + Double(index) * 55)
        }
        add("Rechnung Nr. 100012345", 200, 1450, 72, bold: true)
        add("Seite 1 von 1", 200, 1540)
        for (x, text) in [(200.0, "Pos."), (360, "Art-Nr."), (700, "Bezeichnung"), (1700, "Anz."), (1840, "MwSt."),
                          (2040, "Preis"), (2200, "Betrag")] {
            add(text, x, 1660, 42, bold: true)
        }
        for (row, cells) in [["1", "241821065.1", "Office Paket Box", "1", "19 %", "59,95 €", "59,95 €"],
                             ["2", "", "Versandkosten", "1", "19 %", "4,95 €", "4,95 €"]].enumerated() {
            for (x, text) in zip([200.0, 360, 700, 1730, 1840, 2010, 2190], cells) where !text.isEmpty {
                add(text, x, 1750 + Double(row) * 80, 42)
            }
        }
        add("Gesamtpreis Netto: 54,54 €", 1850, 1990, 42)
        add("zzgl. 19 % MwSt: 10,36 €", 1850, 2060, 42)
        add("Gesamtpreis: 64,90 €", 1800, 2150, 56, bold: true)
        add("Gewählte Zahlungsart: PayPal", 200, 2930)
        add("Gewählte Versandart: Paketversand (Standard)", 200, 3000)
        for (column, texts) in [["Musterhandel24 GmbH", "Beispielallee 9", "12345 Musterstadt"],
                                ["Bankverbindung:", "IBAN: DE02120300000000202051", "BIC: BYLADEM1001"],
                                ["Amtsgericht Musterstadt", "UST-ID: DE987654321", "HRB 123456"],
                                ["Geschäftsführer:", "Max Beispiel"]].enumerated() {
            for (index, text) in texts.enumerated() {
                add(text, 200 + Double(column) * 560, 3200 + Double(index) * 45, 30)
            }
        }
        return lines
    }()

    // MARK: Where things are

    static func inBlue(_ x: Double, _ y: Double) -> Bool {
        let b = blueBlock
        guard x >= b.x0, x < b.x1, y >= b.y0, y < b.y1 else { return false }
        let dx = x - blueHole.cx, dy = y - blueHole.cy
        return dx * dx + dy * dy > blueHole.r * blueHole.r
    }

    static func inYellow(_ x: Double, _ y: Double) -> Bool {
        guard y >= yellowTop, y < yellowBottom, x < 1800 else { return false }
        // Its slanted left side, from (900, bottom) to (1550, top).
        let left = 900 + (yellowBottom - y) / (yellowBottom - yellowTop) * 650
        guard x >= left else { return false }
        let gap = yellowGap
        return !(x >= gap.x0 && x < gap.x1 && y >= gap.y0)
    }

    // MARK: The page

    /// The page as printed, drawn in shapes at `scale` of 300 dots an inch:
    /// its text as strokes where its letters are.
    static func page(scale: Double) -> ScanBitmap {
        let w = Int(width * scale), h = Int(height * scale)
        var page = ScanBitmap(width: w, height: h, red: 255, green: 255, blue: 255)
        background(&page, scale: scale)
        for line in lines { strokes(line, on: &page, scale: scale) }
        return page
    }

    /// The watermark, the logo, the seals and the rules: all but the text.
    static func background(_ page: inout ScanBitmap, scale: Double) {
        let w = page.width, h = page.height
        for y in 0..<h {
            let py = (Double(y) + 0.5) / scale
            for x in 0..<w {
                let px = (Double(x) + 0.5) / scale
                var colour = Colour(red: 255, green: 255, blue: 255)
                if inBlue(px, py) { colour = paleBlue }
                if inYellow(px, py) {
                    colour = Colour(red: colour.red * paleYellow.red / 255, green: colour.green * paleYellow.green / 255,
                                    blue: colour.blue * paleYellow.blue / 255)
                }
                if px >= logo.x0, px < logo.x1, py >= logo.y0, py < logo.y1 {
                    let inner = px >= logo.x0 + 20 && px < logo.x1 - 20 && py >= logo.y0 + 20 && py < logo.y1 - 20
                    colour = inner ? teal : orange
                }
                for seal in seals {
                    let d = ((px - seal.cx) * (px - seal.cx) + (py - seal.cy) * (py - seal.cy)).squareRoot()
                    if d < 100 { colour = d < 70 ? Colour(red: 205, green: 205, blue: 205) : Colour(red: 150, green: 150, blue: 150) }
                }
                for rule in rules where px >= rule.x0 && px < rule.x1 && py >= rule.y0 && py < rule.y1 {
                    colour = rule.orange ? orange : ink
                }
                set(&page, x, y, colour)
            }
        }
    }

    /// A line's letters as strokes: an upright for each, a bar across every
    /// other, as thick as its print, in teal for the logo and ink for the rest.
    static func strokes(_ line: Line, on page: inout ScanBitmap, scale: Double) {
        let colour = line.text == "MUSTERHANDEL" ? teal : ink
        let advance = line.size * 0.55, stroke = line.size * (line.bold ? 0.14 : 0.09)
        let top = line.top + line.size * 0.2, bottom = line.top + line.size * 0.92
        for (index, character) in line.text.enumerated() where character != " " {
            let left = line.x + Double(index) * advance + advance * 0.2
            fill(&page, left, top, left + stroke, bottom, colour, scale)
            fill(&page, left + advance * 0.45, top + line.size * 0.15, left + advance * 0.45 + stroke, bottom, colour, scale)
            if index % 2 == 0 {
                let middle = (top + bottom) / 2
                fill(&page, left, middle, left + advance * 0.45 + stroke, middle + stroke, colour, scale)
            }
        }
    }

    private static func fill(_ page: inout ScanBitmap, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                             _ colour: Colour, _ scale: Double) {
        let left = max(0, Int((x0 * scale).rounded())), right = min(page.width, max(left + 1, Int((x1 * scale).rounded())))
        let top = max(0, Int((y0 * scale).rounded())), bottom = min(page.height, max(top + 1, Int((y1 * scale).rounded())))
        guard left < right, top < bottom else { return }
        for y in top..<bottom { for x in left..<right { set(&page, x, y, colour) } }
    }

    private static func set(_ page: inout ScanBitmap, _ x: Int, _ y: Int, _ colour: Colour) {
        let i = (y * page.width + x) * 4
        page.pixels[i] = UInt8(max(0, min(255, colour.red.rounded())))
        page.pixels[i + 1] = UInt8(max(0, min(255, colour.green.rounded())))
        page.pixels[i + 2] = UInt8(max(0, min(255, colour.blue.rounded())))
    }

    // MARK: The scan

    /// The printed page as the printer and the scanner leave it, at the same
    /// size: the yellow in streaks, the toner soft, the lamp's grey-blue
    /// light dimmer to the sides, the crease, laid crooked with the lid's
    /// shadow along the top and right, a little grain and blur.
    static func scanned(_ page: ScanBitmap, scale: Double) -> ScanBitmap {
        let w = page.width, h = page.height
        var light = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            let py = (Double(y) + 0.5) / scale
            let v = Double(y) / Double(h)
            let off = (py - crease * height)
            var fold = 1 - 0.13 * exp(-pow(off / 2, 2)) + 0.05 * exp(-pow((off + 6) / 3, 2))
            fold *= 1 - 0.05 * exp(-pow(off / 40, 2))
            if off > 0 { fold *= 0.985 }
            for x in 0..<w {
                let px = (Double(x) + 0.5) / scale
                let u = Double(x) / Double(w)
                let i = (y * w + x) * 4
                // A worn drum: the yellow streaked down the page, darker in bands.
                let streak = inYellow(px, py) ? 0.9 * (0.5 + 0.5 * sin(px / 3.1)) * (0.5 + 0.5 * sin(px / 37 + 1)) : 0
                let lamp = 0.90 - 0.12 * ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5))
                for k in 0..<3 {
                    let printed = Double(page.pixels[i + k]) / 255
                    let toner = 0.12 + 0.88 * (printed - (1 - printed) * streak)
                    let tint = k == 0 ? 0.97 : (k == 1 ? 0.985 : 1.0)
                    light[(y * w + x) * 3 + k] = Float(toner * lamp * tint * fold)
                }
            }
        }
        // Laid crooked on the glass: turned about the middle, the glass
        // round it dark.
        var out = ScanBitmap(width: w, height: h, red: 70, green: 72, blue: 76)
        let angle = tilt * .pi / 180, c = cos(angle), s = sin(angle)
        let mx = Double(w) / 2, my = Double(h) / 2
        var seed: UInt32 = 11
        func grain() -> Double {
            var sum = 0.0
            for _ in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                sum += Double(seed >> 8) / Double(1 << 24) - 0.5
            }
            return sum * 2.2 * 2
        }
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) - mx, dy = Double(y) - my
                let sx = c * dx + s * dy + mx, sy = -s * dx + c * dy + my
                let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down))
                let i = (y * w + x) * 4
                var shade = 1.0
                if Double(y) < lidTop * scale { shade *= 0.45 }
                if Double(x) >= Double(w) - lidRight * scale { shade *= 0.6 }
                guard x0 >= 0, y0 >= 0, x0 + 1 < w, y0 + 1 < h else {
                    for k in 0..<3 { out.pixels[i + k] = UInt8(max(0, min(255, Double(out.pixels[i + k]) * shade + grain()))) }
                    continue
                }
                let tx = sx - Double(x0), ty = sy - Double(y0)
                for k in 0..<3 {
                    func at(_ xx: Int, _ yy: Int) -> Double { Double(light[(yy * w + xx) * 3 + k]) }
                    let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
                    let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
                    let value = (top * (1 - ty) + bottom * ty) * 255 * shade + grain()
                    out.pixels[i + k] = UInt8(max(0, min(255, value.rounded())))
                }
            }
        }
        // The scanner's own softness.
        var soft = out
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                for k in 0..<3 {
                    var sum = 0
                    for (dy, wy) in [(-1, 1), (0, 2), (1, 1)] {
                        for (dx, wx) in [(-1, 1), (0, 2), (1, 1)] { sum += Int(out.pixels[((y + dy) * w + x + dx) * 4 + k]) * wy * wx }
                    }
                    soft.pixels[(y * w + x) * 4 + k] = UInt8((sum + 8) / 16)
                }
            }
        }
        return soft
    }
}

/// The brief's numbers on a cleaned page of the made-up invoice, in its own
/// pixels: where the page's point (x, y) at 300 dots an inch lies is
/// `x * scale - left`, `y * scale - top`, the parts cut from its edges taken
/// off. Each part is measured away from its edges by `margin`, at 300 dots
/// an inch, so a page turned a little or cut a little is measured the same.
struct ScanInvoiceMeasures: CustomStringConvertible {
    /// Of the paper's pixels, the share at 250 and brighter; the most and
    /// least bright bands of its rows, apart; its mean saturation.
    var paperWhite = 0.0
    var paperRows = 0
    var paperSaturation = 0.0
    /// The darkest row of the margin where the crease crosses it.
    var crease = 0
    /// The watermark's blue: its mean, how far it spreads, the same near
    /// the sheet's edge and in its middle, and its hue; the yellow's mean
    /// and hue; the logo's orange hue; the outer ring of a seal.
    var blue = (mean: 0.0, spread: 0.0, hue: 0.0)
    var blueAtEdge = 0.0
    var blueInMiddle = 0.0
    var yellow = (mean: 0.0, spread: 0.0, hue: 0.0)
    var orangeHue = 0.0
    var seal = 0.0
    /// The middle of the darkest 5 % in each line of text, over the lines.
    var printDarkness = 255
    /// Pixels darker than 170 in a band 1 % wide along the edges.
    var edgePixels = 0

    var description: String {
        String(format: "paper≥250 %.1f%% rows±%d sat %.3f crease %d blue %.0f (±%.0f, hue %.0f°, edge %.0f middle %.0f) "
               + "yellow %.0f (±%.0f, hue %.0f°) orange %.0f° seal %.0f print %d edge %d",
               paperWhite * 100, paperRows, paperSaturation, crease, blue.mean, blue.spread, blue.hue, blueAtEdge,
               blueInMiddle, yellow.mean, yellow.spread, yellow.hue, orangeHue, seal, printDarkness, edgePixels)
    }
}

enum ScanInvoiceMeasure {
    /// How far a cleaned page was cut in from its left and its top, read
    /// from where the logo's orange frame lies on it; nil where none is seen.
    static func offset(of page: ScanBitmap, scale: Double) -> (left: Int, top: Int)? {
        var left = Int.max, top = Int.max
        for y in 0..<min(page.height, page.height / 6) {
            for x in 0..<page.width {
                let (r, g, b) = page.color(x: x, y: y)
                let high = Double(max(r, g, b)), low = Double(min(r, g, b))
                guard high > 150, (high - low) / high > 0.6 else { continue }
                let hue = ScanColourSample.hue(Double(r), Double(g), Double(b))
                guard hue > 15, hue < 45 else { continue }
                left = min(left, x)
                top = min(top, y)
            }
        }
        guard left != .max else { return nil }
        return (Int((ScanInvoice.logo.x0 * scale).rounded()) - left, Int((ScanInvoice.logo.y0 * scale).rounded()) - top)
    }

    static func measure(_ page: ScanBitmap, scale: Double, left: Int = 0, top: Int = 0, margin: Double = 40,
                        textBoxes: [(x0: Int, y0: Int, x1: Int, y1: Int)]? = nil) -> ScanInvoiceMeasures {
        var result = ScanInvoiceMeasures()
        let w = page.width, h = page.height
        func px(_ x: Double) -> Int { Int((x * scale).rounded()) - left }
        func py(_ y: Double) -> Int { Int((y * scale).rounded()) - top }
        // Back from a pixel to the page's point.
        func point(_ x: Int, _ y: Int) -> (Double, Double) { ((Double(x + left) + 0.5) / scale, (Double(y + top) + 0.5) / scale) }
        // Whether a page's point is within `reach` of print, at 300 dots an inch.
        var printed = [Bool](repeating: false, count: w * h)
        func mark(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ reach: Double) {
            for y in max(0, py(y0 - reach))..<min(h, max(0, py(y1 + reach))) {
                for x in max(0, px(x0 - reach))..<min(w, max(0, px(x1 + reach))) { printed[y * w + x] = true }
            }
        }
        for line in ScanInvoice.lines { mark(line.box.x0, line.box.y0, line.box.x1, line.box.y1, margin) }
        for rule in ScanInvoice.rules { mark(rule.x0, rule.y0, rule.x1, rule.y1, margin) }
        mark(ScanInvoice.logo.x0, ScanInvoice.logo.y0, ScanInvoice.logo.x1, ScanInvoice.logo.y1, margin)
        for seal in ScanInvoice.seals { mark(seal.cx - 100, seal.cy - 100, seal.cx + 100, seal.cy + 100, margin) }
        for box in textBoxes ?? [] {
            for y in max(0, box.y0)..<min(h, max(0, box.y1)) { for x in max(0, box.x0)..<min(w, max(0, box.x1)) { printed[y * w + x] = true } }
        }
        // Whether a pixel lies well inside a part of the watermark, or well clear of it.
        func inside(_ test: (Double, Double) -> Bool, _ x: Int, _ y: Int, by reach: Double) -> Bool {
            let (u, v) = point(x, y)
            return test(u, v) && test(u - reach, v) && test(u + reach, v) && test(u, v - reach) && test(u, v + reach)
        }
        func near(_ test: (Double, Double) -> Bool, _ x: Int, _ y: Int, by reach: Double) -> Bool {
            let (u, v) = point(x, y)
            for du in [-reach, 0, reach] { for dv in [-reach, 0, reach] where test(u + du, v + dv) { return true } }
            return false
        }
        let band = (x: max(2, w / 66), y: max(2, h / 66))
        var white = 0, count = 0, saturation = 0.0
        var rows = [(sum: Int, count: Int)](repeating: (0, 0), count: h)
        var blue: [ScanColourSample] = [], yellow: [ScanColourSample] = [], edge: [Double] = [], middle: [Double] = []
        // Every other pixel each way at 300 dots an inch is plenty, and quicker.
        let every = max(1, Int((scale * 2).rounded(.down)))
        for y in stride(from: band.y, to: h - band.y, by: every) {
            for x in stride(from: band.x, to: w - band.x, by: every) {
                let (r, g, b) = page.color(x: x, y: y)
                let value = Int(ScanClean.brightness(r, g, b))
                let sample = ScanColourSample(red: Double(r), green: Double(g), blue: Double(b), value: Double(value))
                let isPrint = printed[y * w + x]
                if !isPrint, inside(ScanInvoice.inBlue, x, y, by: margin), !near(ScanInvoice.inYellow, x, y, by: margin) {
                    blue.append(sample)
                    let (u, _) = point(x, y)
                    if u < 300 { edge.append(sample.value) } else if u > 500 { middle.append(sample.value) }
                }
                if !isPrint, inside(ScanInvoice.inYellow, x, y, by: margin), !near(ScanInvoice.inBlue, x, y, by: margin) {
                    yellow.append(sample)
                }
                guard !isPrint, !near(ScanInvoice.inBlue, x, y, by: margin), !near(ScanInvoice.inYellow, x, y, by: margin)
                else { continue }
                if value >= 250 { white += 1 }
                count += 1
                let high = Double(max(r, g, b)), low = Double(min(r, g, b))
                saturation += high > 0 ? (high - low) / high : 0
                rows[y].sum += value
                rows[y].count += 1
            }
        }
        result.paperWhite = Double(white) / Double(max(1, count))
        result.paperSaturation = saturation / Double(max(1, count))
        let rowBand = max(1, h / 100)
        var means: [Double] = []
        for start in stride(from: band.y, to: h - band.y - rowBand, by: rowBand) {
            let part = rows[start..<(start + rowBand)]
            let n = part.reduce(0) { $0 + $1.count }
            guard n >= rowBand * w / 5 / (every * every) else { continue }
            means.append(Double(part.reduce(0) { $0 + $1.sum }) / Double(n))
        }
        result.paperRows = Int(((means.max() ?? 0) - (means.min() ?? 0)).rounded())
        // The crease in the left margin, where nothing is printed.
        var darkest = 255.0
        for y in max(0, py(ScanInvoice.crease * ScanInvoice.height - 40))..<min(h, py(ScanInvoice.crease * ScanInvoice.height + 40)) {
            var sum = 0.0, n = 0.0
            for x in max(band.x, px(40))..<min(w, px(170)) {
                sum += Double(page.brightness(x: x, y: y))
                n += 1
            }
            if n > 0 { darkest = min(darkest, sum / n) }
        }
        result.crease = Int(darkest.rounded())
        result.blue = ScanColourSample.summary(blue)
        result.blueAtEdge = edge.isEmpty ? 0 : edge.reduce(0, +) / Double(edge.count)
        result.blueInMiddle = middle.isEmpty ? 0 : middle.reduce(0, +) / Double(middle.count)
        result.yellow = ScanColourSample.summary(yellow)
        // The logo's orange frame, and a seal's outer ring.
        var orange: [ScanColourSample] = [], seal: [Double] = []
        for y in stride(from: 0, to: h, by: every) {
            for x in stride(from: 0, to: w, by: every) {
                let (u, v) = point(x, y)
                let (r, g, b) = page.color(x: x, y: y)
                if u > ScanInvoice.logo.x0 + 4, u < ScanInvoice.logo.x0 + 14, v > ScanInvoice.logo.y0 + 30, v < ScanInvoice.logo.y1 - 30 {
                    orange.append(ScanColourSample(red: Double(r), green: Double(g), blue: Double(b), value: 0))
                }
                let seal0 = ScanInvoice.seals[0]
                let d = ((u - seal0.cx) * (u - seal0.cx) + (v - seal0.cy) * (v - seal0.cy)).squareRoot()
                if d > 78, d < 92 { seal.append(Double(ScanClean.brightness(r, g, b))) }
            }
        }
        result.orangeHue = ScanColourSample.summary(orange).hue
        result.seal = seal.isEmpty ? 0 : seal.reduce(0, +) / Double(seal.count)
        // The print: in each line's box, or each box read.
        let boxes = textBoxes ?? ScanInvoice.lines.map { line in
            (px(line.box.x0), py(line.box.y0), px(line.box.x1), py(line.box.y1))
        }
        var values: [Int] = []
        for box in boxes {
            var pixels: [UInt8] = []
            for y in max(0, box.y0)..<min(h, max(0, box.y1)) {
                for x in max(0, box.x0)..<min(w, max(0, box.x1)) { pixels.append(page.brightness(x: x, y: y)) }
            }
            guard pixels.count > 20 else { continue }
            pixels.sort()
            let darkest = pixels.prefix(max(1, pixels.count / 20))
            values.append(Int(darkest[darkest.startIndex + darkest.count / 2]))
        }
        result.printDarkness = values.isEmpty ? 255 : values.sorted()[values.count / 2]
        let bx = max(1, w / 100), by = max(1, h / 100)
        for y in 0..<h {
            for x in 0..<w where x < bx || x >= w - bx || y < by || y >= h - by {
                if page.brightness(x: x, y: y) < 170 { result.edgePixels += 1 }
            }
        }
        return result
    }
}

/// A pixel's colour and brightness, and over many of them their mean
/// brightness, how far it spreads, and their mean hue in degrees.
struct ScanColourSample {
    let red: Double
    let green: Double
    let blue: Double
    let value: Double

    static func summary(_ samples: [ScanColourSample]) -> (mean: Double, spread: Double, hue: Double) {
        guard !samples.isEmpty else { return (0, 0, 0) }
        let values = samples.map(\.value).sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        let spread = values[values.count - 1 - values.count / 20] - values[values.count / 20]
        let r = samples.reduce(0) { $0 + $1.red } / Double(samples.count)
        let g = samples.reduce(0) { $0 + $1.green } / Double(samples.count)
        let b = samples.reduce(0) { $0 + $1.blue } / Double(samples.count)
        return (mean, spread, hue(r, g, b))
    }

    static func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard span > 0 else { return 0 }
        var hue: Double
        if high == r { hue = (g - b) / span } else if high == g { hue = 2 + (b - r) / span } else { hue = 4 + (r - g) / span }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    /// How far apart two hues are, in degrees.
    static func apart(_ a: Double, _ b: Double) -> Double {
        abs(((a - b + 540).truncatingRemainder(dividingBy: 360)) - 180)
    }
}
