import CoreGraphics
import Foundation

/// A picture being protected, place by place: what Snapfly found and
/// covers, what it only offers to cover, what the owner covered by hand, and
/// what the owner turned on or off. The owner's changes can be undone and
/// done again; what Snapfly finds later, as Apple Intelligence answers or
/// the copy is checked, joins without touching them. Pure, so it is checked
/// without a picture.
struct ProtectionPlan: Equatable {
    /// One place on the picture.
    struct Mark: Equatable, Identifiable {
        enum Origin: Equatable {
            /// Found by Snapfly, covered unless the owner turns it off.
            case found
            /// May be private, like a line shaped like a name that nothing
            /// vouches for: offered, covered only when the owner says so.
            case possible
            /// Covered by the owner's hand.
            case hand
        }

        let id: Int
        /// From 0 to 1 from the bottom left, with its margin, as covered.
        let rect: CGRect
        let kind: PrivateDetail?
        var origin: Origin
        /// Covered, though it is not clear it should be: shown to be checked.
        var check: Bool
        var covered: Bool
        /// What it hides, to check the copy by; never shown or written down.
        let text: String?
    }

    private(set) var marks: [Mark] = []
    private var done: [Change] = []
    private var undone: [Change] = []
    private var nextID = 0
    /// Marks the owner turned on or off, which Snapfly no longer changes.
    private var touched: Set<Int> = []

    /// A change of the owner's, as it can be undone.
    private enum Change: Equatable {
        case toggled(Int)
        case added(Mark)
    }

    init() {}

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
        guard flip(id) else { return }
        done.append(.toggled(id))
        undone.removeAll()
    }

    /// Covers a part of the picture by hand, from 0 to 1 from the bottom
    /// left. A part too small to see is left.
    mutating func cover(_ rect: CGRect) {
        let rect = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width >= 0.005, rect.height >= 0.003 else { return }
        let mark = Mark(id: nextID, rect: rect, kind: nil, origin: .hand, check: false, covered: true, text: nil)
        append(mark)
        touched.insert(mark.id)
        done.append(.added(mark))
        undone.removeAll()
    }

    var canUndo: Bool { !done.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    mutating func undo() {
        guard let change = done.popLast() else { return }
        switch change {
        case .toggled(let id): flip(id)
        case .added(let mark): marks.removeAll { $0.id == mark.id }
        }
        undone.append(change)
    }

    mutating func redo() {
        guard let change = undone.popLast() else { return }
        switch change {
        case .toggled(let id): flip(id)
        case .added(let mark): marks.append(mark)
        }
        done.append(change)
    }

    @discardableResult
    private mutating func flip(_ id: Int) -> Bool {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return false }
        marks[index].covered.toggle()
        touched.insert(id)
        return true
    }

    // MARK: What it comes to

    /// The places to cover, as the copy is made.
    var covered: [Finder.Area] {
        marks.filter(\.covered).map { Finder.Area(rect: $0.rect, kind: $0.kind, text: $0.text, check: $0.check) }
    }

    /// The places the owner chose to leave, which the check of the copy
    /// leaves too.
    var left: [CGRect] {
        marks.filter { !$0.covered && $0.origin != .hand }.map(\.rect)
    }

    /// The smallest mark at a point, from 0 to 1 from the bottom left: the
    /// one a finger means where marks lie over each other.
    func mark(at point: CGPoint) -> Mark? {
        marks.filter { $0.rect.insetBy(dx: -0.01, dy: -0.005).contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// What is covered, kind by kind, for the summary.
    var report: CoverReport {
        CoverReport(marks.filter { $0.covered && $0.origin != .hand }.map {
            Finder.Area(rect: $0.rect, kind: $0.kind, check: $0.check)
        }, hand: marks.filter { $0.covered && $0.origin == .hand }.count)
    }

    /// Places covered that should be checked, and places only offered,
    /// that the owner has not decided on yet.
    var toCheck: Int {
        marks.filter { $0.check && !touched.contains($0.id) && ($0.covered || $0.origin == .possible) }.count
    }

    /// Whether the owner has decided on a mark, by turning it on or off.
    func isDecided(_ id: Int) -> Bool { touched.contains(id) }
}
