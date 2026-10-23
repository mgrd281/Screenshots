import Foundation

/// What is still bent in a page — a curl at the bottom, a slant down it —
/// read from its own long lines and taken out, so every line lies straight
/// and nothing jumps. A line is read in stretches of columns, where a rule
/// is dark from one side of the stretch to the other and text never is, its
/// letters having gaps; a line is the stretches that follow on from each
/// other across most of the page. So a row of dense text is never taken for
/// a rule, and print close by never bends one. Only pixels are moved, as for
/// a perspective correction.
enum ScanBend {
    /// A long line: the row it is laid on, and how far it lies above that
    /// row in every column, in pixels.
    struct Line: Equatable {
        let row: Int
        let heights: [Double]
    }

    /// The long lines across a page, from the top, at most `most`.
    static func lines(in plane: [UInt8], width w: Int, height h: Int, most: Int = 24) -> [Line] {
        let chunk = max(16, w / 40)
        let chunks = (w + chunk - 1) / chunk
        let top = max(1, Int(Double(h) * 0.05)), bottom = min(h - 1, h - h / 30)
        guard bottom > top + 4, chunks >= 5 else { return [] }
        // In each stretch, where a rule crosses it: rows dark against the
        // stretch's own paper, in nearly every column, each run of them at
        // its darkest, to a pixel's fraction.
        var marks = [[Double]](repeating: [], count: chunks)
        for c in 0..<chunks {
            let x0 = c * chunk, x1 = min(w, x0 + chunk)
            guard x1 - x0 >= chunk / 2 else { continue }
            var means = [Double](repeating: 255, count: h)
            for y in top..<bottom {
                var sum = 0
                for x in x0..<x1 { sum += Int(plane[y * w + x]) }
                means[y] = Double(sum) / Double(x1 - x0)
            }
            let sorted = means[top..<bottom].sorted()
            let paper = sorted[sorted.count * 9 / 10]
            guard paper > 60 else { continue }
            let dark = UInt8(max(0, min(255, paper * 0.8)))
            var run: [Int] = []
            func close() {
                guard !run.isEmpty else { return }
                let i = run.min { means[$0] < means[$1] }!
                var at = Double(i)
                let above = means[i - 1], on = means[i], below = means[i + 1]
                let curve = above - 2 * on + below
                if curve > 0 { at += max(-0.5, min(0.5, (above - below) / (2 * curve))) }
                marks[c].append(at)
                run = []
            }
            for y in top..<bottom {
                var covered = 0
                if means[y] < paper * 0.75 {
                    for x in x0..<x1 where min(plane[(y - 1) * w + x], plane[y * w + x], plane[(y + 1) * w + x]) < dark {
                        covered += 1
                    }
                }
                if covered * 10 >= (x1 - x0) * 9 { run.append(y) } else { close() }
            }
            close()
        }
        // Stretches following on from each other, a stretch or two missing
        // at most, each within a few pixels of the last.
        var used = marks.map { [Bool](repeating: false, count: $0.count) }
        var found: [Line] = []
        for start in 0..<chunks {
            for k in marks[start].indices where !used[start][k] {
                var chain: [(c: Int, y: Double)] = [(start, marks[start][k])]
                used[start][k] = true
                var c = start + 1
                while c < chunks, c - chain[chain.count - 1].c <= 3 {
                    let last = chain[chain.count - 1]
                    let reach = 2.0 + Double(c - last.c)
                    if let j = marks[c].indices.filter({ !used[c][$0] && abs(marks[c][$0] - last.y) <= reach })
                        .min(by: { abs(marks[c][$0] - last.y) < abs(marks[c][$1] - last.y) }) {
                        used[c][j] = true
                        chain.append((c, marks[c][j]))
                    }
                    c += 1
                }
                guard chain.count * 5 >= chunks * 3,
                      (chain[chain.count - 1].c - chain[0].c + 1) * 10 >= chunks * 7 else { continue }
                found.append(line(chain, chunk: chunk, width: w))
            }
        }
        found.sort { $0.row < $1.row }
        var apart: [Line] = []
        for line in found where !apart.contains(where: { abs($0.row - line.row) < 4 }) { apart.append(line) }
        return Array(apart.prefix(most))
    }

    /// A line from its stretches: laid on its middle row, straight between
    /// the stretches' middles, and on as the nearest past the ends.
    private static func line(_ chain: [(c: Int, y: Double)], chunk: Int, width w: Int) -> Line {
        let sorted = chain.map(\.y).sorted()
        let row = Int(sorted[sorted.count / 2].rounded())
        let points = chain.map { (x: (Double($0.c) + 0.5) * Double(chunk), y: $0.y) }
        var heights = [Double](repeating: 0, count: w)
        var k = 0
        for x in 0..<w {
            let at = Double(x) + 0.5
            while k + 1 < points.count - 1, at > points[k + 1].x { k += 1 }
            let a = points[k], b = points[min(k + 1, points.count - 1)]
            let y: Double
            if at <= a.x || b.x == a.x {
                y = a.y
            } else if at >= b.x {
                y = b.y
            } else {
                y = a.y + (b.y - a.y) * (at - a.x) / (b.x - a.x)
            }
            heights[x] = Double(row) - y
        }
        return Line(row: row, heights: heights)
    }

    /// The page with its long lines laid straight; the page itself where
    /// none is seen or none is bent.
    static func undeformed(_ page: ScanBitmap) -> ScanBitmap {
        let w = page.width, h = page.height
        guard w > 120, h > 120 else { return page }
        let lines = self.lines(in: page.brightness, width: w, height: h)
        // Bent by less than a pixel end to end: nothing to take out.
        guard lines.contains(where: { ($0.heights.max() ?? 0) - ($0.heights.min() ?? 0) >= 1 }) else { return page }
        var out = page
        page.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                var i = 0
                for y in 0..<h {
                    while i + 1 < lines.count, y > lines[i + 1].row { i += 1 }
                    let a = i, b = min(i + 1, lines.count - 1)
                    var t = 0.0
                    if b > a { t = min(1, max(0, Double(y - lines[a].row) / Double(lines[b].row - lines[a].row))) }
                    for x in 0..<w {
                        let shift = lines[a].heights[x] * (1 - t) + lines[b].heights[x] * t
                        let fromY = min(max(Double(y) - shift, 0), Double(h - 1))
                        let y0 = Int(fromY.rounded(.down)), y1 = min(y0 + 1, h - 1)
                        let ty = fromY - Double(y0)
                        let o = (y * w + x) * 4
                        for k in 0..<3 {
                            let v = Double(src[(y0 * w + x) * 4 + k]) * (1 - ty) + Double(src[(y1 * w + x) * 4 + k]) * ty
                            dst[o + k] = UInt8(min(255, max(0, v + 0.5)))
                        }
                    }
                }
            }
        }
        return out
    }
}
