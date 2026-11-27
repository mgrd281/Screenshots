import CoreGraphics

/// Joins the views of a page, taken one after the other while it scrolls,
/// into one picture of the whole page. Each view is reduced to a few values
/// a row; comparing rows finds the parts that stay put while the page moves,
/// like the browser's toolbar or a site's sticky header, and how far the page
/// moved between two views. Those parts are kept once, and only the rows new
/// in each view are added below the last.
enum PageStitch {
    /// Samples per row: enough to tell rows apart, few enough to compare fast.
    static let samples = 48

    /// One view, a row of gray samples for each row of pixels, top first.
    typealias Rows = [[UInt8]]

    /// How one view follows the one before it.
    struct Step: Equatable {
        /// Rows at the top that did not move: toolbar, sticky header.
        var top: Int
        /// Rows at the bottom that did not move: a cookie bar, a footer bar.
        var bottom: Int
        /// How many rows the page moved. Zero at the end of the page.
        var shift: Int
    }

    /// Two rows show the same thing, give or take the smoothing of a scaled
    /// picture.
    static func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > 6 { return false }
        return true
    }

    /// Two views show the same place on the page, give or take a few rows
    /// that move by themselves, like a carousel or a spinner: at least nine
    /// rows in ten are the same.
    static func alike(_ a: Rows, _ b: Rows) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let differing = a.indices.filter { !same(a[$0], b[$0]) }.count
        return differing * 10 <= a.count
    }

    /// The columns, as samples, where two views differ: the part of the
    /// window that scrolled between them, like a chat's own box beside a
    /// list of chats that stays put. The run around `column`, bridging up
    /// to three columns that stayed the same, like a margin in the box.
    /// Nil when nothing changed at or beside `column`.
    static func band(_ a: Rows, _ b: Rows, around column: Int) -> Range<Int>? {
        guard a.count == b.count, let width = a.first?.count, width > 0,
              a.allSatisfy({ $0.count == width }), b.allSatisfy({ $0.count == width }) else { return nil }
        let changed = (0..<width).map { c in a.indices.contains { abs(Int(a[$0][c]) - Int(b[$0][c])) > 6 } }
        let at = min(max(column, 0), width - 1)
        guard let start = (0...3).flatMap({ [at - $0, at + $0] })
            .first(where: { (0..<width).contains($0) && changed[$0] }) else { return nil }
        var lower = start
        var gap = 0
        for c in stride(from: start - 1, through: 0, by: -1) {
            if changed[c] { lower = c; gap = 0 } else { gap += 1; if gap > 3 { break } }
        }
        var upper = start + 1
        gap = 0
        for c in (start + 1)..<max(start + 1, width) {
            if changed[c] { upper = c + 1; gap = 0 } else { gap += 1; if gap > 3 { break } }
        }
        return lower..<upper
    }

    /// Only these columns of each row, to compare the part that scrolls.
    static func columns(_ rows: Rows, _ band: Range<Int>) -> Rows {
        rows.map { row in
            let kept = band.clamped(to: 0..<row.count)
            return Array(row[kept])
        }
    }

    /// The rows of an image, as gray samples.
    static func rows(of image: CGImage) -> Rows? {
        let height = image.height
        guard height > 0, let context = CGContext(data: nil, width: samples, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: samples, space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: samples, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: samples * height)
        // A bitmap context keeps its top row first in memory.
        return (0..<height).map { row in Array(UnsafeBufferPointer(start: bytes + row * samples, count: samples)) }
    }

    /// How `next` follows `previous`, or nil when no move fits, as when the
    /// page changed by itself in between. `expected` is roughly how many rows
    /// it was asked to move; it settles a tie on a plain stretch of page.
    /// - Parameters:
    ///   - fresh: how many of `previous`'s lowest rows to leave out, the
    ///     ones that came into view last (`seam`).
    ///   - farthest: the longest move to try, when the page cannot have
    ///     moved farther; a long move leaves few rows to compare, and a few
    ///     plain ones line up anywhere.
    ///   - telling: how many rows with something on them must line up for a
    ///     move to count, so a few plain rows that line up anywhere do not.
    static func step(from previous: Rows, to next: Rows, expected: Int, fresh: Int = 0,
                     farthest: Int? = nil, telling: Int = 0) -> Step? {
        let height = min(previous.count, next.count)
        guard height > 0 else { return nil }
        // Nothing moved: the end of the page.
        if (0..<height).allSatisfy({ same(previous[$0], next[$0]) }) { return Step(top: 0, bottom: 0, shift: 0) }
        // Bars that stay put are a part of the window, never most of it; a
        // plain stretch of page can look still too, and must not pass for one.
        let most = height * 35 / 100
        var top = 0
        while top < most, same(previous[top], next[top]) { top += 1 }
        var bottom = 0
        while bottom < most, same(previous[height - 1 - bottom], next[height - 1 - bottom]) { bottom += 1 }
        let middle = height - top - bottom
        guard middle > 8 else { return nil }

        let fresh = leftOut(fresh, middle: middle, expected: expected)
        let shown = telling > 0 ? previous.map { row in (row.max() ?? 0) - (row.min() ?? 0) > 12 } : []

        // The move that lines up most of what both views show.
        var best: (shift: Int, score: Double)?
        for shift in 1..<middle {
            let overlap = middle - shift - fresh
            guard overlap >= 8, shift <= farthest ?? shift else { break }
            // A header that shrinks as the page scrolls may differ; the rest must match.
            let allowed = overlap / 5
            var misses = 0, told = 0
            for i in 0..<overlap {
                if !same(previous[top + shift + i], next[top + i]) {
                    misses += 1
                    if misses > allowed { break }
                } else if telling > 0, shown[top + shift + i] {
                    told += 1
                }
            }
            guard misses <= allowed, told >= telling else { continue }
            let score = Double(overlap - misses) / Double(overlap) - Double(abs(shift - expected)) / Double(middle * 100)
            if best == nil || score > best!.score { best = (shift, score) }
        }
        return best.map { Step(top: top, bottom: bottom, shift: $0.shift) }
    }

    /// How many of the lowest rows of a view to leave out when it is matched
    /// with the next, of the `fresh` asked: never more than half of what the
    /// two views share at the move expected, so enough is left to go by.
    static func leftOut(_ fresh: Int, middle: Int, expected: Int) -> Int {
        min(max(fresh, 0), max(0, middle - expected) / 2)
    }

    /// How `next` follows `previous` when `step` finds no move: something
    /// stayed put over part of the width, like a column that sticks beside
    /// one that scrolls or a scroll bar, or changed by itself in a few
    /// places, like a picture that loaded or a card under the pointer. The
    /// columns that stayed where they were are left out, and so are rows
    /// with nothing to tell them apart; the move that lines up most of the
    /// rest wins, when it lines up most of them. A move of nothing, with only
    /// a few rows changed, is the end of the page with something moving on
    /// it, like a video. For a whole page only: a chat is read strictly.
    /// - Parameter farthest: the longest move to try, when the page cannot
    ///   have moved farther.
    static func follow(from previous: Rows, to next: Rows, expected: Int, fresh: Int = 0,
                       farthest: Int? = nil) -> Step? {
        let height = min(previous.count, next.count)
        guard height > 0, let width = previous.first?.count, width > 0,
              previous.prefix(height).allSatisfy({ $0.count == width }),
              next.prefix(height).allSatisfy({ $0.count == width }) else { return nil }
        if (0..<height).allSatisfy({ same(previous[$0], next[$0]) }) { return Step(top: 0, bottom: 0, shift: 0) }
        let most = height * 35 / 100
        var top = 0
        while top < most, same(previous[top], next[top]) { top += 1 }
        var bottom = 0
        while bottom < most, same(previous[height - 1 - bottom], next[height - 1 - bottom]) { bottom += 1 }
        let middle = height - top - bottom
        guard middle > 8 else { return nil }
        let fresh = leftOut(fresh, middle: middle, expected: expected)

        // Columns that stayed where they were in nine rows of ten.
        let inMiddle = top..<(top + middle)
        let moving = (0..<width).filter { c in
            let stayed = inMiddle.reduce(0) { $0 + (abs(Int(previous[$1][c]) - Int(next[$1][c])) <= 6 ? 1 : 0) }
            return stayed * 10 < middle * 9
        }
        guard !moving.isEmpty else { return nil }
        func alike(_ a: [UInt8], _ b: [UInt8]) -> Bool {
            moving.allSatisfy { abs(Int(a[$0]) - Int(b[$0])) <= 6 }
        }
        // Two rows line up when at least half of what moved does: the rest
        // may be a column that has just stopped sticking, or a button.
        func lineUp(_ a: [UInt8], _ b: [UInt8]) -> Bool {
            moving.reduce(0) { $0 + (abs(Int(a[$1]) - Int(b[$1])) <= 6 ? 1 : 0) } * 2 >= moving.count
        }
        // A row tells where it is when something runs across it and it is
        // not the same as a row beside it, as the rows of a plain box are.
        func telling(_ rows: Rows) -> [Bool] {
            (0..<height).map { r in
                guard inMiddle.contains(r) else { return false }
                var low = 255, high = 0
                for c in moving {
                    low = min(low, Int(rows[r][c]))
                    high = max(high, Int(rows[r][c]))
                }
                guard high - low > 12 else { return false }
                return (r > 0 && !alike(rows[r], rows[r - 1])) || (r + 1 < height && !alike(rows[r], rows[r + 1]))
            }
        }
        let before = telling(previous), after = telling(next)

        var best: (shift: Int, score: Double)?
        for shift in 0..<middle {
            // Enough rows to go by, an eighth of what scrolls: a few short
            // lines line up with plain rows at almost any move.
            let overlap = middle - shift - fresh
            guard overlap >= max(8, middle / 8), shift <= farthest ?? shift else { break }
            var told = 0, hits = 0
            for i in 0..<overlap {
                let p = top + shift + i, n = top + i
                guard before[p] || after[n] else { continue }
                told += 1
                if lineUp(previous[p], next[n]) { hits += 1 }
                // Six rows in ten can no longer line up.
                if (told - hits) * 10 > overlap * 4 { break }
            }
            guard hits >= 16, hits * 10 >= told * 6 else { continue }
            // Of moves that fit as well, the one asked for.
            let score = Double(hits) / Double(told) - Double(abs(shift - expected)) / Double(middle * 100)
            if best == nil || score > best!.score { best = (shift, score) }
        }
        return best.map { Step(top: top, bottom: bottom, shift: $0.shift) }
    }

    /// Where the strip of the earlier of two views ends, in its rows: above
    /// its `fresh` lowest rows, which came into view last. The later view
    /// shows them higher up and longer in view, with their pictures loaded,
    /// so what stays at the window's foot, like a chat button, shows once at
    /// the end of the page rather than at every seam. Never more than half
    /// of what the two views share is left to the later one.
    static func seam(after step: Step, height: Int, fresh: Int) -> Int {
        let shared = max(0, height - step.top - step.bottom - step.shift)
        return height - step.bottom - min(max(fresh, 0), shared / 2)
    }

    /// Which rows of which view make the whole page, top to bottom: the
    /// first view down to its seam, then each next view from where the one
    /// before ended to its own seam, and the last view down to its foot, bar
    /// and all. `PageWalk` hands out the same strips as it goes.
    static func slices(height: Int, steps: [Step], fresh: Int = 0) -> [(view: Int, rows: Range<Int>)] {
        var slices: [(view: Int, rows: Range<Int>)] = []
        var start = 0
        let moves = steps.prefix { $0.shift > 0 }
        for (i, step) in moves.enumerated() {
            let end = seam(after: step, height: height, fresh: fresh)
            if end > start { slices.append((view: i, rows: start..<end)) }
            start = max(start, end) - step.shift
        }
        slices.append((view: moves.count, rows: start..<height))
        return slices
    }

    /// These rows of a view as a picture of their own, so the view itself
    /// can go: a long page keeps only what it adds.
    static func strip(of image: CGImage, rows: Range<Int>) -> CGImage? {
        let rows = rows.clamped(to: 0..<image.height)
        guard !rows.isEmpty,
              let piece = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count)),
              let context = canvas(like: image, height: rows.count) else { return nil }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: image.width, height: rows.count))
        return context.makeImage()
    }

    /// Strips one below the other, the first at the top: the whole page.
    static func stack(_ strips: [CGImage]) -> CGImage? {
        guard let first = strips.first else { return nil }
        let total = strips.reduce(0) { $0 + $1.height }
        guard total > 0, let context = canvas(like: first, height: total) else { return nil }
        var y = total
        for strip in strips {
            y -= strip.height
            // Core Graphics counts from the bottom; the page grows downwards.
            context.draw(strip, in: CGRect(x: 0, y: y, width: first.width, height: strip.height))
        }
        return context.makeImage()
    }

    /// A blank picture as wide as `image` and in its colours.
    private static func canvas(like image: CGImage, height: Int) -> CGContext? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: image.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
