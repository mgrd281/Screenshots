import Foundation

/// A sheet's outline in a photo, as the document's mask gives it: points
/// down its left edge and down its right edge, from the top, in the photo's
/// pixels from its bottom left.
struct ScanOutline: Equatable, Sendable {
    var left: [CGPoint]
    var right: [CGPoint]
}

/// The shape of a sheet that is not flat, worked out from its outline and
/// its lines, and where its edges are clean. Where both its edges bend at
/// about the same height, it is folded there, and each part between its
/// folds is made flat on its own, then the parts are joined along the
/// folds. What is left bent, as a curl, is measured from its lines and
/// taken out by moving pixels up or down, never by drawing. Its edges are
/// cut in until nothing of what it lay on is left. Pure, so all of it is
/// checked without a camera.
enum ScanSheet {
    /// A side bends at a fold by at least this, in degrees.
    static let leastBend = 1.2
    /// A fold lies at least this share of the side from either end.
    static let foldRoom = 0.12
    /// The two ends of a fold lie this close, as a share of the side.
    static let foldPairing = 0.08

    /// A straight line through points down a side, as x from y, and its
    /// summed squared error.
    struct Line {
        let slope: Double
        let offset: Double
        let error: Double

        func x(at y: Double) -> Double { slope * y + offset }
    }

    /// A straight line through points that holds when some are wrong, as
    /// where the floor's grain was taken for the edge: fitted, the farthest
    /// points left out, and fitted again, twice. Its error is over the
    /// points kept, scaled to all of them.
    static func steadyLine(_ points: ArraySlice<CGPoint>) -> Line? {
        guard var fit = line(points) else { return nil }
        var kept = Array(points)
        for _ in 0..<2 {
            let offs = kept.map { abs(Double($0.x) - fit.x(at: Double($0.y))) }
            let limit = max(1.5, offs.sorted()[offs.count * 3 / 4] * 2.5)
            let closer = zip(kept, offs).filter { $0.1 <= limit }.map(\.0)
            guard closer.count >= max(4, kept.count / 2), let again = line(closer[...]) else { break }
            kept = closer
            fit = again
        }
        let scaled = fit.error * Double(points.count) / Double(max(1, kept.count))
        return Line(slope: fit.slope, offset: fit.offset, error: scaled)
    }

    static func line(_ points: ArraySlice<CGPoint>) -> Line? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        var sy = 0.0, sx = 0.0
        for p in points {
            sy += Double(p.y)
            sx += Double(p.x)
        }
        let my = sy / n, mx = sx / n
        var across = 0.0, down = 0.0
        for p in points {
            let dy = Double(p.y) - my
            across += dy * (Double(p.x) - mx)
            down += dy * dy
        }
        guard down > 1e-9 else { return nil }
        let slope = across / down, offset = mx - slope * my
        var error = 0.0
        for p in points {
            let off = Double(p.x) - (slope * Double(p.y) + offset)
            error += off * off
        }
        return Line(slope: slope, offset: offset, error: error)
    }

    /// The best place to split points down a side into two straight lines,
    /// if the two fit clearly better than one and meet at an angle: where
    /// they meet, and how far down the points, as a share of them.
    static func split(_ points: ArraySlice<CGPoint>) -> (point: CGPoint, share: Double)? {
        let n = points.count
        let room = max(6, Int(Double(n) * foldRoom))
        guard n > 2 * room + 2, let whole = steadyLine(points) else { return nil }
        let start = points.startIndex
        // Where to split: the best of every few points, with plain fits, which is quick.
        var best: (index: Int, error: Double)?
        for index in stride(from: start + room, through: start + n - room, by: max(1, n / 120)) {
            guard let top = line(points[start..<index]), let bottom = line(points[index...]) else { continue }
            let error = top.error + bottom.error
            if error < best?.error ?? .infinity { best = (index, error) }
        }
        guard let index = best?.index,
              let top = steadyLine(points[start..<index]), let bottom = steadyLine(points[index...]) else { return nil }
        let error = top.error + bottom.error
        let angle = abs(atan(top.slope) - atan(bottom.slope)) * 180 / .pi
        // Two lines fit at least three times better than one, beyond the edge's own unevenness.
        let spread = (whole.error / Double(n)).squareRoot()
        guard angle >= leastBend, error * 3 < whole.error, spread > 0.6 else { return nil }
        let slopes = top.slope - bottom.slope
        guard abs(slopes) > 1e-9 else { return nil }
        let near = Double(points[index].y)
        let y = min(max((bottom.offset - top.offset) / slopes, near - 60), near + 60)
        return (CGPoint(x: top.x(at: y), y: y), Double(index - start) / Double(n))
    }

    /// The best places to split points down a side into three straight
    /// lines, as a sheet folded twice has: where each two meet and how far
    /// down, if three fit clearly better than two and each meets the next
    /// at an angle.
    static func split3(_ points: ArraySlice<CGPoint>) -> [(point: CGPoint, at: Double)]? {
        let n = points.count
        let room = max(6, Int(Double(n) * foldRoom))
        guard n > 3 * room + 3 else { return nil }
        let start = points.startIndex, step = max(1, n / 60)
        var best: (i: Int, j: Int, error: Double)?
        for i in stride(from: start + room, through: start + n - 2 * room, by: step) {
            guard let top = line(points[start..<i]) else { continue }
            for j in stride(from: i + room, through: start + n - room, by: step) {
                guard let middle = line(points[i..<j]), let bottom = line(points[j...]) else { continue }
                let error = top.error + middle.error + bottom.error
                if error < best?.error ?? .infinity { best = (i, j, error) }
            }
        }
        guard let best, let top = steadyLine(points[start..<best.i]), let middle = steadyLine(points[best.i..<best.j]),
              let bottom = steadyLine(points[best.j...]) else { return nil }
        let three = top.error + middle.error + bottom.error
        // Against the best two lines.
        var two = Double.infinity
        for k in stride(from: start + room, through: start + n - room, by: step) {
            if let a = line(points[start..<k]), let b = line(points[k...]) { two = min(two, a.error + b.error) }
        }
        func angle(_ a: Line, _ b: Line) -> Double { abs(atan(a.slope) - atan(b.slope)) * 180 / .pi }
        guard three * 3 < two, angle(top, middle) >= leastBend, angle(middle, bottom) >= leastBend else { return nil }
        func meet(_ a: Line, _ b: Line, near index: Int) -> CGPoint? {
            let slopes = a.slope - b.slope
            guard abs(slopes) > 1e-9 else { return nil }
            let near = Double(points[index].y)
            let y = min(max((b.offset - a.offset) / slopes, near - 60), near + 60)
            return CGPoint(x: a.x(at: y), y: y)
        }
        guard let first = meet(top, middle, near: best.i), let second = meet(middle, bottom, near: best.j) else { return nil }
        return [(first, Double(best.i - start) / Double(n)), (second, Double(best.j - start) / Double(n))]
    }

    /// Each fold the two sides' light shows, as the middle of its band at
    /// each end, paired where the two sides show it at about the same
    /// share of the way down, left then right.
    private static func folds(of left: [Float], _ right: [Float], rows: [Int],
                              leftAt: [Double], rightAt: [Double]) -> [(left: CGPoint, right: CGPoint)] {
        // Smoothed, so the edge of a line of print is not taken for a band.
        func smoothed(_ values: [Float]) -> [Float] {
            values.indices.map { index in
                let low = max(0, index - 2), high = min(values.count - 1, index + 2)
                return values[low...high].reduce(0, +) / Float(high - low + 1)
            }
        }
        let span = Double(rows.count)
        // Where a band's paper is darker than the paper well above and well
        // below it, by a clear margin, and shallower than a band can be:
        // where it turns away from the light and back again.
        func bands(_ values: [Float]) -> [Int] {
            let light = smoothed(values)
            let far = max(6, Int(span * 0.10)), narrow = max(2, Int(span * 0.06))
            let near = max(3, Int(span * 0.10))
            var dimmer: [(index: Int, depth: Float)] = []
            for index in light.indices {
                let share = Double(index) / span
                guard share > foldRoom, share < 1 - foldRoom else { continue }
                let low = max(0, index - narrow), high = min(light.count - 1, index + narrow)
                // The lowest of the band, and the paper well clear of it darker
                // than it is: a shade of the light, not a line of print.
                let above = light[max(0, index - far)], below = light[min(light.count - 1, index + far)]
                guard light[index] <= light[low...high].min()! + 0.01,
                      max(above, below) - light[index] >= 5,
                      light[low] > light[index] + 3 || light[high] > light[index] + 3 else { continue }
                dimmer.append((index, max(above, below) - light[index]))
            }
            // A fold turns the paper away from the light over a good part of
            // its height: a narrow dip is the edge of a line of print, or the
            // edge of a shadow, and not the paper folded.
            let least = max(8, Int(span * 0.01)), widest = max(20, Int(span * 0.06))
            let bands = dimmer.filter { band in
                let half = light[band.index] + band.depth / 2
                var low = band.index, high = band.index
                while low > 0, light[low - 1] < half { low -= 1 }
                while high + 1 < light.count, light[high + 1] < half { high += 1 }
                return high - low >= least && high - low <= widest
            }
            // The deepest first, so a line of print cannot hide a fold near it.
            var found: [Int] = []
            for band in bands.sorted(by: { $0.depth > $1.depth }) {
                if found.contains(where: { abs($0 - band.index) < near }) { continue }
                found.append(band.index)
            }
            return found.sorted()
        }
        var folds: [(left: CGPoint, right: CGPoint)] = []
        // A fold darkens the paper across its whole width, so both sides show
        // it at the same height: where only one side turns dark, that is a
        // shadow or a shade of the light and not a fold.
        let one = bands(left), other = bands(right)
        // A fold runs across the sheet, so both sides show it at about the
        // same height: as close as a fold can lie across.
        let across = max(2, Int(span * 0.03))
        for index in one {
            // Each end where its own side shows it, as a fold rarely lies
            // level across.
            guard let match = other.first(where: { abs($0 - index) <= across }) else { continue }
            folds.append((CGPoint(x: leftAt[index], y: Double(rows[index])),
                          CGPoint(x: rightAt[match], y: Double(rows[match]))))
        }
        return folds
    }

    // MARK: The outline, sharp

    /// The outline found again in the photo itself, where the mask's is
    /// coarse: for every few rows of the photo, near where the mask puts
    /// each side, the place where the brightness turns most steeply from
    /// what the sheet lies on to the sheet. `photo` is the photo's pixels,
    /// rows from its top; the outline is in its pixels from the bottom left.
    static func refined(_ outline: ScanOutline, in photo: ScanBitmap, every step: Int = 8) -> ScanOutline {
        let w = photo.width, h = photo.height
        let reach = max(12, w / 60)
        func seed(_ side: [CGPoint], at up: Double) -> Double? {
            // The mask's side at this height, between its two nearest points.
            guard let below = side.lastIndex(where: { Double($0.y) >= up }), below + 1 < side.count else { return nil }
            let a = side[below], b = side[below + 1]
            let t = (Double(a.y) - up) / max(1e-9, Double(a.y - b.y))
            return Double(a.x) + Double(b.x - a.x) * t
        }
        func edge(row: Int, near x: Double, rising: Bool) -> Double? {
            let x0 = max(2, Int(x) - reach), x1 = min(w - 3, Int(x) + reach)
            guard x0 < x1 else { return nil }
            var best = x0, steepest = 0
            for xx in x0...x1 {
                // Across a few pixels each way, and a few rows, so the grain counts for little.
                var turn = 0
                for dy in -1...1 {
                    let y = min(max(row + dy, 0), h - 1)
                    let ahead = Int(photo.brightness(x: xx + 2, y: y)) + Int(photo.brightness(x: xx + 1, y: y))
                    let behind = Int(photo.brightness(x: xx - 2, y: y)) + Int(photo.brightness(x: xx - 1, y: y))
                    turn += rising ? ahead - behind : behind - ahead
                }
                if turn > steepest {
                    steepest = turn
                    best = xx
                }
            }
            // A sheet's edge stands well out of the grain.
            return steepest >= 60 ? Double(best) + 0.5 : nil
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        let top = Double(outline.left.first?.y ?? 0), bottom = Double(outline.left.last?.y ?? 0)
        var up = top - Double(step)
        while up > bottom {
            let row = h - 1 - Int(up)
            if let l = seed(outline.left, at: up), let r = seed(outline.right, at: up),
               let lx = edge(row: row, near: l, rising: true), let rx = edge(row: row, near: r, rising: false) {
                left.append(CGPoint(x: lx, y: up))
                right.append(CGPoint(x: rx, y: up))
            }
            up -= Double(step)
        }
        return left.count >= 24 ? ScanOutline(left: left, right: right) : outline
    }

    // MARK: Folds

    /// The paper's light a little in from each edge, row by row, over most
    /// of the way across, from the bottom of the photo up as the outline's
    /// points are; with where each row lies between the sides.
    static func sides(of photo: ScanBitmap, within outline: ScanOutline)
        -> (rows: [Int], leftAt: [Double], rightAt: [Double], left: [Float], right: [Float])? {
        let w = photo.width, h = photo.height
        guard outline.left.count >= 8, outline.right.count >= 8, w > 40, h > 40 else { return nil }
        // A side's point at a row of the photo, between the points the mask gives.
        func at(_ side: [CGPoint], row: Int) -> Double? {
            let y = Double(h - 1 - row)
            guard let first = side.first, let last = side.last,
                  y <= max(first.y, last.y), y >= min(first.y, last.y) else { return nil }
            var index = 0
            while index + 2 < side.count, (side[index + 1].y - y) * (side[index + 1].y - side[index].y) > 0 { index += 1 }
            let a = side[index], b = side[min(index + 1, side.count - 1)]
            let span = b.y - a.y
            let t = abs(span) > 1e-9 ? min(max((y - a.y) / span, 0), 1) : 0
            return Double(a.x + (b.x - a.x) * CGFloat(t))
        }
        // The paper's light a little in from each edge, row by row, over
        // most of the way across: a band darkens the whole of it alike,
        // where a line of print leaves most of a row paper.
        var left: [Float] = [], right: [Float] = []
        var rows: [Int] = [], leftAt: [Double] = [], rightAt: [Double] = []
        var counts = [Int32](repeating: 0, count: 256)
        photo.pixels.withUnsafeBufferPointer { px in
            for row in 0..<h {
                guard let l = at(outline.left, row: row), let r = at(outline.right, row: row), r - l > 40 else { continue }
                let across = r - l
                func light(from: Double, to: Double) -> Float {
                    for i in 0..<256 { counts[i] = 0 }
                    var seen = 0
                    var i = (row * w + max(0, Int(from))) * 4
                    for _ in max(0, Int(from))..<min(w, Int(to)) {
                        counts[Int(ScanClean.brightness(px[i], px[i + 1], px[i + 2]))] += 1
                        seen += 1
                        i += 4
                    }
                    guard seen > 0 else { return 0 }
                    // The paper, which is the light of the row: print takes a
                    // share of it, so read high, where nearly all of a row is
                    // paper and only a band can lower it.
                    var counted = 0
                    let wanted = Int(Double(seen) * 0.9)
                    for value in 0..<256 {
                        counted += Int(counts[value])
                        if counted >= wanted { return Float(value) }
                    }
                    return 255
                }
                // Two strips a side, read for the lighter of them: a line of
                // print in one leaves the other paper.
                left.append(max(light(from: l + across * 0.10, to: l + across * 0.22),
                                light(from: l + across * 0.26, to: l + across * 0.38)))
                right.append(max(light(from: r - across * 0.38, to: r - across * 0.26),
                                 light(from: r - across * 0.22, to: r - across * 0.10)))
                // Where the row lies in the photo, from the bottom up, as the outline's points are.
                rows.append(h - 1 - row)
                leftAt.append(l)
                rightAt.append(r)
            }
        }
        guard rows.count >= 24 else { return nil }
        return (rows, leftAt, rightAt, left, right)
    }

    /// Where the paper itself shows it is folded: a band across the sheet,
    /// its paper a little darker than the paper above and below it, where
    /// it turns away from the light. Read a little in from each edge, so a
    /// sheet lying nearly flat, whose outline hardly bends, still shows its
    /// folds; each as where it lies at either end.
    static func bands(of photo: ScanBitmap, within outline: ScanOutline) -> [(left: CGPoint, right: CGPoint)] {
        guard let side = sides(of: photo, within: outline) else { return [] }
        return folds(of: side.left, side.right, rows: side.rows, leftAt: side.leftAt, rightAt: side.rightAt)
    }

    /// A side's bends, from the top: where it is clearly two straight lines
    /// meeting at an angle, each as where they meet and how far down the
    /// side, as a share of it. Up to two.
    static func bends(of side: [CGPoint]) -> [(point: CGPoint, share: Double)] {
        guard side.count >= 24 else { return [] }
        // The mask rounds the corners: a little is left out at each end.
        let trim = max(2, side.count / 25)
        let points = side[trim..<(side.count - trim)]
        let length = Double(points.count)
        var found: [(point: CGPoint, at: Double)] = []
        if let two = split3(points) {
            found = two
        } else if let first = split(points) {
            found = [(first.point, first.share)]
        }
        return found.map { bend in
            (bend.point, (Double(trim) + bend.at * length) / Double(side.count))
        }.sorted { $0.share < $1.share }
    }

    /// Where the sheet is folded across, from the top, each fold as its two
    /// ends in the photo's pixels: where its left side and its right side
    /// bend at about the same height. None for a flat sheet.
    static func folds(of outline: ScanOutline) -> [(left: CGPoint, right: CGPoint)] {
        let right = bends(of: outline.right)
        return bends(of: outline.left).compactMap { bend -> (left: CGPoint, right: CGPoint)? in
            guard let match = right.min(by: { abs($0.share - bend.share) < abs($1.share - bend.share) }),
                  abs(match.share - bend.share) <= foldPairing else { return nil }
            return (bend.point, match.point)
        }
    }

    /// The folds that belong to a page's corners: each end near the side
    /// between the corners, well inside its length, and each below the one
    /// before. All in the same pixels.
    static func folds(_ folds: [(left: CGPoint, right: CGPoint)], within quad: ScanQuad) -> [(left: CGPoint, right: CGPoint)] {
        func along(_ point: CGPoint, from a: CGPoint, to b: CGPoint) -> (share: Double, off: Double)? {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let length2 = dx * dx + dy * dy
            guard length2 > 1 else { return nil }
            let px = Double(point.x - a.x), py = Double(point.y - a.y)
            let share = (px * dx + py * dy) / length2
            let off = abs(px * dy - py * dx) / length2.squareRoot()
            return (share, off / length2.squareRoot())
        }
        var kept: [(left: CGPoint, right: CGPoint)] = []
        var last = (left: 0.0, right: 0.0)
        // Down the sheet, as the corners run, so each fold is clear of the one above it.
        let ordered = folds.sorted { ($0.left.y + $0.right.y) > ($1.left.y + $1.right.y) }
        for fold in ordered {
            guard let left = along(fold.left, from: quad.topLeft, to: quad.bottomLeft),
                  let right = along(fold.right, from: quad.topRight, to: quad.bottomRight),
                  left.share > max(foldRoom, last.left + foldRoom), left.share < 1 - foldRoom,
                  right.share > max(foldRoom, last.right + foldRoom), right.share < 1 - foldRoom,
                  left.off < 0.05, right.off < 0.05 else { continue }
            kept.append(fold)
            last = (left.share, right.share)
        }
        return kept
    }

    /// The folds with each end brought onto the page's own sides, at the
    /// height that end shows the fold: the parts between them are then cut
    /// by the page's sides exactly, whole and to the page's own shape, and a
    /// fold's end read a little inside the paper does not narrow a part.
    static func seated(_ folds: [(left: CGPoint, right: CGPoint)], on quad: ScanQuad)
        -> [(left: CGPoint, right: CGPoint)] {
        func at(_ top: CGPoint, _ bottom: CGPoint, y: CGFloat) -> CGPoint {
            let span = bottom.y - top.y
            let t = abs(span) > 1e-6 ? (y - top.y) / span : 0
            return CGPoint(x: top.x + (bottom.x - top.x) * t, y: y)
        }
        return folds.map { fold in
            (at(quad.topLeft, quad.bottomLeft, y: fold.left.y),
             at(quad.topRight, quad.bottomRight, y: fold.right.y))
        }
    }

    /// The parts of a page between its folds, from the top, each its own
    /// four corners; the page whole where it has no folds, or where a part
    /// would be too thin or crossed.
    static func panels(of quad: ScanQuad, folds: [(left: CGPoint, right: CGPoint)]) -> [ScanQuad] {
        guard !folds.isEmpty else { return [quad] }
        let tops = [(quad.topLeft, quad.topRight)] + folds.map { ($0.left, $0.right) }
        let bottoms = Array(tops.dropFirst()) + [(quad.bottomLeft, quad.bottomRight)]
        let panels = zip(tops, bottoms).map { top, bottom in
            ScanQuad(topLeft: top.0, topRight: top.1, bottomRight: bottom.1, bottomLeft: bottom.0)
        }
        let whole = max(quad.area, 1e-9)
        let fine = panels.allSatisfy { panel in convex(panel) && panel.area / whole >= 0.08 }
        return fine ? panels : [quad]
    }

    private static func convex(_ quad: ScanQuad) -> Bool {
        let p = quad.corners
        var sign = 0.0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let first = Double((b.x - a.x) * (c.y - b.y)), second = Double((b.y - a.y) * (c.x - b.x))
            let turn = first - second
            guard abs(turn) > 1e-9 else { return false }
            if sign == 0 { sign = turn < 0 ? -1 : 1 }
            if (turn < 0) != (sign < 0) { return false }
        }
        return true
    }

    // MARK: Clean edges

    /// At most this share of a side is cut away, so print near an edge is
    /// never taken for what the sheet lay on.
    static let deepestCut = 0.04

    /// How far in from each edge, in pixels, the page is cut so nothing of
    /// what it lay on is left: along each row or column, the run from the
    /// edge of pixels clearly darker than the paper just inside it, the
    /// longest run on the side, and a little more. Runs reaching further
    /// than `deepestCut` are print or shadow, not floor, and are left.
    static func inset(of page: ScanBitmap) -> (left: Int, top: Int, right: Int, bottom: Int) {
        let w = page.width, h = page.height
        guard w > 40, h > 40 else { return (0, 0, 0, 0) }
        let plane = page.brightness
        var cut = (left: 0, top: 0, right: 0, bottom: 0)
        let deepAcross = Int(Double(w) * deepestCut), deepDown = Int(Double(h) * deepestCut)
        func run(_ line: Int, length: Int, deepest: Int, at: (Int, Int) -> Int) -> Int {
            // The paper just inside: the brightest tenth of the next stretch.
            var inside: [UInt8] = []
            for k in deepest..<min(length, 2 * deepest + 4) { inside.append(plane[at(line, k)]) }
            guard !inside.isEmpty else { return 0 }
            inside.sort()
            let paper = Double(inside[inside.count * 9 / 10])
            var k = 0
            while k < length, Double(plane[at(line, k)]) < 0.78 * paper { k += 1 }
            return k <= deepest ? k : 0
        }
        let margin = max(2, min(w, h) / 500)
        func deepest(_ lines: Range<Int>, length: Int, deep: Int, at: @escaping (Int, Int) -> Int) -> Int {
            var most = 0
            guard !lines.isEmpty else { return 0 }
            for line in lines { most = max(most, run(line, length: length, deepest: deep, at: at)) }
            return most > 0 ? min(deep, most + margin) : 0
        }
        // The sides first, down nearly the whole height, so a dark strip of
        // what the sheet lay on along a side — at its corner too — is cut
        // away and is never read as a top or a bottom edge.
        for _ in 0..<2 {
            let rows = (h / 50)..<(h - h / 50)
            cut.left = max(cut.left, deepest(rows, length: w, deep: deepAcross) { y, k in y * w + k })
            cut.right = max(cut.right, deepest(rows, length: w, deep: deepAcross) { y, k in y * w + (w - 1 - k) })
        }
        // Then the top and the bottom, read within the sides already cut
        // away and a little further in, so no side strip is mistaken for
        // one and no corner shifts the page.
        for _ in 0..<2 {
            let side = max(4, w / 100)
            let lo = max(cut.left, side), hi = min(w, w - max(cut.right, side))
            guard lo < hi else { break }
            cut.top = max(cut.top, deepest(lo..<hi, length: h, deep: deepDown) { x, k in k * w + x })
            cut.bottom = max(cut.bottom, deepest(lo..<hi, length: h, deep: deepDown) { x, k in (h - 1 - k) * w + x })
        }
        return cut
    }

    /// Nothing of what the sheet lay on stays dark along the page's own
    /// edge: in the outermost band, where a page keeps its margin, what is
    /// still dark is made white. What is light there, the paper or a pale
    /// fill printed to the edge, a watermark's, stays as it is. A dark page
    /// — a screen photographed — keeps its own edges.
    static func edgeCleaned(_ bitmap: ScanBitmap) -> ScanBitmap {
        let w = bitmap.width, h = bitmap.height
        guard w > 80, h > 80 else { return bitmap }
        var column: [UInt8] = []
        let step = max(1, h / 80)
        var y = 0
        while y < h { column.append(bitmap.brightness(x: w / 2, y: y)); y += step }
        column.sort()
        guard column[column.count / 2] > 128 else { return bitmap }
        let bandX = max(2, w / 80), bandY = max(2, h / 80)
        var out = bitmap
        for y in 0..<h {
            for x in 0..<w where (x < bandX || x >= w - bandX || y < bandY || y >= h - bandY)
                && bitmap.brightness(x: x, y: y) < 200 {
                let i = (y * w + x) * 4
                out.pixels[i] = 255
                out.pixels[i + 1] = 255
                out.pixels[i + 2] = 255
            }
        }
        return out
    }

    /// The page cut in by `inset`.
    static func cropped(_ page: ScanBitmap, _ cut: (left: Int, top: Int, right: Int, bottom: Int)) -> ScanBitmap {
        let w = page.width - cut.left - cut.right, h = page.height - cut.top - cut.bottom
        guard w > 0, h > 0, cut != (0, 0, 0, 0) else { return page }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        page.pixels.withUnsafeBufferPointer { src in
            pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let from = ((y + cut.top) * page.width + cut.left) * 4
                    for i in 0..<(w * 4) { dst[y * w * 4 + i] = src[from + i] }
                }
            }
        }
        return ScanBitmap(width: w, height: h, pixels: pixels)
    }
}
