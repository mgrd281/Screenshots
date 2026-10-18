import CoreGraphics

/// A picture read as a grid of colours, small enough to look through
/// quickly: one cell for each point of the screen or photo it shows.
struct PixelGrid {
    let width: Int
    let height: Int
    /// Red, green and blue, a byte each in the lower three, row by row from
    /// the top left.
    let pixels: [UInt32]

    init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels.map { $0 & 0xFF_FFFF }
    }

    /// The picture drawn at the given size, on white where it is see-through.
    init?(_ image: CGImage, width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        var data = [UInt32](repeating: 0, count: width * height)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(rect)
            context.interpolationQuality = .medium
            context.draw(image, in: rect)
            return true
        }
        guard drawn else { return nil }
        // Blue, green, red and alpha in memory: red, green and blue from the
        // highest byte down but one, once alpha, all opaque, is masked off.
        self.init(width: width, height: height, pixels: data)
    }

    /// Whether two colours look the same, each part within a few steps.
    static func same(_ a: UInt32, _ b: UInt32, within tolerance: Int = SmartArea.tolerance) -> Bool {
        abs(Int(a & 0xFF) - Int(b & 0xFF)) <= tolerance
            && abs(Int(a >> 8 & 0xFF) - Int(b >> 8 & 0xFF)) <= tolerance
            && abs(Int(a >> 16 & 0xFF) - Int(b >> 16 & 0xFF)) <= tolerance
    }

    /// The colour of a row from x0 up to x1, at its middle, when it is
    /// plain: no step from one cell to the next, and no more than a gentle
    /// shading end to end, as a window's background has. Nil when it holds
    /// something. The cells nearest each end, up to `ends`, are left out, so
    /// a frame or a shadow round a panel doesn't count.
    func rowColor(_ y: Int, from x0: Int, to x1: Int, ends: Int = 0) -> UInt32? {
        guard y >= 0, y < height, x0 >= 0, x1 <= width, x0 < x1 else { return nil }
        let skip = min(ends, (x1 - x0) / 10)
        return plain(from: y * width + x0 + skip, count: x1 - x0 - 2 * skip, step: 1)
    }

    /// The colour of a column from y0 up to y1, as `rowColor` reads a row.
    func columnColor(_ x: Int, from y0: Int, to y1: Int, ends: Int = 0) -> UInt32? {
        guard x >= 0, x < width, y0 >= 0, y1 <= height, y0 < y1 else { return nil }
        let skip = min(ends, (y1 - y0) / 10)
        return plain(from: (y0 + skip) * width + x, count: y1 - y0 - 2 * skip, step: width)
    }

    private func plain(from start: Int, count: Int, step: Int) -> UInt32? {
        guard count > 0 else { return nil }
        return pixels.withUnsafeBufferPointer { buffer -> UInt32? in
            var previous = buffer[start]
            var low = (previous & 0xFF, previous >> 8 & 0xFF, previous >> 16 & 0xFF)
            var high = low
            var index = start
            for _ in 0..<(count - 1) {
                index += step
                let pixel = buffer[index]
                guard Self.same(pixel, previous) else { return nil }
                let parts = (pixel & 0xFF, pixel >> 8 & 0xFF, pixel >> 16 & 0xFF)
                low = (min(low.0, parts.0), min(low.1, parts.1), min(low.2, parts.2))
                high = (max(high.0, parts.0), max(high.1, parts.1), max(high.2, parts.2))
                guard high.0 - low.0 <= SmartArea.shading, high.1 - low.1 <= SmartArea.shading,
                      high.2 - low.2 <= SmartArea.shading else { return nil }
                previous = pixel
            }
            return buffer[start + count / 2 * step]
        }
    }
}

/// One part of a picture, like a photo, a card, a button or a paragraph,
/// and the parts inside it, in the grid's cells from its top left.
struct SmartPart: Equatable {
    var rect: CGRect
    var parts: [SmartPart] = []
}

/// Smart selection: finds the parts of a picture by the empty space round
/// them, as a designer reads a layout. Plain rows or columns of the colour
/// most of them share part one thing from the next; each part is read again
/// for the parts inside it, the way a grid of photos holds rows, a row holds
/// photos, and a photo on its own background holds what it shows.
enum SmartArea {
    /// Empty space at least this wide, in cells, parts two things: wider than
    /// the space between words or lines of text, so a paragraph stays whole.
    static let gap = 6
    /// The smallest part worth outlining, in cells, each way.
    static let smallest: CGFloat = 16
    /// How far each part of a colour may stray and still be the same colour.
    static let tolerance = 3
    /// How much a plain line may shade from one end to the other.
    static let shading: UInt32 = 16
    /// Cells at each end of a line left out when looking for empty space,
    /// where a panel's frame, rounded corners or shadow sit.
    static let ends = 12
    /// The space left round what was dragged over once its empty edges go.
    static let margin = 8

    /// The parts within a rect of the grid, as a tree under it.
    static func parts(of grid: PixelGrid, in rect: CGRect) -> SmartPart {
        let bounds = CGRect(x: 0, y: 0, width: grid.width, height: grid.height)
        let root = rect.integral.intersection(bounds)
        guard !root.isNull, root.width >= 1, root.height >= 1 else { return SmartPart(rect: rect) }
        return part(Box(root), in: grid, background: nil, depth: 0)
    }

    /// The parts under a point, from the smallest out, without two that are
    /// almost the same.
    static func nested(in tree: SmartPart, at point: CGPoint) -> [CGRect] {
        var chain: [CGRect] = []
        var current: SmartPart? = tree.rect.contains(point) ? tree : nil
        while let node = current {
            chain.append(node.rect)
            current = node.parts.first { $0.rect.contains(point) }
        }
        return merged(chain)
    }

    /// Rects from more than one source, smallest first, those too small to
    /// outline left out, and of two almost the same, the smaller kept.
    static func merged(_ rects: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for rect in rects.sorted(by: { $0.width * $0.height < $1.width * $1.height })
        where rect.width >= smallest && rect.height >= smallest && !kept.contains(where: { alike($0, rect) }) {
            kept.append(rect)
        }
        return kept
    }

    /// Whether two rects are the same part, each edge within a few points.
    static func alike(_ a: CGRect, _ b: CGRect, within slack: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.maxX - b.maxX) <= slack
            && abs(a.minY - b.minY) <= slack && abs(a.maxY - b.maxY) <= slack
    }

    /// Every edge of every part, across and down, in order, for a drag to
    /// keep to.
    static func edges(of tree: SmartPart) -> (across: [CGFloat], down: [CGFloat]) {
        var across = Set<CGFloat>()
        var down = Set<CGFloat>()
        func visit(_ node: SmartPart) {
            across.insert(node.rect.minX)
            across.insert(node.rect.maxX)
            down.insert(node.rect.minY)
            down.insert(node.rect.maxY)
            node.parts.forEach(visit)
        }
        visit(tree)
        return (across.sorted(), down.sorted())
    }

    /// The nearest edge within reach, or the value itself without one.
    static func snap(_ value: CGFloat, to edges: [CGFloat], within reach: CGFloat = 6) -> CGFloat {
        var best = value
        var distance = reach
        for edge in edges where abs(edge - value) <= distance {
            best = edge
            distance = abs(edge - value)
        }
        return best
    }

    /// What was dragged over, its empty edges cut down to an even margin:
    /// each side loses its plain rows or columns, while they stay the colour
    /// of the edge, down to the margin, and keeps the rest. A rect with next
    /// to nothing in it stays as it is.
    static func trimmed(_ rect: CGRect, in grid: PixelGrid, margin: Int = margin) -> CGRect {
        let bounds = CGRect(x: 0, y: 0, width: grid.width, height: grid.height)
        let start = rect.integral.intersection(bounds)
        guard !start.isNull, start.width >= 1, start.height >= 1 else { return rect }
        let whole = Box(start)
        var box = whole
        let (left, right) = (box.x0, box.x1)
        box.y0 = eaten(from: box.y0, toward: box.y1) { grid.rowColor($0, from: left, to: right) }
        let top = box.y0
        box.y1 = eaten(from: box.y1 - 1, toward: top - 1) { grid.rowColor($0, from: left, to: right) } + 1
        if box.y0 < box.y1 {
            let (upper, lower) = (box.y0, box.y1)
            box.x0 = eaten(from: box.x0, toward: box.x1) { grid.columnColor($0, from: upper, to: lower) }
            let leading = box.x0
            box.x1 = eaten(from: box.x1 - 1, toward: leading - 1) { grid.columnColor($0, from: upper, to: lower) } + 1
        }
        // Next to nothing left: it was all one colour, or near enough.
        guard CGFloat(box.width) >= smallest / 2, CGFloat(box.height) >= smallest / 2 else { return rect }
        let kept = Box(x0: max(whole.x0, box.x0 - margin), y0: max(whole.y0, box.y0 - margin),
                       x1: min(whole.x1, box.x1 + margin), y1: min(whole.y1, box.y1 + margin))
        return kept == whole ? rect : kept.rect
    }

    /// Where a side stops, going inward from `start` toward `stop` past the
    /// plain lines, each the colour of the one before.
    private static func eaten(from start: Int, toward stop: Int, line: (Int) -> UInt32?) -> Int {
        let step = stop > start ? 1 : -1
        var index = start
        var previous: UInt32?
        while index != stop, let color = line(index), previous.map({ PixelGrid.same($0, color) }) ?? true {
            previous = color
            index += step
        }
        return index
    }

    // MARK: Reading the parts

    /// A rect of whole cells, from x0 and y0 up to x1 and y1.
    struct Box: Equatable {
        var x0, y0, x1, y1: Int

        init(x0: Int, y0: Int, x1: Int, y1: Int) {
            self.x0 = x0
            self.y0 = y0
            self.x1 = x1
            self.y1 = y1
        }

        init(_ rect: CGRect) {
            self.init(x0: Int(rect.minX), y0: Int(rect.minY), x1: Int(rect.maxX), y1: Int(rect.maxY))
        }

        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
        var rect: CGRect { CGRect(x: x0, y: y0, width: width, height: height) }
    }

    /// Deep enough for a window of cards of photos of logos, and no deeper.
    private static let deepest = 14

    /// A box and the parts in it. The empty space round it, `background`,
    /// is tried first for the space between its parts too: a row of photos
    /// on white is parted by the white, not by the grey round each logo.
    private static func part(_ box: Box, in grid: PixelGrid, background: UInt32?, depth: Int) -> SmartPart {
        var inside: [Box] = []
        var between = background
        if depth < deepest, CGFloat(box.width) >= smallest, CGFloat(box.height) >= smallest {
            let rows = split(box, in: grid, rows: true, preferring: background)
            if rows.pieces.count >= 2 {
                (inside, between) = (rows.pieces, rows.background)
            } else {
                let columns = split(box, in: grid, rows: false, preferring: background)
                if columns.pieces.count >= 2 {
                    (inside, between) = (columns.pieces, columns.background)
                } else if let single = [rows, columns].first(where: { $0.pieces.count == 1 && $0.pieces[0] != box }) {
                    // One thing on its own background: the thing, without it.
                    (inside, between) = (single.pieces, single.background)
                }
            }
        }
        return SmartPart(rect: box.rect,
                         parts: inside.map { part($0, in: grid, background: between, depth: depth + 1) })
    }

    /// The pieces of a box between its empty rows, or its empty columns, and
    /// the colour of that empty space: the one round the box when it parts
    /// the box, else the one most plain lines in it share.
    private static func split(_ box: Box, in grid: PixelGrid, rows: Bool,
                              preferring preferred: UInt32?) -> (pieces: [Box], background: UInt32?) {
        let count = rows ? box.height : box.width
        var colors = [UInt32?](repeating: nil, count: count)
        var tally: [UInt32: Int] = [:]
        for index in 0..<count {
            let color = rows
                ? grid.rowColor(box.y0 + index, from: box.x0, to: box.x1, ends: ends)
                : grid.columnColor(box.x0 + index, from: box.y0, to: box.y1, ends: ends)
            colors[index] = color
            if let color { tally[color, default: 0] += 1 }
        }
        // The same each time for a tie.
        guard let common = tally.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return ([], nil) }
        if let preferred, !PixelGrid.same(preferred, common) {
            let pieces = cut(box, in: grid, rows: rows, colors: colors, background: preferred)
            if pieces.count >= 2 { return (pieces, preferred) }
        }
        return (cut(box, in: grid, rows: rows, colors: colors, background: common), common)
    }

    /// The pieces between runs of empty lines: plain lines of the background
    /// colour, and those shading on from them, as a window's background does.
    /// Empty space narrower than the gap stays inside a piece, unless it is
    /// at an end; each piece loses the empty space at its ends the other way
    /// too, and a piece too thin to be anything is dropped.
    private static func cut(_ box: Box, in grid: PixelGrid, rows: Bool, colors: [UInt32?],
                            background: UInt32) -> [Box] {
        let count = colors.count
        var empty = colors.map { $0.map { PixelGrid.same($0, background) } ?? false }
        func shades(_ index: Int, into neighbour: Int) -> Bool {
            guard let color = colors[index], let next = colors[neighbour] else { return false }
            return PixelGrid.same(color, next)
        }
        if count > 1 {
            for index in 1..<count where !empty[index] && empty[index - 1] && shades(index, into: index - 1) {
                empty[index] = true
            }
            for index in stride(from: count - 2, through: 0, by: -1)
            where !empty[index] && empty[index + 1] && shades(index, into: index + 1) {
                empty[index] = true
            }
        }

        var ranges: [Range<Int>] = []
        var start: Int?
        var index = 0
        while index < count {
            guard empty[index] else {
                if start == nil { start = index }
                index += 1
                continue
            }
            var end = index
            while end < count, empty[end] { end += 1 }
            if end - index >= gap || index == 0 || end == count {
                if let begun = start { ranges.append(begun..<index) }
                start = nil
            }
            index = end
        }
        if let begun = start { ranges.append(begun..<count) }

        return ranges.compactMap { range in
            var piece = rows
                ? Box(x0: box.x0, y0: box.y0 + range.lowerBound, x1: box.x1, y1: box.y0 + range.upperBound)
                : Box(x0: box.x0 + range.lowerBound, y0: box.y0, x1: box.x0 + range.upperBound, y1: box.y1)
            piece = tightened(piece, in: grid, background: background, columns: rows)
            // A thin rule on its own is no part.
            guard piece.width >= 3, piece.height >= 3 else { return nil }
            return piece
        }
    }

    /// A box without the empty columns, or rows, at its two ends: plain
    /// lines of the background colour, or shading on from it.
    private static func tightened(_ box: Box, in grid: PixelGrid, background: UInt32, columns: Bool) -> Box {
        var box = box
        func eat(from start: Int, toward stop: Int, line: (Int) -> UInt32?) -> Int {
            let step = stop > start ? 1 : -1
            var index = start
            var previous: UInt32?
            while index != stop, let color = line(index),
                  PixelGrid.same(color, background) || previous.map({ PixelGrid.same($0, color) }) == true {
                previous = color
                index += step
            }
            return index
        }
        if columns {
            let (top, bottom) = (box.y0, box.y1)
            box.x0 = eat(from: box.x0, toward: box.x1) { grid.columnColor($0, from: top, to: bottom) }
            let leading = box.x0
            box.x1 = eat(from: box.x1 - 1, toward: leading - 1) { grid.columnColor($0, from: top, to: bottom) } + 1
        } else {
            let (left, right) = (box.x0, box.x1)
            box.y0 = eat(from: box.y0, toward: box.y1) { grid.rowColor($0, from: left, to: right) }
            let upper = box.y0
            box.y1 = eat(from: box.y1 - 1, toward: upper - 1) { grid.rowColor($0, from: left, to: right) } + 1
        }
        return box
    }
}
