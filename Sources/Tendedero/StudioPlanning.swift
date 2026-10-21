import CoreGraphics
import Foundation

// Studio: a screen recording made to explain. It zooms in where you click
// and type and follows the pointer there, shows each click, and carries
// arrows, boxes, circles, numbered steps and words for as long as each is
// wanted. This file is the part that needs no screen: what was done while
// recording, where to zoom, the camera's path, and the timeline's rules.
// Places run from 0 to 1 from the recorded area's bottom left, as Draw on
// Photo's do; times are seconds from the recording's first picture.

/// What happened while a screen recording ran: where the pointer went, where
/// it clicked, and when keys were pressed. Which keys is never kept, only
/// when, so typing can be zoomed in on without anything typed being stored.
struct StudioEvents: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        var t: Double
        var x: Double
        var y: Double
    }

    struct Click: Codable, Equatable, Sendable {
        var t: Double
        var x: Double
        var y: Double
        var right = false
    }

    /// The recorded area's size in points, for how far to zoom in.
    var width: Double
    var height: Double
    /// In time order, only when the pointer moved.
    var pointer: [Point] = []
    var clicks: [Click] = []
    /// When a key went down, in time order.
    var keys: [Double] = []

    /// Where the pointer was at a time, between the two places it was seen
    /// at around then; nil before anything was seen.
    func pointer(at t: Double) -> CGPoint? {
        guard let first = pointer.first, let last = pointer.last else { return nil }
        if t <= first.t { return CGPoint(x: first.x, y: first.y) }
        if t >= last.t { return CGPoint(x: last.x, y: last.y) }
        var low = 0, high = pointer.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if pointer[middle].t <= t { low = middle } else { high = middle }
        }
        let a = pointer[low], b = pointer[high]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// The same, for a recording with its first `offset` seconds trimmed off
    /// and `duration` seconds kept: earlier times go, and the pointer starts
    /// where it was when the kept part begins.
    func trimmed(from offset: Double, keeping duration: Double) -> StudioEvents {
        var trimmed = self
        let start = pointer(at: offset)
        trimmed.pointer = pointer.compactMap { point in
            let t = point.t - offset
            return t > 0 && t <= duration ? Point(t: t, x: point.x, y: point.y) : nil
        }
        if let start { trimmed.pointer.insert(Point(t: 0, x: start.x, y: start.y), at: 0) }
        trimmed.clicks = clicks.compactMap { click in
            let t = click.t - offset
            return t >= 0 && t <= duration ? Click(t: t, x: click.x, y: click.y, right: click.right) : nil
        }
        trimmed.keys = keys.map { $0 - offset }.filter { $0 >= 0 && $0 <= duration }
        return trimmed
    }

    /// Whether a place is on the recorded area, give or take a little.
    static func isInside(_ x: Double, _ y: Double) -> Bool {
        (-0.02...1.02).contains(x) && (-0.02...1.02).contains(y)
    }
}

/// A stretch of the recording seen closer: from when to when, how close,
/// and where it looks, following the pointer or kept on one place.
struct StudioZoom: Codable, Equatable, Identifiable, Sendable {
    enum Focus: Codable, Equatable, Sendable {
        /// Follows the pointer, moving only once it nears the edge.
        case pointer
        /// Kept on one place, its middle.
        case point(x: Double, y: Double)
    }

    var id = UUID()
    var start: Double
    var end: Double
    /// How many times closer, within `scales`.
    var scale: Double
    var focus: Focus = .pointer
    /// Made from the clicks and typing, and made again when they are; one
    /// changed by hand is the owner's from then on.
    var automatic = false

    static let scales: ClosedRange<Double> = 1.2...4
    /// The shortest a zoom can be, in seconds.
    static let shortest = 1.0
    /// A zoom added by hand lasts this long, where there is room.
    static let added = 3.0

    var duration: Double { end - start }

    func contains(_ t: Double) -> Bool { t >= start && t < end }
}

/// Zooms made from what was done while recording: each run of clicks and
/// typing gets one, starting a little before the first, so the camera has
/// arrived when it happens, and lingering a little after the last.
enum StudioAutoZoom {
    /// The zoom starts this long before the first click of a run.
    static let lead = 0.8
    /// And stays this long after its last.
    static let hold = 1.6
    /// Clicks and keys closer than this in time are one run.
    static let gap = 2.5
    /// Zooms closer than this become one, rather than going out and in.
    static let join = 1.2
    /// A run of clicks shorter than this still gets this long.
    static let shortest = 2.0
    /// A run spread wider than this share of the view is not zoomed in on:
    /// the camera would only sweep about.
    static let fill = 0.85

    /// How close to come by default: closer on a large area, where things
    /// are small, than on a small one.
    static func defaultScale(width: Double, height: Double) -> Double {
        let side = max(width, height)
        if side >= 1400 { return 2.0 }
        if side >= 900 { return 1.7 }
        return 1.4
    }

    /// Where something was done: each left or right click on the area, and
    /// each key, where the pointer was.
    static func activity(in events: StudioEvents) -> [(t: Double, point: CGPoint)] {
        var found: [(t: Double, point: CGPoint)] = events.clicks.compactMap { click in
            StudioEvents.isInside(click.x, click.y) ? (click.t, CGPoint(x: click.x, y: click.y)) : nil
        }
        for key in events.keys {
            guard let point = events.pointer(at: key), StudioEvents.isInside(point.x, point.y) else { continue }
            found.append((key, point))
        }
        return found.sorted { $0.t < $1.t }
    }

    static func zooms(for events: StudioEvents, duration: Double, scale: Double? = nil) -> [StudioZoom] {
        guard duration > 0 else { return [] }
        let base = min(StudioZoom.scales.upperBound,
                       max(StudioZoom.scales.lowerBound, scale ?? defaultScale(width: events.width, height: events.height)))
        var runs: [[(t: Double, point: CGPoint)]] = []
        for item in activity(in: events) where item.t <= duration {
            if let last = runs.last?.last, item.t - last.t <= gap {
                runs[runs.count - 1].append(item)
            } else {
                runs.append([item])
            }
        }
        var zooms: [StudioZoom] = []
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            let xs = run.map(\.point.x), ys = run.map(\.point.y)
            let spreadX = Double((xs.max() ?? 0) - (xs.min() ?? 0))
            let spreadY = Double((ys.max() ?? 0) - (ys.min() ?? 0))
            let fits = min(base, fill / max(spreadX, 0.001), fill / max(spreadY, 0.001))
            guard fits >= StudioZoom.scales.lowerBound else { continue }
            let early = max(0, first.t - lead)
            var end = min(duration, last.t + hold)
            end = max(end, min(duration, early + shortest))
            // Near the end, it starts earlier rather than being cut short.
            let start = max(0, min(early, end - shortest))
            guard end - start >= StudioZoom.shortest else { continue }
            let zoom = StudioZoom(start: start, end: end, scale: (fits * 100).rounded() / 100, automatic: true)
            if let previous = zooms.last, zoom.start - previous.end < join {
                zooms[zooms.count - 1].end = max(previous.end, zoom.end)
                zooms[zooms.count - 1].scale = min(previous.scale, zoom.scale)
            } else {
                zooms.append(zoom)
            }
        }
        return zooms
    }

    /// The zooms made again from the clicks and typing: the ones changed by
    /// hand stay, and a new one that would overlap them is left out.
    static func remade(_ zooms: [StudioZoom], events: StudioEvents, duration: Double, scale: Double?) -> [StudioZoom] {
        let kept = zooms.filter { !$0.automatic }
        let made = Self.zooms(for: events, duration: duration, scale: scale).filter { new in
            !kept.contains { $0.start < new.end && new.start < $0.end }
        }
        return (kept + made).sorted { $0.start < $1.start }
    }
}

/// Where the camera looks at every moment, worked out once for the whole
/// recording: it eases in and out of each zoom and pans after the pointer
/// as a camera operator would, springing to each new place without
/// overshooting. Sixty places a second, between which it is smoothed.
struct StudioCamera: Sendable {
    struct Frame: Equatable, Sendable {
        var x: Double
        var y: Double
        var scale: Double
    }

    static let rate = 60.0
    /// How long the zoom takes to come in or go out, and the pan to follow,
    /// as a spring's response.
    static let zoomResponse = 0.9
    static let panResponse = 0.75
    /// How far ahead the camera reads the pointer, so it moves with the hand
    /// rather than after it.
    static let lookAhead = 0.2
    /// The share of the view, about its middle, the pointer can move in
    /// before the camera follows.
    static let calm = 0.5

    let frames: [Frame]

    /// Without zooms, the whole recording all through.
    static let still = StudioCamera(frames: [Frame(x: 0.5, y: 0.5, scale: 1)])

    init(frames: [Frame]) {
        self.frames = frames.isEmpty ? [Frame(x: 0.5, y: 0.5, scale: 1)] : frames
    }

    init(zooms: [StudioZoom], events: StudioEvents?, duration: Double) {
        let sorted = zooms.sorted { $0.start < $1.start }
        guard duration > 0, !sorted.isEmpty else {
            self.init(frames: [])
            return
        }
        let dt = 1 / Self.rate
        let count = Int((duration * Self.rate).rounded(.up)) + 1
        var frames: [Frame] = []
        frames.reserveCapacity(count)
        var cx = 0.5, cy = 0.5, logScale = 0.0
        var vx = 0.0, vy = 0.0, vs = 0.0
        var focus = CGPoint(x: 0.5, y: 0.5)
        var current: UUID?
        let zoomSpring = 2 * Double.pi / Self.zoomResponse
        let panSpring = 2 * Double.pi / Self.panResponse
        var index = 0
        for i in 0..<count {
            let t = Double(i) * dt
            while index < sorted.count, sorted[index].end <= t { index += 1 }
            let zoom = index < sorted.count && sorted[index].contains(t) ? sorted[index] : nil
            var target = CGPoint(x: 0.5, y: 0.5)
            var targetScale = 1.0
            if let zoom {
                targetScale = max(1, zoom.scale)
                let half = 0.5 / targetScale
                switch zoom.focus {
                case let .point(x, y):
                    focus = CGPoint(x: x, y: y)
                case .pointer:
                    if current != zoom.id {
                        // Where the hand will be once the camera arrives.
                        let arrive = min(zoom.start + StudioAutoZoom.lead, zoom.start + zoom.duration / 2)
                        focus = Self.inside(events?.pointer(at: arrive)) ?? focus
                    } else if let seen = Self.inside(events?.pointer(at: t + Self.lookAhead)) {
                        let calm = half * Self.calm
                        if seen.x > focus.x + calm { focus.x = seen.x - calm }
                        if seen.x < focus.x - calm { focus.x = seen.x + calm }
                        if seen.y > focus.y + calm { focus.y = seen.y - calm }
                        if seen.y < focus.y - calm { focus.y = seen.y + calm }
                    }
                }
                current = zoom.id
                focus = CGPoint(x: min(1 - half, max(half, focus.x)), y: min(1 - half, max(half, focus.y)))
                target = focus
            } else {
                current = nil
            }
            if i > 0 {
                vs += (zoomSpring * zoomSpring * (log(targetScale) - logScale) - 2 * zoomSpring * vs) * dt
                logScale += vs * dt
                vx += (panSpring * panSpring * (Double(target.x) - cx) - 2 * panSpring * vx) * dt
                vy += (panSpring * panSpring * (Double(target.y) - cy) - 2 * panSpring * vy) * dt
                cx += vx * dt
                cy += vy * dt
            }
            frames.append(Frame(x: cx, y: cy, scale: max(1, exp(logScale))))
        }
        self.init(frames: frames)
    }

    /// The pointer's place kept on the area.
    private static func inside(_ point: CGPoint?) -> CGPoint? {
        guard let point else { return nil }
        return CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }

    /// The camera at a time, between the two frames around it.
    func frame(at t: Double) -> Frame {
        let position = max(0, t) * Self.rate
        let i = min(frames.count - 1, Int(position))
        let j = min(frames.count - 1, i + 1)
        let f = min(1, max(0, position - Double(i)))
        let a = frames[i], b = frames[j]
        return Frame(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, scale: a.scale + (b.scale - a.scale) * f)
    }

    /// The part of the recording seen at a time, from 0 to 1 from the bottom
    /// left, always within it and at its proportions.
    func rect(at t: Double) -> CGRect {
        Self.rect(of: frame(at: t))
    }

    static func rect(of frame: Frame) -> CGRect {
        let side = 1 / max(1, frame.scale)
        let x = min(1 - side, max(0, frame.x - side / 2))
        let y = min(1 - side, max(0, frame.y - side / 2))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// A place on the recording as it shows in the view seen through `rect`.
    static func shown(_ point: CGPoint, through rect: CGRect) -> CGPoint {
        CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    /// A place in the view seen through `rect`, on the recording.
    static func recorded(_ point: CGPoint, through rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

/// How marks and clicks come and go.
enum StudioFade {
    /// A mark draws in over this long, an arrow from its tail to its tip.
    static let appear = 0.35
    /// And fades out over this long before it ends.
    static let leave = 0.25
    /// A mark put down lasts this long, where the recording allows.
    static let shown = 3.0
    /// The shortest a mark can show.
    static let shortest = 0.5
    /// A click's ring spreads and fades over this long, as a guide's does.
    static let ripple = 0.45

    /// How far a mark has drawn in and how much of it shows, from 0 to 1;
    /// nil while it doesn't. With `still`, it only fades.
    static func presence(at t: Double, start: Double, end: Double, still: Bool = false)
        -> (drawn: Double, opacity: Double)? {
        guard t >= start, t < end else { return nil }
        let into = t - start, left = end - t
        let opacity = min(1, still ? into / 0.15 : into / 0.12, left / leave)
        let drawn = still ? 1 : easeOut(min(1, into / appear))
        return (drawn, max(0, opacity))
    }

    /// A click's ring, from 0.45 of its size to all of it, and how much of it
    /// shows; nil before the click and once it has faded.
    static func ripple(at t: Double, click: Double) -> (size: Double, opacity: Double)? {
        let p = (t - click) / ripple
        guard p >= 0, p < 1 else { return nil }
        return (0.45 + 0.55 * easeOut(p), 1 - easeOut(p))
    }

    static func easeOut(_ p: Double) -> Double {
        let q = 1 - min(1, max(0, p))
        return 1 - q * q * q
    }
}

/// The timeline's rules: what stays inside the recording, the shortest
/// spans, and zooms that never overlap.
enum StudioTimeline {
    /// A span kept within the recording, at least `shortest` long where
    /// the recording is.
    static func kept(start: Double, end: Double, duration: Double, shortest: Double) -> (start: Double, end: Double) {
        let length = min(duration, max(shortest, end - start))
        let start = min(max(0, start), max(0, duration - length))
        return (start, start + length)
    }

    /// A span moved by `delta` seconds as a whole, between `low` and `high`.
    static func moved(start: Double, end: Double, by delta: Double, low: Double, high: Double) -> (start: Double, end: Double) {
        let length = end - start
        let start = min(max(low, start + delta), max(low, high - length))
        return (start, start + length)
    }

    /// The room a zoom has between its neighbours, within the recording.
    static func room(for id: UUID, among zooms: [StudioZoom], duration: Double) -> (low: Double, high: Double) {
        guard let zoom = zooms.first(where: { $0.id == id }) else { return (0, duration) }
        let others = zooms.filter { $0.id != id }
        let low = others.filter { $0.end <= zoom.start + 0.0001 }.map(\.end).max() ?? 0
        let high = others.filter { $0.start >= zoom.end - 0.0001 }.map(\.start).min() ?? duration
        return (low, high)
    }

    /// A new zoom at a time, as long as `StudioZoom.added` where there is
    /// room, shorter where there is less; nil where there is too little.
    static func added(at t: Double, scale: Double, among zooms: [StudioZoom], duration: Double) -> StudioZoom? {
        guard t >= 0, t < duration, !zooms.contains(where: { $0.contains(t) }) else { return nil }
        let high = zooms.filter { $0.start > t }.map(\.start).min() ?? duration
        let low = zooms.filter { $0.end <= t }.map(\.end).max() ?? 0
        var start = t, end = min(high, t + StudioZoom.added)
        if end - start < StudioZoom.shortest { start = max(low, end - StudioZoom.shortest) }
        guard end - start >= StudioZoom.shortest - 0.0001 else { return nil }
        end = min(end, duration)
        return StudioZoom(start: start, end: end, scale: scale)
    }

    /// Steps numbered in the order they show, those at the same moment in
    /// the order they were put down.
    static func numbers(of steps: [(id: UUID, start: Double)]) -> [UUID: Int] {
        let order = steps.enumerated().sorted { a, b in
            a.element.start == b.element.start ? a.offset < b.offset : a.element.start < b.element.start
        }
        var numbers: [UUID: Int] = [:]
        for (place, step) in order.enumerated() { numbers[step.element.id] = place + 1 }
        return numbers
    }

    /// A time as the timeline says it: "0:07", "1:05", "1:02:03".
    static func text(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let h = whole / 3600, m = whole / 60 % 60, s = whole % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The ruler's step, in seconds, so its labels stand at least `room`
    /// points apart at `pointsPerSecond`.
    static func tick(pointsPerSecond: Double, room: Double = 56) -> Double {
        for step in [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600] where step * pointsPerSecond >= room {
            return step
        }
        return 1200
    }
}

/// The sound's loudness along the recording, for the timeline: the loudest
/// sample in each of `count` equal parts, from 0 to 1, the loudest part 1.
enum StudioWave {
    static func peaks(_ samples: [Float], count: Int) -> [Float] {
        guard count > 0, !samples.isEmpty else { return [] }
        var peaks = [Float](repeating: 0, count: count)
        let per = Double(samples.count) / Double(count)
        for i in 0..<count {
            let from = Int(Double(i) * per), to = max(from + 1, min(samples.count, Int(Double(i + 1) * per)))
            guard from < samples.count else { break }
            var loudest: Float = 0
            for j in from..<to { loudest = max(loudest, abs(samples[j])) }
            peaks[i] = loudest
        }
        let top = peaks.max() ?? 0
        return top > 0 ? peaks.map { $0 / top } : peaks
    }
}
