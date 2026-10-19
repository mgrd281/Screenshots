import CoreGraphics
import Foundation

/// A picture being protected, place by place: what Snapfly found and
/// covers, what it only offers to cover, what the owner hid by hand, and
/// what the owner turned on or off, moved, resized, turned or erased. Every
/// change of the owner's can be undone and done again; what Snapfly finds
/// later, as Apple Intelligence answers or the copy is checked, joins
/// without touching them. Places are from 0 to 1 from the bottom left, on
/// the original picture. Pure, so it is checked without a picture.
struct ProtectionPlan: Equatable {
    /// One place on the picture.
    struct Mark: Equatable, Identifiable {
        enum Origin: Equatable {
            /// Found by Snapfly, covered unless the owner turns it off.
            case found
            /// May be private, like a line shaped like a name that nothing
            /// vouches for: offered, covered only when the owner says so.
            case possible
            /// Hidden by the owner's hand: a word tapped, a box, a stroke of
            /// the marker or an outline.
            case hand
        }

        let id: Int
        /// The box round it, with its margin, as covered.
        var rect: CGRect
        let kind: PrivateDetail?
        var origin: Origin
        /// Covered, though it is not clear it should be: shown to be checked.
        var check: Bool
        var covered: Bool
        /// What it hides, to check the copy by; never shown or written down.
        let text: String?
        /// Drawn by hand, in solid ink; nil, the box itself.
        var shape: HandShape? = nil
    }

    /// How a picture's places stand, each counted once: covered for sure,
    /// still to check, and left uncovered by the owner. A place only
    /// offered is never counted as covered.
    struct Tally: Equatable {
        var covered = 0
        var toCheck = 0
        var left = 0
        /// Places to check that are not covered, like a name offered: while
        /// any is, the picture is not fully protected.
        var exposed = 0
    }

    private(set) var marks: [Mark] = []
    /// The picture's width over its height, so strokes and turned boxes
    /// keep their shape.
    var aspect: CGFloat = 1
    private var done: [Change] = []
    private var undone: [Change] = []
    private var nextID = 0
    /// Marks the owner changed, which Snapfly no longer changes.
    private var touched: Set<Int> = []

    /// A change of the owner's: the marks it changed, as they were and as
    /// they are, nil where there was none; and whether each was touched.
    private struct Change: Equatable {
        var before: [Int: Mark?] = [:]
        var after: [Int: Mark?] = [:]
        var touchedBefore: Set<Int> = []
        var touchedAfter: Set<Int> = []
    }

    init(aspect: CGFloat = 1) {
        self.aspect = aspect
    }

    // MARK: What Snapfly finds

    /// Adds what Snapfly found, covered, and what it only offers. A place
    /// already marked stays as it is, unless it was only offered and the
    /// owner has not touched it: found now, it is covered.
    mutating func add(found areas: [Finder.Area], possible: [Finder.Area] = []) {
        for area in areas {
            if let index = marks.firstIndex(where: { Self.same($0.rect, area.rect) }) {
                if marks[index].origin == .possible, !touched.contains(marks[index].id) {
                    marks[index].origin = .found
                    marks[index].covered = true
                    marks[index].check = area.check
                }
                continue
            }
            append(Mark(id: nextID, rect: area.rect, kind: area.kind, origin: .found, check: area.check, covered: true,
                        text: area.text))
        }
        for area in possible where !marks.contains(where: { Self.same($0.rect, area.rect) }) {
            append(Mark(id: nextID, rect: area.rect, kind: area.kind, origin: .possible, check: true, covered: false,
                        text: area.text))
        }
    }

    /// Two places are one when they nearly coincide, as the same words found
    /// twice do; a name inside an address block is a place of its own.
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        let shared = overlap.width * overlap.height
        let union = a.width * a.height + b.width * b.height - shared
        return union > 0 && shared >= union * 0.6
    }

    private mutating func append(_ mark: Mark) {
        marks.append(mark)
        nextID = max(nextID, mark.id) + 1
    }

    // MARK: What the owner changes

    /// Covers a place left uncovered, or uncovers a covered one.
    mutating func toggle(_ id: Int) {
        change([id]) { $0.covered.toggle() }
    }

    /// Covers a part of the picture by hand, from 0 to 1 from the bottom
    /// left, with the words it hides, if any. A part too small to see is
    /// left. The new mark's id, if one was made.
    @discardableResult
    mutating func cover(_ rect: CGRect, text: String? = nil) -> Int? {
        draw(.box(rect.standardized, angle: 0), text: text)
    }

    /// Hides what is under a shape drawn by hand. The new mark's id, if one
    /// was made: a shape too small to see, or outside the picture, is left.
    @discardableResult
    mutating func draw(_ shape: HandShape, text: String? = nil) -> Int? {
        let bounds = shape.bounds(aspect: aspect)
        let seen = bounds.intersection(Self.whole)
        guard !seen.isNull, seen.width >= 0.004 || seen.height >= 0.004, max(bounds.width, bounds.height) >= 0.005
        else { return nil }
        if case .outline(let points) = shape, points.count < 3 { return nil }
        let mark = Mark(id: nextID, rect: bounds, kind: nil, origin: .hand, check: false, covered: true, text: text,
                        shape: shape)
        record(Change(before: [mark.id: .none], after: [mark.id: mark], touchedBefore: touched,
                      touchedAfter: touched.union([mark.id])))
        nextID = mark.id + 1
        return mark.id
    }

    /// Moves marks by an offset, from 0 to 1, kept on the picture.
    mutating func move(_ ids: Set<Int>, by offset: CGPoint) {
        guard offset != .zero else { return }
        let aspect = self.aspect
        change(ids) { mark in
            let room = CGPoint(x: Self.clamp(offset.x, mark.rect.minX, mark.rect.maxX),
                               y: Self.clamp(offset.y, mark.rect.minY, mark.rect.maxY))
            if let shape = mark.shape {
                mark.shape = shape.moved(by: room)
                mark.rect = mark.shape!.bounds(aspect: aspect)
            } else {
                mark.rect = mark.rect.offsetBy(dx: room.x, dy: room.y)
            }
        }
    }

    /// Gives a mark a new box, as its handles are dragged: a turned box
    /// takes it as it is before its turn. Too small a box is refused.
    mutating func resize(_ id: Int, to rect: CGRect) {
        let rect = rect.standardized
        guard rect.width >= 0.005, rect.height >= 0.003 else { return }
        let aspect = self.aspect
        change([id]) { mark in
            if let shape = mark.shape {
                mark.shape = shape.resized(to: rect, aspect: aspect)
                mark.rect = mark.shape!.bounds(aspect: aspect)
            } else {
                mark.rect = rect
            }
        }
    }

    /// Turns a box drawn by hand further, in radians.
    mutating func turn(_ id: Int, by angle: CGFloat) {
        guard let mark = marks.first(where: { $0.id == id }), case .box = mark.shape else { return }
        let aspect = self.aspect
        change([id]) { mark in
            mark.shape = mark.shape?.turned(by: angle)
            mark.rect = mark.shape!.bounds(aspect: aspect)
        }
    }

    /// Gives strokes of the marker another width.
    mutating func widen(_ ids: Set<Int>, to width: CGFloat) {
        let strokes = Set(marks.filter { ids.contains($0.id) && Self.isStroke($0.shape) }.map(\.id))
        let aspect = self.aspect
        change(strokes) { mark in
            mark.shape = mark.shape?.widened(to: width)
            mark.rect = mark.shape!.bounds(aspect: aspect)
        }
    }

    /// Removes what was hidden by hand, and uncovers what Snapfly found:
    /// the original shows there again, in this picture only.
    mutating func remove(_ ids: Set<Int>) {
        let chosen = marks.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        var change = Change(touchedBefore: touched, touchedAfter: touched.union(ids))
        for mark in chosen {
            change.before[mark.id] = mark
            if mark.origin == .hand {
                change.after.updateValue(nil, forKey: mark.id)
            } else if mark.covered {
                var left = mark
                left.covered = false
                change.after[mark.id] = left
            } else {
                change.before.removeValue(forKey: mark.id)
            }
        }
        guard !change.after.isEmpty else { return }
        record(change)
    }

    /// The marks an eraser touches, drawn through these points with this
    /// reach, from 0 to 1 across the picture's width: those hidden by hand,
    /// and those covered by Snapfly.
    func erased(along points: [CGPoint], reach: CGFloat) -> Set<Int> {
        let room = reach * aspect
        return Set(marks.filter { mark in
            guard mark.covered else { return false }
            if let shape = mark.shape {
                return points.contains { shape.contains($0, aspect: aspect, room: room) }
            }
            let near = mark.rect.insetBy(dx: -reach, dy: -room)
            return points.contains { near.contains($0) }
        }.map(\.id))
    }

    /// Everything hidden by hand taken away, as one change.
    mutating func clearHand() {
        remove(Set(marks.filter { $0.origin == .hand }.map(\.id)))
    }

    /// Back to what Snapfly found: nothing by hand, everything found covered
    /// and everything offered left, as one change that can be undone.
    mutating func resetToFound() {
        var change = Change(touchedBefore: touched, touchedAfter: [])
        for mark in marks {
            if mark.origin == .hand {
                change.before[mark.id] = mark
                change.after.updateValue(nil, forKey: mark.id)
            } else if mark.covered != (mark.origin == .found) || touched.contains(mark.id) {
                var reset = mark
                reset.covered = mark.origin == .found
                change.before[mark.id] = mark
                change.after[mark.id] = reset
            }
        }
        guard !change.after.isEmpty || !touched.isEmpty else { return }
        record(change)
    }

    var canUndo: Bool { !done.isEmpty }
    var canRedo: Bool { !undone.isEmpty }
    /// Whether anything is hidden by hand, to take away.
    var hasHand: Bool { marks.contains { $0.origin == .hand } }
    /// Whether the owner changed anything Snapfly did.
    var isChanged: Bool { hasHand || !touched.isEmpty }

    mutating func undo() {
        guard let change = done.popLast() else { return }
        apply(change.before, touched: change.touchedBefore)
        undone.append(change)
    }

    mutating func redo() {
        guard let change = undone.popLast() else { return }
        apply(change.after, touched: change.touchedAfter)
        done.append(change)
    }

    /// Changes marks as the owner did, as one change.
    private mutating func change(_ ids: Set<Int>, _ edit: (inout Mark) -> Void) {
        var change = Change(touchedBefore: touched, touchedAfter: touched.union(ids))
        for index in marks.indices where ids.contains(marks[index].id) {
            var mark = marks[index]
            edit(&mark)
            guard mark != marks[index] else { continue }
            change.before[mark.id] = marks[index]
            change.after[mark.id] = mark
        }
        guard !change.after.isEmpty else { return }
        record(change)
    }

    private mutating func record(_ change: Change) {
        apply(change.after, touched: change.touchedAfter)
        done.append(change)
        undone.removeAll()
    }

    private mutating func apply(_ state: [Int: Mark?], touched: Set<Int>) {
        for (id, mark) in state {
            if let mark {
                if let index = marks.firstIndex(where: { $0.id == id }) {
                    marks[index] = mark
                } else {
                    marks.insert(mark, at: marks.firstIndex { $0.id > id } ?? marks.endIndex)
                }
            } else {
                marks.removeAll { $0.id == id }
            }
        }
        self.touched = touched
    }

    private static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// How far a mark between these edges may move along one side and stay
    /// on the picture.
    private static func clamp(_ offset: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(offset, min(0, -low)), max(0, 1 - high))
    }

    private static func isStroke(_ shape: HandShape?) -> Bool {
        if case .stroke = shape { return true }
        return false
    }

    // MARK: What it comes to

    /// The places to cover, as the copy is made.
    var covered: [Finder.Area] {
        marks.filter(\.covered).map {
            Finder.Area(rect: $0.rect, kind: $0.kind, text: $0.text, check: $0.check, shape: $0.shape)
        }
    }

    /// The places the owner chose to leave, which the check of the copy
    /// leaves too.
    var left: [CGRect] {
        marks.filter { !$0.covered && $0.origin != .hand }.map(\.rect)
    }

    /// The mark a finger means at a point: one drawn by hand where its
    /// shape is, else the smallest under it, as marks lie over each other.
    func mark(at point: CGPoint) -> Mark? {
        marks.filter { mark in
            if let shape = mark.shape { return shape.contains(point, aspect: aspect, room: 0.01) }
            return mark.rect.insetBy(dx: -0.01, dy: -0.005).contains(point)
        }
        .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// What is covered, kind by kind, for the summary.
    var report: CoverReport {
        CoverReport(marks.filter { $0.covered && $0.origin != .hand }.map {
            Finder.Area(rect: $0.rect, kind: $0.kind, check: $0.check)
        }, hand: marks.filter { $0.covered && $0.origin == .hand }.count)
    }

    /// Whether a mark still waits for the owner: covered though not sure,
    /// or only offered, and not decided on.
    func needsCheck(_ mark: Mark) -> Bool {
        mark.check && !touched.contains(mark.id) && (mark.covered || mark.origin == .possible)
    }

    /// Places covered that should be checked, and places only offered,
    /// that the owner has not decided on yet.
    var toCheck: Int { marks.filter(needsCheck).count }

    var tally: Tally {
        var tally = Tally()
        for mark in marks {
            if needsCheck(mark) {
                tally.toCheck += 1
                if !mark.covered { tally.exposed += 1 }
            } else if mark.covered {
                tally.covered += 1
            } else {
                tally.left += 1
            }
        }
        return tally
    }

    /// Whether the owner has decided on a mark, by changing it.
    func isDecided(_ id: Int) -> Bool { touched.contains(id) }
}
