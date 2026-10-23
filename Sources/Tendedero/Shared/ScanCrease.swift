import Foundation

/// A crease: the thin line a sheet folded flat keeps where it was folded,
/// grey across the whole sheet from one edge to the other, as a flatbed
/// scanner or a photo of a sheet lying flat shows it. It is light, not
/// print, so it is evened as the paper is: the pixels along it are made
/// lighter by as much as the line took from them, print on it included,
/// which comes back as dark as it was printed. Nothing is drawn or moved.
///
/// It is told from a printed line by four things at once: it reaches both
/// edges of the sheet, through the margins where nothing is printed; it is
/// faint; it has no colour of its own, as the blue lines of lined paper
/// have; and a sheet has one or two, never a page of them.
extension ScanClean {
    /// A crease found on a page, as where it lies: a row, or a column for
    /// one running down the page, at the page's left or top end, and how far
    /// it climbs per pixel along it.
    struct Crease: Equatable, Sendable {
        let across: Bool
        let at: Double
        let slope: Double

        /// Where it lies at a point along it.
        func line(at along: Double) -> Double { at + slope * along }
    }

    /// The page with its creases evened out, across and down; the page
    /// itself where it has none, or more than a sheet folded can have.
    static func uncreased(_ page: ScanBitmap, tuning: Tuning = .standard) -> ScanBitmap {
        var out = page
        let plane = page.brightness
        for across in [true, false] {
            let light = profiles(plane, width: page.width, height: page.height, across: across, strips: tuning.creaseStrips)
            let found = creases(in: page, across: across, light: light, tuning: tuning)
            if !found.isEmpty { out = evenedOut(found, in: out, light: light, tuning: tuning) }
        }
        return out
    }

    /// The creases running across the page (`across`), or down it.
    static func creases(in page: ScanBitmap, across: Bool, tuning: Tuning = .standard) -> [Crease] {
        let light = profiles(page.brightness, width: page.width, height: page.height, across: across,
                             strips: tuning.creaseStrips)
        return creases(in: page, across: across, light: light, tuning: tuning)
    }

    private static func creases(in page: ScanBitmap, across: Bool, light: [[Float]], tuning: Tuning) -> [Crease] {
        let w = page.width, h = page.height
        // Along the crease and across it.
        let length = across ? w : h, span = across ? h : w
        guard length >= 200, span >= 200 else { return [] }
        let strips = tuning.creaseStrips, stripLength = length / strips
        let reach = max(6, span / 300)
        // Each strip's rows that are a narrow, faint, grey dip in its paper.
        var dipped = [[Bool]](repeating: [Bool](repeating: false, count: span), count: strips)
        var lowest = [[Int]](repeating: [], count: strips)
        for s in 0..<strips {
            let values = light[s]
            for y in reach..<(span - reach) {
                let around = min(values[y - reach], values[y + reach])
                let dip = around - values[y]
                guard dip >= tuning.creaseDepth, values[y] >= tuning.creaseFaint * around,
                      values[y] <= values[y - 1], values[y] <= values[y + 1],
                      tint(of: page, across: across, row: y, from: s * stripLength, to: (s + 1) * stripLength,
                           atLeast: values[y]) < tuning.neutralBelow else { continue }
                for k in max(0, y - 2)...min(span - 1, y + 2) { dipped[s][k] = true }
                lowest[s].append(y)
            }
        }
        // Lines through dips in nearly every strip, both ends' strips among
        // them, at most a little slanted, each line once.
        var found: [Crease] = []
        let slopes = stride(from: -tuning.creaseSlant, through: tuning.creaseSlant, by: tuning.creaseSlant / 10)
        let needed = Int((Double(strips) * tuning.creaseReach).rounded(.up))
        for y in reach..<(span - reach) {
            var best: (count: Int, slope: Double)?
            for slope in slopes {
                var count = 0, first = false, last = false
                for s in 0..<strips {
                    let middle = Double(s * stripLength + stripLength / 2)
                    let row = Int((Double(y) + slope * (middle - Double(length) / 2)).rounded())
                    guard row >= 0, row < span, dipped[s][row] else { continue }
                    count += 1
                    if s == 0 { first = true }
                    if s == strips - 1 { last = true }
                }
                if first, last, count >= needed, count > best?.count ?? 0 { best = (count, slope) }
            }
            guard let best else { continue }
            // Then laid through each strip's own lowest row near it.
            var points: [(along: Double, row: Double)] = []
            for s in 0..<strips {
                let middle = Double(s * stripLength + stripLength / 2)
                let row = Double(y) + best.slope * (middle - Double(length) / 2)
                if let nearest = lowest[s].min(by: { abs(Double($0) - row) < abs(Double($1) - row) }), abs(Double(nearest) - row) <= 3 {
                    points.append((middle, Double(nearest)))
                }
            }
            var crease = Crease(across: across, at: Double(y) - best.slope * Double(length) / 2, slope: best.slope)
            if let fitted = fit(points) { crease = Crease(across: across, at: fitted.at, slope: fitted.slope) }
            let middle = crease.line(at: Double(length) / 2)
            if found.contains(where: { abs($0.line(at: Double(length) / 2) - middle) < Double(2 * reach) }) { continue }
            found.append(crease)
        }
        // A sheet is folded once or twice, three times at most; more lines
        // than that are the page's own, as lined paper's are.
        return found.count <= 3 ? found : []
    }

    /// The straight line nearest some points, as where it starts and how
    /// far it climbs per pixel; nil for fewer than two.
    private static func fit(_ points: [(along: Double, row: Double)]) -> (at: Double, slope: Double)? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let meanAlong = points.reduce(0) { $0 + $1.along } / n, meanRow = points.reduce(0) { $0 + $1.row } / n
        var across = 0.0, spread = 0.0
        for point in points {
            across += (point.along - meanAlong) * (point.row - meanRow)
            spread += (point.along - meanAlong) * (point.along - meanAlong)
        }
        guard spread > 0 else { return nil }
        let slope = across / spread
        return (meanRow - slope * meanAlong, slope)
    }

    /// For each strip along the page, each row's paper: the value its
    /// brightest third of pixels reach, which print in the row leaves alone
    /// and a crease takes down whole.
    static func profiles(_ plane: [UInt8], width w: Int, height h: Int, across: Bool, strips: Int) -> [[Float]] {
        let length = across ? w : h, span = across ? h : w
        let stripLength = length / strips
        var values = [[Float]](repeating: [Float](repeating: 0, count: span), count: strips)
        var counts = [Int32](repeating: 0, count: 256)
        var buffer = [UInt8](repeating: 0, count: span * (stripLength + length % strips))
        plane.withUnsafeBufferPointer { src in
            buffer.withUnsafeMutableBufferPointer { row in
                counts.withUnsafeMutableBufferPointer { count in
                    for s in 0..<strips {
                        let start = s * stripLength, end = s == strips - 1 ? length : start + stripLength
                        let n = end - start
                        // The strip's rows one after another, read in the page's own order.
                        if across {
                            for y in 0..<span { for k in start..<end { row[y * n + k - start] = src[y * w + k] } }
                        } else {
                            for k in start..<end { for y in 0..<span { row[y * n + k - start] = src[k * w + y] } }
                        }
                        let wanted = Int32(max(1, n / 3))
                        for y in 0..<span {
                            let base = y * n
                            for k in 0..<n { count[Int(row[base + k])] += 1 }
                            var seen: Int32 = 0, value = 255
                            while value > 0 {
                                seen += count[value]
                                if seen >= wanted { break }
                                value -= 1
                            }
                            for k in 0..<n { count[Int(row[base + k])] = 0 }
                            values[s][y] = Float(value)
                        }
                    }
                }
            }
        }
        return values
    }

    /// How coloured a row of a strip's paper is: the mean saturation of its
    /// pixels at `least` and brighter.
    private static func tint(of page: ScanBitmap, across: Bool, row y: Int, from start: Int, to end: Int,
                             atLeast least: Float) -> Float {
        var tint: Float = 0, count = 0
        let w = page.width
        for k in start..<min(end, across ? page.width : page.height) {
            let p = (across ? y * w + k : k * w + y) * 4
            let r = page.pixels[p], g = page.pixels[p + 1], b = page.pixels[p + 2]
            guard Float(brightness(r, g, b)) >= least else { continue }
            let top = Float(max(r, g, b)), bottom = Float(min(r, g, b))
            tint += top > 0 ? (top - bottom) / top : 0
            count += 1
        }
        return tint / Float(max(1, count))
    }

    /// The pixels along each crease made lighter by as much as it took from
    /// the paper there, strip by strip and smoothly between strips.
    private static func evenedOut(_ creases: [Crease], in page: ScanBitmap, light: [[Float]], tuning: Tuning) -> ScanBitmap {
        let w = page.width, h = page.height
        let across = creases[0].across
        let length = across ? w : h, span = across ? h : w
        let strips = tuning.creaseStrips, stripLength = length / strips
        let reach = max(6, span / 300)
        var out = page
        for crease in creases {
            // Each strip's gain down the crease's band: the paper beside it,
            // the lower of its two sides, over the paper on the line.
            var gains = [[Float]](repeating: [Float](repeating: 1, count: 2 * reach + 1), count: strips)
            for s in 0..<strips {
                let middle = Double(s * stripLength + stripLength / 2)
                let centre = Int(crease.line(at: middle).rounded())
                func side(_ from: Int, _ to: Int) -> Float {
                    var most: Float = 0
                    for y in min(from, to)...max(from, to) where y >= 0 && y < span { most = max(most, light[s][y]) }
                    return most
                }
                let paper = min(side(centre - 3 * reach, centre - reach - 1), side(centre + reach + 1, centre + 3 * reach))
                for k in -reach...reach {
                    let y = centre + k
                    guard y >= 0, y < span, paper > 0 else { continue }
                    let value = max(1, light[s][y])
                    gains[s][k + reach] = min(1 / tuning.creaseFaint, max(1, paper / value))
                }
            }
            out.pixels.withUnsafeMutableBufferPointer { px in
                for k in 0..<length {
                    // Between the two nearest strips' middles.
                    let u = (Double(k) + 0.5) / Double(stripLength) - 0.5
                    let s0 = min(max(Int(u.rounded(.down)), 0), strips - 1), s1 = min(s0 + 1, strips - 1)
                    let t = Float(min(max(u - Double(s0), 0), 1))
                    let centre = Int(crease.line(at: Double(k)).rounded())
                    for offset in -reach...reach {
                        let y = centre + offset
                        guard y >= 0, y < span else { continue }
                        let gain = gains[s0][offset + reach] * (1 - t) + gains[s1][offset + reach] * t
                        guard gain > 1.001 else { continue }
                        let p = (across ? y * w + k : k * w + y) * 4
                        for c in 0..<3 { px[p + c] = UInt8(min(255, Float(px[p + c]) * gain + 0.5)) }
                    }
                }
            }
        }
        return out
    }
}
