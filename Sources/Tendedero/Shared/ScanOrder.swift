import Foundation

/// The order of a scanned document's pages: as the photos were chosen, one
/// moved to another's place with the rest closing up, one taken away.
enum ScanOrder {
    /// The item at `from` moved to `place`, kept within the document.
    static func moving<Item>(_ items: [Item], from: Int, to place: Int) -> [Item] {
        guard items.indices.contains(from) else { return items }
        var moved = items
        let item = moved.remove(at: from)
        moved.insert(item, at: min(max(place, 0), moved.count))
        return moved
    }
}
