import Foundation
@testable import Tendedero

/// Where the made-up sick note's (`ScanForm`) own pixels lie on a cleaned
/// page of it: its parts are cut, laid flat one by one and trimmed, so its
/// rules sit some pixels from where a plain scaling puts them, and the part
/// below a fold can come out a little longer or shorter than the part
/// above. Read from the rules themselves: across, the long lines, each
/// matched to where the form printed it and the page laid between them part
/// by part; down, the box's two sides.
struct ScanFormPlace {
    /// The rules across the form, at their middles, pixels down from its top.
    static let across: [Double] = [382, 762, 1082, 1502, 1602, 2302, 2402, 3102]
    /// The box's sides, at their middles, pixels in from its left.
    static let down: [Double] = [162, 2322]

    /// Across: page x = scale · form x + offset.
    let scale: Double
    let offset: Double
    /// Down: the form's rows matched to the page's, in order.
    let rows: [(form: Double, page: Double)]

    func x(_ x: Double) -> Double { scale * x + offset }

    /// A form row on the page, between the two matched rules round it, or
    /// on past the first or last one as the nearest two lie.
    func y(_ y: Double) -> Double {
        guard rows.count >= 2 else { return y }
        var i = 0
        while i + 2 < rows.count, y > rows[i + 1].form { i += 1 }
        let a = rows[i], b = rows[i + 1]
        return a.page + (y - a.form) * (b.page - a.page) / (b.form - a.form)
    }

    /// How many page pixels a form pixel is, down, near a row.
    func scaleDown(at y: Double) -> Double {
        let span = self.y(y + 50) - self.y(y - 50)
        return span > 0 ? span / 100 : scale
    }

    /// The form found on a page; nil where too few of its rules are seen.
    static func of(_ page: ScanBitmap) -> ScanFormPlace? {
        let w = page.width, h = page.height
        let plane = page.brightness
        // Rows dark over half the width, each run of them at its middle.
        var found: [Double] = []
        var run: [Int] = []
        let samples = (w - 2 * (w / 10)) / 2
        for y in 0..<h {
            var dark = 0
            var x = w / 10
            while x < w - w / 10 {
                if plane[y * w + x] < 200 { dark += 1 }
                x += 2
            }
            if dark * 2 > samples { run.append(y) } else if !run.isEmpty {
                found.append(Double(run[0] + run[run.count - 1]) / 2)
                run = []
            }
        }
        // First one scaling for all, loosely, then each rule to the nearest found.
        guard let loose = fit(found, to: across, within: Double(h) * 0.015) else { return nil }
        var rows: [(form: Double, page: Double)] = []
        for e in across {
            let guess = loose.scale * e + loose.offset
            guard let f = found.min(by: { abs($0 - guess) < abs($1 - guess) }), abs(f - guess) <= Double(h) * 0.015,
                  !rows.contains(where: { $0.page == f }) else { continue }
            rows.append((e, f))
        }
        guard rows.count >= 3 else { return nil }
        // The box's sides, down the first box: a little slanted, so a column
        // counts where a pixel within six either side of it is dark, in
        // three rows of every ten.
        let top = Int(rows.first { $0.form == 382 }?.page ?? loose.scale * 382 + loose.offset) + 10
        let bottom = Int(rows.first { $0.form == 1082 }?.page ?? loose.scale * 1082 + loose.offset) - 10
        guard top >= 0, bottom < h, bottom > top + 10 else { return nil }
        var columns: [Double] = []
        run = []
        for x in 0..<w {
            var dark = 0
            for y in stride(from: top, to: bottom, by: 2) {
                var darkest: UInt8 = 255
                for xx in max(0, x - 6)...min(w - 1, x + 6) { darkest = min(darkest, plane[y * w + xx]) }
                if darkest < 200 { dark += 1 }
            }
            if dark * 20 > (bottom - top) * 3 { run.append(x) } else if !run.isEmpty {
                columns.append(Double(run[0] + run[run.count - 1]) / 2)
                run = []
            }
        }
        guard let sides = fit(columns, to: down, within: Double(w) * 0.015) else { return nil }
        return ScanFormPlace(scale: sides.scale, offset: sides.offset, rows: rows)
    }

    /// The scale and offset that lay the most of `expected` onto `found`,
    /// within `within` pixels: tried from every two pairs of them, then
    /// laid through every pair it matched.
    static func fit(_ found: [Double], to expected: [Double], within: Double) -> (scale: Double, offset: Double)? {
        guard found.count >= 2 else { return nil }
        var best: (count: Int, scale: Double, offset: Double)?
        for i in expected.indices {
            for j in expected.indices where j > i {
                for a in found.indices {
                    for b in found.indices where b > a {
                        let scale = (found[b] - found[a]) / (expected[j] - expected[i])
                        guard scale > 0.3, scale < 1.5 else { continue }
                        let offset = found[a] - scale * expected[i]
                        let count = expected.filter { e in found.contains { abs($0 - (scale * e + offset)) <= within } }.count
                        if count > best?.count ?? 0 { best = (count, scale, offset) }
                    }
                }
            }
        }
        guard let best, best.count >= 2 else { return nil }
        var pairs: [(Double, Double)] = []
        for e in expected {
            let guess = best.scale * e + best.offset
            if let f = found.min(by: { abs($0 - guess) < abs($1 - guess) }), abs(f - guess) <= within { pairs.append((e, f)) }
        }
        let n = Double(pairs.count)
        let me = pairs.reduce(0) { $0 + $1.0 } / n, mf = pairs.reduce(0) { $0 + $1.1 } / n
        var sxy = 0.0, sxx = 0.0
        for (e, f) in pairs {
            sxy += (e - me) * (f - mf)
            sxx += (e - me) * (e - me)
        }
        guard sxx > 0 else { return (best.scale, best.offset) }
        let scale = sxy / sxx
        return (scale, mf - scale * me)
    }
}
