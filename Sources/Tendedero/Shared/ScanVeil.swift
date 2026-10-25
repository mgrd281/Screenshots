import Foundation

/// A page's small picture made unreadable, for the Scan tab, which is shown
/// in public: shrunk to a few cells across, each the mean of its pixels,
/// then drawn back at the size asked, smoothly. The shapes of a page stay
/// (where its text and its pictures lie, its paper's colour); no letter or
/// digit survives, at any size it is drawn or zoomed. Made from the covered
/// copy, never from a page without its covers.
enum ScanVeil {
    /// How many cells across the page is made of: a cell is wider than any
    /// line of print is tall, from 7 pt to a 24 pt heading.
    static let cells = 12

    static func veiled(_ page: ScanBitmap, cells: Int = cells) -> ScanBitmap {
        let w = page.width, h = page.height
        let across = max(1, min(cells, w))
        let down = max(1, min(h, Int((Double(h) / Double(w) * Double(across)).rounded())))
        // The cells, each the mean of the pixels it covers.
        var small = [Double](repeating: 0, count: across * down * 3)
        for cy in 0..<down {
            let y0 = cy * h / down, y1 = max(y0 + 1, (cy + 1) * h / down)
            for cx in 0..<across {
                let x0 = cx * w / across, x1 = max(x0 + 1, (cx + 1) * w / across)
                var sum = (0.0, 0.0, 0.0)
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let i = (y * w + x) * 4
                        sum.0 += Double(page.pixels[i])
                        sum.1 += Double(page.pixels[i + 1])
                        sum.2 += Double(page.pixels[i + 2])
                    }
                }
                let n = Double((y1 - y0) * (x1 - x0)), c = (cy * across + cx) * 3
                small[c] = sum.0 / n
                small[c + 1] = sum.1 / n
                small[c + 2] = sum.2 / n
            }
        }
        // Drawn back at the page's size, each pixel between its four nearest cells.
        var out = page
        for y in 0..<h {
            let fy = min(Double(down - 1), max(0, (Double(y) + 0.5) / Double(h) * Double(down) - 0.5))
            let y0 = Int(fy), y1 = min(down - 1, y0 + 1), ty = fy - Double(y0)
            for x in 0..<w {
                let fx = min(Double(across - 1), max(0, (Double(x) + 0.5) / Double(w) * Double(across) - 0.5))
                let x0 = Int(fx), x1 = min(across - 1, x0 + 1), tx = fx - Double(x0)
                let o = (y * w + x) * 4
                for c in 0..<3 {
                    let a = small[(y0 * across + x0) * 3 + c], b = small[(y0 * across + x1) * 3 + c]
                    let d = small[(y1 * across + x0) * 3 + c], e = small[(y1 * across + x1) * 3 + c]
                    let value = (a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty
                    out.pixels[o + c] = UInt8(min(255, max(0, value.rounded())))
                }
            }
        }
        return out
    }
}
