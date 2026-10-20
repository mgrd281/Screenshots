import Foundation

/// The screenshots protected lately, on the iPhone's Protected tab: their
/// identifiers in Photos, newest first, twelve at most. What noting one,
/// taking some off and putting them back do to the list.
enum ProtectedList {
    static let limit = 12

    /// What was taken off, each with the place it had, so it can go back.
    struct Removal: Equatable {
        fileprivate(set) var places: [Place] = []

        struct Place: Equatable {
            let index: Int
            let id: String
        }

        var count: Int { places.count }
        var isEmpty: Bool { places.isEmpty }
        var ids: [String] { places.map(\.id) }
    }

    /// One more protected: first, and only once.
    static func noting(_ id: String, in list: [String]) -> [String] {
        Array(([id] + list.filter { $0 != id }).prefix(limit))
    }

    /// The list without those taken off, and what was, in the list's order.
    static func removing(_ ids: Set<String>, from list: [String]) -> (list: [String], removal: Removal) {
        var removal = Removal()
        var kept: [String] = []
        for (index, id) in list.enumerated() {
            if ids.contains(id) {
                removal.places.append(Removal.Place(index: index, id: id))
            } else {
                kept.append(id)
            }
        }
        return (kept, removal)
    }

    /// Those taken off, back in the places they had; one protected again
    /// meanwhile stays where it is now.
    static func restoring(_ removal: Removal, into list: [String]) -> [String] {
        var list = list
        for place in removal.places.sorted(by: { $0.index < $1.index }) where !list.contains(place.id) {
            list.insert(place.id, at: min(place.index, list.count))
        }
        return Array(list.prefix(limit))
    }
}
