import Foundation

/// How Capture Whole Page goes down a page, from its top to its bottom: how
/// far each scroll goes, when a view is still enough to keep, how the move
/// is found when something on the page changed by itself, what is kept of
/// each view, and when the page has ended. What it sees and how it scrolls
/// are given to it (`Surface`), so it walks a page on the screen just as it
/// walks one made up in a test.
struct PageWalk<Picture> {
    /// What the walk needs from the window.
    struct Surface {
        /// The window as it is now, with its rows as `PageStitch` reads them.
        var shot: @MainActor () async -> (picture: Picture, rows: PageStitch.Rows)?
        /// Scrolls by this many points: up when positive.
        var scroll: @MainActor (Int) async -> Void
        /// Presses a key in the app in front.
        var press: @MainActor (Key) async -> Void
        /// Waits this many nanoseconds.
        var wait: @MainActor (UInt64) async -> Void
        /// Whether to stop where it is, keeping what was taken.
        var stopAsked: @MainActor () -> Bool
        /// Each strip of the page as soon as it is known, top to bottom:
        /// these rows of this view. One after the other they are the whole
        /// page, with nothing twice and nothing left out.
        var strip: @MainActor (Picture, Range<Int>) async -> Void
    }

    enum Key {
        case home, pageDown
    }

    /// Why the walk ended.
    enum End: Equatable {
        /// It reached the bottom of the page.
        case bottom
        /// It was asked to stop.
        case stopped
        /// The page went on past `maxLength`.
        case long
        /// No move fitted, however long it waited: the page kept changing.
        case changing
        /// Not even one view could be taken.
        case nothing
    }

    /// Pixels a point in the views.
    var scale: Double
    /// The window's height, in points.
    var windowHeight: Double
    /// How long a page is given after each scroll: long enough for one that
    /// loads its pictures as they come into view.
    var settle: UInt64 = 450_000_000
    /// How far apart two views are taken to see whether the page is still.
    var calm: UInt64 = 150_000_000
    /// How long all the waiting for a still view may add to the walk, past
    /// the first look again at each view, so a page with a video playing is
    /// not waited for at every view.
    var patience: UInt64 = 12_000_000_000
    /// A page longer than this many points is cut there, like a feed that
    /// never ends.
    var maxLength = 100_000
    /// The rows at the foot of each view, in points, that came into view
    /// last: a page shows a picture or a card there only once it is a little
    /// way in, and a chat button sits there. The next view shows them higher
    /// up, so they are left out of matching and taken from it.
    var fresh = 120

    /// How tall the part that scrolls is, in points, when that was measured
    /// before the walk, as between a sticky header and a bar at the foot.
    var scrolling: Double?

    /// How far each scroll goes at most, in points: most of the window less
    /// its toolbar, so each view shares a good part with the one before.
    var stepLength: Int {
        max(80, Int(((windowHeight - 140) * 0.7).rounded()))
    }

    /// How far a scroll goes for a part that scrolls this many points tall:
    /// most of it, and never more than `stepLength`.
    func step(for scrolling: Double) -> Int {
        min(stepLength, max(40, Int((scrolling * 0.7).rounded())))
    }

    private var freshRows: Int { Int((Double(fresh) * scale).rounded()) }

    /// Down the page from its top, handing out its strips on the way, then
    /// back to the top. Also how many rows the page moved in all.
    @MainActor
    func run(_ surface: Surface) async -> (end: End, moved: Int) {
        var waited: UInt64 = 0
        // The window once it is still, or as it is once it has been given
        // long enough: a picture that loads or a card that fades in has come.
        func look() async -> (picture: Picture, rows: PageStitch.Rows)? {
            await surface.wait(settle)
            guard var view = await surface.shot() else { return nil }
            for round in 0..<4 {
                // The first look again is always taken; more only while
                // there is patience left.
                if round > 0 {
                    guard waited < patience else { break }
                    waited += calm
                }
                await surface.wait(calm)
                guard let again = await surface.shot() else { return view }
                let still = Self.still(view.rows, again.rows)
                view = again
                if still { break }
            }
            return view
        }

        // From the top of the page: up, until the view stops changing.
        var last = await surface.shot()?.rows
        for _ in 0..<40 {
            await surface.scroll(4000)
            await surface.wait(settle / 3)
            guard let now = await surface.shot()?.rows else { break }
            if let last, PageStitch.alike(last, now) { break }
            last = now
        }
        guard var current = await look() else { return (.nothing, 0) }

        // Shorter once the part that scrolls is known to be shorter, as
        // between a sticky header and a bar at the foot, so two views
        // always share some of it.
        var step = scrolling.map { self.step(for: $0) } ?? stepLength
        var keys = false
        var views = 1
        var moved = 0
        var start = 0
        // The rows at the top that stay, like the toolbar, once known.
        var toolbar: Int?
        var bar: Int { toolbar ?? 0 }
        var end = End.bottom
        while true {
            if surface.stopAsked() {
                end = .stopped
                break
            }
            if Double(moved) / scale >= Double(maxLength) || views >= 2000 {
                end = .long
                break
            }
            if keys {
                await surface.press(.pageDown)
            } else {
                await surface.scroll(-step)
            }
            guard var next = await look() else {
                end = .changing
                break
            }
            let expected = Int(((keys ? windowHeight * 0.85 : Double(step)) * scale).rounded())
            var found = match(current.rows, next.rows, expected: expected, keys: keys)
            if found == nil {
                // Still loading, or moving: once more, a little later, at
                // the same place.
                if let again = await look() {
                    next = again
                    found = match(current.rows, next.rows, expected: expected, keys: keys)
                }
            }
            if found == nil, !keys {
                // The view before may have changed since it was taken, like
                // a picture that has loaded: the same place again, now, if
                // what it shared with the one before it is as it was.
                await surface.scroll(step)
                if let again = await look(), Self.samePlace(current.rows, again.rows, through: max(start, bar)) {
                    await surface.scroll(-step)
                    if let after = await look(),
                       let fit = match(again.rows, after.rows, expected: expected, keys: false) {
                        current = again
                        next = after
                        found = fit
                    }
                } else {
                    await surface.scroll(-step)
                }
            }
            if found == nil, !keys {
                // Half way back, so both views share more to go by.
                await surface.scroll(step / 2)
                if let half = await look(),
                   let fit = match(current.rows, half.rows, expected: Int((Double(step - step / 2) * scale).rounded()),
                                   keys: keys) {
                    next = half
                    found = fit
                }
            }
            if found == nil, Self.unmoved(current.rows, next.rows, below: bar) {
                // Nothing else fits, and the page stayed where it was with
                // something moving on it by itself, like a video: its bottom.
                found = PageStitch.Step(top: 0, bottom: 0, shift: 0)
            }
            guard let found else {
                end = .changing
                break
            }
            if found.shift == 0 {
                if views == 1, !keys {
                    // The wheel may not reach this page: from the top again,
                    // by key.
                    keys = true
                    await surface.press(.home)
                    guard let top = await look() else { return (.nothing, 0) }
                    current = top
                    continue
                }
                break
            }
            // What this view adds is known now that the next one fits.
            let seam = PageStitch.seam(after: found, height: current.rows.count, fresh: keys ? 0 : freshRows)
            if seam > start { await surface.strip(current.picture, start..<seam) }
            start = max(start, seam) - found.shift
            moved += found.shift
            toolbar = min(toolbar ?? found.top, found.top)
            step = self.step(for: Double(current.rows.count - found.top - found.bottom) / scale)
            current = next
            views += 1
        }
        // The last view down to its foot.
        await surface.strip(current.picture, start..<current.rows.count)

        // Back to the top, where a page usually starts: by the whole height
        // of what was seen, and more.
        if keys {
            await surface.press(.home)
        } else {
            await surface.scroll(Int((Double(moved) / scale + windowHeight * 2).rounded()))
        }
        return (end, moved)
    }

    /// How `next` follows `current`: strictly first, as a chat is read,
    /// then leaving out what stayed put or changed by itself. The wheel
    /// moves a page by no more than asked, so no longer move is tried for
    /// it; a key's move is only roughly known, and so are its fresh rows.
    private func match(_ current: PageStitch.Rows, _ next: PageStitch.Rows, expected: Int,
                       keys: Bool) -> PageStitch.Step? {
        let fresh = keys ? 0 : freshRows
        let farthest = keys ? nil : expected + 16
        if let step = PageStitch.step(from: current, to: next, expected: expected, fresh: fresh, farthest: farthest,
                                      telling: keys ? 0 : 8) {
            return step
        }
        return PageStitch.follow(from: current, to: next, expected: expected, fresh: fresh, farthest: farthest)
    }

    /// Whether the page stayed where it was between two views, though
    /// something on it changed by itself, like a video or a slideshow:
    /// hardly anything changed, or, under the toolbar, at least half of the
    /// rows are as they were and many of them show something. A plain
    /// stretch looks the same after a move, so it does not count.
    static func unmoved(_ a: PageStitch.Rows, _ b: PageStitch.Rows, below bar: Int) -> Bool {
        if PageStitch.alike(a, b) { return true }
        guard a.count == b.count, !a.isEmpty else { return false }
        let rows = min(max(bar, 0), a.count - 1)..<a.count
        var kept = 0, shown = 0
        for r in rows where PageStitch.same(a[r], b[r]) {
            kept += 1
            if let low = a[r].min(), let high = a[r].max(), Int(high) - Int(low) > 12 { shown += 1 }
        }
        return kept * 2 >= rows.count && shown >= max(16, rows.count / 10)
    }

    /// Whether `again` shows the same place as `view`: its rows down to
    /// `through`, the toolbar and what `view` shared with the view before
    /// it, are as they were, nine in ten of them, or a third of the window
    /// for the first view. Below that, a picture may have loaded since.
    static func samePlace(_ view: PageStitch.Rows, _ again: PageStitch.Rows, through: Int) -> Bool {
        guard view.count == again.count, !view.isEmpty else { return false }
        let rows = 0..<min(view.count, max(through, view.count / 3))
        let differing = rows.filter { !PageStitch.same(view[$0], again[$0]) }.count
        return differing * 10 <= rows.count
    }

    /// Two views a moment apart show the page still: at most one row in
    /// fifty changed, or two rows, so a blinking caret does not count.
    static func still(_ a: PageStitch.Rows, _ b: PageStitch.Rows) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let differing = a.indices.filter { !PageStitch.same(a[$0], b[$0]) }.count
        return differing <= max(2, a.count / 50)
    }
}
