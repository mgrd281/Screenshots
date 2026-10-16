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
    static func step(from previous: Rows, to next: Rows, expected: Int) -> Step? {
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

        // The move that lines up most of what both views show.
        var best: (shift: Int, score: Double)?
        for shift in 1..<middle {
            let overlap = middle - shift
            guard overlap >= 8 else { break }
            // A header that shrinks as the page scrolls may differ; the rest must match.
            let allowed = overlap / 5
            var misses = 0
            for i in 0..<overlap where !same(previous[top + shift + i], next[top + i]) {
                misses += 1
                if misses > allowed { break }
            }
            guard misses <= allowed else { continue }
            let score = Double(overlap - misses) / Double(overlap) - Double(abs(shift - expected)) / Double(middle * 100)
            if best == nil || score > best!.score { best = (shift, score) }
        }
        return best.map { Step(top: top, bottom: bottom, shift: $0.shift) }
    }

    /// Which rows of which view make the whole page, top to bottom: the
    /// first view down to its bottom bar, the new rows of each next view,
    /// then the last view's bottom bar.
    static func slices(height: Int, steps: [Step]) -> [(view: Int, rows: Range<Int>)] {
        let moves = steps.prefix { $0.shift > 0 }
        guard let last = moves.last else { return [(view: 0, rows: 0..<height)] }
        var slices = [(view: 0, rows: 0..<(height - moves.first!.bottom))]
        for (i, step) in moves.enumerated() {
            let end = height - step.bottom
            slices.append((view: i + 1, rows: max(step.top, end - step.shift)..<end))
        }
        if last.bottom > 0 { slices.append((view: moves.count, rows: (height - last.bottom)..<height)) }
        return slices
    }

    /// The whole page as one image.
    static func compose(_ views: [CGImage], steps: [Step]) -> CGImage? {
        guard let first = views.first else { return nil }
        let parts = slices(height: first.height, steps: steps).filter { $0.view < views.count && !$0.rows.isEmpty }
        let total = parts.reduce(0) { $0 + $1.rows.count }
        let space = first.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard total > 0, let context = CGContext(data: nil, width: first.width, height: total, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var y = total
        for part in parts {
            let rect = CGRect(x: 0, y: part.rows.lowerBound, width: first.width, height: part.rows.count)
            guard let piece = views[part.view].cropping(to: rect) else { continue }
            y -= part.rows.count
            // Core Graphics counts from the bottom; the page grows downwards.
            context.draw(piece, in: CGRect(x: 0, y: y, width: first.width, height: part.rows.count))
        }
        return context.makeImage()
    }
}
