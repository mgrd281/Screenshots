import CoreGraphics
import Foundation

/// What is left to do with a page's light once its paper is evened and
/// divided out (`ScanClean`): the tint a coloured sheet leaves on its print,
/// taken away while a ballpoint's blue, a stamp's red or a logo's colour
/// stays; the print's own darkness read and taken to where it reads, a
/// carbon copy's pale print made firm while a grey band or a photo keeps its
/// shade; and the paper found finely enough for a fold's narrow shadow,
/// told from print by how sharp its edge is.
extension ScanClean {
    // MARK: Paper white, ink kept

    /// Colour left in a near-grey pixel after the paper's is divided out,
    /// as a pink, yellow or blue sheet leaves in its print, taken away: a
    /// pixel whose colour is weak, as print's on such paper is, becomes
    /// grey as bright as it was; one whose colour is strong, as a blue or
    /// black ballpoint's, a red stamp's or a logo's, keeps it, and those
    /// between fade from one to the other. Brightness never changes, so
    /// nothing is lighter or darker for it.
    static func neutralized(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        guard tuning.neutralBelow > 0 else { return page }
        var out = page
        let low = tuning.neutralBelow, high = tuning.colourAbove
        out.pixels.withUnsafeMutableBufferPointer { px in
            for i in stride(from: 0, to: px.count, by: 4) {
                let r = Float(px[i]), g = Float(px[i + 1]), b = Float(px[i + 2])
                let top = max(r, g, b), bottom = min(r, g, b)
                guard top > bottom else { continue }
                // Saturation against how bright it is, so faint print's weak tint counts as weak.
                let saturation = (top - bottom) / max(top, 1)
                guard saturation < high else { continue }
                let kept = max(0, min(1, (saturation - low) / max(1e-6, high - low)))
                let grey = Float(Self.brightness(px[i], px[i + 1], px[i + 2]))
                px[i] = UInt8(min(255, max(0, grey + (r - grey) * kept) + 0.5))
                px[i + 1] = UInt8(min(255, max(0, grey + (g - grey) * kept) + 0.5))
                px[i + 2] = UInt8(min(255, max(0, grey + (b - grey) * kept) + 0.5))
            }
        }
        return out
    }

    // MARK: Pale fills kept

    /// A pale fill printed with a sharp edge, as a watermark or a shaded row
    /// is (`Paper.fills`), shown as it was printed: each pixel its share of
    /// the paper round it, colour by colour, its grain smoothed as the
    /// paper's is, wherever cleaning left it lighter than that. So the fill
    /// keeps its tint, its streaks and its shape instead of going white with
    /// the paper, and print over it, made darker, stays as dark.
    static func filled(_ cleaned: ScanBitmap, from page: ScanBitmap, paper: Paper, tuning: Tuning = .standard)
        -> ScanBitmap {
        guard paper.fills.contains(true),
              Paper.lightness(paper.level.red, paper.level.green, paper.level.blue) >= tuning.darkestPaper
        else { return cleaned }
        let w = page.width, h = page.height
        var out = cleaned
        page.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for n in paper.fills.indices where paper.fills[n] {
                    let row = n / paper.columns, column = n % paper.columns
                    let top = row * paper.cell, left = column * paper.cell
                    for y in top..<min(h, top + paper.cell) {
                        for x in left..<min(w, left + paper.cell) {
                            let under = paper.color(x: x, y: y)
                            let p = (y * w + x) * 4
                            let r0 = Int(src[p]), g0 = Int(src[p + 1]), b0 = Int(src[p + 2])
                            var sum = (0, 0, 0), count = (0, 0, 0)
                            for yy in max(0, y - 1)...min(h - 1, y + 1) {
                                for xx in max(0, x - 1)...min(w - 1, x + 1) {
                                    let q = (yy * w + xx) * 4
                                    let r = Int(src[q]), g = Int(src[q + 1]), b = Int(src[q + 2])
                                    if abs(r - r0) <= tuning.grain { sum.0 += r; count.0 += 1 }
                                    if abs(g - g0) <= tuning.grain { sum.1 += g; count.1 += 1 }
                                    if abs(b - b0) <= tuning.grain { sum.2 += b; count.2 += 1 }
                                }
                            }
                            let red = Float(sum.0) / Float(max(1, count.0)) / max(1, under.red)
                            let green = Float(sum.1) / Float(max(1, count.1)) / max(1, under.green)
                            let blue = Float(sum.2) / Float(max(1, count.2)) / max(1, under.blue)
                            // Paper beside the fill, its grain no more, or print over it: left as cleaned.
                            guard min(red, green, blue) < tuning.fillWhite, dst[p] >= 240, dst[p + 1] >= 240, dst[p + 2] >= 240
                            else { continue }
                            dst[p] = min(dst[p], UInt8(min(255, max(0, red * 255 + 0.5))))
                            dst[p + 1] = min(dst[p + 1], UInt8(min(255, max(0, green * 255 + 0.5))))
                            dst[p + 2] = min(dst[p + 2], UInt8(min(255, max(0, blue * 255 + 0.5))))
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: Faint print

    /// Small light print made as plain as the rest: where a patch's strokes
    /// stand out from the paper by little, as thin grey letters do once a
    /// phone's soft picture has spread them, each stroke is taken darker by
    /// as much as brings the patch's darkest to `faintTarget` under the
    /// paper, at most `faintGain` times. Only patches of narrow marks are
    /// deepened, and only by what they lie under the paper past the grain,
    /// so the paper stays white and a shadow or a pale fill keeps its
    /// shade; a patch with too few strokes, a speck of dust, is left alone,
    /// as is print already dark.
    static func strengthened(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        guard tuning.faintGain > 1 else { return page }
        let w = page.width, h = page.height
        guard w > 16, h > 16 else { return page }
        let plane = page.brightness
        // How far each pixel stands out from what is a few pixels round it.
        let near = blurred(plane, width: w, height: h, radius: max(2, min(w, h) / 500))
        var mark = [UInt8](repeating: 0, count: w * h)
        var marked = [UInt8](repeating: 0, count: w * h)
        let floor = Int(tuning.faintFloor)
        for p in 0..<(w * h) {
            let by = max(0, Int(near[p]) - Int(plane[p]))
            mark[p] = UInt8(min(255, by))
            if by >= floor + 4 { marked[p] = 255 }
        }
        // Each patch's strongest stroke and how many of its pixels are strokes.
        let reach = max(6, min(w, h) / 120)
        let strongest = widest(mark, width: w, height: h, radius: reach)
        let share = blurred(marked, width: w, height: h, radius: reach)
        let gains: [UInt8] = (0..<(w * h)).map { p in
            let top = Float(strongest[p])
            // A patch of letters has a stroke in one pixel of fifty and more.
            guard top > tuning.faintFloor, top < tuning.faintTarget, share[p] >= 5 else { return 0 }
            return UInt8(min(tuning.faintGain, tuning.faintTarget / top) * 50)
        }
        let gain = blurred(gains, width: w, height: h, radius: reach)
        // Deepened by how far under the paper close round it each pixel is,
        // so a letter is taken darker whole, its middle as its edges.
        let paper = widest(plane, width: w, height: h, radius: reach)
        var out = page
        out.pixels.withUnsafeMutableBufferPointer { px in
            for p in 0..<(w * h) where gain[p] > 50 {
                // Far under the paper, past the patch's strokes, and no
                // narrow mark itself: a grey fill, a seal or a logo, which
                // keeps its shade.
                let under = Int(paper[p]) - Int(plane[p])
                guard under > floor else { continue }
                guard Float(under) <= 1.5 * Float(strongest[p]) + 2 * tuning.faintFloor || 3 * Int(mark[p]) >= under
                else { continue }
                let deeper = (Float(gain[p]) / 50 - 1) * Float(under - floor)
                for k in 0..<3 {
                    px[p * 4 + k] = UInt8(max(0, Float(px[p * 4 + k]) - deeper).rounded())
                }
            }
        }
        return out
    }

    /// The largest value of each pixel's square around it, `radius` each way:
    /// across, then down.
    static func widest(_ plane: [UInt8], width w: Int, height h: Int, radius: Int) -> [UInt8] {
        let across = widest(plane, count: w, lines: h, step: 1, next: w, radius: radius)
        return widest(across, count: h, lines: w, step: w, next: 1, radius: radius)
    }

    /// The same along one direction: `lines` runs of `count` values, each
    /// `step` apart, the runs `next` apart. Blocks of the window's size
    /// keep their maxima from each end, so a window's is the larger of two.
    private static func widest(_ values: [UInt8], count n: Int, lines: Int, step: Int, next: Int, radius: Int) -> [UInt8] {
        let size = 2 * radius + 1
        var out = [UInt8](repeating: 0, count: values.count)
        var fromStart = [UInt8](repeating: 0, count: n), fromEnd = fromStart
        for line in 0..<lines {
            let base = line * next
            for i in 0..<n {
                let v = values[base + i * step]
                fromStart[i] = i % size == 0 ? v : max(fromStart[i - 1], v)
            }
            for i in stride(from: n - 1, through: 0, by: -1) {
                let v = values[base + i * step]
                fromEnd[i] = (i % size == size - 1 || i == n - 1) ? v : max(fromEnd[i + 1], v)
            }
            for i in 0..<n {
                let a = max(0, i - radius), b = min(n - 1, i + radius)
                out[base + i * step] = max(fromEnd[a], fromStart[b])
            }
        }
        return out
    }

    // MARK: Dark print

    /// The page with its print as dark as the curve says and its paper
    /// white: a near-grey pixel, as print on any paper is, by the curve that
    /// makes pale print read; a coloured one, a ballpoint's or a stamp's, by
    /// the gentle curve, so its colour keeps both its hue and its shade, and
    /// never closes over the print beneath it. Brightness alone is changed,
    /// each pixel by its own share of the paper's.
    static func darkened(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        guard tuning.blackPoint > Tuning.standard.blackPoint else { return curved(page, tuning: tuning) }
        let print = curve(tuning)
        var mild = tuning
        mild.blackPoint = Tuning.standard.blackPoint
        let colour = curve(mild)
        let w = page.width, h = page.height
        let plane = page.brightness
        // The strong curve only where the pixel is a stroke of print: a narrow
        // mark with the paper a few pixels around it. A wide grey fill — a
        // table's header, a photo — and the paper itself take the gentle
        // curve, so a light grey keeps its shade whatever the print's.
        let soft = blurred(plane, width: w, height: h, radius: max(2, w / 1000))
        let contrast = Int(tuning.printContrast)
        var out = page
        let low = tuning.neutralBelow, high = tuning.colourAbove
        out.pixels.withUnsafeMutableBufferPointer { px in
            for i in stride(from: 0, to: px.count, by: 4) {
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                let top = max(r, max(g, b)), bottom = min(r, min(g, b))
                let saturation = top > 0 ? Float(top - bottom) / Float(top) : 0
                let kept = min(1, max(0, (saturation - low) / max(1e-6, high - low)))
                let p = i / 4
                let stroke = Int(soft[p]) - Int(plane[p]) >= contrast
                let strongWeight = stroke ? (1 - kept) : 0
                for k in 0..<3 {
                    let value = Int(px[i + k])
                    let strong = Float(print[value]), gentle = Float(colour[value])
                    px[i + k] = UInt8(min(255, max(0, strong * strongWeight + gentle * (1 - strongWeight) + 0.5)))
                }
            }
        }
        return out
    }

    /// How dark the page's print is once its light is even: of the pixels
    /// that are strokes, the darkest `printShare`'s middle, of 255. A
    /// stroke is a pixel clearly darker than the paper a few pixels around
    /// it, so a wide grey fill, a table's header or a photo, whose middle
    /// has no paper near it, takes no part. Nil where there is too little
    /// print to tell.
    static func printDarkness(_ page: ScanBitmap, tuning: Tuning = .standard, boxes: [CGRect] = []) -> Float? {
        let w = page.width, h = page.height
        guard w > 8, h > 8 else { return nil }
        let plane = page.brightness
        // Inside the boxes of text read, the darkest 5 % of the pixels, then
        // the median over the boxes, as a scanner reads its own print: the
        // rules and boxes of the form are not print here, however dark.
        if !boxes.isEmpty {
            var values: [Int] = []
            for box in boxes {
                let x0 = max(0, Int(box.minX * Double(w))), x1 = min(w, Int(box.maxX * Double(w)))
                let y0 = max(0, Int((1 - box.maxY) * Double(h))), y1 = min(h, Int((1 - box.minY) * Double(h)))
                guard x1 - x0 > 4, y1 - y0 > 4 else { continue }
                var pixels: [UInt8] = []
                for y in y0..<y1 { for x in x0..<x1 { pixels.append(plane[y * w + x]) } }
                pixels.sort()
                let darkest = pixels.prefix(max(1, pixels.count / 20))
                values.append(Int(darkest[darkest.startIndex + darkest.count / 2]))
            }
            if !values.isEmpty {
                values.sort()
                return Float(values[values.count / 2])
            }
        }
        let soft = blurred(plane, width: w, height: h, radius: max(2, w / 1000))
        var counts = [Int](repeating: 0, count: 256)
        var strokes = 0
        let contrast = Int(tuning.printContrast)
        for p in 0..<plane.count {
            let value = Int(plane[p])
            guard Int(soft[p]) - value >= contrast else { continue }
            counts[value] += 1
            strokes += 1
        }
        guard strokes >= 200 else { return nil }
        let wanted = max(1, Int(Double(strokes) * Double(tuning.printShare)))
        var seen = 0
        for value in 0..<256 {
            seen += counts[value]
            if seen >= wanted { return Float(value) }
        }
        return nil
    }

    /// The black point that takes the print's darkness to `printTarget`,
    /// as a share of white: the standard one where the print is already
    /// dark, higher where it is light, never so high that a light grey
    /// (a table's header, a pale stamp) is lost, and never past what
    /// keeps the print's own greys apart.
    static func blackPoint(forPrint darkness: Float?, tuning: Tuning = .standard) -> Float {
        guard let darkness else { return tuning.blackPoint }
        let share = darkness / 255
        let span = tuning.whitePoint - tuning.blackPoint
        // Where the curve as it stands leaves this print.
        let along = max(0, (share - tuning.blackPoint) / span)
        let shown = powf(along, tuning.gamma) * 255
        guard shown > tuning.printTarget else { return tuning.blackPoint }
        // The black point that brings it to the target: t^gamma = target/255.
        let t = powf(tuning.printTarget / 255, 1 / tuning.gamma)
        // share = black + t (white − black) → black = (share − t·white) / (1 − t)
        let black = (share - t * tuning.whitePoint) / max(1e-6, 1 - t)
        return min(max(black, tuning.blackPoint), tuning.highestBlack)
    }
}

extension ScanClean.Paper {
    /// The paper's colour at a pixel, between the four nearest cells' middles.
    func color(x: Int, y: Int) -> (red: Float, green: Float, blue: Float) {
        let size = Float(cell)
        let u = (Float(x) + 0.5) / size - 0.5, v = (Float(y) + 0.5) / size - 0.5
        let c0 = min(max(Int(u.rounded(.down)), 0), columns - 1), r0 = min(max(Int(v.rounded(.down)), 0), rows - 1)
        let c1 = min(c0 + 1, columns - 1), r1 = min(r0 + 1, rows - 1)
        let tx = min(max(u - Float(c0), 0), 1), ty = min(max(v - Float(r0), 0), 1)
        func mix(_ plane: [Float]) -> Float {
            let top = plane[r0 * columns + c0] + (plane[r0 * columns + c1] - plane[r0 * columns + c0]) * tx
            let bottom = plane[r1 * columns + c0] + (plane[r1 * columns + c1] - plane[r1 * columns + c0]) * tx
            return top + (bottom - top) * ty
        }
        return (mix(red), mix(green), mix(blue))
    }

    /// Cells marked as print because they are darker than the paper on
    /// both sides of them, joined where they touch: each patch a band, a
    /// box or a shadow, to tell apart by its edges.
    static func patches(paper: [Bool], firstPass: [Bool], columns: Int, rows: Int) -> [[Int]] {
        var seen = [Bool](repeating: false, count: paper.count)
        var patches: [[Int]] = []
        for start in paper.indices where firstPass[start] && !paper[start] && !seen[start] {
            var patch: [Int] = [], stack = [start]
            seen[start] = true
            while let n = stack.popLast() {
                patch.append(n)
                let row = n / columns, column = n % columns
                for (r, c) in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
                    where r >= 0 && r < rows && c >= 0 && c < columns {
                    let m = r * columns + c
                    if firstPass[m], !paper[m], !seen[m] {
                        seen[m] = true
                        stack.append(m)
                    }
                }
            }
            patches.append(patch)
        }
        return patches
    }

    /// The page's paper without its print, at a small size: each block
    /// the brightest of its pixels, so strokes thinner than a block are
    /// gone and only the paper's own light and what is filled in are left.
    /// Its edges tell light from print: a filled box's turns from one
    /// block to the next; a fold's or a shadow's over many.
    struct Edges {
        let block: Int
        let width: Int
        let height: Int
        let plane: [Float]
        /// The paper's colour in each block: fine enough to follow a fold's
        /// narrow shadow.
        let red: [Float]
        let green: [Float]
        let blue: [Float]
        let cell: Int
        let columns: Int
        let rows: Int
        /// Each cell's paper, the middle of its blocks.
        let cells: [Float]
        /// The paper's colour in each block, the middle of its pixels taken
        /// with the middle of the eight blocks round it: the paper as its
        /// light leaves it, fine enough to follow a fold's or a shadow's
        /// edge, smooth enough not to follow its print.
        let fineRed: [Float]
        let fineGreen: [Float]
        let fineBlue: [Float]

        init(of page: ScanBitmap, cell: Int, columns: Int, rows: Int) {
            let block = max(2, cell / 4)
            let width = (page.width + block - 1) / block, height = (page.height + block - 1) / block
            // Each block's paper, colour by colour: a bright value of its
            // pixels, not the very brightest, which a speck of the camera's
            // grain sets; over the print, which is thinner than a block.
            var counts = [UInt16](repeating: 0, count: width * 768)
            var red = [Float](repeating: 0, count: width * height), green = red, blue = red
            var middleRed = red, middleGreen = red, middleBlue = red
            page.pixels.withUnsafeBufferPointer { px in
                for by in 0..<height {
                    for i in counts.indices { counts[i] = 0 }
                    let top = by * block, bottom = min(page.height, top + block)
                    for y in top..<bottom {
                        var i = y * page.width * 4
                        for x in 0..<page.width {
                            let base = (x / block) * 768
                            counts[base + Int(px[i])] += 1
                            counts[base + 256 + Int(px[i + 1])] += 1
                            counts[base + 512 + Int(px[i + 2])] += 1
                            i += 4
                        }
                    }
                    for bx in 0..<width {
                        let left = bx * block, right = min(page.width, left + block)
                        let pixels = max(1, (right - left) * (bottom - top))
                        // The value a fifth of the pixels reach, from the bright: over the
                        // grain and the print, so a fold's shadow shows its true depth.
                        let wanted = max(1, pixels / 5)
                        // And the middle of them, the paper as its light leaves it,
                        // which a fold's shadow takes down whole and print covers.
                        let middle = max(1, pixels / 2)
                        func reached(_ channel: Int, _ many: Int) -> Float {
                            var seen = 0, value = 255
                            while value > 0 {
                                seen += Int(counts[bx * 768 + channel * 256 + value])
                                if seen >= many { break }
                                value -= 1
                            }
                            return Float(value)
                        }
                        let n = by * width + bx
                        red[n] = reached(0, wanted)
                        green[n] = reached(1, wanted)
                        blue[n] = reached(2, wanted)
                        middleRed[n] = reached(0, middle)
                        middleGreen[n] = reached(1, middle)
                        middleBlue[n] = reached(2, middle)
                    }
                }
            }
            // Not smoothed: a printed fill's edge stays one block wide, and
            // the paper under a fold's shadow is followed to its deepest.
            let plane = (0..<red.count).map { ScanClean.Paper.lightness(red[$0], green[$0], blue[$0]) }
            self.red = red
            self.green = green
            self.blue = blue
            var cells = [Float](repeating: 0, count: columns * rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    var values: [Float] = []
                    let x0 = column * cell / block, x1 = min(width, ((column + 1) * cell + block - 1) / block)
                    let y0 = row * cell / block, y1 = min(height, ((row + 1) * cell + block - 1) / block)
                    for by in y0..<max(y0 + 1, y1) where by < height {
                        for bx in x0..<max(x0 + 1, x1) where bx < width { values.append(plane[by * width + bx]) }
                    }
                    cells[row * columns + column] = values.isEmpty ? 0 : ScanClean.Paper.median(values)
                }
            }
            self.block = block
            self.width = width
            self.height = height
            self.plane = plane
            self.cell = cell
            self.columns = columns
            self.rows = rows
            self.cells = cells
            func middled(_ values: [Float]) -> [Float] {
                var out = values
                guard width > 2, height > 2 else { return out }
                // The middle of the nine round each: kept in a little buffer,
                // in order, so no sorting and no allocation per pixel.
                var least = [Float](repeating: 0, count: 9)
                for by in 0..<height {
                    for bx in 0..<width {
                        var kept = 0
                        for y in max(0, by - 1)...min(height - 1, by + 1) {
                            for x in max(0, bx - 1)...min(width - 1, bx + 1) {
                                let value = values[y * width + x]
                                var k = kept
                                while k > 0, least[k - 1] > value {
                                    least[k] = least[k - 1]
                                    k -= 1
                                }
                                least[k] = value
                                kept += 1
                            }
                        }
                        out[by * width + bx] = least[kept / 2]
                    }
                }
                return out
            }
            self.fineRed = middled(middleRed)
            self.fineGreen = middled(middleGreen)
            self.fineBlue = middled(middleBlue)
        }

        /// The paper's colour at a pixel between the four nearest blocks'
        /// middles, each block taken with those round it.
        @inline(__always)
        func fine(x: Int, y: Int) -> (red: Float, green: Float, blue: Float) {
            let u = (Float(x) + 0.5) / Float(block) - 0.5, v = (Float(y) + 0.5) / Float(block) - 0.5
            let x0 = min(max(Int(u.rounded(.down)), 0), width - 1), y0 = min(max(Int(v.rounded(.down)), 0), height - 1)
            let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let tx = min(max(u - Float(x0), 0), 1), ty = min(max(v - Float(y0), 0), 1)
            func mix(_ plane: [Float]) -> Float {
                let top = plane[y0 * width + x0] + (plane[y0 * width + x1] - plane[y0 * width + x0]) * tx
                let bottom = plane[y1 * width + x0] + (plane[y1 * width + x1] - plane[y1 * width + x0]) * tx
                return top + (bottom - top) * ty
            }
            return (mix(fineRed), mix(fineGreen), mix(fineBlue))
        }

        /// The paper's colour at a pixel, between the four nearest blocks' middles.
        @inline(__always)
        func paper(x: Int, y: Int) -> (red: Float, green: Float, blue: Float) {
            let u = (Float(x) + 0.5) / Float(block) - 0.5, v = (Float(y) + 0.5) / Float(block) - 0.5
            let x0 = min(max(Int(u.rounded(.down)), 0), width - 1), y0 = min(max(Int(v.rounded(.down)), 0), height - 1)
            let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let tx = min(max(u - Float(x0), 0), 1), ty = min(max(v - Float(y0), 0), 1)
            func mix(_ plane: [Float]) -> Float {
                let top = plane[y0 * width + x0] + (plane[y0 * width + x1] - plane[y0 * width + x0]) * tx
                let bottom = plane[y1 * width + x0] + (plane[y1 * width + x1] - plane[y1 * width + x0]) * tx
                return top + (bottom - top) * ty
            }
            return (mix(red), mix(green), mix(blue))
        }

        /// How sharp a darker patch's edge is, from 0 to 1: round its edge,
        /// the share of the change from its darkest to the paper beyond
        /// made in the steepest step from one block to the next, the middle
        /// of them. A box filled in makes nearly all of it in one; a fold or
        /// a shadow spreads it out. Nil where its edge cannot be read, as
        /// for a patch with nothing round it.
        func sharpness(of patch: [Int], tuning: ScanClean.Tuning) -> Float? {
            let inside = Set(patch)
            var shares: [Float] = []
            for n in patch {
                let row = n / columns, column = n % columns
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let r = row + dr, c = column + dc
                    guard r >= 0, r < rows, c >= 0, c < columns, !inside.contains(r * columns + c) else { continue }
                    if let share = steepest(row: row, column: column, toward: (dr, dc), inside: inside, tuning: tuning) {
                        shares.append(share)
                    }
                }
            }
            return shares.count >= 2 ? ScanClean.Paper.median(shares) : nil
        }

        /// Across a patch's edge, from the darkest of it to the paper well
        /// beyond: where it is a cell's width or more into the patch, back
        /// to its darkest, and out as far again past its edge. The share
        /// of the change made in the steepest step from one block to the
        /// next, the middle of a few lines side by side; nil where the
        /// change is too small to read.
        private func steepest(row: Int, column: Int, toward step: (Int, Int), inside: Set<Int>,
                              tuning: ScanClean.Tuning) -> Float? {
            let perCell = max(2, cell / block)
            // Back into the patch as far as it goes, up to two cells, and out two cells past its edge.
            var back = 0
            while back < 2, inside.contains((row - step.0 * (back + 1)) * columns + (column - step.1 * (back + 1))),
                  row - step.0 * (back + 1) >= 0, row - step.0 * (back + 1) < rows,
                  column - step.1 * (back + 1) >= 0, column - step.1 * (back + 1) < columns {
                back += 1
            }
            let edge = (x: (column * cell + cell / 2) / block + step.1 * perCell / 2,
                        y: (row * cell + cell / 2) / block + step.0 * perCell / 2)
            let reachIn = perCell / 2 + back * perCell, reachOut = 2 * perCell
            var shares: [Float] = []
            for offset in stride(from: -(perCell / 2), through: perCell / 2, by: max(1, perCell / 4)) {
                var profile: [Float] = []
                for k in -reachIn...reachOut {
                    let x = edge.x + step.1 * k + (step.1 == 0 ? offset : 0)
                    let y = edge.y + step.0 * k + (step.0 == 0 ? offset : 0)
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    profile.append(plane[y * width + x])
                }
                guard profile.count >= 4, let low = profile.min(), let high = profile.max() else { continue }
                let change = high - low
                guard change >= tuning.edgeContrast else { continue }
                var largest: Float = 0
                for k in 1..<profile.count { largest = max(largest, abs(profile[k] - profile[k - 1])) }
                shares.append(min(1, largest / change))
            }
            return shares.isEmpty ? nil : ScanClean.Paper.median(shares)
        }
    }
}
