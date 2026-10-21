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
/// The paper's colour is measured in cells across the page: the brightness
/// most of a cell's pixels stay under. A cell much darker than the page, or
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
        /// A cell's paper is as bright as this share of its pixels.
        var paperShare = 0.9
        /// A cell darker than this share of the page's paper holds print.
        var printFloor: Float = 0.45
        /// Or darker than this share of cells on both sides of it, like a
        /// table's grey header, which keeps its grey.
        var localFloor: Float = 0.94
        /// How many cells each way count as its sides: a filled box up to
        /// twice as wide keeps its fill all through.
        var around = 12
        /// Passes of a cell's mean with its eight neighbours.
        var smoothing = 1
        /// A dim part of the page is brightened at most as if its paper
        /// were this share of the page's.
        var dimmest: Float = 0.3
        /// Paper darker than this, of 255, is no light page: its light is
        /// left as it is, so a dark screen photographed keeps its words.
        var darkestPaper: Float = 100
        /// The grain: neighbours this close to a pixel, of 255, are smoothed
        /// with it; an edge, further apart, never is.
        var grain = 10
        /// After the light is evened, this share of white and more is white.
        var whitePoint: Float = 0.94
        /// And this share and less is black.
        var blackPoint: Float = 0.04
        /// Above 1, the print's greys a little darker.
        var gamma: Float = 1.15
        /// How much an edge is made clearer, and by how many levels it must
        /// stand out first, so what is left of the grain is left alone.
        var sharpen: Float = 0.6
        var sharpenThreshold: Float = 3
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
    static func clean(_ page: ScanBitmap, _ mode: ScanColor, tuning: Tuning = .standard) -> ScanBitmap {
        let white = Int((tuning.whitePoint * 255).rounded(.up))
        var cleaned = curved(denoised(evened(page, tuning: tuning), grain: tuning.grain, white: white), tuning: tuning)
        sharpen(&cleaned, tuning: tuning)
        switch mode {
        case .color: return cleaned
        case .gray: return grayed(cleaned)
        case .blackAndWhite: return blackAndWhite(grayed(cleaned), tuning: tuning)
        }
    }

    /// How bright a colour is, from 0 to 255, as the eye weighs red, green
    /// and blue (Rec. 709).
    @inline(__always)
    static func brightness(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> UInt8 {
        UInt8((54 * Int(red) + 183 * Int(green) + 19 * Int(blue) + 128) >> 8)
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

        init(of page: ScanBitmap, tuning: Tuning) {
            let w = page.width, h = page.height
            let cell = max(4, Int((Double(min(w, h)) * tuning.cell).rounded()))
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
                                let base = columnOf[x] * 768
                                c[base + Int(px[i])] += 1
                                c[base + 256 + Int(px[i + 1])] += 1
                                c[base + 512 + Int(px[i + 2])] += 1
                                i += 4
                            }
                        }
                    }
                    for column in 0..<columns {
                        let left = column * cell, right = min(w, left + cell)
                        let rank = Int32((Double((right - left) * (bottom - top)) * tuning.paperShare).rounded(.down))
                        let n = row * columns + column, base = column * 768
                        red[n] = Self.value(at: rank, in: counts, from: base)
                        green[n] = Self.value(at: rank, in: counts, from: base + 256)
                        blue[n] = Self.value(at: rank, in: counts, from: base + 512)
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
            func brightest(from row: Int, _ column: Int, step: (Int, Int)) -> Float {
                var best: Float = 0
                for k in 1...max(1, tuning.around) {
                    let r = row + step.0 * k, c = column + step.1 * k
                    guard r >= 0, r < rows, c >= 0, c < columns else { break }
                    if firstPass[r * columns + c] { best = max(best, lightness[r * columns + c]) }
                }
                return best
            }
            for row in 0..<rows {
                for column in 0..<columns where firstPass[row * columns + column] {
                    let brighter = lightness[row * columns + column] / tuning.localFloor
                    let across = brightest(from: row, column, step: (0, -1)) > brighter
                        && brightest(from: row, column, step: (0, 1)) > brighter
                    let down = brightest(from: row, column, step: (-1, 0)) > brighter
                        && brightest(from: row, column, step: (1, 0)) > brighter
                    if across || down { paper[row * columns + column] = false }
                }
            }
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

        /// The value below which `rank` of a cell's pixels lie, in one channel.
        private static func value(at rank: Int32, in counts: [Int32], from base: Int) -> Float {
            var seen: Int32 = 0
            for value in 0..<256 {
                seen += counts[base + value]
                if seen > rank { return Float(value) }
            }
            return 255
        }

        static func median(_ values: [Float]) -> Float {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }

        static func lightness(_ red: Float, _ green: Float, _ blue: Float) -> Float {
            0.2126 * red + 0.7152 * green + 0.0722 * blue
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
        let paper = Paper(of: page, tuning: tuning)
        let pageLightness = Paper.lightness(paper.level.red, paper.level.green, paper.level.blue)
        guard pageLightness >= tuning.darkestPaper else { return page }
        let w = page.width, h = page.height, cell = Float(paper.cell)
        // Where each column of pixels falls between the cells' middles.
        var leftCell = [Int](repeating: 0, count: w), rightCell = leftCell
        var across = [Float](repeating: 0, count: w)
        for x in 0..<w {
            let u = (Float(x) + 0.5) / cell - 0.5
            let c0 = min(max(Int(u.rounded(.down)), 0), paper.columns - 1)
            leftCell[x] = c0
            rightCell[x] = min(c0 + 1, paper.columns - 1)
            across[x] = min(max(u - Float(c0), 0), 1)
        }
        let floor = (red: tuning.dimmest * max(paper.level.red, 1), green: tuning.dimmest * max(paper.level.green, 1),
                     blue: tuning.dimmest * max(paper.level.blue, 1))
        var out = page
        var rowRed = [Float](repeating: 0, count: paper.columns), rowGreen = rowRed, rowBlue = rowRed
        out.pixels.withUnsafeMutableBufferPointer { px in
            for y in 0..<h {
                let v = (Float(y) + 0.5) / cell - 0.5
                let r0 = min(max(Int(v.rounded(.down)), 0), paper.rows - 1), r1 = min(r0 + 1, paper.rows - 1)
                let down = min(max(v - Float(r0), 0), 1)
                for c in 0..<paper.columns {
                    let a = r0 * paper.columns + c, b = r1 * paper.columns + c
                    rowRed[c] = paper.red[a] + (paper.red[b] - paper.red[a]) * down
                    rowGreen[c] = paper.green[a] + (paper.green[b] - paper.green[a]) * down
                    rowBlue[c] = paper.blue[a] + (paper.blue[b] - paper.blue[a]) * down
                }
                var i = y * w * 4
                for x in 0..<w {
                    let c0 = leftCell[x], c1 = rightCell[x], t = across[x]
                    let red = max(rowRed[c0] + (rowRed[c1] - rowRed[c0]) * t, floor.red)
                    let green = max(rowGreen[c0] + (rowGreen[c1] - rowGreen[c0]) * t, floor.green)
                    let blue = max(rowBlue[c0] + (rowBlue[c1] - rowBlue[c0]) * t, floor.blue)
                    px[i] = UInt8(min(Float(px[i]) / red, 1) * 255 + 0.5)
                    px[i + 1] = UInt8(min(Float(px[i + 1]) / green, 1) * 255 + 0.5)
                    px[i + 2] = UInt8(min(Float(px[i + 2]) / blue, 1) * 255 + 0.5)
                    i += 4
                }
            }
        }
        return out
    }

    /// The paper's grain smoothed: each pixel the mean of the neighbours,
    /// itself among them, that are within `grain` of it, colour by colour.
    /// An edge's other side is further off, so it is never blurred. A pixel
    /// that stays at `white` or over whatever its neighbours are, which the
    /// curve makes white anyway, is left as it is, which is much quicker.
    static func denoised(_ page: ScanBitmap, grain: Int, white: Int = 256) -> ScanBitmap {
        guard grain > 0 else { return page }
        let w = page.width, h = page.height
        guard w > 2, h > 2 else { return page }
        var out = page
        page.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let p = (y * w + x) * 4
                        for k in 0..<3 {
                            let middle = Int(src[p + k])
                            guard middle - grain < white else { continue }
                            var sum = 0, count = 0
                            for dy in -1...1 {
                                let row = p + dy * w * 4 + k
                                for dx in -1...1 {
                                    let value = Int(src[row + dx * 4])
                                    if abs(value - middle) <= grain {
                                        sum += value
                                        count += 1
                                    }
                                }
                            }
                            dst[p + k] = UInt8((sum + count / 2) / count)
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
        (0...255).map { step in
            let share = Float(step) / 255
            let t = min(max((share - tuning.blackPoint) / (tuning.whitePoint - tuning.blackPoint), 0), 1)
            return UInt8((powf(t, tuning.gamma) * 255).rounded())
        }
    }

    // MARK: Clearer edges

    /// An unsharp mask on brightness: where a pixel stands out from those
    /// around it by more than the threshold, it stands out a little more,
    /// in all three colours alike, so no colour fringes.
    static func sharpen(_ page: inout ScanBitmap, tuning: Tuning = .standard) {
        guard tuning.sharpen > 0 else { return }
        let w = page.width, h = page.height
        let radius = max(1, Int((Double(min(w, h)) / 1240).rounded()))
        let plane = page.brightness
        let soft = blurred(blurred(plane, width: w, height: h, radius: radius), width: w, height: h, radius: radius)
        let amount = tuning.sharpen, threshold = tuning.sharpenThreshold
        page.pixels.withUnsafeMutableBufferPointer { px in
            for p in 0..<(w * h) {
                let difference = Float(plane[p]) - Float(soft[p])
                guard abs(difference) > threshold else { continue }
                let change = amount * difference
                for k in 0..<3 {
                    px[p * 4 + k] = UInt8(min(max((Float(px[p * 4 + k]) + change).rounded(), 0), 255))
                }
            }
        }
    }

    /// The mean of each pixel's square around it, `radius` each way, the
    /// edges repeated: across, then down.
    static func blurred(_ plane: [UInt8], width w: Int, height h: Int, radius: Int) -> [UInt8] {
        let span = Int32(2 * radius + 1)
        var across = [UInt8](repeating: 0, count: w * h)
        plane.withUnsafeBufferPointer { src in
            across.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let row = y * w
                    var sum: Int32 = 0
                    for k in -radius...radius { sum += Int32(src[row + min(max(k, 0), w - 1)]) }
                    for x in 0..<w {
                        dst[row + x] = UInt8((sum + span / 2) / span)
                        let leaving = src[row + min(max(x - radius, 0), w - 1)]
                        let coming = src[row + min(x + radius + 1, w - 1)]
                        sum += Int32(coming) - Int32(leaving)
                    }
                }
            }
        }
        var down = [UInt8](repeating: 0, count: w * h)
        across.withUnsafeBufferPointer { src in
            down.withUnsafeMutableBufferPointer { dst in
                for x in 0..<w {
                    var sum: Int32 = 0
                    for k in -radius...radius { sum += Int32(src[min(max(k, 0), h - 1) * w + x]) }
                    for y in 0..<h {
                        dst[y * w + x] = UInt8((sum + span / 2) / span)
                        let leaving = src[min(max(y - radius, 0), h - 1) * w + x]
                        let coming = src[min(y + radius + 1, h - 1) * w + x]
                        sum += Int32(coming) - Int32(leaving)
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
        let window = max(8, Int(Double(min(w, h)) * tuning.window))
        let block = max(1, window / 8)
        let smallWidth = (w + block - 1) / block, smallHeight = (h + block - 1) / block
        var small = [UInt8](repeating: 0, count: smallWidth * smallHeight)
        for sy in 0..<smallHeight {
            for sx in 0..<smallWidth {
                var sum = 0, count = 0
                for y in (sy * block)..<min(h, sy * block + block) {
                    for x in (sx * block)..<min(w, sx * block + block) {
                        sum += Int(plane[y * w + x])
                        count += 1
                    }
                }
                small[sy * smallWidth + sx] = UInt8(sum / max(count, 1))
            }
        }
        let mean = blurred(small, width: smallWidth, height: smallHeight, radius: max(1, window / (2 * block)))
        // 2 for print, 1 for pale, 0 for paper.
        var kind = [UInt8](repeating: 0, count: w * h)
        var queue: [Int] = []
        for y in 0..<h {
            let v = (Float(y) + 0.5) / Float(block) - 0.5
            let r0 = min(max(Int(v.rounded(.down)), 0), smallHeight - 1), r1 = min(r0 + 1, smallHeight - 1)
            let down = min(max(v - Float(r0), 0), 1)
            for x in 0..<w {
                let p = y * w + x
                let value = plane[p]
                let u = (Float(x) + 0.5) / Float(block) - 0.5
                let c0 = min(max(Int(u.rounded(.down)), 0), smallWidth - 1), c1 = min(c0 + 1, smallWidth - 1)
                let across = min(max(u - Float(c0), 0), 1)
                let top = Float(mean[r0 * smallWidth + c0]) * (1 - across) + Float(mean[r0 * smallWidth + c1]) * across
                let bottom = Float(mean[r1 * smallWidth + c0]) * (1 - across) + Float(mean[r1 * smallWidth + c1]) * across
                let around = top + (bottom - top) * down
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
