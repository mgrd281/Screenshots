import Foundation

/// How many screenshots stand side by side in the iPhone's grids: three, or
/// four pinched closer, as in Photos, kept for every grid at once. The grid
/// follows the fingers while they pinch, as far as the next grid's size, and
/// changes once they let go past a little way.
enum GridZoom {
    static let key = "screenshotColumns"
    static let standard = 3
    static let range = 3...4

    /// How far a pinch goes before the grid changes.
    static let threshold = 0.1

    /// A number kept by an older or newer version, brought into range.
    static func clamped(_ columns: Int) -> Int {
        min(max(columns, range.lowerBound), range.upperBound)
    }

    /// The grid after a pinch: spread apart, larger, so one fewer to a row;
    /// pinched closer, smaller, one more.
    static func after(pinch magnification: Double, from columns: Int) -> Int {
        let now = clamped(columns)
        if magnification > 1 + threshold { return clamped(now - 1) }
        if magnification < 1 - threshold { return clamped(now + 1) }
        return now
    }

    /// How large the grid shows while it is pinched: with the fingers, up to
    /// the size of the next grid's cards; where the grid can't change that
    /// way, it gives a little and no more.
    static func scale(pinch magnification: Double, columns: Int) -> Double {
        let now = clamped(columns)
        if magnification >= 1 {
            guard now > range.lowerBound else { return min(1 + (magnification - 1) * 0.15, 1.04) }
            return min(magnification, Double(now) / Double(now - 1))
        }
        guard now < range.upperBound else { return max(1 - (1 - magnification) * 0.15, 0.96) }
        return max(magnification, Double(now) / Double(now + 1))
    }

    /// The newest screenshots the Photos tab shows before See All: three rows.
    static func preview(columns: Int) -> Int {
        clamped(columns) * 3
    }
}
