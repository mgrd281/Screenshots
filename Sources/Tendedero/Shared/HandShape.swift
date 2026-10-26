import CoreGraphics
import Foundation

/// A shape drawn over a picture by hand to hide what is under it: a stroke of
/// the marker, a box that may be turned, or an outline drawn round
/// something. Points are from 0 to 1 from the bottom left, as every place
/// is, on the original picture, so zooming never moves them. Widths and
/// turns are measured on the picture itself, so a stroke stays round and a
/// turned box stays square on a picture of any shape: `aspect` is the
/// picture's width over its height. Pure, so it is checked without a
/// picture; drawn in solid ink by `Finder.cover`.
enum HandShape: Codable, Equatable, Sendable {
    /// A stroke of the marker through these points; its width is a share
    /// of the picture's width.
    case stroke([CGPoint], width: CGFloat)
    /// A box turned about its middle by an angle in radians, counterclockwise.
    case box(CGRect, angle: CGFloat)
    /// An outline drawn round something, closed, filled inside.
    case outline([CGPoint])

    /// The marker's widths to choose from, thin to wide.
    static let widths: [CGFloat] = [0.02, 0.035, 0.06]

    // MARK: Where it is

    /// The smallest upright box round it, from 0 to 1.
    func bounds(aspect: CGFloat) -> CGRect {
        switch self {
        case .stroke(let points, let width):
            let reach = Self.reach(width, aspect: aspect)
            return Self.box(round: points).insetBy(dx: -reach.dx, dy: -reach.dy)
        case .box:
            return Self.box(round: corners(aspect: aspect))
        case .outline(let points):
            return Self.box(round: points)
        }
    }

    /// The corners of a box as turned, from 0 to 1; the points of the
    /// others.
    func corners(aspect: CGFloat) -> [CGPoint] {
        switch self {
        case .stroke(let points, _), .outline(let points):
            return points
        case .box(let rect, let angle):
            let a = max(aspect, 0.01)
            let middle = CGPoint(x: rect.midX * a, y: rect.midY)
            let half = CGSize(width: rect.width * a / 2, height: rect.height / 2)
            let c = cos(angle), s = sin(angle)
            return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
                let x = CGFloat(sx) * half.width, y = CGFloat(sy) * half.height
                return CGPoint(x: (middle.x + x * c - y * s) / a, y: middle.y + x * s + y * c)
            }
        }
    }

    /// Whether a point is on it, with some room round it for a finger.
    func contains(_ point: CGPoint, aspect: CGFloat, room: CGFloat = 0) -> Bool {
        let p = Self.even(point, aspect)
        switch self {
        case .stroke(let points, let width):
            return Self.distance(from: p, to: points.map { Self.even($0, aspect) }) <= width * aspect / 2 + room
        case .box, .outline:
            let polygon = corners(aspect: aspect).map { Self.even($0, aspect) }
            return Self.winds(round: p, polygon) || room > 0 && Self.distance(from: p, to: polygon + [polygon[0]]) <= room
        }
    }

    // MARK: Changing it

    /// Moved by an offset, from 0 to 1.
    func moved(by offset: CGPoint) -> HandShape {
        switch self {
        case .stroke(let points, let width):
            return .stroke(points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }, width: width)
        case .box(let rect, let angle):
            return .box(rect.offsetBy(dx: offset.x, dy: offset.y), angle: angle)
        case .outline(let points):
            return .outline(points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) })
        }
    }

    /// Stretched from the box round it to another: a box takes the new box
    /// as it is before its turn, a stroke and an outline are scaled to it.
    func resized(to new: CGRect, aspect: CGFloat) -> HandShape {
        let new = new.standardized
        switch self {
        case .box(_, let angle):
            return .box(new, angle: angle)
        case .stroke(let points, let width):
            return .stroke(Self.scaled(points, from: Self.box(round: points), to: inner(of: new, aspect: aspect)),
                           width: width)
        case .outline(let points):
            return .outline(Self.scaled(points, from: Self.box(round: points), to: new))
        }
    }

    /// A box turned further; the others stay as they are.
    func turned(by angle: CGFloat) -> HandShape {
        guard case .box(let rect, let current) = self else { return self }
        return .box(rect, angle: current + angle)
    }

    /// A stroke with another width; the others stay as they are.
    func widened(to width: CGFloat) -> HandShape {
        guard case .stroke(let points, _) = self else { return self }
        return .stroke(points, width: width)
    }

    /// The box a stroke's points fit in, inside the box round its width.
    private func inner(of bounds: CGRect, aspect: CGFloat) -> CGRect {
        guard case .stroke(_, let width) = self else { return bounds }
        let reach = Self.reach(width, aspect: aspect)
        return bounds.insetBy(dx: min(reach.dx, bounds.width / 2), dy: min(reach.dy, bounds.height / 2))
    }

    // MARK: Checking the copy

    /// Small upright boxes wholly inside it, from 0 to 1, where the copy
    /// must have changed: along a stroke, and spread over a box or an
    /// outline. At most `limit`.
    func insides(aspect: CGFloat, limit: Int = 48) -> [CGRect] {
        let a = max(aspect, 0.01)
        switch self {
        case .stroke(let points, let width):
            // A square inside the round end of the stroke at each step along it.
            let side = width * a * 0.6
            var spots: [CGPoint] = []
            let even = points.map { Self.even($0, a) }
            guard let first = even.first else { return [] }
            spots.append(first)
            guard side > 0 else { return [] }
            // How far along since the last square.
            var since: CGFloat = 0
            for (from, to) in zip(even, even.dropFirst()) {
                let length = hypot(to.x - from.x, to.y - from.y)
                var at = side - since
                while at <= length {
                    let t = at / max(length, 1e-9)
                    spots.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                    at += side
                }
                since = length - (at - side)
            }
            let step = max(1, spots.count / limit + (spots.count % limit == 0 ? 0 : 1))
            return stride(from: 0, to: spots.count, by: step).map { i in
                CGRect(x: (spots[i].x - side / 2) / a, y: spots[i].y - side / 2, width: side / a, height: side)
            }
        case .box, .outline:
            let polygon = corners(aspect: a).map { Self.even($0, a) }
            let bounds = Self.box(round: polygon)
            let count = 7
            let cell = CGSize(width: bounds.width / CGFloat(count), height: bounds.height / CGFloat(count))
            let side = min(cell.width, cell.height) * 0.8
            guard side > 0 else { return [] }
            var found: [CGRect] = []
            for row in 0..<count {
                for column in 0..<count {
                    let middle = CGPoint(x: bounds.minX + (CGFloat(column) + 0.5) * cell.width,
                                         y: bounds.minY + (CGFloat(row) + 0.5) * cell.height)
                    let square = CGRect(x: middle.x - side / 2, y: middle.y - side / 2, width: side, height: side)
                    let inside = [CGPoint(x: square.minX, y: square.minY), CGPoint(x: square.maxX, y: square.minY),
                                  CGPoint(x: square.maxX, y: square.maxY), CGPoint(x: square.minX, y: square.maxY)]
                        .allSatisfy { Self.winds(round: $0, polygon) }
                    if inside {
                        found.append(CGRect(x: square.minX / a, y: square.minY, width: side / a, height: side))
                    }
                }
            }
            return Array(found.prefix(limit))
        }
    }

    // MARK: Geometry

    /// A point measured in heights of the picture both ways.
    private static func even(_ point: CGPoint, _ aspect: CGFloat) -> CGPoint {
        CGPoint(x: point.x * aspect, y: point.y)
    }

    /// Half a stroke's width, from 0 to 1 each way.
    private static func reach(_ width: CGFloat, aspect: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        (width / 2, width * aspect / 2)
    }

    private static func box(round points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func scaled(_ points: [CGPoint], from old: CGRect, to new: CGRect) -> [CGPoint] {
        points.map { point in
            let u = old.width > 0 ? (point.x - old.minX) / old.width : 0.5
            let v = old.height > 0 ? (point.y - old.minY) / old.height : 0.5
            return CGPoint(x: new.minX + u * new.width, y: new.minY + v * new.height)
        }
    }

    /// The shortest way from a point to a line through these points.
    static func distance(from point: CGPoint, to line: [CGPoint]) -> CGFloat {
        guard let first = line.first else { return .infinity }
        var best = hypot(point.x - first.x, point.y - first.y)
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            best = min(best, hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy)))
        }
        return best
    }

    /// Whether an outline goes round a point, as it is filled: a part
    /// crossed twice is filled too.
    static func winds(round point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var winding = 0
        for (a, b) in zip(polygon, polygon.dropFirst() + [polygon[0]]) {
            let side = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
            if a.y <= point.y {
                if b.y > point.y, side > 0 { winding += 1 }
            } else if b.y <= point.y, side < 0 {
                winding -= 1
            }
        }
        return winding != 0
    }
}
