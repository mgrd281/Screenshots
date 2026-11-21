import CoreGraphics
import Foundation

// Studio's own pointer, for recordings made without the Mac's (Smooth
// pointer, Settings › General): larger, gliding rather than jittering, in
// the look the pointer had at each moment (arrow, I-beam, hand) or in one
// shape all through (an arrow, black or white, or a dot), pressed
// in at each click, and, if chosen, fading away while it keeps still. This
// file is the part that needs no screen; StudioDraw draws it.

/// One look the pointer had while recording, as macOS drew it.
struct StudioCursor: Codable, Equatable, Sendable {
    /// The picture, as PNG.
    var image: Data
    /// Where its tip is, in points from its top left.
    var hotX: Double
    var hotY: Double
    /// Its size in points.
    var width: Double
    var height: Double
}

/// What Studio's pointer looks like.
enum StudioPointerShape: String, Codable, CaseIterable, Sendable {
    /// As the Mac drew it at each moment: an arrow, an I-beam over words, a
    /// hand over links.
    case mac
    /// Always an arrow, black with a white edge.
    case arrow
    /// Always an arrow, white with a black edge, as on dark pages.
    case white
    /// A soft round dot, as a finger shows in a phone's video.
    case dot
}

/// How Studio's pointer looks in a recording's video, kept with its work.
struct StudioPointerStyle: Codable, Equatable, Sendable {
    var shows = true
    var shape = StudioPointerShape.mac
    /// How large, against the Mac's own pointer.
    var size = 1.6
    /// Glides as a hand moves, without the jitter of every small move.
    var smooth = true
    /// Fades away while it keeps still, and comes back as it moves.
    var hidesWhenStill = false

    static let sizes: ClosedRange<Double> = 1...3

    init() {}

    // What cannot be read, as from a newer Snapfly, is left as it starts.
    init(from decoder: Decoder) throws {
        let kept = try decoder.container(keyedBy: CodingKeys.self)
        shows = (try? kept.decodeIfPresent(Bool.self, forKey: .shows)) ?? true
        shape = (try? kept.decodeIfPresent(StudioPointerShape.self, forKey: .shape)) ?? .mac
        size = (try? kept.decodeIfPresent(Double.self, forKey: .size)) ?? 1.6
        smooth = (try? kept.decodeIfPresent(Bool.self, forKey: .smooth)) ?? true
        hidesWhenStill = (try? kept.decodeIfPresent(Bool.self, forKey: .hidesWhenStill)) ?? false
    }
}

/// Where Studio's pointer is at each moment: sixty places a second, each
/// following where the hand went on a spring, quick enough to stay with it
/// and soft enough to take the jitter out; or just where it went, unsmoothed.
struct StudioPointerPath: Sendable {
    static let rate = 60.0
    /// The spring's response, in seconds.
    static let response = 0.14
    /// How long it keeps still before fading, and how long the fade takes.
    static let stillFor = 1.5
    static let fade = 0.3
    /// How long a click presses it in and lets it go, and how far in.
    static let press = 0.22
    static let pressed = 0.82

    let points: [CGPoint]

    init(events: StudioEvents?, duration: Double, smooth: Bool) {
        guard let events, !events.pointer.isEmpty, duration > 0 else {
            points = []
            return
        }
        let count = Int((duration * Self.rate).rounded(.up)) + 1
        let dt = 1 / Self.rate
        var made: [CGPoint] = []
        made.reserveCapacity(count)
        guard smooth else {
            for i in 0..<count { made.append(events.pointer(at: Double(i) * dt) ?? .zero) }
            points = made
            return
        }
        let spring = 2 * Double.pi / Self.response
        var p = events.pointer(at: 0) ?? .zero
        var x = Double(p.x), y = Double(p.y), vx = 0.0, vy = 0.0
        for i in 0..<count {
            if i > 0, let target = events.pointer(at: Double(i) * dt) {
                vx += (spring * spring * (Double(target.x) - x) - 2 * spring * vx) * dt
                vy += (spring * spring * (Double(target.y) - y) - 2 * spring * vy) * dt
                x += vx * dt
                y += vy * dt
            }
            p = CGPoint(x: x, y: y)
            made.append(p)
        }
        points = made
    }

    /// Where it is at a time, between the two places around it; nil when
    /// the pointer was never seen.
    func point(at t: Double) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let position = max(0, t) * Self.rate
        let i = min(points.count - 1, Int(position))
        let j = min(points.count - 1, i + 1)
        let f = CGFloat(min(1, max(0, position - Double(i))))
        let a = points[i], b = points[j]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// How much of it shows, from 0 to 1: all of it, unless it hides while
    /// still and has kept still a while. A click counts as moving.
    static func presence(at t: Double, events: StudioEvents, hides: Bool) -> Double {
        guard hides else { return 1 }
        let moved = events.pointer.last { $0.t <= t }?.t ?? 0
        let clicked = events.clicks.last { $0.t <= t }?.t ?? 0
        let still = t - max(moved, clicked)
        guard still > stillFor else { return 1 }
        return max(0, 1 - (still - stillFor) / fade)
    }

    /// How large it is against its size, pressed in at each click: in
    /// quickly, out more slowly.
    static func scale(at t: Double, clicks: [StudioEvents.Click]) -> Double {
        guard let click = clicks.last(where: { $0.t <= t }), t - click.t < press else { return 1 }
        let p = (t - click.t) / press
        let depth = p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7
        return 1 - (1 - pressed) * depth
    }
}
