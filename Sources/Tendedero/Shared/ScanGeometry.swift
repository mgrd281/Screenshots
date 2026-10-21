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
        ScanQuad(topLeft: CGPoint(x: share, y: 1 - share), topRight: CGPoint(x: 1 - share, y: 1 - share),
                 bottomRight: CGPoint(x: 1 - share, y: share), bottomLeft: CGPoint(x: share, y: share))
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
        quad.corners = corners.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        return quad
    }

    /// Whether the corners go round one way without crossing, as a page's
    /// do, and the page is more than a sliver.
    var isUsable: Bool {
        let points = corners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let turn = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
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
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// The corners in a picture's pixels, from its bottom left.
    func pixels(in size: CGSize) -> ScanQuad {
        var quad = self
        quad.corners = corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
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
        let sides = Double((distance(q.topLeft, q.topRight) + distance(q.bottomLeft, q.bottomRight))
            / max(distance(q.topLeft, q.bottomLeft) + distance(q.topRight, q.bottomRight), 1e-9))
        let k2 = dot(cross(m1, m4), m3) / dot(cross(m2, m4), m3)
        let k3 = dot(cross(m1, m4), m2) / dot(cross(m3, m4), m2)
        guard k2.isFinite, k3.isFinite else { return sides }
        let n2 = subtract(scale(m2, k2), m1), n3 = subtract(scale(m3, k3), m1)
        let u0 = Double(size.width) / 2, v0 = Double(size.height) / 2
        let diagonal = Double(hypot(size.width, size.height))
        var focal = known ?? 0.6 * diagonal
        let product = n2.2 * n3.2
        if abs(product) > 1e-12 {
            let across = n2.0 * n3.0 - (n2.0 * n3.2 + n2.2 * n3.0) * u0 + product * u0 * u0
            let down = n2.1 * n3.1 - (n2.1 * n3.2 + n2.2 * n3.1) * v0 + product * v0 * v0
            let squared = -(across + down) / product
            if squared.isFinite, squared > 0 {
                let found = squared.squareRoot()
                // Only a lens a phone or a camera could have.
                if found > 0.25 * diagonal, found < 4 * diagonal { focal = found }
            }
        }
        func length(_ n: (Double, Double, Double)) -> Double {
            let x = (n.0 - u0 * n.2) / focal, y = (n.1 - v0 * n.2) / focal
            return x * x + y * y + n.2 * n.2
        }
        let ratio = (length(n2) / max(length(n3), 1e-30)).squareRoot()
        guard ratio.isFinite, ratio > 0, ratio / sides < 1.6, sides / ratio < 1.6 else { return sides }
        return ratio
    }

    /// A shape this close to A4's or Letter's, upright or lying, is theirs.
    static func snapped(_ aspect: Double) -> Double {
        for paper in [1 / 2.0.squareRoot(), 8.5 / 11, 2.0.squareRoot(), 11 / 8.5]
        where abs(aspect - paper) / paper < snap {
            return paper
        }
        return aspect
    }

    /// The flat page's size in pixels, of the shape given: as many pixels as
    /// its longer sides have in the photo, so nothing is made up, and no
    /// side longer than `longest`.
    static func size(of quad: ScanQuad, in size: CGSize, aspect: Double, longest: Int) -> (width: Int, height: Int) {
        let q = quad.pixels(in: size)
        let across = Double(max(distance(q.topLeft, q.topRight), distance(q.bottomLeft, q.bottomRight)))
        let down = Double(max(distance(q.topLeft, q.bottomLeft), distance(q.topRight, q.bottomRight)))
        var width = across, height = across / max(aspect, 1e-6)
        if height < down {
            height = down
            width = down * aspect
        }
        let shrink = min(1, Double(longest) / max(width, height))
        return (max(1, Int((width * shrink).rounded())), max(1, Int((height * shrink).rounded())))
    }

    // MARK: Upright and level

    /// How far the lines of text lean, in radians, from each line's angle
    /// and length: the middle of them, when at least three lines agree to a
    /// degree; 0 when they lean too little to straighten or do not agree.
    static func skew(of lines: [(angle: Double, length: Double)]) -> Double {
        let degree = Double.pi / 180
        let usable = lines.filter { abs($0.angle) < 15 * degree && $0.length > 0 }.sorted { $0.angle < $1.angle }
        guard usable.count >= 3 else { return 0 }
        let total = usable.reduce(0) { $0 + $1.length }
        var seen = 0.0
        var middle = usable[0].angle
        for line in usable {
            seen += line.length
            if seen >= total / 2 {
                middle = line.angle
                break
            }
        }
        let agreeing = usable.filter { abs($0.angle - middle) <= degree }.reduce(0) { $0 + $1.length }
        guard agreeing >= 0.6 * total, abs(middle) >= 0.3 * degree else { return 0 }
        return middle
    }

    /// Which way up a page reads best, in quarter turns clockwise, from how
    /// much text is read each way: upright unless another way reads clearly
    /// more.
    static func upright(_ readings: [Double]) -> Int {
        guard readings.count == 4, let best = readings.indices.max(by: { readings[$0] < readings[$1] }) else { return 0 }
        return readings[best] > 0 && readings[best] >= 1.5 * readings[0] ? best : 0
    }

    // MARK: On paper

    /// Where a page of this many pixels goes on an A4 page of a PDF, upright
    /// or lying as it is: a page of A4's shape fills it; any other is as
    /// large as fits within 10 mm of its edges, in the middle. Never
    /// stretched: only made larger or smaller as a whole.
    static func layout(width: Int, height: Int) -> (page: CGSize, picture: CGRect) {
        let page = width > height ? CGSize(width: a4.height, height: a4.width) : a4
        let aspect = Double(width) / Double(max(height, 1))
        let paper = Double(page.width / page.height)
        let room = abs(aspect - paper) / paper < 0.02
            ? CGRect(origin: .zero, size: page)
            : CGRect(origin: .zero, size: page).insetBy(dx: margin, dy: margin)
        let scale = min(room.width / CGFloat(max(width, 1)), room.height / CGFloat(max(height, 1)))
        let size = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        return (page, CGRect(x: room.midX - size.width / 2, y: room.midY - size.height / 2,
                             width: size.width, height: size.height))
    }

    /// The page's dots an inch, as the PDF prints it.
    static func dpi(width: Int, height: Int) -> Double {
        Double(width) / Double(layout(width: width, height: height).picture.width / 72)
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
        (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
    }
    private static func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }
    private static func scale(_ a: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
        (a.0 * k, a.1 * k, a.2 * k)
    }
    private static func subtract(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
        (a.0 - b.0, a.1 - b.1, a.2 - b.2)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
}
