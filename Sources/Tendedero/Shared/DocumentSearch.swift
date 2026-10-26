import Foundation

/// Finding words in the documents kept on the iPhone, page by page, as See
/// All finds them in screenshots: every word searched for on the same page,
/// folded so case, accents and widths do not matter. It says where they
/// stand, the pages and how often, never the words around them. Pure, so
/// it is checked without a document.
enum DocumentSearch {
    /// Where a document holds what was searched for.
    struct Found: Equatable, Sendable {
        /// The pages that hold every word, counted from 1.
        var pages: [Int]
        /// How often the words stand there together: on each page, as often
        /// as the rarest of them, added up.
        var count: Int
    }

    /// The words searched for, folded; none for a search of spaces.
    static func words(_ search: String) -> [String] {
        LibraryQuery.fold(search).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// What a document's pages hold of a search, each page's words as
    /// read; nil where no page holds every word.
    static func find(_ search: String, in pages: [String]) -> Found? {
        let words = words(search)
        guard !words.isEmpty else { return nil }
        var found = Found(pages: [], count: 0)
        for (index, page) in pages.enumerated() {
            let said = LibraryQuery.fold(page)
            let counts = words.map { occurrences(of: $0, in: said) }
            guard let least = counts.min(), least > 0 else { continue }
            found.pages.append(index + 1)
            found.count += least
        }
        return found.pages.isEmpty ? nil : found
    }

    private static func occurrences(of word: String, in text: String) -> Int {
        var count = 0
        var rest = text.startIndex..<text.endIndex
        while let match = text.range(of: word, range: rest) {
            count += 1
            rest = match.upperBound..<text.endIndex
        }
        return count
    }

    /// Where it stands, said short: "Seite 2 · 3 Treffer", "Seiten 2, 5 · 4
    /// Treffer"; past three pages, the first three and how many more.
    static func label(_ found: Found) -> String {
        let pages: String
        if found.pages.count == 1 {
            pages = String(format: L("Page %d"), found.pages[0])
        } else {
            let first = found.pages.prefix(3).map(String.init).joined(separator: ", ")
            let more = found.pages.count > 3 ? " " + String(format: L("+%d more"), found.pages.count - 3) : ""
            pages = String(format: L("Pages %@"), first + more)
        }
        let count = found.count == 1 ? L("1 match") : String(format: L("%d matches"), found.count)
        return pages + " · " + count
    }
}
