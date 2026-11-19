import AppKit
import ScreenCaptureKit

/// A whole chat, from its first message to its last, taken by itself: a
/// screenshot of each view as Snapfly scrolls down through it, and a short
/// video of the same scroll, which stops by itself at the bottom. Made for
/// a conversation with a customer, to keep or to send as it was.
///
/// It scrolls the window in front as Capture Whole Page does, but keeps each
/// view as a picture of its own instead of joining them, and glides between
/// them so the video reads like a hand scrolling. The pictures and the video
/// hang on the line once it is done. A click on the note stops it early,
/// and what was taken until then is kept.
///
/// It needs Screen Recording, to capture the window, and the permission to
/// press keys, to scroll it.
@MainActor
final class ChatCapture {
    static let shared = ChatCapture()

    /// Called with each picture and the video, top first, once they are saved.
    var onCapture: (URL) -> Void = { _ in }

    private(set) var isRunning = false
    /// Asked by a click on the note: stop where it is and keep what was taken.
    private var stopAsked = false

    /// Long enough for a chat that loads its pictures as they come into view.
    private nonisolated static let settle: UInt64 = 450_000_000
    /// A chat longer than this many views is cut there.
    static let maxViews = 40

    /// Stops where it is; what was taken until then is kept.
    func stop() {
        stopAsked = true
    }

    /// - Parameter delay: lets a menu that started it fade out first.
    func start(after delay: TimeInterval = 0) {
        guard !isRunning, !FullPage.shared.isRunning, !Recording.shared.isRecording,
              !Countdown.shared.isRunning, Capture.shared.hasPermission() else { return }
        guard Paste.isAllowed else {
            Paste.askToBeAllowed()
            Notice.show(L("To scroll the chat, Snapfly needs to press keys for you. Allow it in System Settings, then try again."))
            return
        }
        guard let app = Paste.frontApp, let window = FullPage.frontWindow(of: app.processIdentifier) else {
            Notice.show(L("Open the chat to capture first, then try again."))
            return
        }
        isRunning = true
        stopAsked = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                await self.capture(window)
                self.isRunning = false
            }
        }
    }

    private func capture(_ target: (id: CGWindowID, frame: CGRect)) async {
        let note = Notice.show(L("Capturing the chat… Click to stop."), working: true) {
            ChatCapture.shared.stopAsked = true
        }
        defer { Notice.end(note) }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == target.id }) else {
            Notice.show(L("The chat could not be captured."))
            return
        }
        // The window alone, as a screenshot of it and as a video, without
        // the pointer, which rests still over the chat.
        let top = NSScreen.screens.first?.frame.height ?? 0
        let region = Capture.Region.window(Capture.Target(
            frame: CGRect(x: target.frame.minX, y: top - target.frame.maxY,
                          width: target.frame.width, height: target.frame.height),
            window: window))
        guard let still = Capture.setup(region, in: content, forVideo: false),
              let film = Capture.setup(region, in: content, forVideo: true) else {
            Notice.show(L("The chat could not be captured."))
            return
        }
        still.config.showsCursor = false
        film.config.showsCursor = false

        // Once the shortcut's keys are let go: a ⌃ or ⌥ still held would
        // turn the scrolling into a zoom.
        await FullPage.waitForKeysUp()

        // The pointer rests over the chat, clear of Snapfly's own windows,
        // so the scrolling reaches the conversation itself; it goes back
        // where it was afterwards.
        let pointer = CGEvent(source: nil)?.location
        let own = NSApp.windows.filter(\.isVisible).map { Scrolling.topLeft($0.frame, screenHeight: top) }
        let over = Scrolling.clear(ChatScroll.restingPoint(in: target.frame, pointer: pointer), of: own)
        _ = CGWarpMouseCursorPosition(over)
        defer { if let pointer { _ = CGWarpMouseCursorPosition(pointer) } }

        func shot() async -> (image: CGImage, rows: PageStitch.Rows)? {
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: still.filter,
                                                                          configuration: still.config),
                  let rows = PageStitch.rows(of: image) else { return nil }
            return (image, rows)
        }
        func wait(_ nanoseconds: UInt64 = Self.settle) async {
            try? await Task.sleep(nanoseconds: nanoseconds)
        }

        // To the first message: up, until the view stops changing.
        var last = await shot()?.rows
        for _ in 0..<40 {
            FullPage.scroll(by: 4000, at: over)
            await wait(Self.settle / 3)
            guard let now = await shot()?.rows else { break }
            if let last, !ChatScroll.moved(last, now) { break }
            last = now
        }
        await wait()

        // The video starts at the top, held a moment before it scrolls.
        let stamp = Capture.stamp()
        var recorder: Recorder?
        var movie: URL?
        do {
            try FileManager.default.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
            // Hidden while it is written, so the folder watcher leaves it
            // alone, and named as a recording is, so one cut short is kept.
            let file = Inbox.folder.appendingPathComponent(".recording-\(UUID().uuidString).mov")
            let started = try Recorder(filter: film.filter, configuration: film.config, url: file)
            started.onFailure = {
                DispatchQueue.main.async { MainActor.assumeIsolated { ChatCapture.shared.stopAsked = true } }
            }
            try await started.start()
            recorder = started
            movie = file
        } catch {
            log.error("Could not record the chat: \(error.localizedDescription, privacy: .public)")
        }
        await wait(600_000_000)

        // Most of a view at a time, so each picture overlaps the last and no
        // message falls between two; glided, so the video is smooth. The
        // bottom is where a glide no longer moves the chat.
        let step = ChatScroll.step(forHeight: target.frame.height)
        var pictures: [URL] = []
        var previous: PageStitch.Rows?
        var cut = false
        while !stopAsked {
            guard let view = await shot() else { break }
            if let previous, !ChatScroll.moved(previous, view.rows) { break }
            if let url = await save(view.image, number: pictures.count + 1, stamp: stamp, from: target.frame) {
                pictures.append(url)
            }
            previous = view.rows
            if pictures.count >= Self.maxViews {
                cut = true
                break
            }
            for piece in ChatScroll.glide(-step) {
                guard !stopAsked else { break }
                FullPage.scroll(by: CGFloat(piece), at: over)
                await wait(ChatScroll.frameTime)
            }
            await wait()
        }
        // The last message held a moment at the end of the video.
        await wait(700_000_000)

        var video: URL?
        if let recorder, let movie {
            let saved = await recorder.finish()
            // A chat that fits in one view has nothing to scroll, so no video.
            if saved, pictures.count > 1, let kept = keep(movie, stamp: stamp, from: target.frame) {
                video = kept
            } else {
                try? FileManager.default.removeItem(at: movie)
            }
        }

        guard !pictures.isEmpty else {
            Notice.show(L("The chat could not be captured."))
            return
        }
        let all = pictures + (video.map { [$0] } ?? [])
        for (index, url) in all.enumerated() {
            // One after the other, so each flies to the line on its own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(index)) {
                MainActor.assumeIsolated { ChatCapture.shared.onCapture(url) }
            }
        }
        if cut {
            Notice.show(String(format: L("The chat was longer than %d views, so it was cut there."), Self.maxViews),
                        lasting: 6)
        } else if pictures.count == 1 {
            Notice.show(L("The whole chat fits in one view: one screenshot, and no video."), lasting: 6)
        } else if recorder == nil || video == nil {
            Notice.show(L("The screenshots were saved, but the video could not be."), lasting: 6)
        }
    }

    // MARK: Saving

    /// Saved in Snapfly's folder and tagged like a screenshot of the window,
    /// numbered from the top, so it flies to the line from there.
    private func save(_ image: CGImage, number: Int, stamp: String, from frame: CGRect) async -> URL? {
        let url = Self.free("Snapfly \(stamp) chat \(number)", extension: "png")
        let area = [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
        let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard Capture.write(image, to: url) else { return false }
            Capture.tag(url, "com.apple.metadata:kMDItemIsScreenCapture", true)
            Capture.tag(url, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
            return true
        }.value
        return saved ? url : nil
    }

    /// Out of hiding, named for the chat, readable only by the user, and
    /// tagged with the window it came from.
    private func keep(_ file: URL, stamp: String, from frame: CGRect) -> URL? {
        let url = Self.free("Snapfly \(stamp) chat", extension: "mov")
        do {
            try FileManager.default.moveItem(at: file, to: url)
        } catch {
            return nil
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let area = [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
        Capture.tag(url, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
        return url
    }

    /// A name in Snapfly's folder that no file has yet.
    private static func free(_ name: String, extension ext: String) -> URL {
        let fm = FileManager.default
        var url = Inbox.folder.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = Inbox.folder.appendingPathComponent("\(name) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

/// How a chat is scrolled for its pictures and its video: from where, how
/// far at a time, how smoothly, and how its bottom is told.
enum ChatScroll {
    /// How long one turn of the glide waits for the next: sixty a second,
    /// as a screen shows them.
    static let frameTime: UInt64 = 16_000_000
    /// How many turns one glide takes: about seven tenths of a second.
    static let glideTurns = 42

    /// Where the pointer rests to scroll a chat: where it already is, when
    /// that is over the window, since that is likely the conversation; else
    /// a little right of the middle, where the conversation usually is, past
    /// a list of chats on the left. On whole points, as a pointer is.
    static func restingPoint(in frame: CGRect, pointer: CGPoint?) -> CGPoint {
        if let pointer, frame.insetBy(dx: 40, dy: 80).contains(pointer) {
            return CGPoint(x: pointer.x.rounded(), y: pointer.y.rounded())
        }
        return CGPoint(x: (frame.minX + frame.width * 0.6).rounded(), y: (frame.minY + frame.height * 0.5).rounded())
    }

    /// How far each glide goes, in points: well under half the window,
    /// since a chat's own box is usually shorter than the window, with its
    /// header above and the message box below, and no message may be
    /// skipped. Never less than 80.
    static func step(forHeight height: CGFloat) -> Int {
        max(80, Int(((height - 140) * 0.4).rounded()))
    }

    /// A scroll of this many points as `turns` turns of the wheel that start
    /// slowly, speed up and slow down again, like a hand. They add up to the
    /// whole, all with its sign; turns of nothing are left out.
    static func glide(_ points: Int, turns: Int = glideTurns) -> [Int32] {
        guard points != 0, turns > 0 else { return [] }
        let sign = points < 0 ? -1 : 1
        let whole = abs(points)
        var pieces: [Int32] = []
        var done = 0
        for turn in 1...turns {
            let t = Double(turn) / Double(turns)
            // Smoothstep: slow at both ends.
            let reached = turn == turns ? whole : Int((Double(whole) * t * t * (3 - 2 * t)).rounded())
            let piece = reached - done
            done = reached
            if piece > 0 { pieces.append(Int32(sign * piece)) }
        }
        return pieces
    }

    /// Whether the chat moved between two views. Stricter than two views
    /// being alike, since a chat's own box may fill only part of the
    /// window: more than one row in a hundred changed, or more than two
    /// rows, so a blinking caret or a typing dot alone does not count.
    static func moved(_ a: PageStitch.Rows, _ b: PageStitch.Rows) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        let differing = a.indices.filter { !PageStitch.same(a[$0], b[$0]) }.count
        return differing > max(2, a.count / 100)
    }
}
