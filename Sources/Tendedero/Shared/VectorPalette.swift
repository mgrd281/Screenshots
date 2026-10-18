import Foundation

/// The picture as the tracer reads it: 8 bits a channel, colour not
/// multiplied by its opacity, row after row from the top left.
struct VectorPixels {
    var width: Int
    var height: Int
    var rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// A picture of one flat colour.
    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8, UInt8)) {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            data[i * 4] = fill.0
            data[i * 4 + 1] = fill.1
            data[i * 4 + 2] = fill.2
            data[i * 4 + 3] = fill.3
        }
        self.init(width: width, height: height, rgba: data)
    }
}

/// What the tracer works out about each pixel before it chooses colours.
enum VectorAnalysis {
    /// Pixels of a flat area, or of a line long enough to be drawn on purpose,
    /// are what the colours of a picture are chosen from: the pixels where
    /// one colour fades into another are only blends of them.
    struct Result {
        /// Pixels, at least half opaque, that lie in a flat area or on a long thin line.
        var solid: [UInt8]
        /// Pixels, at least half opaque, that are not a blend of what lies two
        /// pixels to either side: the middle of a thin stroke, a hairline.
        var feature: [UInt8]
        var solidCount: Int
    }

    /// - Parameter minRun: how long a line of one colour has to run to count
    ///   as a line drawn on purpose rather than the edge of a stroke.
    static func analyse(_ pixels: VectorPixels, minRun: Int = 24) -> Result {
        let w = pixels.width, h = pixels.height
        let count = w * h
        var flat = [UInt8](repeating: 0, count: count)
        var feature = [UInt8](repeating: 0, count: count)
        var longRun = [UInt8](repeating: 0, count: count)
        pixels.rgba.withUnsafeBufferPointer { px in
            flatPixels(px, w, h, &flat)
            featurePixels(px, w, h, &feature)
            longRuns(px, w, h, minRun, &longRun)
        }
        var solid = [UInt8](repeating: 0, count: count)
        var solidCount = 0
        for i in 0..<count where flat[i] != 0 || (feature[i] != 0 && longRun[i] != 0) {
            solid[i] = 1
            solidCount += 1
        }
        return Result(solid: solid, feature: feature, solidCount: solidCount)
    }

    /// A pixel is flat when seven of the eight pixels round it are nearly its colour.
    private static func flatPixels(_ px: UnsafeBufferPointer<UInt8>, _ w: Int, _ h: Int, _ flat: inout [UInt8]) {
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if px[i + 3] < 128 { continue }
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                var similar = 0
                for dy in -1...1 {
                    let yn = min(max(y + dy, 0), h - 1)
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let xn = min(max(x + dx, 0), w - 1)
                        let j = (yn * w + xn) * 4
                        if abs(Int(px[j]) - r) <= 8 && abs(Int(px[j + 1]) - g) <= 8 && abs(Int(px[j + 2]) - b) <= 8 {
                            similar += 1
                        }
                    }
                }
                if similar >= 7 { flat[y * w + x] = 1 }
            }
        }
    }

    /// Whether a pixel stands out from the blend of the two pixels two steps
    /// to its sides, across either axis.
    private static func featurePixels(_ px: UnsafeBufferPointer<UInt8>, _ w: Int, _ h: Int, _ feature: inout [UInt8]) {
        let reach = 2
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if px[i + 3] < 128 { continue }
                let v = SIMD3<Float>(Float(px[i]), Float(px[i + 1]), Float(px[i + 2]))
                for axis in 0..<2 {
                    let xa = axis == 0 ? max(x - reach, 0) : x
                    let ya = axis == 0 ? y : max(y - reach, 0)
                    let xb = axis == 0 ? min(x + reach, w - 1) : x
                    let yb = axis == 0 ? y : min(y + reach, h - 1)
                    let ia = (ya * w + xa) * 4, ib = (yb * w + xb) * 4
                    let a = SIMD3<Float>(Float(px[ia]), Float(px[ia + 1]), Float(px[ia + 2]))
                    let b = SIMD3<Float>(Float(px[ib]), Float(px[ib + 1]), Float(px[ib + 2]))
                    let away = distanceToSegment(v, a, b)
                    if away > 10 {
                        feature[y * w + x] = 1
                        break
                    }
                }
            }
        }
    }

    /// Marks the pixels on a straight run of one colour at least `minRun`
    /// long, along a row or down a column.
    private static func longRuns(_ px: UnsafeBufferPointer<UInt8>, _ w: Int, _ h: Int, _ minRun: Int, _ mark: inout [UInt8]) {
        func same(_ a: Int, _ b: Int) -> Bool {
            abs(Int(px[a]) - Int(px[b])) <= 4 && abs(Int(px[a + 1]) - Int(px[b + 1])) <= 4
                && abs(Int(px[a + 2]) - Int(px[b + 2])) <= 4
        }
        for y in 0..<h {
            var start = 0
            for x in 1...max(w, 1) {
                let ends = x == w || !same((y * w + x) * 4, (y * w + x - 1) * 4)
                if ends {
                    if x - start >= minRun { for k in start..<x { mark[y * w + k] = 1 } }
                    start = x
                }
            }
        }
        for x in 0..<w {
            var start = 0
            for y in 1...max(h, 1) {
                let ends = y == h || !same((y * w + x) * 4, ((y - 1) * w + x) * 4)
                if ends {
                    if y - start >= minRun { for k in start..<y { mark[k * w + x] = 1 } }
                    start = y
                }
            }
        }
    }

    /// How far a colour is from the straight line between two others.
    @inline(__always)
    static func distanceToSegment(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        distanceToSegmentSquared(p, a, b).squareRoot()
    }

    @inline(__always)
    static func distanceToSegmentSquared(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = b - a
        let den = (d * d).sum()
        var t: Float = 0
        if den > 1e-9 { t = min(max(((p - a) * d).sum() / den, 0), 1) }
        let e = p - (a + d * t)
        return (e * e).sum()
    }
}

// MARK: Colour

enum VectorColorMath {
    private static let linear: [Double] = (0..<256).map { value in
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// CIE Lab (D65) of an sRGB colour, which is what colours are told apart in:
    /// a step of one in it is about the least a person sees.
    static func lab(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
        let lr = linear[r], lg = linear[g], lb = linear[b]
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047
        let y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return SIMD3<Float>(Float(116 * fy - 16), Float(500 * (fx - fy)), Float(200 * (fy - fz)))
    }
}

// MARK: Histogram

/// The colours of a picture counted in bins of two levels a channel: coarse
/// enough to count fast, fine enough to tell a white card from a pale page.
struct VectorHistogram {
    static let bits = 7
    static let shift = 8 - bits
    static let size = 1 << (3 * bits)

    static func key(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        (Int(r >> UInt8(shift)) << (2 * bits)) | (Int(g >> UInt8(shift)) << bits) | Int(b >> UInt8(shift))
    }

    /// The colour in the middle of a bin.
    static func centre(of key: Int) -> (Int, Int, Int) {
        let mask = (1 << bits) - 1
        let half = (1 << shift) / 2
        return ((((key >> (2 * bits)) & mask) << shift) + half,
                (((key >> bits) & mask) << shift) + half,
                ((key & mask) << shift) + half)
    }

    /// The bins that hold a pixel, in order.
    var keys: [Int] = []
    /// Pixels of the picture in each bin.
    var count: [Float] = []
    /// Solid pixels in each bin: what the colours are chosen from.
    var weight: [Float] = []
    /// Whether a bin holds a pixel that is a feature.
    var feature: [Bool] = []
    var lab: [SIMD3<Float>] = []
    var rgb: [SIMD3<Float>] = []

    init(pixels: VectorPixels, analysis: VectorAnalysis.Result) {
        var counts = [UInt32](repeating: 0, count: VectorHistogram.size)
        var weights = [UInt32](repeating: 0, count: VectorHistogram.size)
        var features = [UInt8](repeating: 0, count: VectorHistogram.size)
        let total = pixels.width * pixels.height
        for i in 0..<total where pixels.rgba[i * 4 + 3] >= 128 {
            let k = VectorHistogram.key(pixels.rgba[i * 4], pixels.rgba[i * 4 + 1], pixels.rgba[i * 4 + 2])
            counts[k] += 1
            if analysis.solid[i] != 0 { weights[k] += 1 }
            if analysis.feature[i] != 0 { features[k] = 1 }
        }
        for k in 0..<VectorHistogram.size where counts[k] > 0 {
            keys.append(k)
            count.append(Float(counts[k]))
            weight.append(Float(weights[k]))
            feature.append(features[k] != 0)
            let c = VectorHistogram.centre(of: k)
            lab.append(VectorColorMath.lab(c.0, c.1, c.2))
            rgb.append(SIMD3<Float>(Float(c.0), Float(c.1), Float(c.2)))
        }
    }
}

// MARK: Palette

/// The colours a picture is drawn in.
struct VectorPalette {
    struct Entry {
        var lab: SIMD3<Float>
        var rgb: SIMD3<Float>
    }

    var entries: [Entry]

    var count: Int { entries.count }

    /// Chooses the colours: first from the flat areas, merged where they are too
    /// near to tell apart, then any colour of a thin stroke that the blends of
    /// the others cannot explain.
    /// - Parameters:
    ///   - maximum: how many colours there may be.
    ///   - merge: colours nearer than this in Lab are one.
    ///   - total: opaque pixels in the picture.
    ///   - photo: no flat areas to choose from, so every pixel counts.
    static func choose(from histogram: VectorHistogram, maximum: Int, merge: Float, total: Int, photo: Bool) -> VectorPalette {
        let n = histogram.keys.count
        guard n > 0 else { return VectorPalette(entries: []) }
        let weights: [Float] = photo ? histogram.count : histogram.weight
        // The bins to choose from.
        var use: [Int] = []
        use.reserveCapacity(n)
        for i in 0..<n where weights[i] > 0 { use.append(i) }
        if use.isEmpty { use = Array(0..<n) }
        // A photograph has far more colours than can matter: the commonest are enough.
        if use.count > 150_000 {
            use.sort { weights[$0] != weights[$1] ? weights[$0] > weights[$1] : $0 < $1 }
            use = Array(use[0..<150_000]).sorted()
        }
        let m = use.count
        let points = use.map { histogram.lab[$0] }
        let w = use.map { max(weights[$0], 1) }
        let k = max(1, min(maximum, m))

        // Weighted farthest-point start.
        var centers: [Int] = []
        var best = 0
        for i in 0..<m where w[i] > w[best] { best = i }
        centers.append(best)
        var d2 = [Float](repeating: 0, count: m)
        for i in 0..<m {
            let d = points[i] - points[best]
            d2[i] = (d * d).sum()
        }
        while centers.count < k {
            var pick = -1
            var score: Float = 0
            for i in 0..<m {
                let s = w[i] * d2[i]
                if s > score {
                    score = s
                    pick = i
                }
            }
            if pick < 0 { break }
            centers.append(pick)
            for i in 0..<m {
                let d = points[i] - points[pick]
                d2[i] = min(d2[i], (d * d).sum())
            }
        }
        var means = centers.map { points[$0] }
        var weightOf = [Float](repeating: 0, count: means.count)
        var owner = [Int](repeating: 0, count: m)
        for pass in 0..<13 {
            var sums = [SIMD3<Float>](repeating: .zero, count: means.count)
            var totals = [Float](repeating: 0, count: means.count)
            for i in 0..<m {
                var bestK = 0
                var bestD = Float.infinity
                for c in 0..<means.count {
                    let d = points[i] - means[c]
                    let dd = (d * d).sum()
                    if dd < bestD {
                        bestD = dd
                        bestK = c
                    }
                }
                owner[i] = bestK
                sums[bestK] += points[i] * w[i]
                totals[bestK] += w[i]
            }
            weightOf = totals
            if pass == 12 { break }
            for c in 0..<means.count where totals[c] > 0 { means[c] = sums[c] / totals[c] }
        }
        // The colour a bin stands for, as it was seen, for each cluster.
        var rgbSums = [SIMD3<Float>](repeating: .zero, count: means.count)
        for i in 0..<m { rgbSums[owner[i]] += histogram.rgb[use[i]] * w[i] }
        var rgbOf = (0..<means.count).map { weightOf[$0] > 0 ? rgbSums[$0] / weightOf[$0] : SIMD3<Float>(repeating: 128) }

        // Merge colours too near to tell apart, the nearest pair first.
        var alive = Array(0..<means.count)
        while alive.count > 1 {
            var pair: (Int, Int)?
            var nearest = merge
            for a in 0..<alive.count {
                for b in (a + 1)..<alive.count {
                    let d = means[alive[a]] - means[alive[b]]
                    let distance = (d * d).sum().squareRoot()
                    if distance < nearest {
                        nearest = distance
                        pair = (a, b)
                    }
                }
            }
            guard let (a, b) = pair else { break }
            let x = alive[a], y = alive[b]
            let sum = weightOf[x] + weightOf[y]
            if sum > 0 {
                means[x] = (means[x] * weightOf[x] + means[y] * weightOf[y]) / sum
                rgbOf[x] = (rgbOf[x] * weightOf[x] + rgbOf[y] * weightOf[y]) / sum
            }
            weightOf[x] = sum
            alive.remove(at: b)
        }
        // Drop what hardly any pixel supports.
        let minimumWeight: Float = 6
        let kept = alive.filter { weightOf[$0] >= minimumWeight }
        if kept.isEmpty, let strongest = alive.max(by: { weightOf[$0] < weightOf[$1] }) {
            alive = [strongest]
        } else {
            alive = kept
        }
        var entries = alive.map { VectorPalette.Entry(lab: means[$0], rgb: rgbOf[$0]) }

        // Colours the blends of the others cannot explain: thin text, hairlines.
        if !photo, entries.count < maximum {
            entries = addUnexplained(entries, histogram: histogram, maximum: maximum, total: total)
        }
        return VectorPalette(entries: entries)
    }

    /// Adds, most extreme first, the colours of thin features that no blend of
    /// two colours already there accounts for.
    private static func addUnexplained(_ start: [Entry], histogram: VectorHistogram, maximum: Int, total: Int) -> [Entry] {
        var entries = start
        let n = histogram.keys.count
        // The squared distance of every bin to a colour or to a blend of two.
        var resid = [Float](repeating: .infinity, count: n)
        func absorb(_ color: SIMD3<Float>, against others: [SIMD3<Float>]) {
            for i in 0..<n {
                let p = histogram.lab[i]
                let d = p - color
                var best = min(resid[i], (d * d).sum())
                for other in others {
                    best = min(best, VectorAnalysis.distanceToSegmentSquared(p, color, other))
                }
                resid[i] = best
            }
        }
        var placed: [SIMD3<Float>] = []
        for entry in entries {
            absorb(entry.lab, against: placed)
            placed.append(entry.lab)
        }
        let limit: Float = 4 * 4
        let unexplained = 0.0003 * Float(total)
        while entries.count < maximum {
            var badCount: Float = 0
            var mostCommon: Float = 0
            for i in 0..<n where histogram.feature[i] && resid[i] > limit {
                badCount += histogram.count[i]
                mostCommon = max(mostCommon, histogram.count[i])
            }
            if badCount < unexplained || badCount == 0 { break }
            let floor = max(2, 0.08 * mostCommon)
            var pick = -1
            var worst: Float = 0
            for i in 0..<n where histogram.feature[i] && resid[i] > limit && histogram.count[i] >= floor {
                if resid[i] > worst {
                    worst = resid[i]
                    pick = i
                }
            }
            if pick < 0 { break }
            let entry = Entry(lab: histogram.lab[pick], rgb: histogram.rgb[pick])
            absorb(entry.lab, against: placed)
            placed.append(entry.lab)
            entries.append(entry)
        }
        return entries
    }
}

/// Which colour of the palette each colour of the picture is nearest to,
/// worked out the first time a colour comes up.
struct VectorColorIndex {
    private var memo: [UInt8]
    private let labs: [SIMD3<Float>]

    init(palette: VectorPalette) {
        memo = [UInt8](repeating: 255, count: VectorHistogram.size)
        labs = palette.entries.map(\.lab)
    }

    mutating func nearest(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 {
        let key = VectorHistogram.key(r, g, b)
        let known = memo[key]
        if known != 255 { return known }
        let c = VectorHistogram.centre(of: key)
        let lab = VectorColorMath.lab(c.0, c.1, c.2)
        var best = 0
        var bestD = Float.infinity
        for (i, entry) in labs.enumerated() {
            let d = lab - entry
            let dd = (d * d).sum()
            if dd < bestD {
                bestD = dd
                best = i
            }
        }
        memo[key] = UInt8(best)
        return UInt8(best)
    }
}
