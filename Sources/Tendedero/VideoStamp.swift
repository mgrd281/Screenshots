import AppKit

/// The time stamp on a screen recording. While Stamp the date and time is
/// on, each new recording gets the band a screenshot gets, above its
/// picture, in the video itself: the user's words and the date and time,
/// running second by second from the moment the recording began, by the
/// PTB's atomic clock when it answered; where the time came from; and the
/// whole address of the page in the browser in front, which follows the
/// pages visited while recording.
///
/// While recording, the page in front is read about once a second and only
/// its changes are kept (`Sampler`). With the moment of the first picture
/// they are kept with the file as it is saved (`Record`), before it hangs.
/// The band is then drawn in by the pass that draws Snapfly's own pointer
/// (`SmoothPointer`), so the recording is made again only once. The
/// recording Studio works from stays as it was made, without the band.
enum VideoStamp {
    /// One recording's moment and the pages it showed, kept with the file.
    struct Record: Codable, Equatable, Sendable {
        /// When the recording's first picture was taken, by the atomic clock when `atomic`.
        var began: Date
        var atomic: Bool
        /// The page in the browser in front, as it changed: from `at` seconds into the
        /// recording, `address` (a whole address, or nil when no website was in front).
        var pages: [Page]
    }

    struct Page: Codable, Equatable, Sendable {
        var at: Double
        var address: String?
    }

    // MARK: Kept with the file

    private static let recordName = "com.snapfly.video-stamp"
    /// Marks a recording whose band is drawn into its pictures.
    private static let drawnName = "com.snapfly.video-stamp.drawn"

    /// The record kept with a recording (an extended attribute, as TimeStamp keeps its own).
    static func record(of url: URL) -> Record? {
        attribute(recordName, of: url).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    /// Keeps the record with the recording; false when the file would not
    /// take it.
    @discardableResult
    static func keep(_ record: Record, with url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return setAttribute(recordName, data, on: url)
    }

    /// Whether the band is drawn into the recording's own pictures, at its
    /// top, so nothing needs to draw it over them again.
    static func isDrawnIn(_ url: URL) -> Bool {
        attribute(drawnName, of: url) != nil
    }

    /// The recording just made again with its band: the record stays with
    /// it, should replacing the file have left it behind, and it is marked
    /// as drawn in.
    static func drawnIn(_ stamp: Stamp, into url: URL) {
        keep(stamp.record, with: url)
        setAttribute(drawnName, Data([1]), on: url)
    }

    private static func attribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let read = buffer.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read == size ? buffer : nil
        }
    }

    @discardableResult
    private static func setAttribute(_ name: String, _ data: Data, on url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            let result = data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
            return result == 0
        }
    }

    // MARK: The pages

    /// The page in front at a moment of the recording.
    static func page(at t: Double, in record: Record) -> String? {
        index(at: t, in: record.pages).flatMap { record.pages[$0].address }
    }

    /// Which of the pages was in front at a moment: the last to come at or
    /// before it.
    static func index(at t: Double, in pages: [Page]) -> Int? {
        pages.lastIndex(where: { $0.at <= t })
    }

    /// The pages as noted on the host clock, timed from the recording's
    /// first picture: what was in front as it began counts from its start,
    /// even when it was noted a moment after; what was gone before then is
    /// left out, and a page noted twice in a row counts once.
    static func pages(_ seen: [(t: Double, address: String?)], since first: Double) -> [Page] {
        var pages: [Page] = []
        for (i, entry) in seen.enumerated() {
            // Another page came before the first picture: this one never showed.
            if i + 1 < seen.count, seen[i + 1].t <= first { continue }
            if let last = pages.last, last.address == entry.address { continue }
            pages.append(Page(at: pages.isEmpty ? 0 : max(0, entry.t - first), address: entry.address))
        }
        return pages
    }

    /// The same record for the recording with its first `offset` seconds
    /// trimmed off: it began that much later, and each page counts from the
    /// new start, the one in front then from its first moment.
    static func trimmed(_ record: Record, from offset: Double) -> Record {
        guard offset > 0 else { return record }
        var pages: [Page] = []
        if let i = index(at: offset, in: record.pages) { pages.append(Page(at: 0, address: record.pages[i].address)) }
        pages += record.pages.filter { $0.at > offset }.map { Page(at: $0.at - offset, address: $0.address) }
        return Record(began: record.began.addingTimeInterval(offset), atomic: record.atomic, pages: pages)
    }

    /// A recording trimmed in place, as Trim does: its record moves to the
    /// new start, as the band drawn into its pictures already has. The
    /// record and whether the band is drawn in are read before the trimmed
    /// file replaced it, which may have left them behind.
    static func trimmed(_ url: URL, from offset: Double, kept: Record?, drawn: Bool) {
        guard let kept else { return }
        keep(trimmed(kept, from: offset), with: url)
        if drawn { setAttribute(drawnName, Data([1]), on: url) }
    }

    // MARK: The band

    /// What a recording's band says, for the pass that draws it: read on
    /// the main thread, drawn on any.
    struct Stamp: Sendable {
        var record: Record
        /// The user's own words before the date (`TimeStamp.text`).
        var text: String
        var rightToLeft: Bool
        var locale: Locale = .autoupdatingCurrent
        var timeZone: TimeZone = .autoupdatingCurrent
    }

    /// The stamp to draw into a recording, with the words as they are set
    /// now; nil with the time stamp off, or for a recording without a record.
    static func stamp(for url: URL) -> Stamp? {
        guard TimeStamp.isOn, let kept = record(of: url) else { return nil }
        return Stamp(record: kept, text: TimeStamp.text, rightToLeft: TimeStamp.rightToLeft)
    }

    /// What the band says `t` seconds into the recording: the date and time
    /// then, and the page in front then. No fingerprint: a video cannot hold
    /// its own.
    static func mark(at t: Double, of stamp: Stamp) -> TimeStamp.Mark {
        mark(page: page(at: t, in: stamp.record), at: t, of: stamp)
    }

    private static func mark(page: String?, at t: Double, of stamp: Stamp) -> TimeStamp.Mark {
        let moment = TimeStamp.Record(taken: stamp.record.began.addingTimeInterval(t), atomic: stamp.record.atomic,
                                      page: page)
        return TimeStamp.mark(moment, text: stamp.text, locale: stamp.locale, timeZone: stamp.timeZone,
                              rightToLeft: stamp.rightToLeft)
    }

    /// How tall the band is on a video `width` pixels wide, the same all
    /// through it: as tall as the tallest moment needs, as the longest
    /// address it showed takes up to three lines, and even, as video wants.
    static func bandHeight(_ stamp: Stamp, width: Int) -> Int {
        let addresses: [String?] = stamp.record.pages.isEmpty ? [nil] : stamp.record.pages.map(\.address)
        let tallest = addresses.map { TimeStamp.bandHeight(mark(page: $0, at: 0, of: stamp), width: width) }.max() ?? 0
        return even(tallest)
    }

    /// The number, or the next one up when it is odd.
    static func even(_ number: Int) -> Int {
        number % 2 == 0 ? number : number + 1
    }

    /// A moment's band at the height of the whole recording's: the words
    /// where they are, the room below them in the band's own colour, and
    /// its hairline at the foot, as `TimeStamp.band` draws them.
    static func padded(_ band: CGImage, height: Int) -> CGImage? {
        guard band.height < height else { return band }
        let width = band.width
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Core Graphics counts from the bottom: the room is below the band.
        let wide = CGFloat(width), room = CGFloat(height - band.height)
        let line = max(1, (TimeStamp.Metrics(width: width).font / 16).rounded())
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: wide, height: CGFloat(height)))
        context.draw(band, in: CGRect(x: 0, y: room, width: wide, height: CGFloat(band.height)))
        // The band's own hairline, now above the room, goes under its colour.
        context.fill(CGRect(x: 0, y: room, width: wide, height: line))
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: wide, height: line))
        return context.makeImage()
    }

    /// A recording's band for each of its moments, as wide as the video and
    /// always as tall, drawn again only when what it says changes: once a
    /// second, and as another page comes to the front. Used on one queue
    /// alone, that of the export's pictures (`StudioExport`).
    final class Banner: @unchecked Sendable {
        let width: Int
        let height: Int
        private let stamp: Stamp
        /// The second and the page the band shows now, and the band.
        private var shown: (second: Int, page: Int?)?
        private var drawn: CGImage?

        init?(_ stamp: Stamp, width: Int) {
            let height = VideoStamp.bandHeight(stamp, width: width)
            guard width > 0, height > 0 else { return nil }
            self.width = width
            self.height = height
            self.stamp = stamp
        }

        /// The band `t` seconds into the recording; the last one drawn, should
        /// a new one fail.
        func image(at t: Double) -> CGImage? {
            // The time is shown to the second, as the Mac's clock shows it.
            let second = Int((stamp.record.began.timeIntervalSince1970 + t).rounded(.down))
            let page = VideoStamp.index(at: t, in: stamp.record.pages)
            if let shown, shown.second == second, shown.page == page, let drawn { return drawn }
            if let band = TimeStamp.band(VideoStamp.mark(at: t, of: stamp), width: width),
               let made = VideoStamp.padded(band.image, height: height) {
                drawn = made
            }
            shown = (second: second, page: page)
            return drawn
        }
    }

    // MARK: While recording

    /// Notes, while the screen is recorded with the time stamp on, when the
    /// recording began and the page in the browser in front as it changes.
    ///
    /// The page is read through Apple Events (`ChatButton.pageInFront`),
    /// which must be asked on the main thread and wait up to a second for a
    /// busy browser. So it is read about once a second, and a browser slow to
    /// answer is asked less often, up to every eight seconds, so neither the
    /// main thread nor the pointer Studio notes on it is held up for long.
    /// With no browser in front, nothing is asked.
    @MainActor
    final class Sampler {
        /// The host clock the recording's pictures are timed by, and the
        /// Mac's clock, read together.
        private let host = StudioCapture.now
        private let clock = Date()
        /// How far the atomic clock is ahead of the Mac's, once it answered.
        private var offset: TimeInterval?
        private var answered = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        /// The page in front as it changed, on the host clock.
        private var seen: [(t: Double, address: String?)] = []
        private var timer: Timer?
        /// Seconds between questions, and until the next one.
        private var every = 1
        private var left = 1

        /// Asks the atomic clock now, as the recording starts, and notes the
        /// page in front; then about once a second.
        func start() {
            AtomicTime.offset { [weak self] offset in
                MainActor.assumeIsolated { self?.answer(offset) }
            }
            // Should no answer come, the Mac's clock it is.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                MainActor.assumeIsolated { self?.answer(nil) }
            }
            note()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            // Also while a menu is open, which is often what is shown.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        /// The record, timed from the recording's first picture on the host
        /// clock, once the atomic clock has answered or given up, which it
        /// does within a few seconds of the start.
        func record(since first: Double) async -> Record {
            if !answered {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    waiting.append(continuation)
                }
            }
            let began = clock.addingTimeInterval(first - host + (offset ?? 0))
            return Record(began: began, atomic: offset != nil, pages: VideoStamp.pages(seen, since: first))
        }

        private func answer(_ offset: TimeInterval?) {
            guard !answered else { return }
            answered = true
            self.offset = offset
            let waiting = self.waiting
            self.waiting = []
            waiting.forEach { $0.resume() }
        }

        private func tick() {
            left -= 1
            if left <= 0 { note() }
        }

        /// Notes the page in front, if it changed since.
        private func note() {
            let t = StudioCapture.now
            let asked = Date()
            let address = ChatButton.pageInFront().flatMap { StampSite.address(of: $0.absoluteString) }
            every = Date().timeIntervalSince(asked) > 0.25 ? min(every * 2, 8) : 1
            left = every
            if let last = seen.last, last.address == address { return }
            seen.append((t: t, address: address))
        }
    }
}
