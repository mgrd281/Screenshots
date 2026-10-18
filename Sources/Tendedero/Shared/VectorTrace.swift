import Foundation

/// How a picture is turned into shapes.
struct VectorSettings: Equatable {
    /// The most colours it may be drawn in, up to 64.
    var colors = 24
    /// Colours nearer than this (in Lab, where one is the least a person sees) are one.
    var merge = 2.5
    /// From 0, which follows every pixel closely, to 1, which smooths the most.
    var smoothness = 0.25
    /// Patches smaller than this many pixels are left out.
    var speckle = 3
    /// Evens out a gradient before it is cut into bands, so the bands are smooth.
    var smoothsGradients = true
    /// Only the dark ink, as one colour, with nothing behind it.
    var blackAndWhite = false
    /// Leaves out the colour behind everything else.
    var transparentBackground = false

    /// How far an edge may stray from the pixels it covers, and a curve from the ones it follows.
    var polygonTolerance: Double { 0.35 + 0.30 * min(max(smoothness, 0), 1) }
    var curveTolerance: Double { 0.20 + 0.20 * min(max(smoothness, 0), 1) }
}

/// The ready-made settings people choose from.
enum VectorPreset: String, CaseIterable, Identifiable {
    case screenshot, logo, illustration, photo, blackAndWhite

    var id: String { rawValue }

    var settings: VectorSettings {
        var s = VectorSettings()
        switch self {
        case .screenshot:
            s.colors = 24
            s.merge = 2.0
        case .logo:
            s.colors = 16
            s.merge = 4.0
            s.smoothness = 0.35
        case .illustration:
            s.colors = 40
            s.merge = 1.5
            s.smoothness = 0.35
        case .photo:
            s.colors = 64
            s.merge = 1.0
            s.smoothness = 0.5
            s.speckle = 8
        case .blackAndWhite:
            s.colors = 2
            s.merge = 0
            s.smoothness = 0.3
            s.blackAndWhite = true
            s.transparentBackground = true
        }
        return s
    }
}

/// Turns a picture into shapes: it finds the colours the picture is drawn in,
/// says which colour every pixel is, and follows the edge of each colour with
/// lines and curves, the edge placed between pixels by how much of each colour
/// a pixel has.
enum VectorTracer {
    /// The most pixels it traces; a larger picture has to be made smaller first.
    static let maximumPixels = 12_000_000

    /// - Returns: nil for a picture it cannot trace, or when `isCancelled`
    ///   turns true.
    static func trace(_ source: VectorPixels, settings: VectorSettings, isCancelled: () -> Bool = { false }) -> VectorImage? {
        let w = source.width, h = source.height
        let count = w * h
        guard w > 0, h > 0, count <= maximumPixels, source.rgba.count == count * 4 else { return nil }
        var pixels = source

        // Pixels at least half opaque are the picture; a picture that is hardly ever
        // wholly opaque (a faint watermark) is read as opaque where it is half so.
        var opaque = 0, whole = 0, visible = 0
        for i in 0..<count {
            let a = pixels.rgba[i * 4 + 3]
            if a >= 128 { opaque += 1 }
            if a == 255 { whole += 1 }
            if a > 0 { visible += 1 }
        }
        if visible == 0 { return VectorImage(width: w, height: h, layers: []) }
        if whole * 20 < visible {
            for i in 0..<count { pixels.rgba[i * 4 + 3] = pixels.rgba[i * 4 + 3] >= 128 ? 255 : 0 }
            whole = opaque
        }
        let allOpaque = whole == count
        if isCancelled() { return nil }

        // The colours.
        let analysis = VectorAnalysis.analyse(pixels)
        let photo = settings.blackAndWhite || analysis.solidCount * 50 < opaque
        let histogram = VectorHistogram(pixels: pixels, analysis: analysis)
        let palette = VectorPalette.choose(from: histogram, maximum: min(max(settings.colors, 1), 64),
                                           merge: Float(settings.merge), total: opaque, photo: photo)
        guard palette.count > 0 else { return VectorImage(width: w, height: h, layers: []) }
        if isCancelled() { return nil }

        // Which colour each pixel is.
        var index = VectorColorIndex(palette: palette)
        let smoothed = settings.smoothsGradients && !settings.blackAndWhite
            ? VectorTracer.evenedOut(pixels, radius: count > 3_000_000 ? 1 : 2) : nil
        let seen = smoothed ?? pixels.rgba
        var labelAll = [UInt8](repeating: 255, count: count)
        for i in 0..<count where pixels.rgba[i * 4 + 3] != 0 {
            labelAll[i] = index.nearest(seen[i * 4], seen[i * 4 + 1], seen[i * 4 + 2])
        }
        var label = labelAll
        for i in 0..<count where pixels.rgba[i * 4 + 3] < 128 { label[i] = 255 }

        var colors = VectorTracer.colors(pixels, analysis: analysis, labels: label, palette: palette)
        var pairA = [UInt8](repeating: 255, count: count)
        var pairB = [UInt8](repeating: 255, count: count)
        var coverage = [UInt8](repeating: 0, count: count)
        if !photo {
            VectorTracer.resolveBlends(pixels, analysis: analysis, global: labelAll, colors: colors,
                                       labels: &label, pairA: &pairA, pairB: &pairB, coverage: &coverage)
        }
        if isCancelled() { return nil }
        let beforeSpecks = label
        VectorCleanup.removeSpecks(&label, width: w, height: h, minimum: settings.speckle)
        for i in 0..<count where label[i] != beforeSpecks[i] {
            pairA[i] = 255
            pairB[i] = 255
        }
        colors = VectorTracer.colors(pixels, analysis: analysis, labels: label, palette: palette)

        // From the biggest patch of colour to the smallest, which is how they are laid over each other.
        var area = [Int](repeating: 0, count: 256)
        for l in label { area[Int(l)] += 1 }
        var order = (0..<palette.count).filter { area[$0] > 0 }
        order.sort { area[$0] != area[$1] ? area[$0] > area[$1] : $0 < $1 }
        var rank = [Int8](repeating: -1, count: 256)
        for (r, l) in order.enumerated() { rank[l] = Int8(r) }
        var ranked = [Int8](repeating: -1, count: count)
        var rankedAll = [Int8](repeating: -1, count: count)
        for i in 0..<count {
            ranked[i] = rank[Int(label[i])]
            rankedAll[i] = rank[Int(labelAll[i])]
        }
        // Where each colour lies.
        var minX = [Int](repeating: Int.max, count: order.count), maxX = [Int](repeating: -1, count: order.count)
        var minY = [Int](repeating: Int.max, count: order.count), maxY = [Int](repeating: -1, count: order.count)
        for y in 0..<h {
            for x in 0..<w {
                let r = Int(ranked[y * w + x])
                if r < 0 { continue }
                minX[r] = min(minX[r], x)
                maxX[r] = max(maxX[r], x)
                minY[r] = min(minY[r], y)
                maxY[r] = max(maxY[r], y)
            }
        }

        var layers: [VectorLayer] = []
        var squares = VectorMarchingSquares()
        // Black and white keeps only the darker of the two colours.
        var ink: Int?
        if settings.blackAndWhite {
            ink = order.min { palette.entries[$0].lab.x < palette.entries[$1].lab.x }
        }
        for (r, l) in order.enumerated() {
            if isCancelled() { return nil }
            let color = VectorColor(red: UInt8(min(max(colors[l].x.rounded(), 0), 255)),
                                    green: UInt8(min(max(colors[l].y.rounded(), 0), 255)),
                                    blue: UInt8(min(max(colors[l].z.rounded(), 0), 255)))
            if let ink, l != ink { continue }
            if r == 0 && allOpaque && ink == nil {
                if !settings.transparentBackground { layers.append(VectorLayer(color: color, contours: [], fillsPicture: true)) }
                continue
            }
            // The field: whole where the colour lies, and under whatever is laid over it
            // right beside it, so the two never leave a gap; part where a pixel has only
            // some of it.
            let ox = minX[r] - 2, oy = minY[r] - 2
            let fw = maxX[r] - minX[r] + 5, fh = maxY[r] - minY[r] + 5
            var field = [Float](repeating: 0, count: fw * fh)
            let rr = Int8(r)
            for fy in 0..<fh {
                let y = oy + fy
                if y < 0 || y >= h { continue }
                for fx in 0..<fw {
                    let x = ox + fx
                    if x < 0 || x >= w { continue }
                    let p = y * w + x
                    let o = ranked[p]
                    let own = o == rr
                    var beside = false
                    if x > 0 && ranked[p - 1] == rr { beside = true }
                    else if x < w - 1 && ranked[p + 1] == rr { beside = true }
                    else if y > 0 && ranked[p - w] == rr { beside = true }
                    else if y < h - 1 && ranked[p + w] == rr { beside = true }
                    var value: Float = (own || (o > rr && beside)) ? 1 : 0
                    let alpha = pixels.rgba[p * 4 + 3]
                    if alpha > 0 && alpha < 255 && (beside || own || rankedAll[p] == rr) {
                        let k = rankedAll[p]
                        value = (k == rr || (k > rr && beside)) ? Float(alpha) / 255 : 0
                    }
                    if pairA[p] != 255 && (beside || own) {
                        let ra = rank[Int(pairA[p])], rb = rank[Int(pairB[p])]
                        let share = Float(coverage[p]) / 255
                        var sum: Float = 0
                        if ra == rr || (ra > rr && beside) { sum += 1 - share }
                        if rb == rr || (rb > rr && beside) { sum += share }
                        value = min(max(sum, 0), 1)
                    }
                    field[fy * fw + fx] = value
                }
            }
            var contours: [VectorContour] = []
            let loops = squares.loops(of: field, width: fw, height: fh, originX: Double(ox) + 0.5, originY: Double(oy) + 0.5)
            for loop in loops {
                if loop.count < 4 { continue }
                var twice = 0.0
                for i in 0..<loop.count {
                    let a = loop[i], b = loop[(i + 1) % loop.count]
                    twice += a.x * b.y - b.x * a.y
                }
                if abs(twice) < 3 { continue }
                if let contour = VectorFit.contour(loop, polygon: settings.polygonTolerance, tolerance: settings.curveTolerance) {
                    contours.append(contour)
                }
            }
            if !contours.isEmpty { layers.append(VectorLayer(color: color, contours: contours)) }
        }
        return VectorImage(width: w, height: h, layers: layers)
    }

    // MARK: Colours

    /// The colour each palette colour is shown as: the mean of the pixels that
    /// hold it, taken from the solid ones, which are not blends.
    private static func colors(_ pixels: VectorPixels, analysis: VectorAnalysis.Result, labels: [UInt8],
                               palette: VectorPalette) -> [SIMD3<Float>] {
        var solid = [SIMD3<Float>](repeating: .zero, count: 256), solidCount = [Float](repeating: 0, count: 256)
        var all = [SIMD3<Float>](repeating: .zero, count: 256), allCount = [Float](repeating: 0, count: 256)
        for i in 0..<(pixels.width * pixels.height) {
            let l = Int(labels[i])
            if l == 255 || pixels.rgba[i * 4 + 3] < 128 { continue }
            let c = SIMD3<Float>(Float(pixels.rgba[i * 4]), Float(pixels.rgba[i * 4 + 1]), Float(pixels.rgba[i * 4 + 2]))
            all[l] += c
            allCount[l] += 1
            if analysis.solid[i] != 0 {
                solid[l] += c
                solidCount[l] += 1
            }
        }
        return (0..<palette.count).map { l in
            if solidCount[l] > 0 { return solid[l] / solidCount[l] }
            if allCount[l] > 0 { return all[l] / allCount[l] }
            return palette.entries[l].rgb
        }
    }

    /// The picture with each pixel made the mean of the pixels about it that are
    /// close in colour, which takes out noise and the dither of a gradient and
    /// leaves every edge as it is.
    private static func evenedOut(_ pixels: VectorPixels, radius: Int) -> [UInt8] {
        let w = pixels.width, h = pixels.height
        var out = pixels.rgba
        pixels.rgba.withUnsafeBufferPointer { px in
            out.withUnsafeMutableBufferPointer { result in
                for y in 0..<h {
                    for x in 0..<w {
                        let i = (y * w + x) * 4
                        if px[i + 3] < 128 { continue }
                        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                        var sr = 0, sg = 0, sb = 0, n = 0
                        for yn in max(y - radius, 0)...min(y + radius, h - 1) {
                            for xn in max(x - radius, 0)...min(x + radius, w - 1) {
                                let j = (yn * w + xn) * 4
                                let nr = Int(px[j]), ng = Int(px[j + 1]), nb = Int(px[j + 2])
                                if abs(nr - r) <= 20 && abs(ng - g) <= 20 && abs(nb - b) <= 20 {
                                    sr += nr
                                    sg += ng
                                    sb += nb
                                    n += 1
                                }
                            }
                        }
                        result[i] = UInt8((sr + n / 2) / n)
                        result[i + 1] = UInt8((sg + n / 2) / n)
                        result[i + 2] = UInt8((sb + n / 2) / n)
                    }
                }
            }
        }
        return out
    }

    /// A pixel that is not solid lies between colours: it is a blend of two, and
    /// goes to the one it has more of. The two are the commonest colours about it,
    /// or one of them and the colour it is nearest to, if that fits it much better.
    /// How much of the second it has is kept, to place the edge between pixels.
    private static func resolveBlends(_ pixels: VectorPixels, analysis: VectorAnalysis.Result, global: [UInt8],
                                      colors: [SIMD3<Float>], labels: inout [UInt8],
                                      pairA: inout [UInt8], pairB: inout [UInt8], coverage: inout [UInt8]) {
        let w = pixels.width, h = pixels.height
        let bias: Float = 6
        var seen = [UInt8](repeating: 0, count: 25)
        var seenCount = [Int](repeating: 0, count: 25)
        func fit(_ p: SIMD3<Float>, _ a: Int, _ b: Int) -> (distance: Float, share: Float) {
            let from = colors[a], to = colors[b]
            let d = to - from
            let den = (d * d).sum()
            var t: Float = 0
            if den > 1e-9 { t = min(max(((p - from) * d).sum() / den, 0), 1) }
            let e = p - (from + d * t)
            return ((e * e).sum().squareRoot(), t)
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                // A pixel that is only partly opaque has its edge from its opacity, not from a blend.
                if pixels.rgba[i * 4 + 3] != 255 || analysis.solid[i] != 0 { continue }
                // The colours of the solid pixels within two steps.
                var distinct = 0
                for yn in max(y - 2, 0)...min(y + 2, h - 1) {
                    for xn in max(x - 2, 0)...min(x + 2, w - 1) {
                        let j = yn * w + xn
                        if analysis.solid[j] == 0 { continue }
                        let l = global[j]
                        var found = false
                        for s in 0..<distinct where seen[s] == l {
                            seenCount[s] += 1
                            found = true
                            break
                        }
                        if !found {
                            seen[distinct] = l
                            seenCount[distinct] = 1
                            distinct += 1
                        }
                    }
                }
                if distinct == 0 { continue }
                // The commonest and the next; the lower colour wins a tie.
                var first = 0
                for s in 1..<max(distinct, 1) where seenCount[s] > seenCount[first] || (seenCount[s] == seenCount[first] && seen[s] < seen[first]) {
                    first = s
                }
                var second = -1
                for s in 0..<distinct where s != first {
                    if second < 0 || seenCount[s] > seenCount[second] || (seenCount[s] == seenCount[second] && seen[s] < seen[second]) {
                        second = s
                    }
                }
                let g = Int(global[i])
                let a = Int(seen[first])
                let b = second >= 0 ? Int(seen[second]) : g
                let p = SIMD3<Float>(Float(pixels.rgba[i * 4]), Float(pixels.rgba[i * 4 + 1]), Float(pixels.rgba[i * 4 + 2]))
                let local = fit(p, a, b)
                let withA = fit(p, a, g)
                let withB = fit(p, b, g)
                var chosenA = a, chosenB = b, share = local.share
                if withA.distance + bias < local.distance && withA.distance <= withB.distance {
                    chosenA = a
                    chosenB = g
                    share = withA.share
                } else if withB.distance + bias < local.distance && withB.distance < withA.distance {
                    chosenA = b
                    chosenB = g
                    share = withB.share
                }
                labels[i] = UInt8(share > 0.5 ? chosenB : chosenA)
                pairA[i] = UInt8(chosenA)
                pairB[i] = UInt8(chosenB)
                coverage[i] = UInt8((share * 255).rounded())
            }
        }
    }
}

// MARK: Specks

enum VectorCleanup {
    /// Gives each patch of fewer than `minimum` pixels the colour that borders it most.
    static func removeSpecks(_ labels: inout [UInt8], width w: Int, height h: Int, minimum: Int) {
        guard minimum > 1 else { return }
        let count = w * h
        var parent = [Int32](repeating: 0, count: count)
        for i in 0..<count { parent[i] = Int32(i) }
        func find(_ i: Int) -> Int {
            var x = i
            while Int(parent[x]) != x {
                parent[x] = parent[Int(parent[x])]
                x = Int(parent[x])
            }
            return x
        }
        func join(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = Int32(min(ra, rb)) }
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if x > 0 && labels[i] == labels[i - 1] { join(i, i - 1) }
                if y > 0 && labels[i] == labels[i - w] { join(i, i - w) }
            }
        }
        var size = [Int32](repeating: 0, count: count)
        for i in 0..<count { size[find(i)] += 1 }
        var border: [Int: Int] = [:]
        var anySmall = false
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let root = find(i)
                if Int(size[root]) >= minimum { continue }
                anySmall = true
                func touch(_ j: Int) {
                    if labels[j] != labels[i] { border[root * 256 + Int(labels[j]), default: 0] += 1 }
                }
                if x > 0 { touch(i - 1) }
                if x < w - 1 { touch(i + 1) }
                if y > 0 { touch(i - w) }
                if y < h - 1 { touch(i + w) }
            }
        }
        guard anySmall else { return }
        var target: [Int: (label: Int, count: Int)] = [:]
        for (key, n) in border {
            let root = key / 256, l = key % 256
            if let known = target[root], known.count > n || (known.count == n && known.label < l) { continue }
            target[root] = (l, n)
        }
        var result = labels
        for i in 0..<count {
            let root = find(i)
            if Int(size[root]) < minimum, let to = target[root] { result[i] = UInt8(to.label) }
        }
        labels = result
    }
}
