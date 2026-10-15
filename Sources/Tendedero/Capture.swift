import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Takes screenshots from Snapfly itself, with its own shortcut, so nothing
/// has to be set up in the Screenshot app first.
///
/// The screens are captured first and shown still, slightly dimmed. Drag
/// over an area, click a window, or press Return for the whole screen;
/// Escape cancels. The screenshot is saved in Snapfly's folder, tagged as a
/// screenshot with the area it came from, and flies to the line like one
/// taken with the Screenshot app.
///
/// The same screens choose what a timed screenshot takes, a few seconds
/// later, and what a screen recording records.
@MainActor
final class Capture {
    static let shared = Capture()

    /// Called with each screenshot once it is saved.
    var onCapture: (URL) -> Void = { _ in }

    private var overlays: [CaptureOverlay] = []
    /// Between the shortcut and the still screens showing up.
    private var freezing = false
    private var mode = Mode.screenshot

    /// What the choice on the still screens is for.
    enum Mode: Equatable {
        /// A screenshot of the still screens, at once.
        case screenshot
        /// A screenshot of the live screen, this many seconds after the
        /// choice, so a menu opened meanwhile is in it.
        case timer(Int)
        /// A screen recording, until it is stopped.
        case record

        var title: String {
            switch self {
            case .screenshot: L("Take Screenshot")
            case .timer: L("Take Screenshot with Timer")
            case .record: L("Record Screen")
            }
        }

        var hint: String {
            switch self {
            case .screenshot: L("Drag over an area or click a window. Return takes the whole screen, Escape cancels.")
            case .timer: L("Choose what to take: drag over an area, click a window, or press Return for the whole screen. It is taken when the countdown ends.")
            case .record: L("Drag over an area or click a window to record it. Return records the whole screen, Escape cancels.")
            }
        }
    }

    /// How long a timed screenshot can wait, in the menu.
    static let timerChoices = [3, 5, 10]

    /// What is taken once the still screens are gone.
    enum Region {
        case area(CGRect, NSScreen)
        case screen(NSScreen)
        case window(Target)
    }

    private static let askedKey = "screenCaptureAsked"

    /// One window that can be clicked, in AppKit screen coordinates.
    struct Target {
        let frame: CGRect
        let window: SCWindow
    }

    enum Choice {
        case area(CGRect, NSScreen, CGImage)
        case screen(NSScreen, CGImage)
        case window(Target)
        case cancel
    }

    /// - Parameter delay: lets a menu that started it fade out first, so it
    ///   is not caught in the still screens.
    func start(after delay: TimeInterval = 0, mode: Mode = .screenshot) {
        guard !freezing, overlays.isEmpty, !Countdown.shared.isRunning,
              !(mode == .record && Recording.shared.isRecording), hasPermission() else { return }
        freezing = true
        self.mode = mode
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in await self.freezeScreens() }
        }
    }

    // MARK: Permission

    /// macOS asks once, in its own words. After that, a short note says
    /// where to turn it on.
    private func hasPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !UserDefaults.standard.bool(forKey: Self.askedKey) {
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            return CGRequestScreenCaptureAccess()
        }
        explainPermission()
        return false
    }

    private func explainPermission() {
        let alert = NSAlert()
        alert.messageText = L("Allow Snapfly to take screenshots")
        alert.informativeText = L("Turn on Snapfly for screen recording in System Settings › Privacy & Security, then try again.")
        alert.addButton(withTitle: L("Open System Settings…"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: The still screens

    private func freezeScreens() async {
        defer { freezing = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Snapfly's own line and cards stay out of the picture.
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            var stills: [(NSScreen, CGImage)] = []
            for screen in NSScreen.screens {
                guard let id = screen.displayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.showsCursor = false
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                stills.append((screen, image))
            }
            guard !stills.isEmpty else { return }
            show(stills, targets: Self.targets(in: content))
        } catch {
            log.error("Could not capture the screen: \(error.localizedDescription, privacy: .public)")
            if !CGPreflightScreenCaptureAccess() { explainPermission() }
        }
    }

    /// The windows a click can take, front to back, as the window server
    /// orders them.
    private static func targets(in content: SCShareableContent) -> [Target] {
        guard let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int) != Int(me),
                  let number = info[kCGWindowNumber as String] as? Int,
                  let window = windows[CGWindowID(number)],
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  b.width > 40, b.height > 40 else { return nil }
            // The window server counts from the top of the main screen, AppKit from the bottom.
            return Target(frame: CGRect(x: b.minX, y: main.frame.maxY - b.maxY, width: b.width, height: b.height),
                          window: window)
        }
    }

    private func show(_ stills: [(NSScreen, CGImage)], targets: [Target]) {
        let pointer = NSEvent.mouseLocation
        for (screen, image) in stills {
            let overlay = CaptureOverlay(screen: screen, still: image, targets: targets, mode: mode,
                                         showsHint: NSMouseInRect(pointer, screen.frame, false)) { [weak self] choice in
                self?.finish(choice)
            }
            overlays.append(overlay)
        }
        // The keyboard goes to the screen with the pointer, for Return and
        // Escape, without bringing Snapfly to the front.
        for overlay in overlays {
            if NSMouseInRect(pointer, overlay.frame, false) {
                overlay.makeKeyAndOrderFront(nil)
            } else {
                overlay.orderFrontRegardless()
            }
        }
        NSCursor.crosshair.set()
    }

    private func finish(_ choice: Choice) {
        guard !overlays.isEmpty else { return }
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        NSCursor.arrow.set()
        if mode != .screenshot, let region = Self.region(of: choice) {
            if case let .timer(seconds) = mode {
                takeLater(region, after: seconds)
            } else {
                Recording.shared.start(region)
            }
            return
        }
        switch choice {
        case .cancel:
            return
        case let .screen(screen, image):
            save(image, from: screen.frame)
        case let .area(rect, screen, image):
            let sx = CGFloat(image.width) / screen.frame.width
            let sy = CGFloat(image.height) / screen.frame.height
            let pixels = CGRect(x: (rect.minX - screen.frame.minX) * sx, y: (screen.frame.maxY - rect.maxY) * sy,
                                width: rect.width * sx, height: rect.height * sy).integral
            guard let cropped = image.cropping(to: pixels) else { return }
            save(cropped, from: rect)
        case let .window(target):
            Task { @MainActor in
                let filter = SCContentFilter(desktopIndependentWindow: target.window)
                let config = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                config.width = Int(filter.contentRect.width * scale)
                config.height = Int(filter.contentRect.height * scale)
                config.showsCursor = false
                config.captureResolution = .best
                config.ignoreShadowsSingleWindow = true
                do {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    self.save(image, from: target.frame)
                } catch {
                    log.error("Could not capture a window: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private static func region(of choice: Choice) -> Region? {
        switch choice {
        case .cancel: nil
        case let .area(rect, screen, _): .area(rect, screen)
        case let .screen(screen, _): .screen(screen)
        case let .window(target): .window(target)
        }
    }

    // MARK: Timer

    /// Counts down, then takes the live screen. A window is taken as the
    /// area it covers, so a menu opened over it in the meantime is in it.
    private func takeLater(_ chosen: Region, after seconds: Int) {
        var region = chosen
        if case let .window(target) = chosen {
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) })
                    ?? NSScreen.screens.first else { return }
            region = .area(target.frame.intersection(screen.frame), screen)
        }
        let taken = region
        Countdown.shared.run(seconds, on: Self.screen(of: taken)) { [weak self] in
            Task { @MainActor in await self?.takeLive(taken) }
        }
    }

    private func takeLive(_ region: Region) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let setup = Self.setup(region, in: content, forVideo: false) else {
                Notice.show(L("Could not take the screenshot."), on: Self.screen(of: region))
                return
            }
            let image = try await SCScreenshotManager.captureImage(contentFilter: setup.filter,
                                                                    configuration: setup.config)
            save(image, from: setup.frame)
        } catch {
            log.error("Could not take a timed screenshot: \(error.localizedDescription, privacy: .public)")
            Notice.show(L("Could not take the screenshot."), on: Self.screen(of: region))
        }
    }

    // MARK: Live capture

    static func screen(of region: Region) -> NSScreen? {
        switch region {
        case let .area(_, screen), let .screen(screen): return screen
        case let .window(target):
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
        }
    }

    /// What takes a region of the live screen, with Snapfly's own line and
    /// controls left out, and where it is in AppKit screen coordinates. Nil
    /// when its screen or window has gone. A video is kept within 4K, which
    /// every Mac can encode and every chat can play.
    static func setup(_ region: Region, in content: SCShareableContent, forVideo: Bool)
        -> (filter: SCContentFilter, config: SCStreamConfiguration, frame: CGRect)? {
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let config = SCStreamConfiguration()
        config.showsCursor = forVideo
        config.captureResolution = .best
        let filter: SCContentFilter
        let frame: CGRect
        var width: CGFloat, height: CGFloat
        switch region {
        case let .window(target):
            let window = content.windows.first { $0.windowID == target.window.windowID } ?? target.window
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadowsSingleWindow = true
            frame = target.frame
            let scale = CGFloat(filter.pointPixelScale)
            width = filter.contentRect.width * scale
            height = filter.contentRect.height * scale
        case let .screen(screen):
            guard let display = display(of: screen, in: content) else { return nil }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            frame = screen.frame
            width = screen.frame.width * screen.backingScaleFactor
            height = screen.frame.height * screen.backingScaleFactor
        case let .area(rect, screen):
            guard let display = display(of: screen, in: content) else { return nil }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            // The display counts from its own top left corner.
            config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                       width: rect.width, height: rect.height)
            frame = rect
            width = rect.width * screen.backingScaleFactor
            height = rect.height * screen.backingScaleFactor
        }
        if forVideo {
            (width, height) = videoSize(width, height)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 6
            config.pixelFormat = kCVPixelFormatType_32BGRA
        }
        config.width = max(1, Int(width.rounded()))
        config.height = max(1, Int(height.rounded()))
        return (filter, config, frame)
    }

    /// Within 4K, at most 3840 on the long side, and even, as video wants.
    nonisolated static func videoSize(_ width: CGFloat, _ height: CGFloat) -> (CGFloat, CGFloat) {
        let fit = min(1, 3840 / max(width, height, 1), (3840 * 2160 / max(width * height, 1)).squareRoot())
        return (max(2, (width * fit / 2).rounded() * 2), max(2, (height * fit / 2).rounded() * 2))
    }

    private static func display(of screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        guard let id = screen.displayID else { return nil }
        return content.displays.first { $0.displayID == id }
    }

    // MARK: Saving

    /// Written off the main thread, then tagged the way macOS tags its own
    /// screenshots, so the line treats it as one and knows where it flew from.
    private func save(_ image: CGImage, from rect: CGRect) {
        let fm = FileManager.default
        var url = Inbox.folder.appendingPathComponent("Snapfly \(Self.stamp()).png")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = Inbox.folder.appendingPathComponent("Snapfly \(Self.stamp()) \(n).png")
            n += 1
        }
        let destination = url
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let area = [rect.minX, top - rect.maxY, rect.width, rect.height].map { Double($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let saved = Self.write(image, to: destination)
            if saved {
                Self.tag(destination, "com.apple.metadata:kMDItemIsScreenCapture", true)
                Self.tag(destination, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if saved {
                        self.onCapture(destination)
                    } else {
                        log.error("Could not save a screenshot to \(destination.path, privacy: .public)")
                    }
                }
            }
        }
    }

    nonisolated private static func write(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return false }
        // What is on screen can be private: only the user can read it.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    nonisolated static func tag(_ url: URL, _ name: String, _ value: Any) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
        }
    }

    nonisolated static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// One screen, still, over everything else while a screenshot is chosen.
private final class CaptureOverlay: NSPanel {
    init(screen: NSScreen, still: CGImage, targets: [Capture.Target], mode: Capture.Mode, showsHint: Bool,
         done: @escaping (Capture.Choice) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = true
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        let view = CaptureView(screen: screen, still: still, targets: targets, title: mode.title, done: done)
        contentView = view
        setFrame(screen.frame, display: false)
        if showsHint { view.showHint(mode.hint) }
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the still screen, the dimming, the area being dragged or the window
/// under the pointer, and the size of what will be taken.
private final class CaptureView: NSView {
    private let screen: NSScreen
    private let still: CGImage
    private let targets: [Capture.Target]
    private let done: (Capture.Choice) -> Void

    private var dragStart: CGPoint?
    private var area: CGRect?
    private var hovered: Capture.Target?
    private var hint: NSView?
    private var finished = false

    /// How far the pointer moves before a click becomes a drag.
    private static let dragThreshold: CGFloat = 4

    init(screen: NSScreen, still: CGImage, targets: [Capture.Target], title: String,
         done: @escaping (Capture.Choice) -> Void) {
        self.screen = screen
        self.still = still
        self.targets = targets
        self.done = done
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        updateHover()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showHint(_ text: String) {
        let host = NSHostingView(rootView: CaptureHint(text: text))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Above the Dock, where there is one on this screen.
            host.bottomAnchor.constraint(equalTo: bottomAnchor,
                                         constant: -(screen.visibleFrame.minY - screen.frame.minY) - 16),
            host.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
        ])
        hint = host
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(bounds)
        guard area != nil || max(rect.width, rect.height) >= Self.dragThreshold else { return }
        area = rect
        hovered = nil
        hint?.isHidden = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let area {
            self.area = nil
            needsDisplay = true
            // Too small to be meant: wait for another try.
            guard area.width >= Self.dragThreshold, area.height >= Self.dragThreshold else { return }
            let onScreen = area.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            finish(.area(onScreen, screen, still))
        } else if let hovered {
            finish(.window(hovered))
        } else {
            finish(.screen(screen, still))
        }
    }

    override func rightMouseDown(with event: NSEvent) { finish(.cancel) }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            finish(.cancel)
        case 36, 76: // Return, Enter
            // The whole screen with the pointer, which may be another one.
            let pointer = NSEvent.mouseLocation
            if NSMouseInRect(pointer, screen.frame, false) {
                finish(.screen(screen, still))
            } else if let other = (NSApp.windows.compactMap { $0 as? CaptureOverlay }
                                    .first { NSMouseInRect(pointer, $0.frame, false) }),
                      let view = other.contentView as? CaptureView {
                view.finish(.screen(view.screen, view.still))
            }
        default:
            NSSound.beep()
        }
    }

    private func finish(_ choice: Capture.Choice) {
        guard !finished else { return }
        finished = true
        done(choice)
    }

    /// The frontmost window under the pointer, if it is on this screen.
    private func updateHover() {
        guard area == nil else { return }
        let pointer = NSEvent.mouseLocation
        let next = NSMouseInRect(pointer, screen.frame, false)
            ? targets.first { NSMouseInRect(pointer, $0.frame, false) }
            : nil
        guard next?.window.windowID != hovered?.window.windowID else { return }
        hovered = next
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.draw(still, in: bounds)

        if let area {
            // Everything but the area dims, so the area reads as what is taken.
            let shade = NSBezierPath(rect: bounds)
            shade.append(NSBezierPath(rect: area))
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill()
            shade.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let edge = NSBezierPath(rect: area.insetBy(dx: -0.5, dy: -0.5))
            edge.lineWidth = 1
            edge.stroke()
            drawSize(of: area)
        } else {
            NSColor.black.withAlphaComponent(0.12).setFill()
            bounds.fill(using: .sourceOver)
            if let hovered {
                let rect = hovered.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
                rect.fill(using: .sourceOver)
            }
        }
    }

    /// The size in points, as macOS shows it, in a small capsule below the
    /// area's trailing corner, kept on screen.
    private func drawSize(of area: CGRect) {
        let text = "\(Int(area.width.rounded())) × \(Int(area.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var capsule = CGRect(x: area.maxX - size.width - 16, y: area.minY - 26,
                             width: size.width + 16, height: 20)
        if capsule.minY < bounds.minY + 4 { capsule.origin.y = area.minY + 6 }
        capsule.origin.x = max(bounds.minX + 4, min(capsule.origin.x, bounds.maxX - capsule.width - 4))
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: 10, yRadius: 10).fill()
        text.draw(at: CGPoint(x: capsule.minX + 8, y: capsule.midY - size.height / 2), withAttributes: attributes)
    }
}

/// What to do, at the bottom of the screen with the pointer, until a drag
/// begins.
private struct CaptureHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .controlGlass(capsule: true)
            .padding(24)
    }
}
