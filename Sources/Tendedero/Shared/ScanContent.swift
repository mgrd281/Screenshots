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
    static func lost(before: [Line], after: [Line], crossed: (CGRect) -> Bool = { _ in false }) -> [CGRect] {
        var places: [CGRect] = []
        // A line a signature or a stamp crosses, or runs close along, reads
        // one way one time and another the next, cleaned or not: it says
        // nothing of the cleaning.
        let before = before.filter { !crossed($0.box.insetBy(dx: 0, dy: -1.5 * $0.box.height)) }
        for line in before {
            let numbers = self.numbers(in: line.text)
            guard !numbers.isEmpty else { continue }
            let row: [Line] = after.filter { sameRow($0.box, line.box) }
            let ordered: [Line] = row.sorted { $0.box.minX < $1.box.minX }
            let read: String = ordered.map { digits(in: readAsDigits($0.text)) }.joined()
            if numbers.contains(where: { !read.contains($0) }) { places.append(line.box) }
        }
        let counted = before.filter { letters(in: $0.text) >= shortest }
        let left = after.filter { letters(in: $0.text) >= shortest }
        let kept: Double = Double(counted.count) * linesKept
        if Double(left.count) < kept, counted.count - left.count >= fewestGone {
            for line in counted where !after.contains(where: { sameRow($0.box, line.box) }) {
                places.append(line.box)
            }
        }
        return merged(places)
    }

    /// A line read before cleaning, and how sure the reading was of it,
    /// from 0 to 1.
    struct Read: Equatable, Sendable {
        let text: String
        let box: CGRect
        let confidence: Float
    }

    /// How sure a reading must be of a line before cleaning for what it
    /// says to count as what the page says.
    static let sure: Float = 0.9

    /// The lines whose reading changed with cleaning (`ScanCleaner`'s
    /// guard): each line read surely before, of a few letters at least,
    /// whose every character, an umlaut's dots, an accent, an @ and a digit
    /// among them, is not read in the same order on its row after. Spaces
    /// do not count, and more read after, as a neighbour's words joined to
    /// the line, is not less. Cleaning may make text clearer, never
    /// different, so each of these is cleaned again more gently.
    static func changed(before: [Read], after: [Line]) -> [CGRect] {
        before.compactMap { line in
            guard line.confidence >= sure, letters(in: line.text) >= shortest else { return nil }
            let row = after.filter { sameRow($0.box, line.box) }.sorted { $0.box.minX < $1.box.minX }
            let read = compact(row.map(\.text).joined())
            return read.contains(compact(line.text)) ? nil : line.box
        }
    }

    /// Whether a line read after cleaning says what it said before: every
    /// character in the same order, spaces aside.
    static func says(_ after: String, _ before: String) -> Bool {
        compact(after).contains(compact(before))
    }

    /// A line's characters without its spaces, each as it was read.
    static func compact(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    /// Whether a ballpoint's or a stamp's colour crosses print in a place,
    /// from 0 to 1 from the bottom left: strongly coloured strokes over a
    /// hundredth of it, among grey or black print. A line printed in colour,
    /// with no grey print, is not crossed.
    static func crossed(_ page: ScanBitmap, _ box: CGRect) -> Bool {
        let w = Double(page.width), h = Double(page.height)
        let x0 = max(0, Int(box.minX * w)), x1 = min(page.width, Int((box.maxX * w).rounded(.up)))
        let y0 = max(0, Int((1 - box.maxY) * h)), y1 = min(page.height, Int(((1 - box.minY) * h).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return false }
        var coloured = 0, grey = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * page.width + x) * 4
                let r = Int(page.pixels[i]), g = Int(page.pixels[i + 1]), b = Int(page.pixels[i + 2])
                let top = max(r, g, b), spread = top - min(r, g, b)
                if spread >= 60, top < 235 { coloured += 1 } else if spread < 30, top < 140 { grey += 1 }
            }
        }
        let all = (x1 - x0) * (y1 - y0)
        return coloured * 100 >= all && grey * 50 >= all
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

    /// A line with the letters a reading takes for digits, beside a digit,
    /// read as those digits: "Z00.0" as "200.0", "O4O-12" as "040-12", "1b" as "16". A
    /// typewriter's Z and 2, or O and 0, are read either way from one reading
    /// to the next, and that is not a number lost.
    static func readAsDigits(_ text: String) -> String {
        let alike: [Character: Character] = ["Z": "2", "z": "2", "O": "0", "o": "0", "D": "0", "I": "1", "l": "1",
                                              "|": "1", "S": "5", "s": "5", "B": "8", "b": "6", "G": "6", "g": "9"]
        let characters = Array(text)
        func digitNear(_ i: Int) -> Bool {
            for j in [i - 1, i + 1] where j >= 0 && j < characters.count {
                if characters[j].isASCII, characters[j].isNumber { return true }
            }
            return false
        }
        return String(characters.indices.map { i in
            if let digit = alike[characters[i]], digitNear(i) { return digit }
            return characters[i]
        })
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
        let shared: CGFloat = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let across: CGFloat = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let half: CGFloat = 0.5 * min(a.height, b.height)
        return across > -0.01 && shared >= half
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
