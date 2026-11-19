import Foundation

/// A part of the recording between two splits: kept, at its own speed, or
/// cut out of the video. The parts follow one another from the start of
/// the recording to its end; with none, the recording is one part, kept as
/// it is. Zooms, marks and clicks stay on the recording's own time, so a
/// cut or a faster part takes what is on it along.
struct StudioPart: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    /// How much faster than recorded it plays: 1 as recorded.
    var speed = 1.0
    /// Cut out of the video.
    var removed = false

    var duration: Double { end - start }

    /// How long it lasts in the video.
    var length: Double { removed ? 0 : duration / max(speed, 0.01) }

    func contains(_ t: Double) -> Bool { t >= start && t < end }

    /// The speeds a part can be played at.
    static let speeds: [Double] = [1, 1.5, 2, 4, 8]

    /// The shortest part a split leaves, in seconds.
    static let shortest = 0.25

    init(start: Double, end: Double, speed: Double = 1, removed: Bool = false) {
        self.start = start
        self.end = end
        self.speed = speed
        self.removed = removed
    }

    // What cannot be read, as from a newer Snapfly, is left as it starts.
    init(from decoder: Decoder) throws {
        let kept = try decoder.container(keyedBy: CodingKeys.self)
        id = try kept.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try kept.decode(Double.self, forKey: .start)
        end = try kept.decode(Double.self, forKey: .end)
        speed = (try? kept.decodeIfPresent(Double.self, forKey: .speed)) ?? 1
        removed = (try? kept.decodeIfPresent(Bool.self, forKey: .removed)) ?? false
    }
}

/// How the parts make the video: where to split, how long the video is,
/// and which moment of the recording shows at each moment of the video.
enum StudioCuts {
    /// The parts from the start to the end, with none missing or
    /// overlapping: one part of the whole recording where there are none.
    static func parts(_ parts: [StudioPart], duration: Double) -> [StudioPart] {
        let sorted = parts.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard duration > 0, !sorted.isEmpty else { return [StudioPart(start: 0, end: max(0, duration))] }
        var made: [StudioPart] = []
        var at = 0.0
        for var part in sorted where part.start < duration {
            part.start = at
            part.end = min(duration, max(at, part.end))
            guard part.end > part.start else { continue }
            made.append(part)
            at = part.end
        }
        if let last = made.indices.last {
            made[last].end = duration
        } else {
            made = [StudioPart(start: 0, end: duration)]
        }
        return made
    }

    /// Whether the parts change anything: some cut out or faster.
    static func edits(_ parts: [StudioPart]) -> Bool {
        parts.contains { $0.removed || $0.speed != 1 }
    }

    /// The part a time falls in, by its place among the parts.
    static func index(at t: Double, in parts: [StudioPart]) -> Int? {
        guard !parts.isEmpty else { return nil }
        if let i = parts.firstIndex(where: { $0.contains(t) }) { return i }
        return t >= (parts.last?.end ?? 0) ? parts.count - 1 : 0
    }

    /// The parts split in two at a time, the new part after the split
    /// keeping the speed and the cut of the one split; nil where the split
    /// would leave a part shorter than `StudioPart.shortest`.
    static func split(_ parts: [StudioPart], at t: Double) -> [StudioPart]? {
        guard let i = parts.firstIndex(where: { $0.contains(t) }) else { return nil }
        let part = parts[i]
        guard t - part.start >= StudioPart.shortest, part.end - t >= StudioPart.shortest else { return nil }
        var before = part, after = part
        before.end = t
        after.id = UUID()
        after.start = t
        var split = parts
        split[i] = before
        split.insert(after, at: i + 1)
        return split
    }

    /// The parts with one joined to the next, as one, with the first's
    /// speed and cut; nil for the last part.
    static func joined(_ parts: [StudioPart], at i: Int) -> [StudioPart]? {
        guard parts.indices.contains(i), parts.indices.contains(i + 1) else { return nil }
        var joined = parts
        joined[i].end = parts[i + 1].end
        joined.remove(at: i + 1)
        return joined
    }

    /// How long the video is.
    static func length(of parts: [StudioPart]) -> Double {
        parts.reduce(0) { $0 + $1.length }
    }

    /// The moment of the recording that shows at a moment of the video.
    static func source(at t: Double, in parts: [StudioPart]) -> Double {
        var left = max(0, t)
        for part in parts where !part.removed {
            if left < part.length { return part.start + left * part.speed }
            left -= part.length
        }
        // At the end: the last moment kept.
        return parts.last(where: { !$0.removed })?.end ?? 0
    }

    /// The moment of the video a moment of the recording shows at; nil
    /// where it is cut out.
    static func output(at t: Double, in parts: [StudioPart]) -> Double? {
        var before = 0.0
        for part in parts {
            if part.contains(t) || (part.end == t && part.id == parts.last?.id) {
                return part.removed ? nil : before + (t - part.start) / max(part.speed, 0.01)
            }
            before += part.length
        }
        return nil
    }

    /// Where playing goes on from a moment: the same moment where it is
    /// kept, else the start of the next part kept; nil when nothing kept
    /// follows.
    static func playable(from t: Double, in parts: [StudioPart]) -> Double? {
        guard let i = index(at: t, in: parts) else { return t }
        if !parts[i].removed { return t }
        return parts[(i + 1)...].first(where: { !$0.removed })?.start
    }

    /// The parts after the recording's first `offset` seconds were trimmed
    /// off and `duration` kept: they move to the new start, and what fell
    /// outside goes.
    static func trimmed(_ parts: [StudioPart], from offset: Double, keeping duration: Double) -> [StudioPart] {
        guard !parts.isEmpty else { return [] }
        let moved = parts.compactMap { part -> StudioPart? in
            var part = part
            part.start = max(0, part.start - offset)
            part.end = min(duration, part.end - offset)
            return part.end - part.start > 0.0001 ? part : nil
        }
        let made = Self.parts(moved, duration: duration)
        return edits(made) || made.count > 1 ? made : []
    }
}
