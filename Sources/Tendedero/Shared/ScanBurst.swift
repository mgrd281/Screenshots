import Foundation

/// A few photos of one page taken in a moment, merged into one sharper,
/// quieter page: each laid exactly over the sharpest (a shift and a slight
/// turn, found to a fraction of a pixel on the print's edges), those
/// blurred or moved too much left out, and each pixel the mean of the
/// frames' values with the highest and the lowest left out, so a speck of
/// grain or a passing reflection in one frame does not count. Nothing is
/// drawn or guessed: every pixel is a mean of what the camera took. The
/// frames live in memory only and are gone once merged.
enum ScanBurst {
    struct Tuning: Equatable, Sendable {
        /// Frames are laid over each other measured at about this many
        /// pixels on their longer side, then to a fraction of a pixel on the
        /// frames themselves.
        var measuredSide = 360
        /// A frame may lie this share of the longer side away, and turned
        /// this many degrees, at most.
        var reach = 0.04
        var turn = 1.5
        /// The print's edges the frames are laid by: this many of the
        /// steepest, spread over the page.
        var edgePoints = 3000
        /// A frame less sharp than this share of the sharpest is left out.
        var keptSharpness: Float = 0.8
        /// A frame that differs, once laid over, more than this many times
        /// the frames' usual difference is left out: the page moved in it.
        var keptDifference = 1.8
        /// A frame with this share of its pixels brighter than the others',
        /// by four times the grain, holds a reflection and is left out.
        var glareShare = 0.003
    }

    /// Where a frame lies against the sharpest: a pixel of the sharpest at
    /// (x, y) is at this shift from it in the frame, turned about the
    /// middle by `angle` radians; and how far apart the two still are there.
    struct Placement: Equatable, Sendable {
        var dx: Double
        var dy: Double
        var angle: Double
        var difference: Double

        static let none = Placement(dx: 0, dy: 0, angle: 0, difference: 0)
    }

    /// The merged page, the frames it was made of, where each lay and how
    /// sharp each was.
    struct Merged: Sendable {
        let page: ScanBitmap
        let reference: Int
        let used: [Int]
        let placements: [Placement]
        let sharpness: [Float]
    }

    /// The frames merged; nil without frames, or frames of different sizes.
    static func merged(_ frames: [ScanBitmap], tuning: Tuning = .init()) -> Merged? {
        guard let first = frames.first,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return nil }
        let contrast = frames.map { Self.contrast(of: $0) }.max() ?? 0
        let sharpness = frames.map { Self.sharpness(of: $0, against: contrast) }
        let reference = sharpness.indices.max { sharpness[$0] < sharpness[$1] } ?? 0
        guard frames.count > 1 else {
            return Merged(page: first, reference: 0, used: [0], placements: [.none], sharpness: sharpness)
        }
        let planes = frames.map(\.brightness)
        let points = edgePoints(planes[reference], width: first.width, height: first.height, tuning: tuning)
        var placements = [Placement](repeating: .none, count: frames.count)
        for index in frames.indices where index != reference {
            placements[index] = placement(of: planes[index], onto: planes[reference], width: first.width,
                                          height: first.height, points: points, tuning: tuning)
        }
        // Left out: frames much less sharp than the sharpest, and frames the
        // page moved in, which still differ once laid over.
        let differences = frames.indices.filter { $0 != reference }.map { placements[$0].difference }.sorted()
        let usual = differences.isEmpty ? 0 : differences[differences.count / 2]
        let best = sharpness[reference]
        let used = frames.indices.filter { index in
            index == reference || (sharpness[index] >= best * tuning.keptSharpness
                && placements[index].difference <= max(usual, 1) * tuning.keptDifference)
        }
        // The sharpest first: the merge keeps to it. A frame with a reflection
        // the others have not is left out, the sharpest too.
        var laid = [frames[reference]] + used.filter { $0 != reference }.map { warped(frames[$0], by: placements[$0]) }
        var order = [reference] + used.filter { $0 != reference }
        let glare = Self.glare(laid, tuning: tuning)
        if laid.count >= 3, glare.contains(true), glare.filter({ !$0 }).count >= 2 {
            let kept = laid.indices.filter { !glare[$0] }.sorted { sharpness[order[$0]] > sharpness[order[$1]] }
            laid = kept.map { laid[$0] }
            order = kept.map { order[$0] }
        }
        return Merged(page: mean(laid), reference: order[0], used: order.sorted(), placements: placements,
                      sharpness: sharpness)
    }

    /// How sharp a frame's print is: how steeply the brightness turns at its
    /// steepest edges, the steepest two hundredth of them, against
    /// `contrast` (by default the frame's own), across and down apart and the
    /// lesser of the two, as a shake blurs one way only; its grain taken out
    /// first (`ScanQuality.despeckled`) so a grainy frame does not count as
    /// sharp; 0 without print. Frames of one page are measured against one
    /// contrast, as a shaken frame has less of its own.
    static func sharpness(of frame: ScanBitmap, against contrast: Float? = nil) -> Float {
        let w = frame.width, h = frame.height
        guard w > 4, h > 4 else { return 0 }
        let plane = ScanQuality.despeckled(frame.brightness, width: w, height: h)
        let contrast = contrast ?? Self.contrast(of: frame)
        guard contrast >= 20 else { return 0 }
        var across = [Int](repeating: 0, count: 256), down = [Int](repeating: 0, count: 256)
        var total = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let p = y * w + x
                across[abs(Int(plane[p + 1]) - Int(plane[p - 1]))] += 1
                down[abs(Int(plane[p + w]) - Int(plane[p - w]))] += 1
                total += 1
            }
        }
        // The mean of the steepest two hundredth.
        func steepest(_ steps: [Int]) -> Float {
            var left = max(1, total / 200), sum = 0, n = 0
            for step in stride(from: 255, through: 0, by: -1) where left > 0 {
                let take = min(left, steps[step])
                sum += take * step
                n += take
                left -= take
            }
            return n > 0 ? Float(sum) / Float(n) / 2 / contrast : 0
        }
        return min(steepest(across), steepest(down))
    }

    /// How far apart a frame's dark and light are: its 5th and 95th
    /// percentile of brightness.
    static func contrast(of frame: ScanBitmap) -> Float {
        let plane = frame.brightness
        var counts = [Int](repeating: 0, count: 256)
        for value in plane { counts[Int(value)] += 1 }
        func level(_ share: Double) -> Float {
            let wanted = Int(Double(plane.count) * share)
            var seen = 0
            for value in 0..<256 {
                seen += counts[value]
                if seen > wanted { return Float(value) }
            }
            return 255
        }
        return level(0.95) - level(0.05)
    }

    // MARK: Laying frames over each other

    /// The print's steepest edges on the sharpest frame, spread over it: in
    /// each of a grid of cells, its steepest points.
    static func edgePoints(_ plane: [UInt8], width w: Int, height h: Int, tuning: Tuning) -> [(x: Int, y: Int)] {
        guard w > 8, h > 8 else { return [] }
        let cells = 16, perCell = max(1, tuning.edgePoints / (cells * cells))
        var points: [(x: Int, y: Int)] = []
        for cy in 0..<cells {
            for cx in 0..<cells {
                let x0 = max(2, cx * w / cells), x1 = min(w - 2, (cx + 1) * w / cells)
                let y0 = max(2, cy * h / cells), y1 = min(h - 2, (cy + 1) * h / cells)
                guard x1 > x0, y1 > y0 else { continue }
                var found: [(steep: Int, x: Int, y: Int)] = []
                let step = max(1, min(x1 - x0, y1 - y0) / 48)
                for y in stride(from: y0, to: y1, by: step) {
                    for x in stride(from: x0, to: x1, by: step) {
                        let across = abs(Int(plane[y * w + x + 1]) - Int(plane[y * w + x - 1]))
                        let down = abs(Int(plane[(y + 1) * w + x]) - Int(plane[(y - 1) * w + x]))
                        let steep = across + down
                        guard steep >= 24 else { continue }
                        found.append((steep, x, y))
                    }
                }
                found.sort { $0.steep > $1.steep }
                points += found.prefix(perCell).map { ($0.x, $0.y) }
            }
        }
        return points
    }

    /// Where `plane` lies against `reference`: first by trying every shift
    /// and turn within reach on both made small, then step by step on the
    /// frames themselves down to a twentieth of a pixel.
    static func placement(of plane: [UInt8], onto reference: [UInt8], width w: Int, height h: Int,
                          points: [(x: Int, y: Int)], tuning: Tuning) -> Placement {
        guard !points.isEmpty else { return .none }
        let factor = max(1, max(w, h) / max(1, tuning.measuredSide))
        let (small, sw, sh) = ScanQuality.shrunk(plane, width: w, height: h, by: factor)
        let (smallReference, _, _) = ScanQuality.shrunk(reference, width: w, height: h, by: factor)
        let smallPoints = edgePoints(smallReference, width: sw, height: sh, tuning: tuning)
        let reach = Int((tuning.reach * Double(max(sw, sh))).rounded(.up))
        var best = Placement(dx: 0, dy: 0, angle: 0, difference: .infinity)
        let turn = tuning.turn * .pi / 180
        let turns = stride(from: -turn, through: turn + 1e-9, by: max(turn / 6, 1e-6))
        for angle in turns {
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let trial = Placement(dx: Double(dx), dy: Double(dy), angle: angle, difference: 0)
                    let difference = Self.difference(small, smallReference, width: sw, height: sh,
                                                     points: smallPoints, placement: trial)
                    if difference < best.difference {
                        best = trial
                        best.difference = difference
                    }
                }
            }
        }
        // On the frames themselves, from the small frames' best.
        var placement = Placement(dx: best.dx * Double(factor), dy: best.dy * Double(factor), angle: best.angle,
                                  difference: 0)
        placement.difference = difference(plane, reference, width: w, height: h, points: points, placement: placement)
        var step = Double(factor) / 2
        var turnStep = turn / 12
        while step >= 0.05 {
            var improved = true
            while improved {
                improved = false
                for (ddx, ddy, dangle) in [(step, 0.0, 0.0), (-step, 0, 0), (0, step, 0), (0, -step, 0),
                                           (0, 0, turnStep), (0, 0, -turnStep)] {
                    var trial = placement
                    trial.dx += ddx
                    trial.dy += ddy
                    trial.angle += dangle
                    trial.difference = difference(plane, reference, width: w, height: h, points: points, placement: trial)
                    if trial.difference < placement.difference {
                        placement = trial
                        improved = true
                    }
                }
            }
            step /= 2
            turnStep /= 2
        }
        return placement
    }

    /// How far apart the two are at the reference's edge points, the frame
    /// laid as `placement` says: the root mean square of the difference.
    static func difference(_ plane: [UInt8], _ reference: [UInt8], width w: Int, height h: Int,
                           points: [(x: Int, y: Int)], placement: Placement) -> Double {
        let cx = Double(w) / 2, cy = Double(h) / 2
        let cosine = cos(placement.angle), sine = sin(placement.angle)
        var sum = 0.0
        var count = 0
        for point in points {
            let x = Double(point.x) - cx, y = Double(point.y) - cy
            let fx = cx + cosine * x - sine * y + placement.dx
            let fy = cy + sine * x + cosine * y + placement.dy
            guard let value = sampled(plane, width: w, height: h, x: fx, y: fy) else { continue }
            let gap = value - Double(reference[point.y * w + point.x])
            sum += gap * gap
            count += 1
        }
        // A frame laid so that most points fall outside it says nothing.
        guard count >= max(8, points.count / 2) else { return .infinity }
        return (sum / Double(count)).squareRoot()
    }

    /// A plane's value between its pixels, nil outside it.
    @inline(__always)
    static func sampled(_ plane: [UInt8], width w: Int, height h: Int, x: Double, y: Double) -> Double? {
        guard x >= 0, y >= 0, x <= Double(w - 1), y <= Double(h - 1) else { return nil }
        let x0 = min(w - 2, Int(x)), y0 = min(h - 2, Int(y))
        let tx = x - Double(x0), ty = y - Double(y0)
        let a = Double(plane[y0 * w + x0]), b = Double(plane[y0 * w + x0 + 1])
        let c = Double(plane[(y0 + 1) * w + x0]), d = Double(plane[(y0 + 1) * w + x0 + 1])
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    /// The frame laid over the sharpest, as `placement` says, each pixel
    /// taken between its sixteen nearest with a cubic curve, which keeps a
    /// stroke's edge as steep as it was; where it does not reach, the
    /// nearest of its own pixels.
    static func warped(_ frame: ScanBitmap, by placement: Placement) -> ScanBitmap {
        let w = frame.width, h = frame.height
        let cx = Double(w) / 2, cy = Double(h) / 2
        let cosine = cos(placement.angle), sine = sin(placement.angle)
        var out = frame
        frame.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                // Bands of rows side by side, each on its own core.
                let bands = Self.bands(h)
                DispatchQueue.concurrentPerform(iterations: bands) { band in
                    var wx = [Double](repeating: 0, count: 4), wy = [Double](repeating: 0, count: 4)
                    for y in (band * h / bands)..<((band + 1) * h / bands) {
                        let ry = Double(y) - cy
                        for x in 0..<w {
                            let rx = Double(x) - cx
                            let fx = min(Double(w - 1), max(0, cx + cosine * rx - sine * ry + placement.dx))
                            let fy = min(Double(h - 1), max(0, cy + sine * rx + cosine * ry + placement.dy))
                            let x0 = Int(fx), y0 = Int(fy)
                            Self.weights(fx - Double(x0), into: &wx)
                            Self.weights(fy - Double(y0), into: &wy)
                            let o = (y * w + x) * 4
                            for c in 0..<3 {
                                var value = 0.0
                                for j in 0..<4 {
                                    let yy = min(h - 1, max(0, y0 + j - 1))
                                    var row = 0.0
                                    for i in 0..<4 {
                                        let xx = min(w - 1, max(0, x0 + i - 1))
                                        row += Double(src[(yy * w + xx) * 4 + c]) * wx[i]
                                    }
                                    value += row * wy[j]
                                }
                                dst[o + c] = UInt8(min(255, max(0, value.rounded())))
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    /// How many bands of rows a page is worked in, side by side.
    static func bands(_ height: Int) -> Int {
        max(1, min(height, ProcessInfo.processInfo.activeProcessorCount * 4))
    }

    /// The four weights of a cubic curve (Keys, a = −0.5) for a point `t`
    /// of the way between the second and the third pixel.
    @inline(__always)
    static func weights(_ t: Double, into weights: inout [Double]) {
        let t2 = t * t, t3 = t2 * t
        weights[0] = -0.5 * t3 + t2 - 0.5 * t
        weights[1] = 1.5 * t3 - 2.5 * t2 + 1
        weights[2] = -1.5 * t3 + 2 * t2 + 0.5 * t
        weights[3] = 0.5 * t3 - 0.5 * t2
    }

    // MARK: Merging

    /// The frames, laid over each other, merged, the sharpest first: each
    /// pixel the mean of the values within `spread` times the grain of an
    /// anchor, so the grain is averaged away and a value far from it does
    /// not count. On the print's edges the anchor is the sharpest frame's
    /// own value, so an edge another frame misses by a fraction of a pixel
    /// keeps its steepness; elsewhere it is the middle of all the frames
    /// (of two, the sharpest's), so a reflection or a speck in any one frame,
    /// the sharpest too, is left out.
    static func mean(_ frames: [ScanBitmap], spread: Double = 2.5) -> ScanBitmap {
        guard var out = frames.first, frames.count > 1 else { return frames.first! }
        let grain = Self.grain(frames)
        let near = max(2, spread * grain), closest = max(1, grain), edge = Int(max(12, 6 * grain))
        let w = out.width, h = out.height
        let plane = frames[0].brightness
        let count = frames.count
        let sources = frames.map(\.pixels)
        out.pixels.withUnsafeMutableBufferPointer { dst in
            let bands = Self.bands(h)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                var values = [Double](repeating: 0, count: count)
                var all = values
                for y in (band * h / bands)..<((band + 1) * h / bands) {
                    for x in 0..<w {
                        let p = y * w + x
                        var onEdge = false
                        if x > 0, x < w - 1, y > 0, y < h - 1 {
                            let across = abs(Int(plane[p + 1]) - Int(plane[p - 1]))
                            let down = abs(Int(plane[p + w]) - Int(plane[p - w]))
                            onEdge = across + down >= edge
                        }
                        for c in 0..<3 {
                            let i = p * 4 + c
                            for n in 0..<count { values[n] = Double(sources[n][i]) }
                            let anchor: Double
                            if onEdge || count < 3 {
                                anchor = values[0]
                            } else {
                                all = values
                                all.sort()
                                anchor = count % 2 == 1 ? all[count / 2] : (all[count / 2 - 1] + all[count / 2]) / 2
                            }
                            // On an edge, only values very close to the sharpest frame's.
                            let reach = onEdge ? closest : near
                            var sum = 0.0, kept = 0.0
                            for value in values where abs(value - anchor) <= reach {
                                sum += value
                                kept += 1
                            }
                            dst[i] = UInt8(min(255, max(0, (kept > 0 ? sum / kept : anchor).rounded())))
                        }
                    }
                }
            }
        }
        return out
    }

    /// Which of the frames, laid over each other, holds a reflection the
    /// others have not: more than `glareShare` of its pixels brighter than
    /// the middle of all the frames by four times the grain and more.
    static func glare(_ frames: [ScanBitmap], tuning: Tuning = .init()) -> [Bool] {
        guard frames.count >= 3, let first = frames.first else { return frames.map { _ in false } }
        let grain = Self.grain(frames)
        let above = max(12.0, 4 * grain)
        let planes = frames.map(\.brightness)
        let step = max(1, first.width * first.height / 250_000)
        var brighter = [Int](repeating: 0, count: frames.count)
        var total = 0
        var values = [Int](repeating: 0, count: frames.count)
        for p in stride(from: 0, to: first.width * first.height, by: step) {
            for n in frames.indices { values[n] = Int(planes[n][p]) }
            let sorted = values.sorted()
            let middle = Double(sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
            for n in frames.indices where Double(values[n]) - middle > above { brighter[n] += 1 }
            total += 1
        }
        return brighter.map { Double($0) / Double(max(1, total)) > tuning.glareShare }
    }

    /// The camera's grain, as the frames differ from the first where they
    /// are laid over each other: the middle of the differences, as a
    /// standard deviation of one frame's grain.
    static func grain(_ frames: [ScanBitmap]) -> Double {
        guard let first = frames.first, frames.count > 1 else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        var total = 0
        let step = max(1, first.pixels.count / 4 / 200_000)
        for frame in frames.dropFirst() {
            for p in stride(from: 0, to: first.width * first.height, by: step) {
                let i = p * 4 + 1
                counts[abs(Int(frame.pixels[i]) - Int(first.pixels[i]))] += 1
                total += 1
            }
        }
        var seen = 0, median = 0
        for gap in 0..<256 {
            seen += counts[gap]
            if seen * 2 >= total { median = gap; break }
        }
        // The middle of the absolute difference of two frames, each with grain of the same spread.
        return Double(median) * 1.4826 / 2.0.squareRoot()
    }
}
