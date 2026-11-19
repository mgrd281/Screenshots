import AppKit
import ScreenCaptureKit

/// A screenshot of a whole page, from top to bottom, however long it is.
/// Snapfly scrolls the window in front itself, captures it after each
/// scroll, and joins the views into one picture (`PageStitch`), with the
/// toolbar and any sticky header kept once. It works in a browser and in any
/// window that scrolls. The picture hangs like any screenshot, and with the
/// time stamp on it names the page it came from.
///
/// It needs Screen Recording, to capture the window, and the permission to
/// press keys, to scroll it.
@MainActor
final class FullPage {
    static let shared = FullPage()

    /// Called with the picture once it is saved.
    var onCapture: (URL) -> Void = { _ in }

    private(set) var isRunning = false
    /// Long enough for a page that loads its pictures as they come into view.
    private nonisolated static let settle: UInt64 = 450_000_000
    /// A page longer than this many views is cut there.
    private static let maxViews = 60
    /// Taller than this, a picture is hard to open; the page is cut there.
    private static let maxHeight = 40_000

    /// - Parameter delay: lets a menu that started it fade out first.
    func start(after delay: TimeInterval = 0) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                await self.capture(window)
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

    private func capture(_ target: (id: CGWindowID, frame: CGRect)) async {
        let note = Notice.show(L("Capturing the whole page…"), working: true)
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
        let band = found.band

        func shot() async -> (image: CGImage, rows: PageStitch.Rows)? {
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let rows = PageStitch.rows(of: image) else { return nil }
            return (image, band.map { PageStitch.columns(rows, $0) } ?? rows)
        }
        func wait(_ nanoseconds: UInt64 = Self.settle) async {
            try? await Task.sleep(nanoseconds: nanoseconds)
        }

        // From the top of the page: up, until the view stops changing.
        var last = await shot()?.rows
        for _ in 0..<40 {
            Self.scroll(by: 4000, at: over)
            await wait(Self.settle / 3)
            guard let now = await shot()?.rows else { break }
            if let last, PageStitch.alike(last, now) { break }
            last = now
        }
        await wait()

        // Most of a view at a time, so each new view overlaps the last. When
        // the page moves too far, or changes by itself, the step is halved
        // and tried again; when it does not move at all on the first try,
        // the keys take over from the wheel, in case the page does not
        // follow the wheel.
        var step = max(80, (target.frame.height - 140) * 0.8)
        var keys = false
        var retries = 0
        var views: [CGImage] = []
        var rows: [PageStitch.Rows] = []
        var steps: [PageStitch.Step] = []
        var height = 0
        while views.count < Self.maxViews {
            guard let view = await shot() else { break }
            if let previous = rows.last {
                let expected = keys ? target.frame.height * 0.85 : step
                guard let next = PageStitch.step(from: previous, to: view.rows, expected: Int(expected * scale)) else {
                    // No fit: back up by what was asked, then half as far.
                    guard retries < 2, !keys else { break }
                    retries += 1
                    Self.scroll(by: step, at: over)
                    await wait()
                    step = max(40, step / 2)
                    Self.scroll(by: -step, at: over)
                    await wait()
                    continue
                }
                if next.shift == 0 {
                    if views.count == 1, !keys {
                        // Maybe the wheel does not reach this page: start
                        // again from the top, by key.
                        keys = true
                        views.removeAll()
                        rows.removeAll()
                        Self.press(Self.homeKey)
                        await wait()
                        continue
                    }
                    break
                }
                steps.append(next)
                height += next.shift
                retries = 0
            } else {
                height = view.image.height
            }
            views.append(view.image)
            rows.append(view.rows)
            if height > Self.maxHeight { break }
            if keys {
                Self.press(Self.pageDownKey)
            } else {
                Self.scroll(by: -step, at: over)
            }
            await wait()
        }
        // Back to the top, where a page usually starts: by the whole height
        // of what was seen, and more.
        if keys {
            Self.press(Self.homeKey)
        } else {
            Self.scroll(by: CGFloat(height) / scale + target.frame.height * 2, at: over)
        }

        guard !views.isEmpty else {
            Notice.show(L("The page could not be captured."))
            return
        }
        let frame = target.frame
        let joined: CGImage? = await Task.detached(priority: .userInitiated) { [views, steps] in
            PageStitch.compose(views, steps: steps)
        }.value
        guard let joined else {
            Notice.show(L("The page could not be captured."))
            return
        }
        save(joined, from: frame)
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
    /// first, with no columns. `scale` is pixels a point in the views.
    static func findScroller(among points: [CGPoint], in frame: CGRect, scale: CGFloat,
                             shot: () async -> PageStitch.Rows?) async -> (point: CGPoint, band: Range<Int>?) {
        let expected = Int(probe * scale)
        var best: (point: CGPoint, band: Range<Int>?, rows: Int)?
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
                best = (point, farther.band, farther.rows)
            }
            if farther.rows >= expected * 9 / 10 { break }
        }
        guard let best, best.rows > 1 else {
            let first = points.first ?? Scrolling.restingPoint(in: frame)
            _ = CGWarpMouseCursorPosition(first)
            return (first, nil)
        }
        _ = CGWarpMouseCursorPosition(best.point)
        return (best.point, best.band)
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
    /// so it flies to the line from there, and marked as a whole page.
    private func save(_ image: CGImage, from frame: CGRect) {
        let fm = FileManager.default
        var url = Inbox.folder.appendingPathComponent("Snapfly \(Capture.stamp()) page.png")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = Inbox.folder.appendingPathComponent("Snapfly \(Capture.stamp()) page \(n).png")
            n += 1
        }
        let destination = url
        let area = [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let saved = Capture.write(image, to: destination)
            if saved {
                Capture.tag(destination, "com.apple.metadata:kMDItemIsScreenCapture", true)
                Capture.tag(destination, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
                Capture.tag(destination, TimeStamp.fullPageMarker, true)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if saved {
                        self.onCapture(destination)
                    } else {
                        Notice.show(L("The page could not be captured."))
                    }
                }
            }
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
    /// itself. `expected` is how far it was asked to move.
    static func distance(from a: PageStitch.Rows, to b: PageStitch.Rows, around column: Int,
                         expected: Int) -> (rows: Int, band: Range<Int>?) {
        guard let band = PageStitch.band(a, b, around: column), band.count >= 4 else { return (0, nil) }
        let step = PageStitch.step(from: PageStitch.columns(a, band), to: PageStitch.columns(b, band),
                                   expected: expected)
        guard let step else { return (1, band) }
        return (step.shift, step.shift > 0 ? band : nil)
    }

    /// An AppKit frame, counted from the bottom left of the main screen, as
    /// the window server counts it: from the top left.
    static func topLeft(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
