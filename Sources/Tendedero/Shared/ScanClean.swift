import CoreGraphics
import Foundation

/// How a scanned page keeps its colours: in colour, a logo and a stamp as
/// they are; in greys; or in black and white, the smallest file, where pale
/// marks can go.
enum ScanColor: String, CaseIterable, Identifiable, Sendable {
    case color, gray, blackAndWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: L("Color")
        case .gray: L("Grayscale")
        case .blackAndWhite: L("Black and white")
        }
    }

    /// What it does to the page, under its name in the menu; nil where
    /// there is nothing to add.
    var detail: String? {
        switch self {
        case .color: L("Logos stay in color")
        case .gray: nil
        case .blackAndWhite: L("Smallest file, pale stamps can go")
        }
    }

    /// Whether its pages are grey only, so they are kept and sent with one
    /// channel.
    var isGray: Bool { self != .color }
}

/// A page's pixels to clean: red, green and blue, 8 bits each, and a fourth
/// byte that is not used, row after row from the top.
struct ScanBitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height * 4, "not a page's pixels")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A page of one colour.
    init(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red
            pixels[i + 1] = green
            pixels[i + 2] = blue
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    func color(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    /// How bright a pixel is, from 0 to 255, as the eye weighs the colours.
    func brightness(x: Int, y: Int) -> UInt8 {
        let i = (y * width + x) * 4
        return ScanClean.brightness(pixels[i], pixels[i + 1], pixels[i + 2])
    }

    /// Every pixel's brightness, row after row from the top.
    var brightness: [UInt8] {
        var plane = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeBufferPointer { px in
            plane.withUnsafeMutableBufferPointer { out in
                for p in 0..<out.count {
                    out[p] = ScanClean.brightness(px[p * 4], px[p * 4 + 1], px[p * 4 + 2])
                }
            }
        }
        return plane
    }
}

/// A page cleaned as a good scanner leaves it: its light made even and its
/// paper white, the colour cast of the lamp taken away, the paper's grain
/// smoothed, the print a little firmer and its edges a little clearer; then,
/// where asked, in greys or in black and white. Each pixel is only made
/// lighter or darker by what is around it, never moved, so nothing on the
/// page is drawn, removed or changed: a stroke, a stamp, a signature and
/// every number stay where and what they are. Only black and white can lose
/// a mark too pale to tell from the paper, which its menu says.
///
/// The paper's colour is measured in cells across the page: the commonest
/// value among the brighter half of a cell's pixels, which neither its print
/// nor a camera's bright specks move. A cell much darker than the page, or
/// than the cells around it, holds a photo, a filled box or a band of
/// colour, not paper, and is left out and filled in from its neighbours, so
/// what is printed keeps its shade; the cells are then smoothed, so only the
/// light's slow changes across the page are followed. Each pixel is divided
/// by the paper's colour where it is, which evens the light and whitens the
/// paper in one step; the grain left is smoothed where neighbours are alike,
/// never across an edge; then a gentle curve makes the paper white and the
/// print a little darker.
enum ScanClean {
    struct Tuning: Equatable, Sendable {
        /// A cell's side, as a share of the page's shorter side.
        var cell = 1.0 / 60
        /// A cell darker than this share of the page's paper holds print.
        var printFloor: Float = 0.45
        /// Or darker than this share of cells on both sides of it, like a
        /// table's grey header, which keeps its grey.
        var localFloor: Float = 0.94
        /// Or darker than this share of cells on both sides of it, as a pale
        /// watermark or a shaded row is: print, keeping its shade, where its
        /// edge is sharp (`edgeShare`); light, evened, where it is not.
        var paleFloor: Float = 0.985
        /// In and round a pale fill, a pixel this share of its paper and
        /// more in every colour is the paper's grain, and white.
        var fillWhite: Float = 0.985
        /// A pale fill's edge is sharper than this, from 0 to 1: a printed
        /// one, not a soft shade of the light.
        var fillEdgeShare: Float = 0.6
        /// And a fill is this many cells at least: a watermark or a shaded row,
        /// not a speck of a shadow's grain.
        var fillCells = 60
        var fillSolid = 0.4
        /// And no larger than this share of the page: a fold's lower part, a
        /// whole half darker for its angle, is light, not a fill.
        var fillLargest = 0.15
        /// How many cells each way count as its sides: a filled box up to
        /// twice as wide keeps its fill all through.
        var around = 12
        /// A darker patch is print, keeping its shade, where this share of
        /// the change at its edge is made from one block (a quarter cell)
        /// to the next; light, as a fold's or a shadow's, where it is spread
        /// out more. Read only where the change is `edgeContrast` levels or more.
        var edgeShare: Float = 0.42
        var edgeContrast: Float = 8
        /// A crease (`uncreased`) is a dip in the paper of this many levels
        /// and more, to no darker than `creaseFaint` of the paper beside it,
        /// in `creaseReach` of the strips along it, the two at its ends
        /// among them, and slanted at most `creaseSlant`.
        var creaseStrips = 32
        var creaseDepth: Float = 4
        var creaseFaint: Float = 0.6
        var creaseReach = 0.85
        var creaseSlant = 0.01
        /// Passes of a cell's mean with its eight neighbours.
        var smoothing = 1
        /// A dim part of the page is brightened at most as if its paper
        /// were this share of the page's.
        var dimmest: Float = 0.3
        /// Paper darker than this, of 255, is no light page: its light is
        /// left as it is, so a dark screen photographed keeps its words.
        var darkestPaper: Float = 100
        /// The paper a cell has, taken this share of it: the paper's own
        /// grain and the blocks' over-bright reading are under it, so what
        /// is paper shows white, and print keeps its shade.
        var headroom: Float = 0.95
        /// Within the lines of light neutral print read (`lightPrint`), the
        /// paper is taken at its own level instead: a mark a little darker than the paper, an
        /// umlaut's dot, an accent or a thin grey stroke, keeps all of its
        /// contrast, and the grain there is left to the line's own toning
        /// (`toned`) and to the curve.
        var textHeadroom: Float = 1
        /// The grain: neighbours this close to a pixel, of 255, are smoothed
        /// with it; an edge, further apart, never is. Within the lines of
        /// light print read, `textGrain`, so a faint mark's rim is not
        /// smoothed away.
        var grain = 10
        var textGrain = 4
        /// After the light is evened, this share of white and more is white:
        /// the paper's grain below its commonest value, while a table's
        /// light grey header stays grey.
        var whitePoint: Float = 0.96
        /// And this share and less is black.
        var blackPoint: Float = 0.04
        /// Above 1, the print's greys a little darker.
        var gamma: Float = 1.15
        /// The print's own darkness: of the pixels the paper around them makes
        /// strokes, the darkest `printShare`'s middle, of 255, taken to
        /// `printTarget` by a higher black point where it is light, as a
        /// typewriter's or a carbon copy's print is; never above `highestBlack`
        /// of white. A wide grey fill, whose paper is not around it, takes no
        /// part, so a table's header and a photo keep their shade.
        var printShare: Float = 0.25
        /// A pixel this far under the paper around it, of 255, is a stroke.
        var printContrast: Float = 10
        /// The light is evened by the blocks' paper only where a pixel is
        /// this share of it and more: a stroke, much darker, is left to the
        /// print's own tuning, so evened light never lightens print.
        var printEdge: Float = 0.78
        /// A pixel under this share of the brightest close round it is a
        /// stroke, and is evened by the cell's paper alone.
        var strokeBelow: Float = 0.95
        var printTarget: Float = 30
        var highestBlack: Float = 0.75
        /// Faint print (`strengthened`): a patch whose strokes stand out by
        /// less than `faintTarget`, of 255, is deepened toward it, at most
        /// `faintGain` times, by what each stroke stands out past
        /// `faintFloor`, the grain.
        var faintFloor: Float = 6
        var faintTarget: Float = 70
        var faintGain: Float = 4
        /// Colour weaker than `neutralBelow`, against how bright a pixel
        /// is, is taken away once the paper's colour is divided out, as
        /// tinted paper leaves on its print; stronger than `colourAbove`
        /// is kept whole, as a ballpoint's, a stamp's or a logo's.
        var neutralBelow: Float = 0.1
        var colourAbove: Float = 0.24
        /// How much an edge is made clearer, and by how many levels it must
        /// stand out first, so what is left of the grain is left alone.
        var sharpen: Float = 0.6
        var sharpenThreshold: Float = 3
        /// Light print, line by line (`toned`): where a line's darkest ink,
        /// of 255, is lighter than `lightInk`, and wholly from `lightInkFull`
        /// on, its ink is taken to `lineInk`, at most `lineGain` times, in
        /// windows `lineWindow` times the line's height wide; its smallest
        /// marks made as clear as its strokes by `lineSharpen`; and what is
        /// within `lineGrain` times the paper's spread of the paper, white.
        /// A window of paper darker than `linePaper` is a fill, left as it is.
        /// Only print lighter than the page's own dark print by `lightApart`
        /// counts (`lightPrint`). Where the body of a line's ink, its darkest
        /// `lineBody` share, would stay lighter than `lineDark`, the line is
        /// toned further, up to `lineDrive` times.
        var lightInk: Float = 100
        var lightInkFull: Float = 140
        var lineInk: Float = 6
        var lineGain: Float = 5
        var lineDark: Float = 60
        var lineBody: Float = 0.1
        var lineDrive: Float = 2
        var lightApart: Float = 40
        var lineWindow: Float = 4
        var lineSharpen: Float = 1.4
        var lineGrain: Float = 2.5
        var linePaper: Float = 240
        /// Black and white, against the mean brightness around a pixel in a
        /// window this share of the shorter side: darker than `dark` of it
        /// is print; darker than `pale` of it is print only where it
        /// touches print, so a stroke keeps its edges and a pale line is
        /// kept or left out whole, never in dashes.
        var window = 1.0 / 16
        var dark: Float = 0.86
        var pale: Float = 0.93
        /// This dark and darker is print, whatever is around.
        var alwaysBlack: UInt8 = 100

        static let standard = Tuning()
    }

    /// The page cleaned in the colours asked for.
    static func clean(_ page: ScanBitmap, _ mode: ScanColor, tuning: Tuning = .standard,
                      printBoxes: [CGRect] = []) -> ScanBitmap {
        cleaned(page, mode, tuning: tuning, printBoxes: printBoxes).page
    }

    /// A page cleaned, with the page as it was before its print was toned
    /// (`base`): what a line goes back to where cleaning would change what
    /// it says (`ScanCleaner`).
    struct Cleaned {
        let page: ScanBitmap
        let base: ScanBitmap
        /// The boxes of light print, toned line by line (`lightPrint`).
        let light: [CGRect]
    }

    /// The page cleaned in the colours asked for, and its base.
    static func cleaned(_ page: ScanBitmap, _ mode: ScanColor, tuning: Tuning = .standard,
                        printBoxes: [CGRect] = []) -> Cleaned {
        let white = Int((tuning.whitePoint * 255).rounded(.up))
        let paper = Paper(of: page, tuning: tuning)
        // Where text was read: only there is faint print looked for, and
        // small marks kept whole.
        let text = textMask(printBoxes, width: page.width, height: page.height)
        // Light print, a grey column beside the body, is evened at its paper's
        // own level, smoothed less and toned line by line, so its faintest marks stay.
        let light = lightPrint(printBoxes, in: page, tuning: tuning)
        let lines = printLines(light, width: page.width, height: page.height)
        let faint = textMask(light, width: page.width, height: page.height)
        let flat = uncreased(evened(page, paper: paper, tuning: tuning, text: text, faint: faint), tuning: tuning)
        let even = neutralized(denoised(flat, grain: tuning.grain, white: white, text: faint, textGrain: tuning.textGrain),
                               tuning: tuning)
        // Faint print deepened, sharpened, then taken darker, so the darkening sets the print's
        // final shade: an unsharp mask run after it would drive a stroke to
        // black. The print's own darkness is read inside the boxes of text.
        var sharpened = strengthened(even, tuning: tuning, text: text)
        sharpen(&sharpened, tuning: tuning)
        var tuned = tuning
        tuned.blackPoint = blackPoint(forPrint: printDarkness(sharpened, tuning: tuning, boxes: printBoxes), tuning: tuning)
        var darkened = darkened(sharpened, tuning: tuned)
        // Light print, line by line, as dark as the rest, every mark of it kept.
        toned(even, into: &darkened, lines: lines, tuning: tuning)
        let cleaned = filled(darkened, from: page, paper: paper, tuning: tuning)
        let shown: ScanBitmap
        switch mode {
        case .color: shown = cleaned
        case .gray: shown = grayed(cleaned)
        case .blackAndWhite: shown = blackAndWhite(grayed(cleaned), tuning: tuning)
        }
        return Cleaned(page: shown, base: even, light: light)
    }

    /// How bright a colour is, from 0 to 255, as the eye weighs red, green
    /// and blue (Rec. 709).
    @inline(__always)
    static func brightness(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> UInt8 {
        let r = Int(red), g = Int(green), b = Int(blue)
        let weighed: Int = 54 * r + 183 * g + 19 * b + 128
        return UInt8(truncatingIfNeeded: weighed >> 8)
    }

    // MARK: The paper

    /// The paper's colour across the page, a value for each cell.
    struct Paper {
        let cell: Int
        let columns: Int
        let rows: Int
        var red: [Float]
        var green: [Float]
        var blue: [Float]
        /// The page's paper, as most of its cells have it.
        let level: (red: Float, green: Float, blue: Float)
        /// Which cells hold paper rather than print, before they were filled in.
        let paper: [Bool]
        /// Which cells hold a pale fill printed with sharp edges, a watermark
        /// or a shaded row, or its edge: it keeps its own shade (`filled`).
        let fills: [Bool]
        /// The patches darker than the paper round them, and how sharp each
        /// one's edge is, from 0 to 1: print at `edgeShare` and over, light
        /// under it; nil where it could not be read, kept as print.
        let darker: [(cells: [Int], sharpness: Float?)]
        let edges: Edges

        init(of page: ScanBitmap, tuning: Tuning) {
            let w = page.width, h = page.height
            let shorter = Double(min(w, h))
            let cell = max(4, Int((shorter * tuning.cell).rounded()))
            let columns = (w + cell - 1) / cell, rows = (h + cell - 1) / cell
            self.cell = cell
            self.columns = columns
            self.rows = rows
            var red = [Float](repeating: 0, count: columns * rows), green = red, blue = red
            let columnOf = (0..<w).map { $0 / cell }
            page.pixels.withUnsafeBufferPointer { px in
                for row in 0..<rows {
                    var counts = [Int32](repeating: 0, count: columns * 768)
                    let top = row * cell, bottom = min(h, top + cell)
                    counts.withUnsafeMutableBufferPointer { c in
                        for y in top..<bottom {
                            var i = y * w * 4
                            for x in 0..<w {
                                let base: Int = columnOf[x] * 768
                                let red = Int(px[i]), green = Int(px[i + 1]), blue = Int(px[i + 2])
                                c[base + red] += 1
                                c[base + 256 + green] += 1
                                c[base + 512 + blue] += 1
                                i += 4
                            }
                        }
                    }
                    for column in 0..<columns {
                        let left = column * cell, right = min(w, left + cell)
                        let half = Int32((right - left) * (bottom - top) / 2)
                        let n = row * columns + column, base = column * 768
                        red[n] = Self.commonest(above: half, in: counts, from: base)
                        green[n] = Self.commonest(above: half, in: counts, from: base + 256)
                        blue[n] = Self.commonest(above: half, in: counts, from: base + 512)
                    }
                }
            }
            let level = (red: Self.median(red), green: Self.median(green), blue: Self.median(blue))
            self.level = level
            // Cells that hold print: much darker than the page, or darker
            // than cells on both sides of them, across or down, as a table's
            // grey header or a filled box is. A shadow's edge has paper as
            // dark as itself on one side, so its light is still evened.
            let lightness = (0..<red.count).map { Self.lightness(red[$0], green[$0], blue[$0]) }
            let pageLightness = Self.lightness(level.red, level.green, level.blue)
            var paper = lightness.map { $0 >= tuning.printFloor * pageLightness }
            let firstPass = paper
            func brightest(from row: Int, _ column: Int, step: (Int, Int), reach: Int = tuning.around) -> Float {
                var best: Float = 0
                for k in 1...max(1, reach) {
                    let r = row + step.0 * k, c = column + step.1 * k
                    guard r >= 0, r < rows, c >= 0, c < columns else { break }
                    if firstPass[r * columns + c] { best = max(best, lightness[r * columns + c]) }
                }
                return best
            }
            // And cells only a little darker than both sides, as a pale
            // watermark or a shaded row is, looked for twice as far, as such
            // a fill is often wide: print only where their edge is sharp, below.
            var pale = [Bool](repeating: false, count: paper.count)
            // The paper beside each pale cell: the dimmer of its two brighter sides.
            var beside = [Float](repeating: 0, count: paper.count)
            for row in 0..<rows {
                for column in 0..<columns where firstPass[row * columns + column] {
                    let left = brightest(from: row, column, step: (0, -1)), right = brightest(from: row, column, step: (0, 1))
                    let up = brightest(from: row, column, step: (-1, 0)), below = brightest(from: row, column, step: (1, 0))
                    let here = lightness[row * columns + column]
                    let brighter = here / tuning.localFloor, paler = here / tuning.paleFloor
                    if (left > brighter && right > brighter) || (up > brighter && below > brighter) {
                        paper[row * columns + column] = false
                        continue
                    }
                    let far = 2 * tuning.around
                    let farLeft = brightest(from: row, column, step: (0, -1), reach: far)
                    let farRight = brightest(from: row, column, step: (0, 1), reach: far)
                    let farUp = brightest(from: row, column, step: (-1, 0), reach: far)
                    let farBelow = brightest(from: row, column, step: (1, 0), reach: far)
                    if farLeft > paler && farRight > paler {
                        pale[row * columns + column] = true
                        beside[row * columns + column] = min(farLeft, farRight)
                    } else if farUp > paler && farBelow > paler {
                        pale[row * columns + column] = true
                        beside[row * columns + column] = min(farUp, farBelow)
                    }
                }
            }
            // A darker patch is print only where its edge is sharp, as a
            // filled box's is; a fold's or a shadow's fades over many pixels,
            // and is light, evened as paper is.
            let edges = Edges(of: page, cell: cell, columns: columns, rows: rows)
            var darker: [(cells: [Int], sharpness: Float?)] = []
            for patch in Self.patches(paper: paper, firstPass: firstPass, columns: columns, rows: rows) {
                let sharpness = edges.sharpness(of: patch, tuning: tuning)
                darker.append((patch, sharpness))
                // A patch that runs from one side of the page to the other,
                // or from its top to its bottom, is light: no letter or box
                // of print reaches both, while a fold's shadow and a curl's
                // do, however sharp their edges are. So is one that reaches
                // the page's own border, where its shadow falls.
                if Self.spans(patch, columns: columns, rows: rows) || Self.borders(patch, columns: columns, rows: rows)
                    || (sharpness ?? 1) < tuning.edgeShare {
                    for n in patch { paper[n] = true }
                }
            }
            // A pale fill keeps its shade where its edge is sharp, as a
            // watermark's or a shaded row's is printed, with the cells round
            // it, which hold its edge; a soft one, the light's, is evened.
            var fills = [Bool](repeating: false, count: paper.count)
            let paleFills = Self.patches(paper: pale.map { !$0 }, firstPass: firstPass, columns: columns, rows: rows)
            for found in paleFills where found.count >= tuning.fillCells && !Self.spans(found, columns: columns, rows: rows) {
                guard let sharpness = edges.sharpness(of: found, tuning: tuning), sharpness >= tuning.fillEdgeShare else { continue }
                // A wide fill is taken whole: the cells next to it as light as
                // it is belong to it, where paper is too far off on one side to tell.
                let patch = Self.grown(found, paper: Self.median(found.map { beside[$0] }), lightness: lightness,
                                       firstPass: firstPass, columns: columns, rows: rows)
                guard !Self.spans(patch, columns: columns, rows: rows),
                      Double(patch.count) <= tuning.fillLargest * Double(columns * rows),
                      Self.solid(found, columns: columns, rows: rows) >= tuning.fillSolid else { continue }
                darker.append((patch, sharpness))
                for n in patch {
                    let row = n / columns, column = n % columns
                    for r in max(0, row - 1)...min(rows - 1, row + 1) {
                        for c in max(0, column - 1)...min(columns - 1, column + 1) {
                            paper[r * columns + c] = false
                            fills[r * columns + c] = true
                        }
                    }
                }
            }
            self.fills = fills
            self.darker = darker
            self.edges = edges
            self.paper = paper
            Self.fill(&red, &green, &blue, known: paper, columns: columns, rows: rows, level: level)
            for _ in 0..<tuning.smoothing {
                red = Self.smoothed(red, columns: columns, rows: rows)
                green = Self.smoothed(green, columns: columns, rows: rows)
                blue = Self.smoothed(blue, columns: columns, rows: rows)
            }
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// A cell's paper in one channel: the commonest value above the
        /// middle one, each counted with the two on either side, the
        /// brighter where two are as common. The print lies below the
        /// middle, and a camera's bright specks are spread too thin to be
        /// common, so neither moves it, and grainy paper in a shadow comes
        /// out as white as the rest.
        private static func commonest(above half: Int32, in counts: [Int32], from base: Int) -> Float {
            var seen: Int32 = 0, middle = 255
            for value in 0..<256 {
                seen += counts[base + value]
                if seen > half {
                    middle = value
                    break
                }
            }
            var best = middle, most: Int32 = -1
            for value in middle...255 {
                var near: Int32 = 0
                for k in max(0, value - 2)...min(255, value + 2) { near += counts[base + k] }
                if near >= most {
                    best = value
                    most = near
                }
            }
            return Float(best)
        }

        /// The share of a patch's cells whose eight neighbours are all in it
        /// too: a blob's is large, a thin ring, a shadow's fringe, has none.
        private static func solid(_ patch: [Int], columns: Int, rows: Int) -> Double {
            let inside = Set(patch)
            var inner = 0
            for n in patch {
                let row = n / columns, column = n % columns
                var all = true
                for r in (row - 1)...(row + 1) {
                    for c in (column - 1)...(column + 1) where !inside.contains(r * columns + c) { all = false }
                }
                if all { inner += 1 }
            }
            return Double(inner) / Double(max(1, patch.count))
        }

        /// A patch with the cells next to it, and next to those, that are as
        /// light as the cell beside them: within 1 %, and within a third of
        /// how much lighter the `paper` beside it is, so a fill is followed
        /// across a page lit unevenly, and its sharp edge, a step from it to
        /// the paper, is never crossed.
        private static func grown(_ patch: [Int], paper: Float, lightness: [Float], firstPass: [Bool], columns: Int,
                                  rows: Int) -> [Int] {
            func neighbours(_ n: Int) -> [Int] {
                let row = n / columns, column = n % columns
                return [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
                    .filter { $0.0 >= 0 && $0.0 < rows && $0.1 >= 0 && $0.1 < columns }.map { $0.0 * columns + $0.1 }
            }
            let level = median(patch.map { lightness[$0] })
            var inside = Set(patch)
            let step = min(level * 0.01, (paper - level) / 3)
            guard step > 0 else { return patch }
            var stack = patch
            while let n = stack.popLast() {
                for m in neighbours(n) where firstPass[m] && !inside.contains(m) && abs(lightness[m] - lightness[n]) <= step {
                    inside.insert(m)
                    stack.append(m)
                }
            }
            return Array(inside)
        }

        /// Whether a patch of cells reaches both of two opposite sides of the
        /// page: down its whole width, or across its whole height.
        private static func spans(_ patch: [Int], columns: Int, rows: Int) -> Bool {
            var leastColumn = columns, mostColumn = -1, leastRow = rows, mostRow = -1
            for n in patch {
                leastColumn = min(leastColumn, n % columns)
                mostColumn = max(mostColumn, n % columns)
                leastRow = min(leastRow, n / columns)
                mostRow = max(mostRow, n / columns)
            }
            return (leastColumn == 0 && mostColumn == columns - 1) || (leastRow == 0 && mostRow == rows - 1)
        }

        /// Whether a patch of cells reaches the page's own border, where a
        /// shadow of the sheet's edge falls, rather than print.
        private static func borders(_ patch: [Int], columns: Int, rows: Int) -> Bool {
            patch.contains { n in
                let row = n / columns, column = n % columns
                return row == 0 || row == rows - 1 || column == 0 || column == columns - 1
            }
        }

        static func median(_ values: [Float]) -> Float {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }

        static func lightness(_ red: Float, _ green: Float, _ blue: Float) -> Float {
            let r: Float = 0.2126 * red, g: Float = 0.7152 * green, b: Float = 0.0722 * blue
            return r + g + b
        }

        /// Cells of print take the paper of the cells around them, from the
        /// edges of what is known inwards; with no paper anywhere, the page's.
        private static func fill(_ red: inout [Float], _ green: inout [Float], _ blue: inout [Float], known: [Bool],
                                 columns: Int, rows: Int, level: (red: Float, green: Float, blue: Float)) {
            var known = known
            guard known.contains(true) else {
                red = red.map { _ in level.red }
                green = green.map { _ in level.green }
                blue = blue.map { _ in level.blue }
                return
            }
            while known.contains(false) {
                var next = known
                for row in 0..<rows {
                    for column in 0..<columns where !known[row * columns + column] {
                        var sum: (Float, Float, Float) = (0, 0, 0)
                        var count: Float = 0
                        for r in max(0, row - 1)...min(rows - 1, row + 1) {
                            for c in max(0, column - 1)...min(columns - 1, column + 1) where known[r * columns + c] {
                                let n = r * columns + c
                                sum = (sum.0 + red[n], sum.1 + green[n], sum.2 + blue[n])
                                count += 1
                            }
                        }
                        guard count > 0 else { continue }
                        let n = row * columns + column
                        red[n] = sum.0 / count
                        green[n] = sum.1 / count
                        blue[n] = sum.2 / count
                        next[n] = true
                    }
                }
                known = next
            }
        }

        /// Each cell the mean of itself and its eight neighbours.
        private static func smoothed(_ values: [Float], columns: Int, rows: Int) -> [Float] {
            var out = values
            for row in 0..<rows {
                for column in 0..<columns {
                    var sum: Float = 0, count: Float = 0
                    for r in max(0, row - 1)...min(rows - 1, row + 1) {
                        for c in max(0, column - 1)...min(columns - 1, column + 1) {
                            sum += values[r * columns + c]
                            count += 1
                        }
                    }
                    out[row * columns + column] = sum / count
                }
            }
            return out
        }
    }

    // MARK: Even light, white paper

    /// The page with its light made even: each pixel as its share of the
    /// paper's colour where it is, 255 for the paper itself. A page whose
    /// paper is dark is left as it is.
    static func evened(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        evened(page, paper: Paper(of: page, tuning: tuning), tuning: tuning)
    }

    /// The same, with the paper already measured; `text` where text was
    /// read, `faint` where it is light print (`textHeadroom`).
    static func evened(_ page: ScanBitmap, paper: Paper, tuning: Tuning, text: [Bool]? = nil,
                       faint: [Bool]? = nil) -> ScanBitmap {
        let pageLightness = Paper.lightness(paper.level.red, paper.level.green, paper.level.blue)
        guard pageLightness >= tuning.darkestPaper else { return page }
        let w = page.width, h = page.height, cell = Float(paper.cell)
        // Where each column of pixels falls between the cells' middles.
        var leftCell = [Int](repeating: 0, count: w), rightCell = leftCell
        var across = [Float](repeating: 0, count: w)
        for x in 0..<w {
            let u: Float = (Float(x) + 0.5) / cell - 0.5
            let c0: Int = min(max(Int(u.rounded(.down)), 0), paper.columns - 1)
            leftCell[x] = c0
            rightCell[x] = min(c0 + 1, paper.columns - 1)
            let past: Float = u - Float(c0)
            across[x] = min(max(past, 0), 1)
        }
        let floor = (red: tuning.dimmest * max(paper.level.red, 1), green: tuning.dimmest * max(paper.level.green, 1),
                     blue: tuning.dimmest * max(paper.level.blue, 1))
        // The brightest pixel close round each: within the text read, a
        // pixel well under it is a stroke, however faint, and never takes a
        // fold's or a shadow's finer light, which faint small print would
        // otherwise pass for.
        let around = text == nil ? [] : widest(page.brightness, width: w, height: h, radius: 2)
        var out = page
        var rowRed = [Float](repeating: 0, count: paper.columns), rowGreen = rowRed, rowBlue = rowRed
        out.pixels.withUnsafeMutableBufferPointer { px in
            for y in 0..<h {
                let v: Float = (Float(y) + 0.5) / cell - 0.5
                let r0: Int = min(max(Int(v.rounded(.down)), 0), paper.rows - 1)
                let r1: Int = min(r0 + 1, paper.rows - 1)
                let past: Float = v - Float(r0)
                let down: Float = min(max(past, 0), 1)
                for c in 0..<paper.columns {
                    let a = r0 * paper.columns + c, b = r1 * paper.columns + c
                    rowRed[c] = Self.between(paper.red[a], paper.red[b], down)
                    rowGreen[c] = Self.between(paper.green[a], paper.green[b], down)
                    rowBlue[c] = Self.between(paper.blue[a], paper.blue[b], down)
                }
                var i = y * w * 4
                let cellRow = min(y / paper.cell, paper.rows - 1)
                for x in 0..<w {
                    let c0 = leftCell[x], c1 = rightCell[x], t = across[x]
                    var red: Float = Self.between(rowRed[c0], rowRed[c1], t)
                    var green: Float = Self.between(rowGreen[c0], rowGreen[c1], t)
                    var blue: Float = Self.between(rowBlue[c0], rowBlue[c1], t)
                    // Paper anywhere, as the blocks have it just there: finer
                    // than a cell, so a fold's or a shadow's light is evened
                    // whole instead of averaged with the paper round it. A
                    // cell of print, a filled box or a grey header, takes the
                    // paper of the cells round it, and so keeps its shade.
                    let cellIndex = cellRow * paper.columns + min(x / paper.cell, paper.columns - 1)
                    if paper.paper[cellIndex] {
                        let fine = paper.edges.fine(x: x, y: y)
                        let here = Paper.lightness(red, green, blue)
                        let there = Paper.lightness(fine.red, fine.green, fine.blue)
                        // A dimmer paper near, all its colours taken down
                        // alike, so the paper keeps its colour; and paper
                        // only, so no stroke is lightened by its light: a
                        // block that is all stroke says nothing of paper,
                        // and is left to the cell's own.
                        let own = Float(Self.brightness(px[i], px[i + 1], px[i + 2]))
                        if there < here, there >= here * tuning.printEdge,
                           own >= here * tuning.printEdge,
                           !(text?[y * w + x] ?? false) || own >= Float(around[y * w + x]) * tuning.strokeBelow {
                            let share = there / here
                            red *= share
                            green *= share
                            blue *= share
                        }
                    }
                    let headroom = faint?[y * w + x] ?? false ? tuning.textHeadroom : tuning.headroom
                    red = max(red, floor.red) * headroom
                    green = max(green, floor.green) * headroom
                    blue = max(blue, floor.blue) * headroom
                    px[i] = Self.share(px[i], of: red)
                    px[i + 1] = Self.share(px[i + 1], of: green)
                    px[i + 2] = Self.share(px[i + 2], of: blue)
                    i += 4
                }
            }
        }
        return out
    }

    /// The places of text read, from 0 to 1 from the bottom left, a little
    /// larger, as a pixel mask; nil where none was read.
    static func textMask(_ boxes: [CGRect], width w: Int, height h: Int) -> [Bool]? {
        guard !boxes.isEmpty else { return nil }
        var mask = [Bool](repeating: false, count: w * h)
        for box in boxes {
            let grown = box.insetBy(dx: -box.height * 0.5, dy: -box.height * 0.3)
            let x0 = max(0, Int(grown.minX * Double(w))), x1 = min(w, Int((grown.maxX * Double(w)).rounded(.up)))
            let y0 = max(0, Int((1 - grown.maxY) * Double(h))), y1 = min(h, Int(((1 - grown.minY) * Double(h)).rounded(.up)))
            guard x1 > x0, y1 > y0 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { mask[y * w + x] = true } }
        }
        return mask
    }

    /// The point `t` of the way from `a` to `b`.
    @inline(__always)
    private static func between(_ a: Float, _ b: Float, _ t: Float) -> Float {
        let step: Float = (b - a) * t
        return a + step
    }

    /// `a` and `b` mixed, `t` of `b`.
    @inline(__always)
    private static func blend(_ a: Float, _ b: Float, _ t: Float) -> Float {
        let kept: Float = a * (1 - t), added: Float = b * t
        return kept + added
    }

    /// A pixel's value as its share of its paper's, of 255.
    @inline(__always)
    private static func share(_ value: UInt8, of paper: Float) -> UInt8 {
        let part: Float = min(Float(value) / paper, 1)
        let shown: Float = part * 255 + 0.5
        return UInt8(shown)
    }

    /// The paper's grain smoothed: each pixel the mean of the neighbours,
    /// itself among them, that are within `grain` of it, colour by colour,
    /// or `textGrain` within the lines of light print read (`text`), so a faint
    /// mark's rim is kept. An edge's other side is further off, so it is
    /// never blurred. A pixel that stays at `white` or over whatever its
    /// neighbours are, which the curve makes white anyway, is left as it
    /// is, which is much quicker.
    static func denoised(_ page: ScanBitmap, grain: Int, white: Int = 256, text: [Bool]? = nil,
                         textGrain: Int = 0) -> ScanBitmap {
        guard grain > 0 else { return page }
        let w = page.width, h = page.height
        guard w > 2, h > 2 else { return page }
        var out = page
        page.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let p = (y * w + x) * 4
                        let near = text?[y * w + x] ?? false ? textGrain : grain
                        guard near > 0 else { continue }
                        for k in 0..<3 {
                            let middle = Int(src[p + k])
                            guard middle - near < white else { continue }
                            var sum = 0, count = 0
                            for dy in -1...1 {
                                let row = p + dy * w * 4 + k
                                for dx in -1...1 {
                                    let value = Int(src[row + dx * 4])
                                    if abs(value - middle) <= near {
                                        sum += value
                                        count += 1
                                    }
                                }
                            }
                            let mean: Int = (sum + count / 2) / count
                            dst[p + k] = UInt8(mean)
                        }
                    }
                }
            }
        }
        return out
    }

    /// The curve over every pixel (`curve`).
    static func curved(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        let curve = self.curve(tuning)
        var out = page
        out.pixels.withUnsafeMutableBufferPointer { px in
            for i in stride(from: 0, to: px.count, by: 4) {
                px[i] = curve[Int(px[i])]
                px[i + 1] = curve[Int(px[i + 1])]
                px[i + 2] = curve[Int(px[i + 2])]
            }
        }
        return out
    }

    /// From a pixel's share of its paper's brightness, of 255, to the value
    /// it shows: white at the white point and over, black at the black
    /// point and under, the greys between a little darker.
    static func curve(_ tuning: Tuning) -> [UInt8] {
        let span: Float = tuning.whitePoint - tuning.blackPoint
        return (0...255).map { step -> UInt8 in
            let share: Float = Float(step) / 255
            let along: Float = (share - tuning.blackPoint) / span
            let t: Float = min(max(along, 0), 1)
            let shown: Float = (powf(t, tuning.gamma) * 255).rounded()
            return UInt8(shown)
        }
    }

    // MARK: Clearer edges

    /// An unsharp mask on brightness: where a pixel stands out from those
    /// around it by more than the threshold, it stands out a little more,
    /// in all three colours alike, so no colour fringes.
    static func sharpen(_ page: inout ScanBitmap, tuning: Tuning = .standard) {
        guard tuning.sharpen > 0 else { return }
        let w = page.width, h = page.height
        let shorter = Double(min(w, h))
        let radius = max(1, Int((shorter / 1240).rounded()))
        let plane = page.brightness
        let soft = blurred(blurred(plane, width: w, height: h, radius: radius), width: w, height: h, radius: radius)
        let amount = tuning.sharpen, threshold = tuning.sharpenThreshold
        page.pixels.withUnsafeMutableBufferPointer { px in
            for p in 0..<(w * h) {
                let difference: Float = Float(plane[p]) - Float(soft[p])
                guard abs(difference) > threshold else { continue }
                let change: Float = amount * difference
                for k in 0..<3 {
                    let index = p * 4 + k
                    let value: Float = (Float(px[index]) + change).rounded()
                    let clamped: Float = min(max(value, 0), 255)
                    px[index] = UInt8(clamped)
                }
            }
        }
    }

    /// The mean of each pixel's square around it, `radius` each way, the
    /// edges repeated: across, then down.
    static func blurred(_ plane: [UInt8], width w: Int, height h: Int, radius: Int) -> [UInt8] {
        let width: Int = 2 * radius + 1
        let span = Int32(width), half: Int32 = span / 2
        var across = [UInt8](repeating: 0, count: w * h)
        plane.withUnsafeBufferPointer { src in
            across.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let row = y * w
                    var sum: Int32 = 0
                    for k in -radius...radius {
                        let x: Int = min(max(k, 0), w - 1)
                        sum += Int32(src[row + x])
                    }
                    for x in 0..<w {
                        let mean: Int32 = (sum + half) / span
                        dst[row + x] = UInt8(mean)
                        let back: Int = min(max(x - radius, 0), w - 1)
                        let ahead: Int = min(x + radius + 1, w - 1)
                        let leaving = Int32(src[row + back]), coming = Int32(src[row + ahead])
                        sum += coming - leaving
                    }
                }
            }
        }
        var down = [UInt8](repeating: 0, count: w * h)
        across.withUnsafeBufferPointer { src in
            down.withUnsafeMutableBufferPointer { dst in
                for x in 0..<w {
                    var sum: Int32 = 0
                    for k in -radius...radius {
                        let y: Int = min(max(k, 0), h - 1)
                        sum += Int32(src[y * w + x])
                    }
                    for y in 0..<h {
                        let mean: Int32 = (sum + half) / span
                        dst[y * w + x] = UInt8(mean)
                        let back: Int = min(max(y - radius, 0), h - 1)
                        let ahead: Int = min(y + radius + 1, h - 1)
                        let leaving = Int32(src[back * w + x]), coming = Int32(src[ahead * w + x])
                        sum += coming - leaving
                    }
                }
            }
        }
        return down
    }

    // MARK: Greys, black and white

    /// The page in greys, each pixel as bright as its colour was.
    static func grayed(_ page: ScanBitmap) -> ScanBitmap {
        var out = page
        out.pixels.withUnsafeMutableBufferPointer { px in
            for i in stride(from: 0, to: px.count, by: 4) {
                let value = brightness(px[i], px[i + 1], px[i + 2])
                px[i] = value
                px[i + 1] = value
                px[i + 2] = value
            }
        }
        return out
    }

    /// The page in black and white. A pixel clearly darker than the mean
    /// around it is print; one a little darker is print only where it
    /// touches print, through others like it, so a stroke keeps its soft
    /// edges and a pale line or stamp is kept or left out whole. The mean is
    /// taken at a smaller size and drawn back, which is as good for a
    /// window this wide and much quicker.
    static func blackAndWhite(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        let w = page.width, h = page.height
        let plane = page.brightness
        let shorter = Double(min(w, h))
        let window = max(8, Int(shorter * tuning.window))
        let block = max(1, window / 8)
        let smallWidth = (w + block - 1) / block, smallHeight = (h + block - 1) / block
        var small = [UInt8](repeating: 0, count: smallWidth * smallHeight)
        for sy in 0..<smallHeight {
            for sx in 0..<smallWidth {
                var sum = 0, count = 0
                let top: Int = sy * block, left: Int = sx * block
                let bottom: Int = min(h, top + block), right: Int = min(w, left + block)
                for y in top..<bottom {
                    for x in left..<right {
                        sum += Int(plane[y * w + x])
                        count += 1
                    }
                }
                let mean: Int = sum / max(count, 1)
                small[sy * smallWidth + sx] = UInt8(mean)
            }
        }
        let mean = blurred(small, width: smallWidth, height: smallHeight, radius: max(1, window / (2 * block)))
        // 2 for print, 1 for pale, 0 for paper.
        var kind = [UInt8](repeating: 0, count: w * h)
        var queue: [Int] = []
        let blockSize = Float(block)
        for y in 0..<h {
            let v: Float = (Float(y) + 0.5) / blockSize - 0.5
            let r0: Int = min(max(Int(v.rounded(.down)), 0), smallHeight - 1)
            let r1: Int = min(r0 + 1, smallHeight - 1)
            let pastRow: Float = v - Float(r0)
            let down: Float = min(max(pastRow, 0), 1)
            for x in 0..<w {
                let p = y * w + x
                let value = plane[p]
                let u: Float = (Float(x) + 0.5) / blockSize - 0.5
                let c0: Int = min(max(Int(u.rounded(.down)), 0), smallWidth - 1)
                let c1: Int = min(c0 + 1, smallWidth - 1)
                let pastColumn: Float = u - Float(c0)
                let across: Float = min(max(pastColumn, 0), 1)
                let topLeft = Float(mean[r0 * smallWidth + c0]), topRight = Float(mean[r0 * smallWidth + c1])
                let bottomLeft = Float(mean[r1 * smallWidth + c0]), bottomRight = Float(mean[r1 * smallWidth + c1])
                let top: Float = Self.blend(topLeft, topRight, across)
                let bottom: Float = Self.blend(bottomLeft, bottomRight, across)
                let around: Float = Self.between(top, bottom, down)
                if value <= tuning.alwaysBlack || Float(value) < around * tuning.dark {
                    kind[p] = 2
                    queue.append(p)
                } else if Float(value) < around * tuning.pale {
                    kind[p] = 1
                }
            }
        }
        // Pale pixels touching print become print, and so on outwards.
        while let p = queue.popLast() {
            let x = p % w, y = p / w
            for dy in -1...1 {
                let yy = y + dy
                guard yy >= 0, yy < h else { continue }
                for dx in -1...1 {
                    let xx = x + dx
                    guard xx >= 0, xx < w else { continue }
                    let q = yy * w + xx
                    if kind[q] == 1 {
                        kind[q] = 2
                        queue.append(q)
                    }
                }
            }
        }
        var out = page
        out.pixels.withUnsafeMutableBufferPointer { px in
            for p in 0..<(w * h) {
                let shown: UInt8 = kind[p] == 2 ? 0 : 255
                px[p * 4] = shown
                px[p * 4 + 1] = shown
                px[p * 4 + 2] = shown
            }
        }
        return out
    }
}
