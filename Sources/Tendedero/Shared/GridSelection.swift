import Foundation

/// Several screenshots chosen at once in the iPhone's grids, as in Photos:
/// a tap turns one on or off; a finger drawn sideways across the grid, then
/// on in any direction, takes in every card between the one it started on
/// and the one under it, in reading order, all turned on or all turned off
/// as that first card was turned.
struct GridSelection: Equatable {
    /// The screenshots chosen, by their identifier in Photos.
    private(set) var chosen: Set<String> = []
    private var sweep: Sweep?

    /// A finger being drawn: where it started, whether it turns cards on,
    /// and what was chosen before it.
    private struct Sweep: Equatable {
        let start: Int
        let on: Bool
        let before: Set<String>
    }

    init(_ chosen: Set<String> = []) {
        self.chosen = chosen
    }

    var count: Int { chosen.count }
    var isEmpty: Bool { chosen.isEmpty }

    func contains(_ id: String) -> Bool { chosen.contains(id) }

    mutating func toggle(_ id: String) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }

    /// Every one shown, or, when all of them already are, none.
    mutating func toggleAll(_ ids: [String]) {
        chosen = ids.allSatisfy(chosen.contains) ? [] : Set(ids)
    }

    /// Only those still to be done again, after the others went.
    mutating func keep(_ ids: Set<String>) {
        chosen = chosen.intersection(ids)
    }

    // MARK: Drawing a finger across

    /// A finger starts on a card: it turns cards on, unless that card was on.
    mutating func begin(at index: Int, in ids: [String]) {
        guard ids.indices.contains(index) else { return }
        sweep = Sweep(start: index, on: !chosen.contains(ids[index]), before: chosen)
        move(to: index, in: ids)
    }

    /// The finger over another card: every card from the first to this one
    /// is turned as the first was; those it has left are as they were before.
    mutating func move(to index: Int, in ids: [String]) {
        guard let sweep, !ids.isEmpty else { return }
        let start = min(sweep.start, ids.count - 1)
        let end = min(max(index, 0), ids.count - 1)
        let range = Set(ids[min(start, end)...max(start, end)])
        chosen = sweep.on ? sweep.before.union(range) : sweep.before.subtracting(range)
    }

    mutating func end() {
        sweep = nil
    }

    var isSweeping: Bool { sweep != nil }

    // MARK: Where the finger is

    /// The card under a point of a grid of square cards, `columns` to a row
    /// across `width`, `spacing` apart: a point in a gap counts for the card
    /// before it, one past the last row or the last card for the last card,
    /// and one above the grid or off its sides for the nearest. Nil when
    /// there are no cards.
    static func index(atX x: Double, y: Double, width: Double, columns: Int, spacing: Double, count: Int) -> Int? {
        guard count > 0, columns > 0, width > 0 else { return nil }
        let cell = (width - spacing * Double(columns - 1)) / Double(columns)
        let step = cell + spacing
        guard step > 0 else { return nil }
        let column = min(max(Int((x / step).rounded(.down)), 0), columns - 1)
        let row = max(Int((y / step).rounded(.down)), 0)
        return min(row * columns + column, count - 1)
    }
}
