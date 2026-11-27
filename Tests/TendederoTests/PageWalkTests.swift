import XCTest
@testable import Tendedero

/// Capture Whole Page's walk down a page, on pages made up here: one whose
/// pictures load late, one whose cards fade in, a chat button that stays at
/// the window's foot, a column that sticks, a video, a page that never ends.
/// Each must reach the bottom with every row of the page once, or say why
/// it stopped.
final class PageWalkTests: XCTestCase {
    /// A made-up window over a made-up page, scrolled by the walk, with a
    /// clock that moves only when the walk waits.
    @MainActor
    final class Page {
        /// What a shot shows: the window's rows.
        typealias Shot = PageStitch.Rows

        let scale = 2
        /// The window's height and its toolbar's, in rows.
        let window: Int
        let toolbar: Int
        var rows: PageStitch.Rows
        var offset = 0
        var clock: UInt64 = 0
        var wheelWorks = true
        /// Rows the page moves past the scroll asked, the first time it
        /// scrolls down: a header above it that shrank.
        var jump = 0
        var stopAfter: Int?
        var shots = 0
        /// When each row of the page first came into view.
        var seen: [Int: UInt64] = [:]
        /// Changes made to what the window shows, given the window, the
        /// page row of each window row (nil for the toolbar) and the time.
        var effects: [(inout Shot, [Int?], Page) -> Void] = []
        var strips: [(shot: Shot, rows: Range<Int>)] = []

        init(length: Int, window: Int = 1840, toolbar: Int = 160, seed: UInt64 = 7) {
            self.window = window
            self.toolbar = toolbar
            rows = Page.made(length, seed: seed)
        }

        var content: Int { window - toolbar }
        var maxOffset: Int { max(0, rows.count - content) }

        /// Text in blocks with blank gaps between them, as a page reads.
        nonisolated static func made(_ length: Int, seed: UInt64) -> PageStitch.Rows {
            var state = seed
            func next() -> Int {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Int(state >> 33)
            }
            var rows: PageStitch.Rows = []
            while rows.count < length {
                for _ in 0..<(60 + next() % 300) {
                    rows.append((0..<PageStitch.samples).map { _ in UInt8(30 + next() % 190) })
                }
                for _ in 0..<(20 + next() % 80) {
                    rows.append([UInt8](repeating: 250, count: PageStitch.samples))
                }
            }
            return Array(rows.prefix(length))
        }

        /// A value that follows no pattern, as a video's frames.
        nonisolated static func noise(_ a: Int, _ b: Int, _ c: Int) -> UInt8 {
            var x = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
            x ^= x >> 33
            x = x &* 0xff51afd7ed558ccd
            x ^= x >> 33
            return UInt8(x % 200)
        }

        nonisolated static func toolbarRow(_ i: Int) -> [UInt8] {
            (0..<PageStitch.samples).map { UInt8(225 + (i * 3 + $0) % 25) }
        }

        func shot() -> Shot? {
            shots += 1
            if let stopAfter, shots > stopAfter { return nil }
            var where_: [Int?] = Array(repeating: nil, count: toolbar)
            var shown: Shot = (0..<toolbar).map(Page.toolbarRow)
            for r in 0..<content {
                let row = offset + r
                if row < rows.count {
                    if seen[row] == nil { seen[row] = clock }
                    shown.append(rows[row])
                    where_.append(row)
                } else {
                    shown.append([UInt8](repeating: 250, count: PageStitch.samples))
                    where_.append(nil)
                }
            }
            for effect in effects { effect(&shown, where_, self) }
            return shown
        }

        func surface() -> PageWalk<Shot>.Surface {
            PageWalk<Shot>.Surface(
                shot: { self.shot().map { (picture: $0, rows: $0) } },
                scroll: { points in
                    guard self.wheelWorks else { return }
                    var rows = points * self.scale
                    if rows < 0, self.jump > 0 {
                        rows -= self.jump
                        self.jump = 0
                    }
                    self.offset = min(max(0, self.offset - rows), self.maxOffset)
                },
                press: { key in
                    switch key {
                    case .home: self.offset = 0
                    case .pageDown: self.offset = min(self.offset + self.content - 80, self.maxOffset)
                    }
                },
                wait: { self.clock += $0 },
                stopAsked: { false },
                strip: { shot, rows in self.strips.append((shot, rows)) })
        }

        func walk(maxLength: Int = 100_000) async -> (end: PageWalk<Shot>.End, moved: Int) {
            var walk = PageWalk<Shot>(scale: Double(scale), windowHeight: Double(window / scale))
            walk.maxLength = maxLength
            return await walk.run(surface())
        }

        /// The strips, one below the other.
        var joined: PageStitch.Rows {
            strips.flatMap { Array($0.shot[$0.rows]) }
        }

        /// The toolbar, then the whole page.
        var whole: PageStitch.Rows {
            (0..<toolbar).map(Page.toolbarRow) + rows
        }
    }

    @MainActor
    func testAPlainPageIsTakenWholeToItsBottom() async {
        let page = Page(length: 30_000)
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        XCTAssertEqual(page.joined, page.whole)
        // Back at the top afterwards.
        XCTAssertEqual(page.offset, 0)
    }

    @MainActor
    func testTheStripsAreThoseTheSlicesSay() async {
        let page = Page(length: 9000)
        _ = await page.walk()
        XCTAssertEqual(page.joined.count, page.whole.count)
        // Every strip but the last ends above the fresh rows of its view.
        for strip in page.strips.dropLast() {
            XCTAssertLessThanOrEqual(strip.rows.upperBound, page.window - 240)
        }
        XCTAssertEqual(page.strips.last?.rows.upperBound, page.window)
    }

    @MainActor
    func testPicturesThatLoadLateStillReachTheBottom() async {
        let page = Page(length: 24_000)
        // Every few screens a picture, grey until 900 ms after it came into view.
        let pictures = stride(from: 1500, to: 24_000, by: 2600).map { $0..<($0 + 700) }
        page.effects.append { shown, where_, page in
            for (r, row) in where_.enumerated() {
                guard let row, pictures.contains(where: { $0.contains(row) }),
                      let since = page.seen[row], page.clock < since + 900_000_000 else { continue }
                shown[r] = [UInt8](repeating: 200, count: PageStitch.samples)
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        // Every row in its place: where the picture differs from the page,
        // it is only a picture still loading when its view was taken.
        let joined = page.joined, whole = page.whole
        XCTAssertEqual(joined.count, whole.count)
        let grey = [UInt8](repeating: 200, count: PageStitch.samples)
        let wrong = joined.indices.filter { !PageStitch.same(joined[$0], whole[$0]) }
        XCTAssertTrue(wrong.allSatisfy { row in
            joined[row] == grey && pictures.contains { $0.contains(row - page.toolbar) }
        })
    }

    @MainActor
    func testCardsThatFadeInAreTakenOnceTheyHave() async {
        let page = Page(length: 20_000)
        // Rows fade in over 600 ms once they are 120 points into the window,
        // as many shops show their cards.
        page.effects.append { shown, where_, page in
            for (r, row) in where_.enumerated() {
                guard let row, let since = page.seen[row] else { continue }
                guard r < page.window - 240 else {
                    shown[r] = [UInt8](repeating: 250, count: PageStitch.samples)
                    continue
                }
                let elapsed = page.clock - since
                let p = min(1, Double(elapsed) / 600_000_000)
                shown[r] = shown[r].map { UInt8(250 + (Double($0) - 250) * p) }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        // Every row of the page came out as it is once shown, but the last
        // view's foot, which never came 120 points into the window.
        let joined = page.joined, whole = page.whole
        XCTAssertEqual(joined.count, whole.count)
        let settled = joined.count - 240
        let wrong = (0..<settled).filter { !PageStitch.same(joined[$0], whole[$0]) }.count
        XCTAssertEqual(wrong, 0)
    }

    @MainActor
    func testAChatButtonAtTheFootShowsOnceAtTheEnd() async {
        let page = Page(length: 16_000)
        // A round button, bottom right, that stays where it is.
        let button = (page.window - 160)..<(page.window - 40)
        page.effects.append { shown, _, _ in
            for r in button {
                for c in 42..<47 { shown[r][c] = 10 }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        let joined = page.joined, whole = page.whole
        XCTAssertEqual(joined.count, whole.count)
        // The button only at the very end, where the page ends in the window.
        let marked = joined.indices.filter { joined[$0][44] == 10 && whole[$0][44] != 10 }
        XCTAssertFalse(marked.isEmpty)
        XCTAssertTrue(marked.allSatisfy { $0 >= joined.count - 160 })
    }

    @MainActor
    func testAPageBetweenAStickyHeaderAndATallBarIsWalkedInShorterSteps() async {
        let page = Page(length: 16_000)
        // A header of 100 points and a bar of 300 at the foot leave 440 of
        // page, less than the first scroll.
        let header = Page.made(200, seed: 41), bar = Page.made(600, seed: 42)
        page.effects.append { shown, _, page in
            for r in 0..<200 { shown[page.toolbar + r] = header[r] }
            for r in 0..<600 { shown[page.window - 600 + r] = bar[r] }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
    }

    @MainActor
    func testAColumnThatSticksDoesNotEndIt() async {
        let page = Page(length: 18_000)
        // A product's details on the left stay put while the page scrolls,
        // until it has scrolled 8000 rows; then they go up with the page.
        let panel = Page.made(page.content, seed: 99)
        page.effects.append { shown, where_, page in
            let past = max(0, page.offset - 8000)
            for (r, row) in where_.enumerated() where row != nil {
                let at = r - page.toolbar + past
                guard at < panel.count else { continue }
                for c in 0..<20 { shown[r][c] = panel[at][c] }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
    }

    @MainActor
    func testAVideoAtTheEndIsStillTheBottom() async {
        let page = Page(length: 8000)
        // A video in the page's last screen, a new frame at every shot.
        page.effects.append { shown, where_, page in
            for (r, row) in where_.enumerated() {
                guard let row, row >= 6800, row < 7300 else { continue }
                for c in 8..<40 { shown[r][c] = Page.noise(page.shots, r, c) }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
    }

    @MainActor
    func testAVideoOverMostOfTheLastScreenIsStillTheBottom() async {
        let page = Page(length: 8000)
        // A video 500 points tall across the page, where the page ends.
        page.effects.append { shown, where_, page in
            for (r, row) in where_.enumerated() {
                guard let row, row >= 6700, row < 7700 else { continue }
                for c in 2..<46 { shown[r][c] = Page.noise(page.shots, r, c) }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
    }

    @MainActor
    func testAHeaderThatShrinksOnTheFirstScrollIsFollowed() async {
        let page = Page(length: 12_000)
        // 12 points more than asked, as a sticky header that shrinks.
        page.jump = 24
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        XCTAssertEqual(page.joined, page.whole)
    }

    @MainActor
    func testATallBandOfOneColourIsCrossed() async {
        let page = Page(length: 12_000)
        // 900 points of plain white in the middle of the page.
        for r in 4000..<5800 { page.rows[r] = [UInt8](repeating: 250, count: PageStitch.samples) }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        XCTAssertEqual(page.joined, page.whole)
    }

    @MainActor
    func testAPageThatNeverEndsIsCut() async {
        let page = Page(length: 60_000)
        let result = await page.walk(maxLength: 10_000)
        XCTAssertEqual(result.end, .long)
        XCTAssertGreaterThanOrEqual(result.moved, 20_000)
        XCTAssertLessThan(result.moved, page.maxOffset)
        XCTAssertEqual(page.joined, Array(page.whole.prefix(page.joined.count)))
    }

    @MainActor
    func testAPageThatChangesWhollyIsNotPassedOffAsWhole() async {
        let page = Page(length: 12_000)
        page.effects.append { shown, where_, page in
            guard page.offset > 3000 else { return }
            let shot = page.shots
            for (r, row) in where_.enumerated() where row != nil {
                shown[r] = (0..<PageStitch.samples).map { (c: Int) -> UInt8 in Page.noise(shot, r, c) }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .changing)
        XCTAssertLessThan(result.moved, page.maxOffset)
    }

    @MainActor
    func testAPageTheWheelDoesNotReachGoesByKey() async {
        let page = Page(length: 9000)
        page.wheelWorks = false
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
        XCTAssertEqual(page.joined, page.whole)
    }

    @MainActor
    func testAVideoAtTheTopOfAPageTheWheelDoesNotReachStillGoesByKey() async {
        let page = Page(length: 9000)
        page.wheelWorks = false
        page.effects.append { shown, where_, page in
            for (r, row) in where_.enumerated() {
                guard let row, row >= 100, row < 500 else { continue }
                for c in 8..<40 { shown[r][c] = Page.noise(page.shots, r, c) }
            }
        }
        let result = await page.walk()
        XCTAssertEqual(result.end, .bottom)
        XCTAssertEqual(result.moved, page.maxOffset)
    }

    @MainActor
    func testAWindowThatGoesAwayEndsTheWalk() async {
        let page = Page(length: 9000)
        page.stopAfter = 0
        let result = await page.walk()
        XCTAssertEqual(result.end, .nothing)
        XCTAssertTrue(page.strips.isEmpty)
    }

    @MainActor
    func testItStopsWhenAsked() async {
        let page = Page(length: 30_000)
        var asked = 0
        var walk = PageWalk<Page.Shot>(scale: 2, windowHeight: 920)
        walk.maxLength = 100_000
        var surface = page.surface()
        surface.stopAsked = {
            asked += 1
            return asked > 3
        }
        let result = await walk.run(surface)
        XCTAssertEqual(result.end, .stopped)
        XCTAssertEqual(page.joined, Array(page.whole.prefix(page.joined.count)))
        XCTAssertGreaterThan(page.joined.count, page.window)
    }

    func testTwoViewsAMomentApartAreStillDespiteACaret() {
        let rows: PageStitch.Rows = Page.made(400, seed: 3)
        var blink = rows
        blink[10] = [UInt8](repeating: 0, count: PageStitch.samples)
        XCTAssertTrue(PageWalk<Int>.still(rows, blink))
        var fading = rows
        for i in 100..<160 { fading[i] = fading[i].map { $0 / 2 } }
        XCTAssertFalse(PageWalk<Int>.still(rows, fading))
    }
}
