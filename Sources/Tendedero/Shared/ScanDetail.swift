import Foundation

/// Small print taken again close up, laid onto its page: the close-up found
/// on the page (how much larger it is, how it is turned and where it lies,
/// to a fraction of the page's pixel), brought to the page's light, and
/// drawn into the place of the small print with a soft edge, so the page
/// keeps its size and its covers their places. Nothing is drawn or guessed:
/// every pixel laid is the close-up's own, made smaller. Whether it is kept
/// is decided by the reading (`better`): only where the small print reads
/// more surely than before.
enum ScanDetail {
    struct Tuning: Equatable, Sendable {
        /// The close-up is this many to this many times as large as the page.
        var leastScale = 1.2
        var mostScale = 4.0
        /// Sizes tried in between, each this many times the one before.
        var scaleStep = 1.08
        /// Turns tried first, in degrees, before they are found exactly.
        var turns: [Double] = [-3, -1.5, 0, 1.5, 3]
        /// The small print's longer side at the first search, in pixels.
        var firstSide = 64.0
        /// The second search, closer.
        var secondSide = 256.0
        /// The print's edges the close-up is laid by, at most.
        var points = 1500
        /// It is laid only where it matches the page this well, from 0 to 1.
        var leastMatch = 0.6
        /// Its edge fades into the page over this many of the page's pixels.
        var blend = 12.0
    }

    /// Where a pixel of the page at (x, y) falls in the close-up: `scale`
    /// times as far from the small print's middle, turned by `angle`
    /// radians, from (`dx`, `dy`), where the middle falls; and how well the
    /// two match there, from −1 to 1.
    struct Placement: Equatable, Sendable {
        var scale: Double
        var angle: Double
        var dx: Double
        var dy: Double
        var match: Double

        /// The close-up's point for a point of the page, `centre` the small print's middle.
        @inline(__always)
        func detailPoint(_ x: Double, _ y: Double, centre: (x: Double, y: Double)) -> (x: Double, y: Double) {
            let rx = x - centre.x, ry = y - centre.y
            let c = cos(angle) * scale, s = sin(angle) * scale
            return (c * rx - s * ry + dx, s * rx + c * ry + dy)
        }
    }

    /// A plane of brightness made smaller by `factor`, a pixel's own mean
    /// over the pixels it covers.
    struct Plane {
        let values: [Float]
        let width: Int
        let height: Int
        /// How many of the original's pixels one of its pixels is wide.
        let factor: Double

        /// `plane` made `factor` times smaller; `already` says how many
        /// times smaller it is than the original it stands for.
        init(_ plane: [UInt8], width w: Int, height h: Int, factor: Double, already: Int = 1) {
            // An integer part first, then what is left.
            let whole = max(1, Int(factor / 1.5))
            let (base, bw, bh) = ScanQuality.shrunk(plane, width: w, height: h, by: whole)
            let rest = factor / Double(whole)
            let width = max(1, Int(Double(bw) / rest)), height = max(1, Int(Double(bh) / rest))
            var values = [Float](repeating: 0, count: width * height)
            for y in 0..<height {
                let y0 = min(bh - 1, Int(Double(y) * rest)), y1 = min(bh, max(y0 + 1, Int(Double(y + 1) * rest)))
                for x in 0..<width {
                    let x0 = min(bw - 1, Int(Double(x) * rest)), x1 = min(bw, max(x0 + 1, Int(Double(x + 1) * rest)))
                    var sum = 0
                    for yy in y0..<y1 {
                        for xx in x0..<x1 { sum += Int(base[yy * bw + xx]) }
                    }
                    values[y * width + x] = Float(sum) / Float((y1 - y0) * (x1 - x0))
                }
            }
            self.values = values
            self.width = width
            self.height = height
            self.factor = Double(w) / Double(width) * Double(already)
        }

        /// Its value at a point of the original, nil outside it.
        @inline(__always)
        func value(at x: Double, _ y: Double) -> Float? {
            let fx = (x + 0.5) / factor - 0.5, fy = (y + 0.5) / factor - 0.5
            guard fx >= 0, fy >= 0, fx <= Double(width - 1), fy <= Double(height - 1) else { return nil }
            let x0 = min(width - 2, Int(fx)), y0 = min(height - 2, Int(fy))
            guard x0 >= 0, y0 >= 0 else { return values[0] }
            let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
            let a = values[y0 * width + x0], b = values[y0 * width + x0 + 1]
            let c = values[(y0 + 1) * width + x0], d = values[(y0 + 1) * width + x0 + 1]
            return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        }
    }

    // MARK: Finding the close-up on the page

    /// Where the close-up lies on the page, around `area`, the small print,
    /// in the page's pixels from the top left; nil where it matches nowhere well.
    static func placement(of detail: [UInt8], width dw: Int, height dh: Int, onto page: [UInt8], width pw: Int,
                          height ph: Int, around area: CGRect, tuning: Tuning = .init()) -> Placement? {
        let area = area.intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
        guard !area.isNull, area.width >= 8, area.height >= 8, dw > 16, dh > 16 else { return nil }
        let centre = (x: Double(area.midX), y: Double(area.midY))
        let side = Double(max(area.width, area.height))
        // First every size, turn and place, both made small.
        let firstFactor = max(1, side / tuning.firstSide)
        let firstPage = Plane(page, width: pw, height: ph, factor: firstFactor)
        let firstPoints = Self.points(firstPage, in: area, count: 200)
        guard firstPoints.count >= 20 else { return nil }
        var found: [Placement] = []
        // The close-up made smaller once for all the sizes tried.
        let once = max(1, Int(firstFactor * tuning.leastScale / 2))
        let (base, bw, bh) = ScanQuality.shrunk(detail, width: dw, height: dh, by: once)
        var scale = tuning.leastScale
        while scale <= tuning.mostScale * 1.0001 {
            let small = Plane(base, width: bw, height: bh, factor: firstFactor * scale / Double(once), already: once)
            for degrees in tuning.turns {
                var best = Placement(scale: scale, angle: degrees * .pi / 180, dx: 0, dy: 0, match: -2)
                for qy in 0..<small.height {
                    for qx in 0..<small.width {
                        var trial = best
                        trial.dx = (Double(qx) + 0.5) * small.factor - 0.5
                        trial.dy = (Double(qy) + 0.5) * small.factor - 0.5
                        trial.match = match(firstPoints, on: firstPage, in: small, placement: trial, centre: centre)
                        if trial.match > best.match { best = trial }
                    }
                }
                found.append(best)
            }
            scale *= tuning.scaleStep
        }
        // Then the best few closer, and the best of them on the page itself.
        let secondFactor = max(1, side / tuning.secondSide)
        let secondPage = Plane(page, width: pw, height: ph, factor: secondFactor)
        let secondPoints = Self.points(secondPage, in: area, count: 600)
        var refined: [Placement] = []
        for candidate in found.sorted(by: { $0.match > $1.match }).prefix(4) {
            let small = Plane(detail, width: dw, height: dh, factor: secondFactor * candidate.scale)
            refined.append(refine(candidate, points: secondPoints, page: secondPage, detail: small, centre: centre,
                                  step: small.factor, until: small.factor / 8))
        }
        guard let second = refined.max(by: { $0.match < $1.match }) else { return nil }
        let fullPage = Plane(page, width: pw, height: ph, factor: 1)
        let fullPoints = Self.points(fullPage, in: area, count: tuning.points)
        let near = Plane(detail, width: dw, height: dh, factor: max(1, floor(second.scale)))
        let placement = refine(second, points: fullPoints, page: fullPage, detail: near, centre: centre,
                               step: secondFactor * second.scale / 2, until: 0.05 * second.scale)
        return placement.match >= tuning.leastMatch ? placement : nil
    }

    /// The print's steepest edges inside `area`, spread over it: in each of
    /// a grid of cells, its steepest points; in the plane's own pixels.
    static func points(_ plane: Plane, in area: CGRect, count: Int) -> [(x: Int, y: Int)] {
        let w = plane.width, h = plane.height
        let x0 = max(1, Int(Double(area.minX) / plane.factor)), x1 = min(w - 1, Int(Double(area.maxX) / plane.factor))
        let y0 = max(1, Int(Double(area.minY) / plane.factor)), y1 = min(h - 1, Int(Double(area.maxY) / plane.factor))
        guard x1 - x0 > 4, y1 - y0 > 4 else { return [] }
        let cells = 8, perCell = max(1, count / (cells * cells))
        var points: [(x: Int, y: Int)] = []
        for cy in 0..<cells {
            for cx in 0..<cells {
                let ax = x0 + cx * (x1 - x0) / cells, bx = x0 + (cx + 1) * (x1 - x0) / cells
                let ay = y0 + cy * (y1 - y0) / cells, by = y0 + (cy + 1) * (y1 - y0) / cells
                var steep: [(turn: Float, x: Int, y: Int)] = []
                for y in ay..<by {
                    for x in ax..<bx {
                        let p = y * w + x
                        let turn = abs(plane.values[p + 1] - plane.values[p - 1]) + abs(plane.values[p + w] - plane.values[p - w])
                        if turn >= 12 { steep.append((turn, x, y)) }
                    }
                }
                steep.sort { $0.turn > $1.turn }
                points += steep.prefix(perCell).map { ($0.x, $0.y) }
            }
        }
        return points
    }

    /// How well the close-up, laid as `placement` says, matches the page at
    /// the page's points: their correlation, from −1 to 1; −1 where too few
    /// of them fall inside it.
    static func match(_ points: [(x: Int, y: Int)], on page: Plane, in detail: Plane, placement: Placement,
                      centre: (x: Double, y: Double)) -> Double {
        var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0, n = 0.0
        let c = cos(placement.angle) * placement.scale, s = sin(placement.angle) * placement.scale
        for point in points {
            let a = Double(page.values[point.y * page.width + point.x])
            // The point in the page's own pixels, then in the close-up's.
            let rx = (Double(point.x) + 0.5) * page.factor - 0.5 - centre.x
            let ry = (Double(point.y) + 0.5) * page.factor - 0.5 - centre.y
            guard let value = detail.value(at: c * rx - s * ry + placement.dx, s * rx + c * ry + placement.dy)
            else { continue }
            let b = Double(value)
            sa += a
            sb += b
            saa += a * a
            sbb += b * b
            sab += a * b
            n += 1
        }
        // A close-up that covers less than a third of the small print says too little.
        guard n >= max(12, Double(points.count) / 3) else { return -1 }
        let cov = sab / n - sa / n * sb / n
        let va = saa / n - sa / n * sa / n, vb = sbb / n - sb / n * sb / n
        guard va > 1e-6, vb > 1e-6 else { return -1 }
        return cov / (va * vb).squareRoot()
    }

    /// The placement found step by step: its place by `step` of the
    /// close-up's pixels, its size by 2 % and its turn by 0.5°, each halved
    /// in turn until the place moves by `until`.
    static func refine(_ start: Placement, points: [(x: Int, y: Int)], page: Plane, detail: Plane,
                       centre: (x: Double, y: Double), step first: Double, until last: Double) -> Placement {
        var placement = start
        placement.match = match(points, on: page, in: detail, placement: placement, centre: centre)
        var step = first, grow = 0.02, turn = 0.5 * .pi / 180
        while step >= last {
            var improved = true
            while improved {
                improved = false
                let moves: [(Double, Double, Double, Double)] = [
                    (step, 0, 0, 0), (-step, 0, 0, 0), (0, step, 0, 0), (0, -step, 0, 0),
                    (0, 0, grow, 0), (0, 0, -grow, 0), (0, 0, 0, turn), (0, 0, 0, -turn),
                ]
                for (ddx, ddy, dscale, dangle) in moves {
                    var trial = placement
                    trial.dx += ddx
                    trial.dy += ddy
                    trial.scale *= 1 + dscale
                    trial.angle += dangle
                    trial.match = match(points, on: page, in: detail, placement: trial, centre: centre)
                    if trial.match > placement.match {
                        placement = trial
                        improved = true
                    }
                }
            }
            step /= 2
            grow /= 2
            turn /= 2
        }
        return placement
    }

    // MARK: Laying it onto the page

    /// The page with the close-up laid into `area`, the small print in the
    /// page's pixels from the top left, and where it lay; nil where the
    /// close-up matches the page nowhere well.
    static func laid(_ detail: ScanBitmap, onto page: ScanBitmap, around area: CGRect,
                     tuning: Tuning = .init()) -> (page: ScanBitmap, placement: Placement)? {
        guard let placement = placement(of: detail.brightness, width: detail.width, height: detail.height,
                                        onto: page.brightness, width: page.width, height: page.height,
                                        around: area, tuning: tuning) else { return nil }
        let w = page.width, h = page.height
        let centre = (x: Double(area.midX), y: Double(area.midY))
        // The close-up made about as small as the page, each colour apart.
        let factor = max(1, floor(placement.scale))
        let channels = (0..<3).map { c -> Plane in
            var plane = [UInt8](repeating: 0, count: detail.width * detail.height)
            for i in plane.indices { plane[i] = detail.pixels[i * 4 + c] }
            return Plane(plane, width: detail.width, height: detail.height, factor: factor)
        }
        let region = area.insetBy(dx: -CGFloat(tuning.blend), dy: -CGFloat(tuning.blend))
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let x0 = Int(region.minX), x1 = Int(region.maxX), y0 = Int(region.minY), y1 = Int(region.maxY)
        // How much of the close-up lands at a page pixel: none outside it or
        // the small print's place, fading in over `blend` pixels.
        func weight(_ x: Int, _ y: Int, _ q: (x: Double, y: Double)) -> Double {
            let inside = min(Double(x) - Double(region.minX), Double(region.maxX) - Double(x),
                             Double(y) - Double(region.minY), Double(region.maxY) - Double(y))
            let margin = channels[0].factor * 2
            let onDetail = min(q.x - margin, Double(detail.width) - margin - q.x,
                               q.y - margin, Double(detail.height) - margin - q.y) / placement.scale
            return min(1, max(0, min(inside, onDetail) / tuning.blend))
        }
        // The close-up brought to the page's light, each colour by where its
        // paper lies on both and by their mean, which a soft page keeps as
        // a sharp one has it, where its ink's darkest is spread out.
        var gains = [Double](repeating: 1, count: 3), offsets = [Double](repeating: 0, count: 3)
        for c in 0..<3 {
            var pageValues: [Double] = [], detailValues: [Double] = []
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    let q = placement.detailPoint(Double(x), Double(y), centre: centre)
                    guard weight(x, y, q) >= 1, let value = channels[c].value(at: q.x, q.y) else { continue }
                    pageValues.append(Double(page.pixels[(y * w + x) * 4 + c]))
                    detailValues.append(Double(value))
                }
            }
            guard pageValues.count >= 50 else { continue }
            func level(_ values: [Double], _ share: Double) -> Double {
                let sorted = values.sorted()
                return sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))]
            }
            let mean = { (values: [Double]) in values.reduce(0, +) / Double(values.count) }
            let pageSpan = level(pageValues, 0.9) - mean(pageValues)
            let detailSpan = level(detailValues, 0.9) - mean(detailValues)
            guard detailSpan > 4, pageSpan > 0 else { continue }
            gains[c] = min(2, max(0.5, pageSpan / detailSpan))
            offsets[c] = level(pageValues, 0.9) - gains[c] * level(detailValues, 0.9)
        }
        var out = page
        for y in y0..<y1 {
            for x in x0..<x1 {
                let q = placement.detailPoint(Double(x), Double(y), centre: centre)
                let share = weight(x, y, q)
                guard share > 0 else { continue }
                let i = (y * w + x) * 4
                for c in 0..<3 {
                    guard let value = channels[c].value(at: q.x, q.y) else { continue }
                    let laid = Double(value) * gains[c] + offsets[c]
                    let mixed = Double(page.pixels[i + c]) * (1 - share) + laid * share
                    out.pixels[i + c] = UInt8(min(255, max(0, mixed.rounded())))
                }
            }
        }
        return (out, placement)
    }

    // MARK: Kept or not

    /// Whether the small print reads better with the close-up laid: inside
    /// `area` (from 0 to 1 from the bottom left), the lines read after are
    /// read more surely than before, by `margin` at least, and no fewer of
    /// them are read.
    static func better(before: [ScanReadability.Line], after: [ScanReadability.Line], area: CGRect,
                       margin: Float = 0.02) -> Bool {
        func inside(_ lines: [ScanReadability.Line]) -> [ScanReadability.Line] {
            lines.filter { area.contains(CGPoint(x: $0.box.midX, y: $0.box.midY))
                && ScanContent.letters(in: $0.text) >= ScanContent.shortest }
        }
        let was = inside(before), now = inside(after)
        guard !now.isEmpty, now.count >= was.count else { return false }
        let letters = { (lines: [ScanReadability.Line]) in lines.reduce(0) { $0 + ScanContent.letters(in: $1.text) } }
        guard letters(now) >= letters(was) else { return false }
        let mean = { (lines: [ScanReadability.Line]) in lines.map(\.confidence).reduce(0, +) / Float(max(1, lines.count)) }
        return was.isEmpty || mean(now) >= mean(was) + margin
    }
}
