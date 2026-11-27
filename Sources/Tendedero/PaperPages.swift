import Foundation

/// A picture too long for one page of paper, like a whole page of a
/// website, put on pages of A4 or US Letter one below the other for Make
/// PDF: as wide as the paper less 10 mm round it, with every pixel kept, so
/// it reads sharp, and cut where a row is the same as the rows beside it,
/// as between two lines of text, so no line is cut in half.
enum PaperPages {
    /// Where the picture goes on a sheet, in points from its bottom left.
    static func room(on paper: CGSize) -> CGRect {
        CGRect(origin: .zero, size: paper).insetBy(dx: PaperSize.margin, dy: PaperSize.margin)
    }

    /// How many rows of a picture this many pixels wide fill one sheet.
    static func rowsPerPage(width: Int, paper: CGSize) -> Int {
        let room = room(on: paper)
        guard room.width > 0 else { return 1 }
        return max(1, Int((CGFloat(max(width, 1)) * room.height / room.width).rounded(.down)))
    }

    /// Whether a picture is too long for one sheet: more than two of them.
    /// A whole page goes on sheets whatever its length.
    static func needed(width: Int, height: Int, paper: CGSize) -> Bool {
        height > 2 * rowsPerPage(width: width, paper: paper)
    }

    /// The rows on each sheet, top first: as many as fit, less those below
    /// the last quiet row in the sheet's last fifth, so a line of text goes
    /// whole to the next sheet. With no quiet row there, the sheet is full.
    /// Every row is on exactly one sheet.
    /// - Parameter quiet: for each row, whether it is the same as the rows
    ///   beside it.
    static func cuts(quiet: [Bool], perPage: Int) -> [Range<Int>] {
        let total = quiet.count
        let perPage = max(1, perPage)
        var pages: [Range<Int>] = []
        var start = 0
        while start < total {
            let full = start + perPage
            guard full < total else {
                pages.append(start..<total)
                break
            }
            let lowest = max(start + 1, full - perPage / 5)
            let cut = stride(from: full, through: lowest, by: -1).first { quiet[$0] } ?? full
            pages.append(start..<cut)
            start = cut
        }
        return pages
    }

    /// For each row of samples, whether it is the same as the rows above
    /// and below it, give or take `tolerance`: a gap between lines, a plain
    /// stretch, never a row through text.
    static func quiet(_ rows: [[UInt8]], tolerance: Int = 3) -> [Bool] {
        func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
            a.count == b.count && a.indices.allSatisfy { abs(Int(a[$0]) - Int(b[$0])) <= tolerance }
        }
        return rows.indices.map { r in
            (r == 0 || same(rows[r], rows[r - 1])) && (r + 1 == rows.count || same(rows[r], rows[r + 1]))
        }
    }
}
