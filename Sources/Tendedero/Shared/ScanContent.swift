import Foundation

/// Whether cleaning a page kept its text: the page is read before its light
/// is cleaned and after, and every number read before must be read after,
/// where it was, and the lines read must not drop by more than a few. Where
/// less is read, the place is marked beside the page, never on it. It can
/// only tell what the reading tells, so it never says a page was verified.
enum ScanContent {
    /// A line read on the page.
    struct Line: Equatable, Sendable {
        let text: String
        /// From 0 to 1 from the bottom left, as Vision gives it.
        let box: CGRect
    }

    /// The share of lines that may be gone, and how many at least, before
    /// it counts: a reading is never quite the same twice.
    static let linesKept = 0.9
    static let fewestGone = 2
    /// Lines with fewer letters and digits than this are not counted.
    static let shortest = 3

    /// The places where less was read after cleaning: each line with a
    /// number read before and not after, and, when enough lines are gone,
    /// each line gone. Empty when everything read before was read again.
    static func lost(before: [Line], after: [Line]) -> [CGRect] {
        var places: [CGRect] = []
        for line in before {
            let numbers = self.numbers(in: line.text)
            guard !numbers.isEmpty else { continue }
            let read = after.filter { sameRow($0.box, line.box) }
                .sorted { $0.box.minX < $1.box.minX }
                .map { digits(in: $0.text) }
                .joined()
            if numbers.contains(where: { !read.contains($0) }) { places.append(line.box) }
        }
        let counted = before.filter { letters(in: $0.text) >= shortest }
        let left = after.filter { letters(in: $0.text) >= shortest }
        if Double(left.count) < Double(counted.count) * linesKept, counted.count - left.count >= fewestGone {
            for line in counted where !after.contains(where: { sameRow($0.box, line.box) }) {
                places.append(line.box)
            }
        }
        return merged(places)
    }

    /// The numbers in a line, each as its digits alone: digits with dots,
    /// commas, colons, slashes, dashes, apostrophes or single spaces between
    /// them are one number, as "1.234,56" or "DE89 3704". Single digits are
    /// left out: they are read too unsurely to count.
    static func numbers(in text: String) -> [String] {
        var numbers: [String] = []
        var current = ""
        var gap = false
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
                gap = false
            } else if !current.isEmpty, !gap, ".,:/-' ".contains(character) {
                gap = true
            } else {
                if current.count >= 2 { numbers.append(current) }
                current = ""
                gap = false
            }
        }
        if current.count >= 2 { numbers.append(current) }
        return numbers
    }

    /// A line's digits, nothing else.
    static func digits(in text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    static func letters(in text: String) -> Int {
        text.filter { $0.isLetter || $0.isNumber }.count
    }

    /// Whether two lines are read in the same place: overlapping across,
    /// and sharing at least half of the lower one's height.
    static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let across = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return across > -0.01 && shared >= 0.5 * min(a.height, b.height)
    }

    /// Places that touch, as one.
    static func merged(_ places: [CGRect]) -> [CGRect] {
        var merged: [CGRect] = []
        for place in places {
            var grown = place
            while let i = merged.firstIndex(where: { $0.insetBy(dx: -0.005, dy: -0.005).intersects(grown) }) {
                grown = grown.union(merged.remove(at: i))
            }
            merged.append(grown)
        }
        return merged
    }
}
