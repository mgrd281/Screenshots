import AppKit
import ScreenCaptureKit

/// A screenshot of a whole page, from top to bottom, however long it is.
/// Snapfly scrolls the window in front itself, captures it after each
/// scroll once the page is still, and joins the views into one picture
/// (`PageWalk`, `PageStitch`), with the toolbar and any sticky header kept
/// once. It works in a browser and in any window that scrolls. A page too
/// long for one picture goes on in the next, one below the other. The
/// pictures hang like any screenshot, and with the time stamp on them name
/// the page they came from. Taken as a PDF, the PDF of them hangs too, on
/// paper pages. A click on the note stops it early, and what was taken
/// until then is kept.
///
/// It needs Screen Recording, to capture the window, and the permission to
/// press keys, to scroll it.
@MainActor
final class FullPage {
    static let shared = FullPage()

    /// Called with each picture once it is saved, top first.
    var onCapture: (URL) -> Void = { _ in }
    /// Called with the pictures of a page taken as a PDF, top first, once
    /// they are saved; they hang through `onCapture` as well.
    var onPDF: ([URL]) -> Void = { _ in }

    private(set) var isRunning = false
    /// Asked by a click on the note or from the menu: stop where it is and
    /// keep what was taken.
    private var stopAsked = false
    /// Long enough for a page that loads its pictures as they come into view.
    private nonisolated static let settle: UInt64 = 450_000_000
    /// Taller than this, one picture is hard to open: a longer page goes on
    /// in another picture, below it.
    nonisolated static let maxHeight = 40_000
    /// A page longer than this many points is cut there, like a feed that
    /// never ends.
    private static let maxLength = 100_000

    /// Stops where it is; what was taken until then is kept.
    func stop() {
        stopAsked = true
    }

    /// - Parameters:
    ///   - delay: lets a menu that started it fade out first.
    ///   - asPDF: also make a PDF of the whole page once it hangs.
    func start(after delay: TimeInterval = 0, asPDF: Bool = false) {
        guard !isRunning, !ChatCapture.shared.isRunning, !Countdown.shared.isRunning,
              Capture.shared.hasPermission() else { return }
        guard Paste.isAllowed else {
            Paste.askToBeAllowed()
            Notice.show(L("To scroll the page, Snapfly needs to press keys for you. Allow it in System Settings, then try again."))
            return
        }
        guard let app = Paste.frontApp, let window = Self.frontWindow(of: app.processIdentifier) else {
            Notice.show(L("Open the page to capture first, then try again."))
            return
        }
        isRunning = true
        stopAsked = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                await self.capture(window, asPDF: asPDF)
                self.isRunning = false
            }
        }
    }

    /// The window in front of an app, as the window server lists it: its
    /// number and its frame, counted from the top left of the main screen.
    static func frontWindow(of pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 100, frame.height > 100 else { continue }
            return (number, frame)
        }
        return nil
    }

    private func capture(_ target: (id: CGWindowID, frame: CGRect), asPDF: Bool) async {
        let note = Notice.show(L("Capturing the whole page… Click to stop."), working: true) {
            FullPage.shared.stopAsked = true
        }
        defer { Notice.end(note) }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == target.id }) else {
            Notice.show(L("The page could not be captured."))
            return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(target.frame.width * scale)
        config.height = Int(target.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        // Once the shortcut's keys are let go: a ⌃ or ⌥ still held would
        // turn the scrolling into a zoom.
        await Self.waitForKeysUp()

        // The pointer rests over what scrolls, clear of Snapfly's own
        // windows, so the scrolling reaches it: the page itself, or a box
        // of its own that holds the content, like a chat's; it goes back
        // where it was afterwards.
        let pointer = CGEvent(source: nil)?.location
        defer { if let pointer { _ = CGWarpMouseCursorPosition(pointer) } }
        func whole() async -> PageStitch.Rows? {
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            else { return nil }
            return PageStitch.rows(of: image)
        }
        let points = Scrolling.candidates(in: target.frame, pointer: pointer, chat: false)
            .map { Self.clearOfOwnWindows($0) }
        let found = await Self.findScroller(among: points, in: target.frame, scale: scale, shot: whole)
        let over = found.point
        // Only the columns that scroll are compared, so a part that stays
        // beside them, like a list beside a chat, does not hide the move.
        let band = Scrolling.compared(found.band)

        func shot() async -> (picture: CGImage, rows: PageStitch.Rows)? {
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let rows = PageStitch.rows(of: image) else { return nil }
            return (image, PageStitch.columns(rows, band))
        }

        // Each strip is kept as it comes, and each view let go; a page
        // taller than one picture goes on in the next.
        let stamp = Capture.stamp()
        let frame = target.frame
        var strips: [CGImage] = []
        var height = 0
        var saving: [Task<URL?, Never>] = []
        func close() {
            guard !strips.isEmpty else { return }
            let part = strips, number = saving.count + 1
            strips = []
            height = 0
            saving.append(Task.detached(priority: .userInitiated) {
                guard let joined = PageStitch.stack(part) else { return nil }
                return Self.save(joined, part: number, stamp: stamp, from: frame)
            })
        }
        var walk = PageWalk<CGImage>(scale: Double(scale), windowHeight: Double(target.frame.height))
        walk.settle = Self.settle
        walk.maxLength = Self.maxLength
        let walked = await walk.run(PageWalk<CGImage>.Surface(
            shot: shot,
            scroll: { Self.scroll(by: CGFloat($0), at: over) },
            press: { Self.press($0 == .home ? Self.homeKey : Self.pageDownKey) },
            wait: { try? await Task.sleep(nanoseconds: $0) },
            stopAsked: { FullPage.shared.stopAsked },
            strip: { view, rows in
                guard let piece = PageStitch.strip(of: view, rows: rows) else { return }
                if height + piece.height > Self.maxHeight { close() }
                strips.append(piece)
                height += piece.height
            }))
        close()
        var parts: [URL] = []
        for task in saving {
            if let url = await task.value { parts.append(url) }
        }

        guard !parts.isEmpty else {
            Notice.show(L("The page could not be captured."))
            return
        }
        for (index, url) in parts.enumerated() {
            // One after the other, so each flies to the line on its own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(index)) {
                MainActor.assumeIsolated { FullPage.shared.onCapture(url) }
            }
        }
        switch walked.end {
        case _ where parts.count < saving.count:
            Notice.show(L("The page could not be captured."))
        case .long:
            Notice.show(L("The page was too long, so it was cut there."), lasting: 6)
        case .changing:
            Notice.show(L("The page kept changing as it scrolled, so the picture may stop before its end."),
                        lasting: 6)
        default:
            if parts.count > 1 {
                Notice.show(String(format: L("The page is long, so it hangs as %d pictures, one below the other."),
                                   parts.count), lasting: 6)
            }
        }
        if asPDF {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(parts.count) + 0.3) {
                MainActor.assumeIsolated { FullPage.shared.onPDF(parts) }
            }
        }
    }

    // MARK: Scrolling the window in front

    /// A point to scroll at, moved clear of Snapfly's own windows, like the
    /// screenshot button at the screen's edge.
    static func clearOfOwnWindows(_ point: CGPoint) -> CGPoint {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let own = NSApp.windows.filter(\.isVisible).map { Scrolling.topLeft($0.frame, screenHeight: screenHeight) }
        return Scrolling.clear(point, of: own)
    }

    /// How far each point is tried: a little, up and back, then down and
    /// back. Where the window is left then does not matter, since the
    /// capture starts by scrolling to the top.
    private static let probe: CGFloat = 300

    /// Of the points given, tried in turn, the one where the window scrolls
    /// the farthest, and the columns that scrolled there: the page itself,
    /// or a box of its own, like a chat's, beside parts that stay put. The
    /// first that moves as far as asked wins at once; when none moves, the
    /// first, with no columns. Also how tall the part that scrolls is, in
    /// rows, or zero when that is not sure. `scale` is pixels a point in the
    /// views.
    static func findScroller(among points: [CGPoint], in frame: CGRect, scale: CGFloat,
                             shot: () async -> PageStitch.Rows?) async
        -> (point: CGPoint, band: Range<Int>?, span: Int) {
        let expected = Int(probe * scale)
        var best: (point: CGPoint, band: Range<Int>?, rows: Int, span: Int)?
        for point in points {
            _ = CGWarpMouseCursorPosition(point)
            let column = Scrolling.column(of: point, in: frame)
            guard let start = await shot() else { continue }
            scroll(by: probe, at: point)
            try? await Task.sleep(nanoseconds: settle / 2)
            guard let up = await shot() else { continue }
            scroll(by: -probe, at: point)
            try? await Task.sleep(nanoseconds: settle / 2)
            guard let back = await shot() else { continue }
            scroll(by: -probe, at: point)
            try? await Task.sleep(nanoseconds: settle / 2)
            guard let down = await shot() else { continue }
            scroll(by: probe, at: point)
            try? await Task.sleep(nanoseconds: settle / 2)
            // Scrolled up, the view before follows the one after.
            let rise = Scrolling.distance(from: up, to: start, around: column, expected: expected)
            let fall = Scrolling.distance(from: back, to: down, around: column, expected: expected)
            let farther = fall.rows >= rise.rows ? fall : rise
            if best == nil || farther.rows > best!.rows {
                best = (point, farther.band, farther.rows, farther.span)
            }
            if farther.rows >= expected * 9 / 10 { break }
        }
        guard let best, best.rows > 1 else {
            let first = points.first ?? Scrolling.restingPoint(in: frame)
            _ = CGWarpMouseCursorPosition(first)
            return (first, nil, 0)
        }
        _ = CGWarpMouseCursorPosition(best.point)
        return (best.point, best.band, best.span)
    }

    /// Until the shortcut's keys are let go, a second at most.
    static func waitForKeysUp() async {
        for _ in 0..<50 {
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            if held.isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Turns of the scroll wheel adding up to this many points: up when
    /// positive. Given in small pieces, as a wheel gives them, since apps are
    /// wary of one large value; and marked as pixels, so the page moves by
    /// just that much.
    static func scroll(by points: CGFloat, at point: CGPoint) {
        for piece in Scrolling.pieces(of: Int(points.rounded())) {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: piece, wheel2: 0, wheel3: 0) else { continue }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.location = point
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    /// Home and Page Down, as the keyboard numbers them.
    private static let homeKey: CGKeyCode = 0x73
    private static let pageDownKey: CGKeyCode = 0x79

    /// One press of a key, in the app in front.
    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Saved in Snapfly's folder and tagged like a screenshot of the window,
    /// so it flies to the line from there, and marked as a whole page, with
    /// which picture of it this is when it took more than one.
    private nonisolated static func save(_ image: CGImage, part: Int, stamp: String, from frame: CGRect) -> URL? {
        let fm = FileManager.default
        let name = part == 1 ? "Snapfly \(stamp) page" : "Snapfly \(stamp) page part \(part)"
        var url = Inbox.folder.appendingPathComponent("\(name).png")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = Inbox.folder.appendingPathComponent("\(name) \(n).png")
            n += 1
        }
        guard Capture.write(image, to: url) else { return nil }
        let area = [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
        Capture.tag(url, "com.apple.metadata:kMDItemIsScreenCapture", true)
        Capture.tag(url, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
        Capture.tag(url, TimeStamp.fullPageMarker, true)
        Capture.tag(url, partMarker, ["capture": stamp, "part": part] as [String: Any])
        return url
    }

    /// Which picture of a whole page a file is: the capture it came from,
    /// as its time, and its place, from 1 at the top.
    private nonisolated static let partMarker = "com.snapfly.full-page-part"

    nonisolated static func part(of url: URL) -> (capture: String, number: Int)? {
        guard let data = attribute(partMarker, of: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let capture = value["capture"] as? String, let number = value["part"] as? Int else { return nil }
        return (capture, number)
    }

    /// Whether a file is a picture of a whole page, or of part of one.
    nonisolated static func isWholePage(_ url: URL) -> Bool {
        attribute(TimeStamp.fullPageMarker, of: url) != nil || attribute(partMarker, of: url) != nil
    }

    private nonisolated static func attribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let read = buffer.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read == size ? buffer : nil
        }
    }
}

/// How the window in front is scrolled: in what pieces, and from where.
enum Scrolling {
    /// The most one turn of the wheel says, in points. Apple warns that a
    /// large value may do something unexpected in the app that gets it.
    static let mostPerTurn = 100

    /// A scroll of this many points as turns of the wheel, each no more than
    /// `mostPerTurn`, all with the sign of the whole.
    static func pieces(of points: Int) -> [Int32] {
        guard points != 0 else { return [] }
        let sign = points < 0 ? -1 : 1
        var left = abs(points)
        var pieces: [Int32] = []
        while left > 0 {
            let piece = min(left, mostPerTurn)
            pieces.append(Int32(sign * piece))
            left -= piece
        }
        return pieces
    }

    /// Where the pointer rests over a window to scroll it: 90% across and
    /// 55% down, away from the edges, where a page's own scrolling boxes
    /// seldom are. On whole points, as a pointer is.
    static func restingPoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: (frame.minX + frame.width * 0.9).rounded(), y: (frame.minY + frame.height * 0.55).rounded())
    }

    /// The point moved left, 80 points at a time, until it is 12 points clear
    /// of every frame given, at most five times.
    static func clear(_ point: CGPoint, of frames: [CGRect]) -> CGPoint {
        var point = point
        var moves = 0
        while moves < 5, frames.contains(where: { $0.insetBy(dx: -12, dy: -12).contains(point) }) {
            point.x -= 80
            moves += 1
        }
        return point
    }

    /// Where to try scrolling a window, in turn: for a whole page, first
    /// the resting point, where a page's own boxes seldom are; for a chat,
    /// first the pointer when it is over the window, since that is likely
    /// the conversation. Then a little right of the middle, where a chat
    /// usually is past a list of chats, then left of it. No two closer than
    /// 40 points.
    static func candidates(in frame: CGRect, pointer: CGPoint?, chat: Bool) -> [CGPoint] {
        let resting = restingPoint(in: frame)
        let mine = pointer.flatMap { frame.insetBy(dx: 40, dy: 80).contains($0) ? $0 : nil }
            .map { CGPoint(x: $0.x.rounded(), y: $0.y.rounded()) }
        let right = CGPoint(x: (frame.minX + frame.width * 0.6).rounded(), y: (frame.minY + frame.height * 0.5).rounded())
        let left = CGPoint(x: (frame.minX + frame.width * 0.35).rounded(), y: (frame.minY + frame.height * 0.55).rounded())
        let order = chat ? [mine, right, left, resting] : [resting, mine, right, left]
        var points: [CGPoint] = []
        for case let point? in order where !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 40 }) {
            points.append(point)
        }
        return points
    }

    /// Which column of `PageStitch`'s samples a point over the window is in.
    static func column(of point: CGPoint, in frame: CGRect) -> Int {
        guard frame.width > 0 else { return 0 }
        let column = Int(((point.x - frame.minX) / frame.width * CGFloat(PageStitch.samples)).rounded(.down))
        return min(max(column, 0), PageStitch.samples - 1)
    }

    /// How far the part under `column` moved from one view to the next,
    /// in rows, and which columns moved: zero and nil when nothing did; one
    /// row when something changed but no move fits, as when it changed by
    /// itself. `expected` is how far it was asked to move. With it, how
    /// tall the part that moves is, in rows, between what stays above and
    /// below it, like a chat's box between its header and its message box;
    /// zero when that is not sure, as when what stays is too tall to tell;
    /// and how many rows at the top stayed, like a toolbar and a header.
    static func distance(from a: PageStitch.Rows, to b: PageStitch.Rows, around column: Int,
                         expected: Int) -> (rows: Int, band: Range<Int>?, span: Int, top: Int) {
        guard let band = PageStitch.band(a, b, around: column), band.count >= 4 else { return (0, nil, 0, 0) }
        let rows = PageStitch.columns(a, band)
        let step = PageStitch.step(from: rows, to: PageStitch.columns(b, band), expected: expected)
        guard let step else { return (1, band, 0, 0) }
        guard step.shift > 0 else { return (0, nil, 0, 0) }
        // Bars that stay are found up to a third of the window; one that
        // tall may be taller still, and the box shorter than it seems.
        let most = rows.count * 35 / 100
        let sure = step.top < most && step.bottom < most
        return (step.shift, band, sure ? rows.count - step.top - step.bottom : 0, step.top)
    }

    /// The columns a whole page is matched on: those that scrolled, less a
    /// column at either edge of the window, where a scroll bar comes and
    /// goes as the page moves.
    static func compared(_ band: Range<Int>?) -> Range<Int> {
        let band = band ?? 0..<PageStitch.samples
        let lower = band.lowerBound == 0 ? 1 : band.lowerBound
        let upper = band.upperBound == PageStitch.samples ? PageStitch.samples - 1 : band.upperBound
        return lower < upper ? lower..<upper : band
    }

    /// An AppKit frame, counted from the bottom left of the main screen, as
    /// the window server counts it: from the top left.
    static func topLeft(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
