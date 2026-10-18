import CoreGraphics
import Foundation

/// How far someone has come through the introduction, kept with the
/// settings: the steps seen through, where it was ended before its end, and
/// whether it was finished, for the version of the introduction it was.
/// The Mac and the iPhone each keep their own.
struct GuideProgress: Codable, Equatable {
    /// The introduction this was for. A newer one is offered once more.
    var version = 0
    /// Steps seen through, by their id.
    var seen: [String] = []
    /// Where it was ended before its end, to go on from there.
    var stoppedAt: String?
    /// Gone through to the end.
    var finished = false

    static let key = "guideProgress"

    static func load(from defaults: UserDefaults = .standard) -> GuideProgress {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(GuideProgress.self, from: data) else { return GuideProgress() }
        return saved
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// Offered at launch only while this version of it has never been.
    func offers(version current: Int) -> Bool { version < current }

    /// Ended before its end: the menu offers to go on.
    var canContinue: Bool { !finished && stoppedAt != nil }

    /// A step seen through, once.
    mutating func see(_ id: String) {
        if !seen.contains(id) { seen.append(id) }
    }

    /// Started again from the beginning: what was seen stays seen, so the
    /// tips it already taught stay away.
    mutating func restart() {
        stoppedAt = nil
        finished = false
    }
}

/// The order of the steps, skipping those whose part is not there right
/// now, like the lock on a photo with nothing covered.
enum GuideFlow {
    /// The first step after this one that can show; the first of all
    /// without one.
    static func step(after id: String?, in ids: [String], shows: (String) -> Bool) -> String? {
        let start = id.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        guard start < ids.count else { return nil }
        return ids[start...].first(where: shows)
    }

    /// The last step before this one that can show.
    static func step(before id: String, in ids: [String], shows: (String) -> Bool) -> String? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return ids[..<index].last(where: shows)
    }

    /// Where to go on from: the step it was ended at, if it can show, or the
    /// next one that can.
    static func resume(from id: String?, in ids: [String], shows: (String) -> Bool) -> String? {
        guard let id, ids.contains(id) else { return step(after: nil, in: ids, shows: shows) }
        return shows(id) ? id : step(after: id, in: ids, shows: shows)
    }

    /// Which step of how many, counting only those that show and this one.
    static func place(of id: String, in ids: [String], shows: (String) -> Bool) -> (number: Int, count: Int)? {
        let showing = ids.filter { $0 == id || shows($0) }
        guard let index = showing.firstIndex(of: id) else { return nil }
        return (index + 1, showing.count)
    }
}

/// Where a card goes beside what it points at, inside an area, in
/// coordinates that grow downwards: below it when there is room, else above,
/// else beside it, else in the middle; never past the area's edges. The
/// arrow on the edge facing what it points at says where along that edge.
enum GuidePlacement {
    enum Side: Equatable {
        /// The card is below what it points at, its arrow on its top edge.
        case below
        case above
        /// To the right, its arrow on its left edge.
        case right
        case left
        /// Pointing at nothing, or nowhere to point from.
        case none
    }

    struct Placed: Equatable {
        var frame: CGRect
        var side: Side
        /// From the start of the edge with the arrow: its left end, or its
        /// top for the sides.
        var arrow: CGFloat
    }

    /// How far the arrow keeps from the card's corners.
    static let arrowInset: CGFloat = 24

    /// - Parameters:
    ///   - top: where a card pointing at nothing begins, from the area's
    ///     top; nil centres it.
    static func place(_ size: CGSize, at target: CGRect?, in area: CGRect,
                      gap: CGFloat = 12, margin: CGFloat = 8, top: CGFloat? = nil) -> Placed {
        let inner = area.insetBy(dx: margin, dy: margin)
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, inner.minX), max(inner.minX, inner.maxX - size.width)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, inner.minY), max(inner.minY, inner.maxY - size.height)) }
        func along(_ point: CGFloat, length: CGFloat) -> CGFloat {
            min(max(point, arrowInset), max(arrowInset, length - arrowInset))
        }

        guard let target, !target.isNull, !target.isEmpty else {
            let x = clampX(inner.midX - size.width / 2)
            let y = clampY(top.map { inner.minY + $0 } ?? inner.midY - size.height / 2)
            return Placed(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), side: .none, arrow: 0)
        }

        let x = clampX(target.midX - size.width / 2)
        let below = target.maxY + gap
        if below + size.height <= inner.maxY {
            return Placed(frame: CGRect(x: x, y: below, width: size.width, height: size.height),
                          side: .below, arrow: along(target.midX - x, length: size.width))
        }
        let above = target.minY - gap - size.height
        if above >= inner.minY {
            return Placed(frame: CGRect(x: x, y: above, width: size.width, height: size.height),
                          side: .above, arrow: along(target.midX - x, length: size.width))
        }
        let y = clampY(target.midY - size.height / 2)
        let right = target.maxX + gap
        if right + size.width <= inner.maxX {
            return Placed(frame: CGRect(x: right, y: y, width: size.width, height: size.height),
                          side: .right, arrow: along(target.midY - y, length: size.height))
        }
        let left = target.minX - gap - size.width
        if left >= inner.minX {
            return Placed(frame: CGRect(x: left, y: y, width: size.width, height: size.height),
                          side: .left, arrow: along(target.midY - y, length: size.height))
        }
        return Placed(frame: CGRect(x: clampX(inner.midX - size.width / 2), y: clampY(inner.midY - size.height / 2),
                                    width: size.width, height: size.height),
                      side: .none, arrow: 0)
    }

    /// The hole round what is pointed at: a little room on every side, and
    /// corners that follow its own, up to a capsule.
    static func hole(around target: CGRect, room: CGFloat = 6, corner: CGFloat) -> (rect: CGRect, corner: CGFloat) {
        let rect = target.insetBy(dx: -room, dy: -room)
        return (rect, min(corner + room, min(rect.width, rect.height) / 2))
    }
}
