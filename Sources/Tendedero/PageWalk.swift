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
        /// Notes where the things on the page are now, so `measured` can
        /// tell later how far they moved.
        var mark: @MainActor () async -> Void = {}
        /// How far the page moved since `mark`, in points, down when
        /// positive, as the app itself tells it, like a browser through
        /// Accessibility: no guessing from pictures. Nil when it cannot tell.
        var measured: @MainActor () async -> Double? = { nil }
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
    /// How long a page that did not move is given before the scroll down is
    /// tried once more: a feed may be loading more at its end.
    var more: UInt64 = 2_000_000_000
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

    /// A view as the walk keeps it: what it shows, its rows, and for each
    /// row, as bits, the columns that changed by themselves while it was
    /// taken, like a video or a button that pulses.
    typealias View = (picture: Picture, rows: PageStitch.Rows, restless: [UInt64])

    /// Down the page from its top, handing out its strips on the way, then
    /// back to the top. Also how many rows the page moved in all.
    @MainActor
    func run(_ surface: Surface) async -> (end: End, moved: Int) {
        var waited: UInt64 = 0
        // The window once it is still, or as it is once it has been given
        // long enough: a picture that loads or a card that fades in has come.
        func look() async -> View? {
            await surface.wait(settle)
            guard var view = await surface.shot() else { return nil }
            var restless = [UInt64](repeating: 0, count: view.rows.count)
            for round in 0..<4 {
                // The first look again is always taken; more only while
                // there is patience left.
                if round > 0 {
                    guard waited < patience else { break }
                    waited += calm
                }
                await surface.wait(calm)
                guard let again = await surface.shot() else { break }
                let still = Self.still(view.rows, again.rows)
                for (r, bits) in Self.restless(view.rows, again.rows).enumerated() where r < restless.count {
                    restless[r] |= bits
                }
                view = again
                if still { break }
            }
            return (view.picture, view.rows, restless)
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
        // Whether the scroll down from this view was tried once more, after
        // it did not move the page.
        var tried = false
        // Whether the app has told a move in this walk: one that tells
        // nothing ever moves, like Chrome before its page has loaded, is
        // not believed when it says the page stayed.
        var tells = false
        while true {
            if surface.stopAsked() {
                end = .stopped
                break
            }
            if Double(moved) / scale >= Double(maxLength) || views >= 2000 {
                end = .long
                break
            }
            await surface.mark()
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
            // How far the page moved, as the app itself tells it, once what
            // both views show agrees; else as the pictures tell it.
            var found: PageStitch.Step?
            var told = false
            // The move the app told, in rows, for the views compared now.
            var toldRows: Int?
            // Asked again for a later view, as the page may have moved on
            // since the first: how far it is from where it was at the mark.
            func retold(_ a: View, _ b: View) async -> PageStitch.Step? {
                guard toldRows != nil, let points = await surface.measured(),
                      Int((points * scale).rounded()) > 0 else {
                    toldRows = nil
                    return nil
                }
                toldRows = Int((points * scale).rounded())
                guard let toldRows,
                      let step = PageStitch.check(from: a.rows, to: b.rows, shift: toldRows,
                                                  restless: (a.restless, b.restless)),
                      !Self.sitsStill(a, b, beside: step) else { return nil }
                return step
            }
            // A fit the pictures find far from the move told gives way to
            // it when what both views show goes against it more.
            func heeded(_ fit: PageStitch.Step?, _ a: View, _ b: View) -> PageStitch.Step? {
                guard let fit, fit.shift > 0, let toldRows, abs(fit.shift - toldRows) > 2 else { return fit }
                return PageStitch.check(from: a.rows, to: b.rows, shift: toldRows, restless: (a.restless, b.restless),
                                        rival: fit.shift) ?? fit
            }
            if let points = await surface.measured() {
                let rows = Int((points * scale).rounded())
                if rows > 0 {
                    tells = true
                    toldRows = rows
                    found = PageStitch.check(from: current.rows, to: next.rows, shift: rows,
                                             restless: (current.restless, next.restless))
                    if let step = found, Self.sitsStill(current, next, beside: step) {
                        // Something that moves by itself, like a wall of
                        // cards that scrolls on its own, told the move, while
                        // the page stayed where it was.
                        found = nil
                        told = true
                    }
                } else if rows == 0 {
                    // It stayed where it was, if the pictures agree, or, as
                    // the app has told moves before, unless they clearly say
                    // it moved: then a dot that pulses at the page's end
                    // does not pass for a move.
                    told = Self.sat(current, next)
                        || (tells && (PageStitch.step(from: current.rows, to: next.rows, expected: expected,
                                                      fresh: freshRows, farthest: expected + expected / 8 + 16,
                                                      telling: 8)?.shift ?? 0) < 16)
                }
            }
            if found == nil, !told {
                found = heeded(match(current, next, expected: expected, keys: keys), current, next)
            }
            if found == nil, !told {
                // Still loading, or moving: once more, a little later, at
                // the same place.
                if let again = await look() {
                    next = again
                    found = await retold(current, next)
                    if found == nil {
                        found = heeded(match(current, next, expected: expected, keys: keys), current, next)
                    }
                }
            }
            // Whether the scroll left the page where it was, with only a
            // dot that pulses or the like changing on it: then a view above
            // it would fit by chance, so none is looked for.
            var stayed = told || (found == nil && !keys && Self.sat(current, next))
            if found == nil, !keys, !stayed {
                // The view before may have changed since it was taken, like
                // a picture that has loaded: the same place again, now, if
                // what it shared with the one before it is as it was.
                await surface.scroll(step)
                let again = await look()
                if let again, Self.samePlace(current.rows, again.rows, through: max(start, bar), below: bar) {
                    await surface.scroll(-step)
                    if let after = await look(),
                       let fit = await retold(again, after)
                           ?? heeded(match(again, after, expected: expected, keys: false), again, after) {
                        current = again
                        next = after
                        found = fit
                    }
                } else {
                    // One step up shows the page just one step above the
                    // view before: the scroll down did not move it, as at
                    // its end with a video playing over much of it.
                    if let again, PageStitch.step(from: again.rows, to: current.rows, expected: expected,
                                                  fresh: freshRows, farthest: expected + 16,
                                                  telling: 8)?.shift == expected {
                        stayed = true
                    }
                    await surface.scroll(-step)
                }
            }
            if found == nil, stayed, !tried {
                // A feed may be loading more: the scroll down once more, a
                // little later, from the same place.
                tried = true
                await surface.wait(more)
                continue
            }
            if found == nil, !keys, !stayed {
                // Half way back, so both views share more to go by.
                await surface.scroll(step / 2)
                let halfway = Int((Double(step - step / 2) * scale).rounded())
                // Last, a longer move than asked, strictly: a header above
                // the page shrank, or a script added to the scroll.
                if let half = await look(),
                   let fit = await retold(current, half)
                       ?? heeded(match(current, half, expected: halfway, keys: keys)
                           ?? PageStitch.step(from: current.rows, to: half.rows, expected: halfway,
                                              fresh: freshRows, telling: 8), current, half) {
                    next = half
                    found = fit
                }
            }
            if found == nil, stayed || Self.unmoved(current.rows, next.rows, below: bar) {
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
            tried = false
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
    /// then leaving out what stayed put or changed by itself. A page may
    /// move an eighth farther than the wheel asked, so the strict match
    /// looks that far, with enough lines of something to go by; the others
    /// only a little past it (the walk tries longer moves strictly once,
    /// last). A key's move is only roughly known, and so are its fresh rows.
    private func match(_ seen: View, _ following: View, expected: Int, keys: Bool) -> PageStitch.Step? {
        let current = seen.rows, next = following.rows
        let fresh = keys ? 0 : freshRows
        let farthest = keys ? nil : expected + 16
        if let step = PageStitch.step(from: current, to: next, expected: expected, fresh: fresh,
                                      farthest: keys ? nil : expected + expected / 8 + 16,
                                      telling: keys ? 0 : 8) {
            return step
        }
        // A short move, like the last one to the page's foot, may be told
        // only by what came into view last: strictly, with those rows too,
        // when enough of them tell where they are.
        if !keys, fresh > 0, let step = PageStitch.step(from: current, to: next, expected: expected, fresh: 0,
                                                        farthest: farthest, telling: 8),
           Self.told(current, next, at: step) >= 8 {
            return step
        }
        // A plain stretch, like a tall band of one colour, lines up at any
        // move with nothing to tell them apart: the one the wheel was asked
        // for, when nothing on the page goes against it. Not when the page
        // sat still with something changing by itself on it, nor when what
        // came into view last says otherwise, as when the page moved less
        // or more than asked.
        if !keys, let plain = PageStitch.step(from: current, to: next, expected: expected, fresh: fresh,
                                              farthest: expected),
           plain.shift == expected,
           !Self.stillBut(current, next, restless: (seen.restless, following.restless),
                          rows: plain.top..<max(plain.top, min(current.count, next.count) - plain.bottom)),
           Self.freshAgree(current, next, at: plain, fresh: fresh,
                           restless: (seen.restless, following.restless)) {
            return plain
        }
        // Leaving out what stayed put, a page of cards in a grid lines up
        // a card further, as if it had not moved, and something that
        // pulses, a row or two: neither is a move. A short last move
        // beside a column that sticks is one, where the page did not stay
        // and all that both views share agrees with it.
        guard let followed = PageStitch.follow(from: current, to: next, expected: expected, fresh: fresh,
                                               farthest: farthest) else { return nil }
        if followed.shift == 0, !Self.sat(seen, following) { return nil }
        if followed.shift > 0, followed.shift < 16, expected >= 64,
           Self.sat(seen, following) || Self.unmoved(current, next, below: followed.top)
               || PageStitch.check(from: current, to: next, shift: followed.shift,
                                   restless: (seen.restless, following.restless)) == nil {
            return nil
        }
        return followed
    }

    /// Whether the page sat where it was between two views although a move
    /// was told and fits: something on it moves by itself, like a wall of
    /// cards that scrolls on its own, and much of what both show, an eighth
    /// of what scrolls, is where it was.
    static func sitsStill(_ a: View, _ b: View, beside step: PageStitch.Step) -> Bool {
        guard sat(a, b) else { return false }
        let middle = min(a.rows.count, b.rows.count) - step.top - step.bottom
        let still = PageStitch.Step(top: step.top, bottom: step.bottom, shift: 0)
        return told(a.rows, b.rows, at: still) >= max(16, middle / 8)
    }

    /// How far the page moved, in points, down when positive, from how far
    /// each of several things on it moved up (`deltas`, as `PageMeasure`
    /// reads them): the move most of those that moved agree on, two at
    /// least and six in ten, within a point and a half, as apps round to
    /// whole points. Things that stay put, like a sticky header, tell
    /// nothing of it. Nothing at all moved, three things or more: zero, the
    /// page stayed where it was. Nil when they do not agree.
    static func told(by deltas: [Double]) -> Double? {
        let moved = deltas.filter { abs($0) >= 0.75 }.sorted()
        if moved.count <= 1 { return deltas.count - moved.count >= 3 ? 0 : nil }
        // The largest group of moves within a point and a half of each other.
        var best = 0..<0
        var low = 0
        for high in moved.indices {
            while moved[high] - moved[low] > 1.5 { low += 1 }
            if high + 1 - low > best.count { best = low..<(high + 1) }
        }
        guard best.count >= 2, best.count * 10 >= moved.count * 6 else { return nil }
        let group = moved[best]
        return group[group.startIndex + group.count / 2]
    }

    /// What the things on a page told of its moves so far, as
    /// `PageMeasure` keeps it: those that stayed put when it moved, like a
    /// sticky header or a bar fixed at the window's foot, tell nothing of a
    /// move, and only those that moved with it tell that it stayed.
    struct Moves<Thing> {
        /// Whether two answers from the app are the same thing.
        let same: (Thing, Thing) -> Bool
        private(set) var stuck: [Thing] = []
        private(set) var moving: [Thing] = []

        init(same: @escaping (Thing, Thing) -> Bool) {
            self.same = same
        }

        func isStuck(_ thing: Thing) -> Bool {
            stuck.contains { same($0, thing) }
        }

        /// How far the page moved, as `told(by:)` reads it from how far each
        /// thing moved up, noting which stayed put and which moved with it.
        /// That it stayed, only as two things or more tell it that moved
        /// with the page when it last moved.
        mutating func told(by deltas: [(thing: Thing, delta: Double)]) -> Double? {
            let told = PageWalk.told(by: deltas.map(\.delta))
            if let told, told != 0 {
                for still in deltas where abs(still.delta) < 0.75 && !isStuck(still.thing) {
                    stuck.append(still.thing)
                }
                moving = deltas.filter { abs($0.delta - told) <= 1.5 }.map(\.thing)
            }
            if told == 0, deltas.filter({ seen in
                abs(seen.delta) < 0.75 && moving.contains(where: { same($0, seen.thing) })
            }).count < 2 {
                return nil
            }
            return told
        }
    }

    /// Whether the page sat where it was between two views, as far as
    /// they tell: all of it as it was but what was seen changing by itself
    /// (`stillBut`), or nine rows in ten (`alikeInPlace`).
    static func sat(_ a: View, _ b: View) -> Bool {
        stillBut(a.rows, b.rows, restless: (a.restless, b.restless)) || alikeInPlace(a.rows, b.rows)
    }

    /// Nine rows in ten as they were, where each of the others shows
    /// something in both views, as a dot that pulses does. A row that went
    /// from plain to showing something, or back, tells that the page moved,
    /// as two views of a page with much white between its lines may be
    /// alike after a move.
    static func alikeInPlace(_ a: PageStitch.Rows, _ b: PageStitch.Rows) -> Bool {
        guard PageStitch.alike(a, b) else { return false }
        func shows(_ row: [UInt8]) -> Bool {
            guard let low = row.min(), let high = row.max() else { return false }
            return Int(high) - Int(low) > 12
        }
        return zip(a, b).allSatisfy { x, y in PageStitch.same(x, y) || (shows(x) && shows(y)) }
    }

    /// How many rows of `current` line up with `next` at this move and
    /// tell where they are: something shows on them, and they are not the
    /// same as both rows beside them, as the rows of a plain button that
    /// stays at the window's foot are, which line up at many moves.
    static func told(_ current: PageStitch.Rows, _ next: PageStitch.Rows, at step: PageStitch.Step) -> Int {
        let height = min(current.count, next.count)
        let rows = (step.top + step.shift)..<max(step.top + step.shift, height - step.bottom)
        return rows.filter { r in
            let row = current[r]
            guard let low = row.min(), let high = row.max(), Int(high) - Int(low) > 12,
                  PageStitch.same(row, next[r - step.shift]) else { return false }
            return (r > 0 && !PageStitch.same(row, current[r - 1]))
                || (r + 1 < height && !PageStitch.same(row, current[r + 1]))
        }.count
    }

    /// Whether two views, or these rows of them, are as they were with no
    /// move at all, but for what was seen changing by itself (`restless`,
    /// as `look` keeps them) and a row in fifty, like a blinking caret.
    /// Not when most of them change by themselves: then nothing tells.
    static func stillBut(_ a: PageStitch.Rows, _ b: PageStitch.Rows, restless: ([UInt64], [UInt64]),
                         rows: Range<Int>? = nil) -> Bool {
        let height = min(a.count, b.count)
        let rows = (rows ?? 0..<height).clamped(to: 0..<height)
        guard !rows.isEmpty else { return false }
        func bits(_ masks: [UInt64], _ r: Int) -> UInt64 { masks.indices.contains(r) ? masks[r] : 0 }
        let changing = rows.filter { bits(restless.0, $0) | bits(restless.1, $0) != 0 }.count
        guard changing * 3 <= rows.count else { return false }
        let differing = rows.filter { r in
            guard a[r].count == b[r].count else { return true }
            let changing = bits(restless.0, r) | bits(restless.1, r)
            return a[r].indices.contains { c in
                !(c < 64 && changing & (1 << UInt64(c)) != 0) && abs(Int(a[r][c]) - Int(b[r][c])) > 6
            }
        }.count
        return differing <= max(2, rows.count / 50)
    }

    /// Whether the rows left out of matching at the foot of `current`, the
    /// ones that came into view last, line up with `next` at this move too,
    /// but for what stayed where it was, like a chat button, and what was
    /// seen changing by itself, like a dot that pulses (`restless`, as
    /// `look` keeps them): at a move shorter or longer than asked, a line
    /// there would not.
    static func freshAgree(_ current: PageStitch.Rows, _ next: PageStitch.Rows, at step: PageStitch.Step,
                           fresh: Int, restless: ([UInt64], [UInt64]) = ([], [])) -> Bool {
        let height = min(current.count, next.count)
        let lower = height - step.bottom
        let left = PageStitch.leftOut(fresh, middle: height - step.top - step.bottom, expected: step.shift)
        let rows = min(max(step.top + step.shift, lower - left), lower)..<lower
        func bits(_ masks: [UInt64], _ r: Int) -> UInt64 { masks.indices.contains(r) ? masks[r] : 0 }
        return rows.allSatisfy { r in
            let now = current[r], moved = next[r - step.shift], stayed = next[r]
            guard now.count == moved.count, now.count == stayed.count else { return false }
            let changing = bits(restless.0, r) | bits(restless.1, r) | bits(restless.1, r - step.shift)
            return now.indices.allSatisfy { c in
                (c < 64 && changing & (1 << UInt64(c)) != 0)
                    || abs(Int(now[c]) - Int(moved[c])) <= 6 || abs(Int(now[c]) - Int(stayed[c])) <= 6
            }
        }
    }

    /// For each row of two views a moment apart, as bits, the columns that
    /// changed, if only a little: what changes by itself, when the page did
    /// not move, like a ring that pulses.
    static func restless(_ a: PageStitch.Rows, _ b: PageStitch.Rows) -> [UInt64] {
        guard a.count == b.count else { return [UInt64](repeating: 0, count: a.count) }
        return zip(a, b).map { x, y in
            var bits: UInt64 = 0
            for c in 0..<min(x.count, y.count, 64) where abs(Int(x[c]) - Int(y[c])) > 2 { bits |= 1 << UInt64(c) }
            return bits
        }
    }

    /// Whether the page stayed where it was between two views, though
    /// something on it changed by itself, like a video or a slideshow:
    /// hardly anything changed (`alikeInPlace`), or, under the toolbar, at
    /// least half of the rows are as they were and many of them show
    /// something. A plain stretch looks the same after a move, so it does
    /// not count.
    static func unmoved(_ a: PageStitch.Rows, _ b: PageStitch.Rows, below bar: Int) -> Bool {
        if alikeInPlace(a, b) { return true }
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
    /// Rows with nothing on them look alike in any place, so enough of
    /// them under the toolbar, below `bar`, must show something.
    static func samePlace(_ view: PageStitch.Rows, _ again: PageStitch.Rows, through: Int,
                          below bar: Int = 0) -> Bool {
        guard view.count == again.count, !view.isEmpty else { return false }
        let rows = 0..<min(view.count, max(through, view.count / 3))
        let differing = rows.filter { !PageStitch.same(view[$0], again[$0]) }.count
        let shown = rows.filter { r in
            guard r >= bar, let low = view[r].min(), let high = view[r].max() else { return false }
            return Int(high) - Int(low) > 12
        }.count
        return differing * 10 <= rows.count && shown >= 16
    }

    /// Two views a moment apart show the page still: at most one row in
    /// fifty changed, or two rows, so a blinking caret does not count.
    static func still(_ a: PageStitch.Rows, _ b: PageStitch.Rows) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let differing = a.indices.filter { !PageStitch.same(a[$0], b[$0]) }.count
        return differing <= max(2, a.count / 50)
    }
}
