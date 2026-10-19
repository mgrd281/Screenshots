import AppKit
import ScreenCaptureKit

/// Hide Desktop Icons, in the menu bar: the wallpaper laid over the icons on
/// every screen, so a screenshot or a recording shows a clean desktop. The
/// icons and the files stay as they are, and come back the moment it is
/// turned off. Clicks go through to what is under it. Windows stay above it,
/// so only the desktop changes; Snapfly's own screenshots keep it in.
@MainActor
final class DesktopIcons {
    static let shared = DesktopIcons()

    private static let key = "hidesDesktopIcons"

    /// Off until turned on; kept when Snapfly opens again.
    static var isHidden: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private var covers: [CGDirectDisplayID: NSWindow] = [:]
    private var watching: [NSObjectProtocol] = []
    private var refresh: Timer?

    /// The covers' window numbers, kept in Snapfly's own captures.
    var windowIDs: Set<CGWindowID> {
        Set(covers.values.map { CGWindowID($0.windowNumber) })
    }

    /// At launch: the covers again if they were on.
    func start() {
        watch()
        if Self.isHidden { show() }
    }

    func toggle() {
        Self.isHidden.toggle()
        if Self.isHidden { show() } else { hide() }
    }

    // MARK: The covers

    private func show() {
        layOut()
        // Dynamic wallpapers change through the day.
        refresh?.invalidate()
        refresh = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { DesktopIcons.shared.paint() }
        }
    }

    private func hide() {
        refresh?.invalidate()
        refresh = nil
        covers.values.forEach { $0.orderOut(nil) }
        covers = [:]
    }

    /// A cover for each screen, at its size, and none for a screen gone.
    private func layOut() {
        guard Self.isHidden else { return }
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let window = covers[id] ?? makeCover()
            window.setFrame(screen.frame, display: false)
            covers[id] = window
            window.orderFrontRegardless()
        }
        for (id, window) in covers where !seen.contains(id) {
            window.orderOut(nil)
            covers[id] = nil
        }
        paint()
    }

    private func makeCover() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        // Just above the icons and below every window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.backgroundColor = .black
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        view.imageAlignment = .alignCenter
        window.contentView = view
        return window
    }

    /// Each cover shows its screen's wallpaper as the screen shows it now,
    /// taken from the screen itself where it can be, else from its file.
    private func paint() {
        guard Self.isHidden, !covers.isEmpty else { return }
        Task { @MainActor in
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            for screen in NSScreen.screens {
                guard let id = screen.displayID, let window = covers[id],
                      let view = window.contentView as? NSImageView else { continue }
                window.backgroundColor = Self.fillColor(for: screen)
                if let content, let image = await Self.wallpaper(of: screen, in: content) {
                    view.image = NSImage(cgImage: image, size: screen.frame.size)
                } else {
                    view.image = Self.wallpaperFile(of: screen).map { Self.filled($0, to: screen.frame.size) }
                }
            }
        }
    }

    /// The wallpaper window the Dock draws for a screen, captured.
    private static func wallpaper(of screen: NSScreen, in content: SCShareableContent) async -> CGImage? {
        let frame = screen.frame
        let top = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        // Window frames count from the top left of the main screen.
        let flipped = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        let candidates = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "com.apple.dock"
                && $0.windowLayer < Int(CGWindowLevelForKey(.desktopIconWindow))
                && abs($0.frame.minX - flipped.minX) < 1 && abs($0.frame.minY - flipped.minY) < 1
                && abs($0.frame.width - flipped.width) < 1 && abs($0.frame.height - flipped.height) < 1
        }
        guard let window = candidates.min(by: { $0.windowLayer < $1.windowLayer }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(frame.width * screen.backingScaleFactor)
        config.height = Int(frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        config.captureResolution = .best
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func wallpaperFile(of screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func fillColor(for screen: NSScreen) -> NSColor {
        NSWorkspace.shared.desktopImageOptions(for: screen)?[.fillColor] as? NSColor ?? .black
    }

    /// The picture filling the screen, cut at its edges as the desktop does.
    private static func filled(_ image: NSImage, to size: CGSize) -> NSImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: CGRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
            return true
        }
    }

    // MARK: Following the screens

    private func watch() {
        guard watching.isEmpty else { return }
        let center = NotificationCenter.default
        watching.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopIcons.shared.layOut() }
        })
        watching.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopIcons.shared.paint() }
        })
    }
}
