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
    private static let settle: UInt64 = 450_000_000
    /// A page longer than this many views is cut there.
    private static let maxViews = 60
    /// Taller than this, a picture is hard to open; the page is cut there.
    private static let maxHeight = 40_000

    /// - Parameter delay: lets a menu that started it fade out first.
    func start(after delay: TimeInterval = 0) {
        guard !isRunning, !Countdown.shared.isRunning, Capture.shared.hasPermission() else { return }
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
    private static func frontWindow(of pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
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

        // The pointer rests over the page, near its edge, so the scrolling
        // reaches the page itself; it goes back where it was afterwards.
        let pointer = CGEvent(source: nil)?.location
        let over = CGPoint(x: target.frame.maxX - 24, y: target.frame.midY + target.frame.height * 0.1)
        _ = CGWarpMouseCursorPosition(over)
        defer { if let pointer { _ = CGWarpMouseCursorPosition(pointer) } }

        // From the top of the page.
        for _ in 0..<12 { Self.scroll(by: 5000, at: over) }
        try? await Task.sleep(nanoseconds: Self.settle)

        // Most of a view at a time, so each new view overlaps the last.
        let step = max(80, (target.frame.height - 140) * 0.8)
        var views: [CGImage] = []
        var rows: [PageStitch.Rows] = []
        var steps: [PageStitch.Step] = []
        var height = 0
        while views.count < Self.maxViews {
            guard let view = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let viewRows = PageStitch.rows(of: view) else { break }
            if let previous = rows.last {
                guard let next = PageStitch.step(from: previous, to: viewRows, expected: Int(step * scale)),
                      next.shift > 0 else { break }
                steps.append(next)
                height += next.shift
            } else {
                height = view.height
            }
            views.append(view)
            rows.append(viewRows)
            if height > Self.maxHeight { break }
            Self.scroll(by: -step, at: over)
            try? await Task.sleep(nanoseconds: Self.settle)
        }
        // Back to the top, where a page usually starts.
        for _ in 0..<12 { Self.scroll(by: 5000, at: over) }

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

    /// One turn of the scroll wheel, by this many points: up when positive.
    private static func scroll(by points: CGFloat, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(points.rounded()), wheel2: 0, wheel3: 0) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
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
