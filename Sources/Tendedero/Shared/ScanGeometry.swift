import Foundation

/// A page's four corners in a picture, from 0 to 1 from the bottom left,
/// as Vision gives them.
struct ScanQuad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// The whole picture.
    static let whole = ScanQuad(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
                                bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0))

    /// The whole picture, this share in from each edge: where to start
    /// when no page is found.
    static func inset(_ share: CGFloat) -> ScanQuad {
        let far: CGFloat = 1 - share
        return ScanQuad(topLeft: CGPoint(x: share, y: far), topRight: CGPoint(x: far, y: far),
                        bottomRight: CGPoint(x: far, y: share), bottomLeft: CGPoint(x: share, y: share))
    }

    /// The corners in order round the page, from the top left.
    var corners: [CGPoint] {
        get { [topLeft, topRight, bottomRight, bottomLeft] }
        set {
            topLeft = newValue[0]
            topRight = newValue[1]
            bottomRight = newValue[2]
            bottomLeft = newValue[3]
        }
    }

    /// Every corner kept inside the picture.
    var clamped: ScanQuad {
        var quad = self
        quad.corners = corners.map { point -> CGPoint in
            let x: CGFloat = min(max(point.x, 0), 1), y: CGFloat = min(max(point.y, 0), 1)
            return CGPoint(x: x, y: y)
        }
        return quad
    }

    /// Whether the corners go round one way without crossing, as a page's
    /// do, and the page is more than a sliver.
    var isUsable: Bool {
        let points = corners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let first: CGFloat = (b.x - a.x) * (c.y - b.y), second: CGFloat = (b.y - a.y) * (c.x - b.x)
            let turn: CGFloat = first - second
            guard abs(turn) > 1e-6 else { return false }
            if sign == 0 { sign = turn.sign == .minus ? -1 : 1 }
            if (turn < 0) != (sign < 0) { return false }
        }
        return area > 0.01
    }

    /// Its area, as a share of the picture's.
    var area: CGFloat {
        let points = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4]
            let ab: CGFloat = a.x * b.y, ba: CGFloat = b.x * a.y
            sum += ab - ba
        }
        return abs(sum) / 2
    }

    /// The same corners in the picture turned clockwise by quarter turns,
    /// each named again for where it is then.
    func turned(_ quarterTurns: Int) -> ScanQuad {
        let turns = ((quarterTurns % 4) + 4) % 4
        let points = corners.map { point -> CGPoint in
            var p = point
            // A quarter turn clockwise takes (x, y), from the bottom left, to (y, 1 - x).
            for _ in 0..<turns {
                let flipped: CGFloat = 1 - p.x
                p = CGPoint(x: p.y, y: flipped)
            }
            return p
        }
        // Round the page the same way, from the corner now at the top left.
        let first = points.indices.min { a, b in
            let pa = points[a], pb = points[b]
            let da: CGFloat = pa.x - pa.y, db: CGFloat = pb.x - pb.y
            return da < db
        } ?? 0
        let order = (0..<4).map { points[(first + $0) % 4] }
        return ScanQuad(topLeft: order[0], topRight: order[1], bottomRight: order[2], bottomLeft: order[3])
    }

    /// The corners in a picture's pixels, from its bottom left.
    func pixels(in size: CGSize) -> ScanQuad {
        var quad = self
        quad.corners = corners.map { point -> CGPoint in
            let x: CGFloat = point.x * size.width, y: CGFloat = point.y * size.height
            return CGPoint(x: x, y: y)
        }
        return quad
    }
}

/// The geometry of a page: its true shape from where its corners are in a
/// photo, how far its lines lean, which way up it reads, and where it goes
/// on an A4 page of a PDF.
enum ScanGeometry {
    /// A4 in points, upright, and 10 mm.
    static let a4 = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 28.35
    /// A page's shape this close to A4's or to Letter's is taken as theirs.
    static let snap = 0.03

    // MARK: The page's shape

    /// The page's width over its height as it lies flat, from where its
    /// corners are in a photo taken at an angle: Zhang and He's way, with
    /// the camera's centre in the middle of the picture. The lens's focal
    /// length, in pixels, is worked out from the corners where they tell
    /// it; where they cannot, as when two sides look parallel, it is
    /// `focal`, or a phone's usual lens, 0.6 of the picture's diagonal.
    /// Where all that tells something far from the sides' own lengths, the
    /// sides' lengths say.
    static func aspect(of quad: ScanQuad, in size: CGSize, focal known: Double? = nil) -> Double {
        let q = quad.pixels(in: size)
        let m1 = vector(q.topLeft), m2 = vector(q.topRight), m3 = vector(q.bottomLeft), m4 = vector(q.bottomRight)
        let wide: CGFloat = distance(q.topLeft, q.topRight) + distance(q.bottomLeft, q.bottomRight)
        let tall: CGFloat = distance(q.topLeft, q.bottomLeft) + distance(q.topRight, q.bottomRight)
        let sides = Double(wide / max(tall, 1e-9))
        let k2: Double = dot(cross(m1, m4), m3) / dot(cross(m2, m4), m3)
        let k3: Double = dot(cross(m1, m4), m2) / dot(cross(m3, m4), m2)
        guard k2.isFinite, k3.isFinite else { return sides }
        let n2 = subtract(scale(m2, k2), m1), n3 = subtract(scale(m3, k3), m1)
        let u0: Double = Double(size.width) / 2, v0: Double = Double(size.height) / 2
        let diagonal = Double(hypot(size.width, size.height))
        var focal: Double = known ?? 0.6 * diagonal
        let product: Double = n2.2 * n3.2
        if abs(product) > 1e-12 {
            let mixedAcross: Double = n2.0 * n3.2 + n2.2 * n3.0, mixedDown: Double = n2.1 * n3.2 + n2.2 * n3.1
            let squareAcross: Double = product * u0 * u0, squareDown: Double = product * v0 * v0
            let across: Double = n2.0 * n3.0 - mixedAcross * u0 + squareAcross
            let down: Double = n2.1 * n3.1 - mixedDown * v0 + squareDown
            let squared: Double = -(across + down) / product
            if squared.isFinite, squared > 0 {
                let found = squared.squareRoot()
                // Only a lens a phone or a camera could have.
                if found > 0.25 * diagonal, found < 4 * diagonal { focal = found }
            }
        }
        func length(_ n: (Double, Double, Double)) -> Double {
            let x: Double = (n.0 - u0 * n.2) / focal, y: Double = (n.1 - v0 * n.2) / focal
            let flat: Double = x * x + y * y
            return flat + n.2 * n.2
        }
        let lengths: Double = length(n2) / max(length(n3), 1e-30)
        let ratio = lengths.squareRoot()
        guard ratio.isFinite, ratio > 0, ratio / sides < 1.6, sides / ratio < 1.6 else { return sides }
        return ratio
    }

    /// A shape this close to A4's or Letter's, upright or lying, is theirs.
    static func snapped(_ aspect: Double) -> Double {
        let papers: [Double] = [1 / 2.0.squareRoot(), 8.5 / 11, 2.0.squareRoot(), 11 / 8.5]
        for paper in papers where abs(aspect - paper) / paper < snap {
            return paper
        }
        return aspect
    }

    /// The flat page's size in pixels, of the shape given: as many pixels as
    /// its longer sides have in the photo, so nothing is made up, and no
    /// side longer than `longest`.
    static func size(of quad: ScanQuad, in size: CGSize, aspect: Double, longest: Int) -> (width: Int, height: Int) {
        let q = quad.pixels(in: size)
        let wide: CGFloat = max(distance(q.topLeft, q.topRight), distance(q.bottomLeft, q.bottomRight))
        let tall: CGFloat = max(distance(q.topLeft, q.bottomLeft), distance(q.topRight, q.bottomRight))
        let across = Double(wide), down = Double(tall)
        var width: Double = across, height: Double = across / max(aspect, 1e-6)
        if height < down {
            height = down
            width = down * aspect
        }
        let shrink: Double = min(1, Double(longest) / max(width, height))
        let pixelsAcross = Int((width * shrink).rounded()), pixelsDown = Int((height * shrink).rounded())
        return (max(1, pixelsAcross), max(1, pixelsDown))
    }

    // MARK: Upright and level

    /// How far the lines of text lean, in radians, from each line's angle
    /// and length: the middle of them, when at least three lines agree to a
    /// degree; 0 when they lean too little to straighten or do not agree.
    static func skew(of lines: [(angle: Double, length: Double)]) -> Double {
        let degree: Double = Double.pi / 180
        let steepest: Double = 15 * degree
        let usable = lines.filter { abs($0.angle) < steepest && $0.length > 0 }.sorted { $0.angle < $1.angle }
        guard usable.count >= 3 else { return 0 }
        let total: Double = usable.reduce(0) { $0 + $1.length }
        var seen = 0.0
        var middle = usable[0].angle
        for line in usable {
            seen += line.length
            if seen >= total / 2 {
                middle = line.angle
                break
            }
        }
        let agreeing: Double = usable.filter { abs($0.angle - middle) <= degree }.reduce(0) { $0 + $1.length }
        let enough: Double = 0.6 * total, least: Double = 0.3 * degree
        guard agreeing >= enough, abs(middle) >= least else { return 0 }
        return middle
    }

    /// Which way up a page reads best, in quarter turns clockwise, from how
    /// much text is read each way: upright unless another way reads clearly
    /// more.
    static func upright(_ readings: [Double]) -> Int {
        guard readings.count == 4, let best = readings.indices.max(by: { readings[$0] < readings[$1] }) else { return 0 }
        let clearly: Double = 1.5 * readings[0]
        return readings[best] > 0 && readings[best] >= clearly ? best : 0
    }

    // MARK: On paper

    /// Where a page of this many pixels goes on an A4 page of a PDF, upright
    /// or lying as it is: a page of A4's shape fills it; any other is as
    /// large as fits within 10 mm of its edges, in the middle. Never
    /// stretched: only made larger or smaller as a whole.
    static func layout(width: Int, height: Int) -> (page: CGSize, picture: CGRect) {
        let lying = CGSize(width: a4.height, height: a4.width)
        let page: CGSize = width > height ? lying : a4
        let aspect: Double = Double(width) / Double(max(height, 1))
        let paper = Double(page.width / page.height)
        let whole = CGRect(origin: .zero, size: page)
        let close: Bool = abs(aspect - paper) / paper < 0.02
        let room: CGRect = close ? whole : whole.insetBy(dx: margin, dy: margin)
        let pixelsAcross = CGFloat(max(width, 1)), pixelsDown = CGFloat(max(height, 1))
        let scale: CGFloat = min(room.width / pixelsAcross, room.height / pixelsDown)
        let shownWidth: CGFloat = CGFloat(width) * scale, shownHeight: CGFloat = CGFloat(height) * scale
        let left: CGFloat = room.midX - shownWidth / 2, bottom: CGFloat = room.midY - shownHeight / 2
        return (page, CGRect(x: left, y: bottom, width: shownWidth, height: shownHeight))
    }

    /// The page's dots an inch, as the PDF prints it.
    static func dpi(width: Int, height: Int) -> Double {
        let inches: CGFloat = layout(width: width, height: height).picture.width / 72
        return Double(width) / Double(inches)
    }

    /// By how much a page is drawn larger or smaller for the PDF: up to 300
    /// dots an inch when it has fewer, never more than four times, and down
    /// to 600 when it has more, so the file stays small enough to send.
    static func printScale(width: Int, height: Int) -> Double {
        let dpi = self.dpi(width: width, height: height)
        if dpi < 300 { return min(4, 300 / dpi) }
        if dpi > 600 { return 600 / dpi }
        return 1
    }

    // MARK: Vectors

    private static func vector(_ point: CGPoint) -> (Double, Double, Double) { (Double(point.x), Double(point.y), 1) }
    private static func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
        let x: Double = a.1 * b.2 - a.2 * b.1
        let y: Double = a.2 * b.0 - a.0 * b.2
        let z: Double = a.0 * b.1 - a.1 * b.0
        return (x, y, z)
    }
    private static func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let xy: Double = a.0 * b.0 + a.1 * b.1
        return xy + a.2 * b.2
    }
    private static func scale(_ a: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
        (a.0 * k, a.1 * k, a.2 * k)
    }
    private static func subtract(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
        (a.0 - b.0, a.1 - b.1, a.2 - b.2)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
}
