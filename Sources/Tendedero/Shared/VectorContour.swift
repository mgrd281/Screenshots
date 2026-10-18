import Foundation

/// Finds where a field of values, one for each pixel, crosses one half:
/// closed loops of points between the pixel centres, placed along each step
/// by how far the values lie from a half, so an edge that falls between two
/// pixels is found between them.
struct VectorMarchingSquares {
    /// For each edge between two neighbouring pixels, the crossing on it.
    private var edgeIndex: [Int32] = []

    /// - Parameters:
    ///   - field: values for `width` by `height` pixels, with a border of
    ///     zeros all round so every loop closes.
    ///   - originX: where the centre of the field's first pixel lies.
    mutating func loops(of field: [Float], width: Int, height: Int, originX: Double, originY: Double) -> [[VectorPoint]] {
        let size = 2 * width * height
        var edges = edgeIndex
        edgeIndex = []
        if edges.count < size { edges = [Int32](repeating: -1, count: size) }
        var xs: [Double] = []
        var ys: [Double] = []
        var first: [Int32] = []
        var second: [Int32] = []
        var touched: [Int] = []

        func crossing(_ id: Int, horizontal: Bool, _ x: Int, _ y: Int) -> Int32 {
            let known = edges[id]
            if known >= 0 { return known }
            let v0 = field[y * width + x]
            let v1 = horizontal ? field[y * width + x + 1] : field[(y + 1) * width + x]
            let t = Double((0.5 - v0) / (v1 - v0))
            xs.append(originX + Double(x) + (horizontal ? t : 0))
            ys.append(originY + Double(y) + (horizontal ? 0 : t))
            first.append(-1)
            second.append(-1)
            let index = Int32(xs.count - 1)
            edges[id] = index
            touched.append(id)
            return index
        }
        func link(_ a: Int32, _ b: Int32) {
            if first[Int(a)] < 0 { first[Int(a)] = b } else { second[Int(a)] = b }
            if first[Int(b)] < 0 { first[Int(b)] = a } else { second[Int(b)] = a }
        }

        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let i = y * width + x
                let tl = field[i] >= 0.5, tr = field[i + 1] >= 0.5
                let bl = field[i + width] >= 0.5, br = field[i + width + 1] >= 0.5
                if tl == tr && tr == br && br == bl { continue }
                let top = crossingID(horizontal: true, x, y, width)
                let bottom = crossingID(horizontal: true, x, y + 1, width)
                let left = crossingID(horizontal: false, x, y, width)
                let right = crossingID(horizontal: false, x + 1, y, width)
                if tl == br && tr == bl {
                    // Two corners meet only at a point: keep the pair that are in apart.
                    if tl {
                        link(crossing(top, horizontal: true, x, y), crossing(left, horizontal: false, x, y))
                        link(crossing(bottom, horizontal: true, x, y + 1), crossing(right, horizontal: false, x + 1, y))
                    } else {
                        link(crossing(top, horizontal: true, x, y), crossing(right, horizontal: false, x + 1, y))
                        link(crossing(bottom, horizontal: true, x, y + 1), crossing(left, horizontal: false, x, y))
                    }
                    continue
                }
                var ends: [Int32] = []
                if tl != tr { ends.append(crossing(top, horizontal: true, x, y)) }
                if tr != br { ends.append(crossing(right, horizontal: false, x + 1, y)) }
                if bl != br { ends.append(crossing(bottom, horizontal: true, x, y + 1)) }
                if tl != bl { ends.append(crossing(left, horizontal: false, x, y)) }
                if ends.count == 2 { link(ends[0], ends[1]) }
            }
        }
        for id in touched { edges[id] = -1 }
        edgeIndex = edges

        var visited = [Bool](repeating: false, count: xs.count)
        var loops: [[VectorPoint]] = []
        for start in 0..<xs.count where !visited[start] {
            var points: [VectorPoint] = []
            var previous: Int32 = -1
            var current = Int32(start)
            while true {
                visited[Int(current)] = true
                points.append(VectorPoint(xs[Int(current)], ys[Int(current)]))
                let a = first[Int(current)], b = second[Int(current)]
                let next = (a == previous || a < 0) ? b : a
                if next < 0 || visited[Int(next)] { break }
                previous = current
                current = next
            }
            loops.append(points)
        }
        return loops
    }

    private func crossingID(horizontal: Bool, _ x: Int, _ y: Int, _ width: Int) -> Int {
        2 * (y * width + x) + (horizontal ? 0 : 1)
    }
}

/// Turns a closed loop of points into lines and curves that follow it:
/// straight edges stay straight and corners stay sharp, and what is
/// round becomes a few smooth curves.
enum VectorFit {
    /// - Parameters:
    ///   - polygon: how far a straight edge may lie from the points it covers.
    ///   - tolerance: how far a curve may lie from the points it follows.
    static func contour(_ traced: [VectorPoint], polygon: Double, tolerance: Double) -> VectorContour? {
        let loop = squareCorners(traced)
        let n = loop.count
        guard n >= 3 else { return nil }
        if n < 6 {
            return VectorContour(start: loop[0], segments: loop.dropFirst().map { .line($0) })
        }
        // Start on the leftmost point, which is surely on a corner of the outline.
        var start = 0
        for i in 1..<n where loop[i].x < loop[start].x || (loop[i].x == loop[start].x && loop[i].y < loop[start].y) {
            start = i
        }
        let q = Array(loop[start...] + loop[..<start])
        var corners = polygonCorners(q, tolerance: polygon)
        if corners.count < 3 { corners = [0, n / 3, 2 * n / 3] }
        let m = corners.count
        let ends = corners + [n]

        // A line through the points of every edge, to put the corners where the lines meet.
        var lines: [(centre: VectorPoint, direction: VectorPoint)] = []
        for t in 0..<m {
            let a = ends[t], b = ends[t + 1]
            var points = Array(q[a..<min(b + 1, n)])
            if b >= n { points.append(q[0]) }
            if points.count >= 3 {
                lines.append(bestLine(points))
            } else {
                lines.append((q[a], normalised(sub(q[b % n], q[a]))))
            }
        }
        var vertices: [VectorPoint] = []
        for t in 0..<m {
            let here = q[corners[t]]
            let before = lines[(t - 1 + m) % m], after = lines[t]
            let cross = abs(before.direction.x * after.direction.y - before.direction.y * after.direction.x)
            if cross > 0.2, let meet = intersection(before, after), length(sub(meet, here)) <= 1.2 {
                vertices.append(meet)
            } else {
                vertices.append(here)
            }
        }
        // A long edge whose points all lie on its line is a straight line of the picture.
        var straight = [Bool](repeating: false, count: m)
        for t in 0..<m {
            let first = ends[t], last = ends[t + 1]
            guard length(sub(q[last % n], q[first])) >= 4 else { continue }
            var worst = 0.0
            for i in first...last {
                let off = sub(q[i % n], lines[t].centre)
                worst = max(worst, abs(off.x * lines[t].direction.y - off.y * lines[t].direction.x))
            }
            straight[t] = worst <= 0.12
        }
        // A vertex is a corner when the turn is sharp for the length of the edges that meet there.
        var sharp = [Bool](repeating: false, count: m)
        for t in 0..<m {
            // Two straight edges meet at a corner, however gently.
            if straight[(t - 1 + m) % m] && straight[t] {
                sharp[t] = true
                continue
            }
            let a = vertices[(t - 1 + m) % m], b = vertices[t], c = vertices[(t + 1) % m]
            let e0 = sub(b, a), e1 = sub(c, b)
            let l0 = length(e0), l1 = length(e1)
            if l0 < 1e-9 || l1 < 1e-9 { continue }
            let turn = acos(max(-1, min(1, dot(e0, e1) / (l0 * l1))))
            let shorter = min(l0, l1)
            sharp[t] = shorter * turn > 6.5 || (turn > 1.3 && shorter >= 1.5)
        }

        // Positions along the loop and round the polygon are counted on past the end.
        func wrapped(_ k: Int) -> Int { ((k % m) + m) % m }
        func endIndex(_ k: Int) -> Int { ends[wrapped(k)] + ((k - wrapped(k)) / m) * n }
        func at(_ i: Int) -> VectorPoint { q[((i % n) + n) % n] }
        /// The direction an edge runs in, when it is a straight line.
        func direction(_ k: Int) -> VectorPoint {
            let t = wrapped(k)
            let d = lines[t].direction
            return dot(d, sub(q[ends[t + 1] % n], q[ends[t]])) < 0 ? VectorPoint(-d.x, -d.y) : d
        }
        func projected(_ p: VectorPoint, onto k: Int) -> VectorPoint {
            let line = lines[wrapped(k)]
            let along = dot(sub(p, line.centre), line.direction)
            return VectorPoint(line.centre.x + along * line.direction.x, line.centre.y + along * line.direction.y)
        }

        // The outline is cut where a corner is, and on either side of a straight edge: between those
        // it is a line, or one run of curves that follows the points.
        var cuts: [Int] = (0..<m).filter { sharp[$0] || straight[$0] || straight[wrapped($0 - 1)] }
        if cuts.count < 2 {
            // A round outline with no corner is cut in two, so each curve has two ends.
            let one = cuts.first ?? 0
            cuts = [one, (one + m / 2) % m].sorted()
        }
        /// Where the outline passes a cut: a corner, or where a curve and a line run into each other.
        func anchor(_ k: Int) -> VectorPoint {
            let t = wrapped(k)
            if sharp[t] { return vertices[t] }
            if straight[t] { return projected(at(ends[t]), onto: t) }
            if straight[wrapped(t - 1)] { return projected(at(ends[t]), onto: t - 1) }
            return at(ends[t])
        }
        func across(_ k: Int) -> VectorPoint {
            normalised(sub(vertices[wrapped(k + 1)], vertices[wrapped(k - 1)]))
        }
        /// The direction a curve sets off in from a cut.
        func leaving(_ k: Int) -> VectorPoint {
            let t = wrapped(k)
            if sharp[t] { return normalised(sub(vertices[wrapped(t + 1)], vertices[t])) }
            if straight[wrapped(t - 1)] { return direction(t - 1) }
            return across(t)
        }
        /// The direction a curve comes in from, looking back along it, at a cut.
        func arriving(_ k: Int) -> VectorPoint {
            let t = wrapped(k)
            if sharp[t] { return normalised(sub(vertices[wrapped(t - 1)], vertices[t])) }
            if straight[t] {
                let d = direction(t)
                return VectorPoint(-d.x, -d.y)
            }
            let d = across(t)
            return VectorPoint(-d.x, -d.y)
        }

        var segments: [VectorSegment] = []
        let first = anchor(cuts[0])
        for (i, from) in cuts.enumerated() {
            var to = cuts[(i + 1) % cuts.count]
            if to <= from { to += m }
            let target = anchor(to)
            if to - from == 1 && straight[wrapped(from)] {
                segments.append(.line(target))
                continue
            }
            var points: [VectorPoint] = []
            for k in endIndex(from)...endIndex(to) { points.append(at(k)) }
            points[0] = anchor(from)
            points[points.count - 1] = target
            // The points that round off a corner are not part of the curve that leaves it.
            if sharp[wrapped(from)] {
                while points.count > 3 && length(sub(points[1], points[0])) < 0.9 { points.remove(at: 1) }
            }
            if sharp[wrapped(to)] {
                while points.count > 3 && length(sub(points[points.count - 2], points[points.count - 1])) < 0.9 {
                    points.remove(at: points.count - 2)
                }
            }
            segments += BezierFit.segments(points, leaving(from), arriving(to), tolerance)
        }
        // The path closes itself, so a last line back to the start says nothing.
        if case .line(let end)? = segments.last, length(sub(end, first)) < 0.005 { segments.removeLast() }
        return VectorContour(start: first, segments: segments)
    }

    // MARK: Square corners

    /// Where a loop runs straight, turns by a short diagonal and runs straight
    /// again at a right angle, it has cut across the corner of a shape that
    /// really is square (the pixels of a button, a panel, a window). The two
    /// points of the diagonal are put back to the corner where the runs meet.
    private static func squareCorners(_ loop: [VectorPoint]) -> [VectorPoint] {
        let n = loop.count
        guard n >= 8 else { return loop }
        func point(_ i: Int) -> VectorPoint { loop[((i % n) + n) % n] }
        /// The direction of three points that lie on one line, if they do.
        func run(_ a: VectorPoint, _ b: VectorPoint, _ c: VectorPoint) -> VectorPoint? {
            let d = sub(c, a)
            let l = length(d)
            guard l >= 1.5 else { return nil }
            let direction = VectorPoint(d.x / l, d.y / l)
            let off = sub(b, a)
            guard abs(off.x * direction.y - off.y * direction.x) <= 0.03 else { return nil }
            return direction
        }
        var replacement: [Int: VectorPoint] = [:]
        var dropped = Set<Int>()
        for i in 0..<n {
            let j = i + 1
            if replacement[i % n] != nil || dropped.contains(i % n) || dropped.contains(j % n) { continue }
            let step = sub(point(j), point(i))
            let l = length(step)
            guard l >= 0.2 && l <= 1.0 else { continue }
            guard let d0 = run(point(i - 2), point(i - 1), point(i)),
                  let d1 = run(point(j), point(j + 1), point(j + 2)) else { continue }
            guard abs(dot(d0, d1)) <= 0.1 else { continue }
            let before = (centre: point(i), direction: d0), after = (centre: point(j), direction: d1)
            guard let corner = intersection(before, after),
                  length(sub(corner, point(i))) <= 1.0, length(sub(corner, point(j))) <= 1.0 else { continue }
            replacement[i % n] = corner
            dropped.insert(j % n)
        }
        if replacement.isEmpty { return loop }
        var out: [VectorPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n where !dropped.contains(i) {
            out.append(replacement[i] ?? loop[i])
        }
        return out
    }

    // MARK: Polygon

    /// The fewest-edge polygon through points of the closed loop `q` (which
    /// starts on a corner) in which no edge strays further than `tolerance`
    /// from the points it covers; the indices of its corners.
    private static func polygonCorners(_ q: [VectorPoint], tolerance: Double) -> [Int] {
        let n = q.count
        let p = q + [q[0]]
        let none = Int.max / 2
        var best = [Int](repeating: none, count: n + 1)
        var previous = [Int](repeating: -1, count: n + 1)
        best[0] = 0
        // No straight edge needs to run longer than this many points; a longer one is cut.
        let longest = 600
        for i in 0..<n where best[i] < none {
            var low = -Double.pi, high = Double.pi
            var base: Double?
            let stop = min(n, i + longest)
            var j = i + 1
            while j <= stop {
                let dx = p[j].x - p[i].x, dy = p[j].y - p[i].y
                let r = (dx * dx + dy * dy).squareRoot()
                if r < 1e-9 { break }
                let theta = atan2(dy, dx)
                if base == nil { base = theta }
                let relative = wrap(theta - (base ?? 0))
                if relative >= low - 1e-9 && relative <= high + 1e-9 && best[i] + 1 < best[j] {
                    best[j] = best[i] + 1
                    previous[j] = i
                }
                // This point now limits how the edge may be aimed.
                let spread = asin(min(1, tolerance / r))
                low = max(low, relative - spread)
                high = min(high, relative + spread)
                if low > high { break }
                j += 1
            }
        }
        var corners: [Int] = []
        var j = n
        while j > 0 {
            j = previous[j]
            if j < 0 { return Array(0..<n) }
            corners.append(j)
        }
        return corners.reversed()
    }

    private static func wrap(_ angle: Double) -> Double {
        var a = angle
        while a > Double.pi { a -= 2 * Double.pi }
        while a <= -Double.pi { a += 2 * Double.pi }
        return a
    }

    // MARK: Vectors

    private static func sub(_ a: VectorPoint, _ b: VectorPoint) -> VectorPoint { VectorPoint(a.x - b.x, a.y - b.y) }
    private static func length(_ a: VectorPoint) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }
    private static func dot(_ a: VectorPoint, _ b: VectorPoint) -> Double { a.x * b.x + a.y * b.y }
    private static func mid(_ a: VectorPoint, _ b: VectorPoint) -> VectorPoint { VectorPoint((a.x + b.x) / 2, (a.y + b.y) / 2) }

    private static func normalised(_ a: VectorPoint) -> VectorPoint {
        let l = length(a)
        return l > 1e-12 ? VectorPoint(a.x / l, a.y / l) : VectorPoint(0, 0)
    }

    /// The straight line that lies closest to the points, as a point on it and its direction.
    private static func bestLine(_ points: [VectorPoint]) -> (centre: VectorPoint, direction: VectorPoint) {
        var cx = 0.0, cy = 0.0
        for p in points {
            cx += p.x
            cy += p.y
        }
        cx /= Double(points.count)
        cy /= Double(points.count)
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for p in points {
            let dx = p.x - cx, dy = p.y - cy
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        return (VectorPoint(cx, cy), VectorPoint(cos(angle), sin(angle)))
    }

    private static func intersection(_ a: (centre: VectorPoint, direction: VectorPoint),
                                     _ b: (centre: VectorPoint, direction: VectorPoint)) -> VectorPoint? {
        let cross = a.direction.x * b.direction.y - a.direction.y * b.direction.x
        if abs(cross) < 1e-9 { return nil }
        let t = ((b.centre.x - a.centre.x) * b.direction.y - (b.centre.y - a.centre.y) * b.direction.x) / cross
        return VectorPoint(a.centre.x + t * a.direction.x, a.centre.y + t * a.direction.y)
    }
}

/// Fitting cubic curves to points (Schneider's method): one curve if it
/// follows them closely enough, else two, split where it strays most.
enum BezierFit {
    private typealias Cubic = (VectorPoint, VectorPoint, VectorPoint, VectorPoint)

    /// Lines and curves from the first of the points to the last, leaving
    /// the first in direction `start` and arriving at the last from `end`.
    static func segments(_ points: [VectorPoint], _ start: VectorPoint, _ end: VectorPoint, _ tolerance: Double) -> [VectorSegment] {
        fit(points, start, end, tolerance).map { cubic -> VectorSegment in
            if isStraight(cubic, 0.12) { return VectorSegment.line(cubic.3) }
            return VectorSegment.curve(cubic.1, cubic.2, cubic.3)
        }
    }

    private static func fit(_ points: [VectorPoint], _ t1: VectorPoint, _ t2: VectorPoint, _ tolerance: Double) -> [Cubic] {
        if points.count == 2 {
            let d = distance(points[0], points[1]) / 3
            return [(points[0], add(points[0], scale(t1, d)), add(points[1], scale(t2, d)), points[1])]
        }
        var u = chordParameters(points)
        var curve = generate(points, u, t1, t2)
        var (error, split) = worstError(points, curve, u)
        if error < tolerance { return [curve] }
        if error < tolerance * 4 {
            for _ in 0..<5 {
                u = reparameterise(points, curve, u)
                curve = generate(points, u, t1, t2)
                (error, split) = worstError(points, curve, u)
                if error < tolerance { return [curve] }
            }
        }
        split = min(max(split, 1), points.count - 2)
        let centre = normalise(sub(points[split - 1], points[split + 1]))
        let left = fit(Array(points[0...split]), t1, centre, tolerance)
        let right = fit(Array(points[split...]), scale(centre, -1), t2, tolerance)
        return left + right
    }

    private static func chordParameters(_ points: [VectorPoint]) -> [Double] {
        var u = [0.0]
        for i in 1..<points.count { u.append(u[i - 1] + distance(points[i], points[i - 1])) }
        let total = u[u.count - 1] > 0 ? u[u.count - 1] : 1
        return u.map { $0 / total }
    }

    /// The curve whose ends are the first and last points, leaving and arriving in the
    /// given directions, that lies closest to the points in the least-squares sense.
    private static func generate(_ points: [VectorPoint], _ u: [Double], _ t1: VectorPoint, _ t2: VectorPoint) -> Cubic {
        let p0 = points[0], p3 = points[points.count - 1]
        var c00 = 0.0, c01 = 0.0, c11 = 0.0, x0 = 0.0, x1 = 0.0
        for (p, t) in zip(points, u) {
            let mt = 1 - t
            let b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t
            let a1 = scale(t1, b1), a2 = scale(t2, b2)
            c00 += dot(a1, a1)
            c01 += dot(a1, a2)
            c11 += dot(a2, a2)
            let tmp = sub(p, add(scale(p0, b0 + b1), scale(p3, b2 + b3)))
            x0 += dot(a1, tmp)
            x1 += dot(a2, tmp)
        }
        let det = c00 * c11 - c01 * c01
        let segment = distance(p0, p3)
        var left = 0.0, right = 0.0
        if abs(det) > 1e-12 {
            left = (x0 * c11 - x1 * c01) / det
            right = (c00 * x1 - c01 * x0) / det
        }
        let tiny = 1e-6 * segment
        if left < tiny || right < tiny || left > 1.5 * segment || right > 1.5 * segment {
            left = segment / 3
            right = segment / 3
        }
        return (p0, add(p0, scale(t1, left)), add(p3, scale(t2, right)), p3)
    }

    private static func point(_ c: Cubic, _ t: Double) -> VectorPoint {
        let mt = 1 - t
        let b0 = mt * mt * mt
        let b1 = 3 * mt * mt * t
        let b2 = 3 * mt * t * t
        let b3 = t * t * t
        let x = b0 * c.0.x + b1 * c.1.x + b2 * c.2.x + b3 * c.3.x
        let y = b0 * c.0.y + b1 * c.1.y + b2 * c.2.y + b3 * c.3.y
        return VectorPoint(x, y)
    }

    /// The slope of the curve at `t`.
    private static func first(_ c: Cubic, _ t: Double) -> VectorPoint {
        let mt = 1 - t
        let a = 3 * mt * mt
        let b = 6 * mt * t
        let d = 3 * t * t
        let x = a * (c.1.x - c.0.x) + b * (c.2.x - c.1.x) + d * (c.3.x - c.2.x)
        let y = a * (c.1.y - c.0.y) + b * (c.2.y - c.1.y) + d * (c.3.y - c.2.y)
        return VectorPoint(x, y)
    }

    /// How the slope changes at `t`.
    private static func second(_ c: Cubic, _ t: Double) -> VectorPoint {
        let mt = 1 - t
        let ax = c.2.x - 2 * c.1.x + c.0.x
        let ay = c.2.y - 2 * c.1.y + c.0.y
        let bx = c.3.x - 2 * c.2.x + c.1.x
        let by = c.3.y - 2 * c.2.y + c.1.y
        return VectorPoint(6 * mt * ax + 6 * t * bx, 6 * mt * ay + 6 * t * by)
    }

    /// Newton's step on each parameter, towards the point of the curve nearest its point.
    private static func reparameterise(_ points: [VectorPoint], _ c: Cubic, _ u: [Double]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(u.count)
        for (p, t) in zip(points, u) {
            let diff = sub(point(c, t), p)
            let d1 = first(c, t), d2 = second(c, t)
            let numerator = dot(diff, d1)
            let denominator = dot(d1, d1) + dot(diff, d2)
            let next = abs(denominator) > 1e-12 ? t - numerator / denominator : t
            out.append(min(1, max(0, next)))
        }
        return out
    }

    /// The largest distance of a point from the curve, and which point it is.
    private static func worstError(_ points: [VectorPoint], _ c: Cubic, _ u: [Double]) -> (Double, Int) {
        var worst = 0.0
        var index = points.count / 2
        if points.count > 2 {
            for i in 1..<(points.count - 1) {
                let d = distance(point(c, u[i]), points[i])
                if d > worst {
                    worst = d
                    index = i
                }
            }
        }
        return (worst, index)
    }

    /// Whether a curve's control points lie within `eps` of the chord, so a line will do.
    private static func isStraight(_ c: Cubic, _ eps: Double) -> Bool {
        let d = sub(c.3, c.0)
        let l = length(d)
        if l < 1e-9 { return false }
        let normal = VectorPoint(-d.y / l, d.x / l)
        return abs(dot(sub(c.1, c.0), normal)) <= eps && abs(dot(sub(c.2, c.0), normal)) <= eps
    }

    private static func sub(_ a: VectorPoint, _ b: VectorPoint) -> VectorPoint { VectorPoint(a.x - b.x, a.y - b.y) }
    private static func add(_ a: VectorPoint, _ b: VectorPoint) -> VectorPoint { VectorPoint(a.x + b.x, a.y + b.y) }
    private static func scale(_ a: VectorPoint, _ s: Double) -> VectorPoint { VectorPoint(a.x * s, a.y * s) }
    private static func dot(_ a: VectorPoint, _ b: VectorPoint) -> Double { a.x * b.x + a.y * b.y }
    private static func length(_ a: VectorPoint) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }
    private static func distance(_ a: VectorPoint, _ b: VectorPoint) -> Double { length(sub(a, b)) }

    private static func normalise(_ a: VectorPoint) -> VectorPoint {
        let l = length(a)
        return l > 1e-12 ? VectorPoint(a.x / l, a.y / l) : VectorPoint(0, 0)
    }
}
