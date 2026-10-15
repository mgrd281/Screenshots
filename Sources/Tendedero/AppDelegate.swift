import AppKit
import Carbon
import Combine
import Quartz
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let line = Line()
    private var panel: LinePanel!
    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher!
    /// In inbox mode, a second watcher on the Desktop. If a macOS version
    /// ignores the screenshot settings (macOS 27 renamed one), captures keep
    /// landing on the Desktop, and they still hang on the line.
    private var safetyWatcher: ScreenshotWatcher?
    /// Folders chosen in "Also watch folders", like the one another
    /// screenshot app saves to.
    private var folderWatchers: [ScreenshotWatcher] = []
    private var clipboardWatcher: ClipboardWatcher!
    private var signalSources: [DispatchSourceSignal] = []
    private var hotKeys: [Shortcut.Role: HotKey] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?
    /// What the settings window shows and changes.
    private var preferences: Preferences?
    /// The send button over a chat while photos hang.
    private var chatButton: ChatButton?

    /// Whether the panel is ordered in. It can be in and still tucked away
    /// above the top edge, like an auto-hiding Dock.
    private var isPresent = false
    /// Whether the line has slid down into view.
    private var isRevealed = false
    /// Opened on purpose with the shortcut or the menu: it stays down until
    /// the cursor has visited it and left, or the shortcut is pressed again.
    private var pinned = false
    /// A new screenshot shows itself for a moment, then tucks away.
    private var peekUntil = Date.distantPast
    private var hotZoneSince: Date?
    /// After a click in the menu bar the line stays up there hidden until the
    /// pointer leaves the menu bar, so it does not come back over a menu.
    private var menuBarSuppressed = false
    private var clickMonitors: [Any] = []
    private var awaySince: Date?
    /// Whether the line should be up, if nothing prevents it. A full screen
    /// app on that screen does: the line waits until you leave full screen.
    private var wanted = false
    /// Set when you open the line on purpose, so it stays up while empty.
    private var keepOpen = false

    // What brings the line down, from the menu bar's "Bring the line down".
    // Out of the box, the first two are on and the third off.

    /// Resting the pointer in the menu bar. Off, only the shortcut and the
    /// menu open it.
    static var opensFromMenuBar: Bool {
        get { !UserDefaults.standard.bool(forKey: "menuBarRevealOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "menuBarRevealOff") }
    }

    /// Something new hanging shows itself for a moment. Off, it hangs
    /// quietly and waits for you to bring the line down.
    static var peeksAtNew: Bool {
        get { !UserDefaults.standard.bool(forKey: "quietHang") }
        set { UserDefaults.standard.set(!newValue, forKey: "quietHang") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        panel = LinePanel(content: host)
        panel.placeOnScreen()
        updateCapacity()

        if Inbox.isEnabled || Edition.appStore { Inbox.apply() }
        restoreSettingsOnTermination()
        startWatcher()
        clipboardWatcher = ClipboardWatcher { [weak self] url in self?.hangCapture(url) }
        Capture.shared.onCapture = { [weak self] url in self?.hangCapture(url) }
        Recording.shared.onFinish = { [weak self] url in self?.hangCapture(url) }
        Recording.shared.onChange = { [weak self] in self?.updateStatusIcon() }
        Recording.cleanUp()
        History.purge()
        HistoryWindow.shared.onHang = { [weak self] url in self?.hangCapture(url) }
        let chatButton = ChatButton(line: line)
        chatButton.openSettings = { [weak self] in self?.openSettings() }
        self.chatButton = chatButton
        if ClipboardWatcher.isEnabled { clipboardWatcher.start() }

        Shortcut.Role.allCases.forEach(registerShortcut)

        setUpStatusItem()
        watchMenuBarClicks()

        setUpPreferences()

        Markup.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        Trim.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        panel.onScroll = { [weak self] event in
            // Sideways on a trackpad, or the wheel of a mouse.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            self?.line.scroll(by: event.hasPreciseScrollingDeltas ? delta : delta * 12)
        }
        line.onFall = { [weak self] item in self?.fall(item) }
        line.onSend = { [weak self] photos in self?.send(photos) ?? 0 }
        line.frameOfPhoto = { [weak self] id in self?.cardFrame(for: id) }
        line.onSearch = { [weak self] in self?.openSearch() }

        line.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.itemsChanged() }
            .store(in: &cancellables)
        // Picked from a search, the line stays down for the send button,
        // until the pointer has been to it and left.
        line.$isSearching
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] searching in
                guard let self, !searching, self.isRevealed, !self.line.pickedIDs.isEmpty else { return }
                self.pinned = true
            }
            .store(in: &cancellables)
        // Photos kept from last time show themselves for a moment.
        if line.liveCount > 0 { comeDown(on: nil) }

        // Entering or leaving full screen switches Space. Check again once the
        // switch animation has settled.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.refresh() }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.placeOnScreen()
                self?.updateCapacity()
            }
        }

        if !Inbox.wasOffered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.offerInbox() }
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            keepOpen = true
            wanted = true
            refresh()
            reveal(pinned: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.line.liveCount == 0 else { return }
                self.keepOpen = false
                self.wanted = false
                self.refresh()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
    }

    // MARK: Inbox mode

    private func startWatcher() {
        watcher?.stop()
        safetyWatcher?.stop()
        safetyWatcher = nil
        watcher = ScreenshotWatcher(
            folder: Edition.appStore ? Inbox.folder : nil,
            onNew: { [weak self] url in self?.hangCapture(url) },
            onChange: { [weak self] in self?.line.prune() })
        watcher.start()
        if Inbox.isEnabled, watcher.folder.standardizedFileURL != ScreenshotWatcher.desktop.standardizedFileURL {
            let safety = ScreenshotWatcher(
                folder: ScreenshotWatcher.desktop,
                onNew: { [weak self] url in
                    log.notice("Screenshot landed on the Desktop despite inbox mode: \(url.lastPathComponent, privacy: .public)")
                    self?.hangCapture(url)
                },
                onChange: { [weak self] in self?.line.prune() })
            safety.start()
            safetyWatcher = safety
        }
        folderWatchers.forEach { $0.stop() }
        folderWatchers = []
        // A folder may also be watched for screenshots, like the Desktop; an
        // image both report hangs once.
        for folder in Self.extraFolders {
            let extra = ScreenshotWatcher(
                folder: folder, anyImage: true,
                onNew: { [weak self] url in self?.hangCapture(url) },
                onChange: { [weak self] in self?.line.prune() })
            extra.start()
            folderWatchers.append(extra)
        }
    }

    /// Up to three folders: enough for another screenshot app or an export
    /// folder, few enough that screenshots still have room on the line.
    static let maxExtraFolders = 3

    /// The folders from "Also watch folders" that still exist. New images in
    /// them hang like screenshots; taking one down leaves the file there.
    static var extraFolders: [URL] {
        get {
            if Edition.appStore { return bookmarkedFolders }
            let paths = UserDefaults.standard.stringArray(forKey: "extraFolders") ?? []
            return paths.compactMap { path in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        set {
            if Edition.appStore {
                bookmarkedFolders = newValue
            } else {
                UserDefaults.standard.set(newValue.map(\.path), forKey: "extraFolders")
            }
        }
    }

    /// The sandbox lets Snapfly into a folder only once it was picked, and
    /// again after a relaunch through a bookmark.
    private static var bookmarkedFolders: [URL] {
        get {
            let marks = UserDefaults.standard.array(forKey: "extraFolderBookmarks") as? [Data] ?? []
            return marks.compactMap { mark in
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: mark, options: .withSecurityScope,
                                         relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
                if !openedFolders.contains(url.path), url.startAccessingSecurityScopedResource() {
                    openedFolders.insert(url.path)
                }
                return url
            }
        }
        set {
            let marks = newValue.compactMap {
                try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            UserDefaults.standard.set(marks, forKey: "extraFolderBookmarks")
        }
    }

    private static var openedFolders: Set<String> = []

    private func chooseExtraFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Watch")
        panel.message = L("New images saved to this folder will hang on the line.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, Self.extraFolders.count < Self.maxExtraFolders,
              !Self.extraFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        Self.extraFolders.append(url)
        startWatcher()
    }

    private func setInbox(_ on: Bool) {
        Inbox.isEnabled = on
        if on { Inbox.apply() } else { Inbox.restore() }
        startWatcher()
    }

    /// Asked once. Changing system settings is the user's call, never ours.
    private func offerInbox() {
        if Edition.appStore { return guideScreenshots() }
        Inbox.wasOffered = true
        let alert = NSAlert()
        alert.messageText = L("Let Snapfly handle your screenshots?")
        alert.informativeText = L(
            "Screenshots will hang on the line the instant you take them, without the floating thumbnail, and will not pile up on your Desktop. Drag one to a folder to keep it, or discard it with the cross. You can turn this off in Settings, and your settings come back when Snapfly quits.")
        alert.addButton(withTitle: L("Turn on"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { setInbox(true) }
    }

    /// The App Store edition may not change the screenshot settings, so it
    /// says where to change them, and opens the Screenshot app.
    private func guideScreenshots() {
        Inbox.wasOffered = true
        Inbox.apply()
        let alert = NSAlert()
        alert.messageText = L("Set up screenshots")
        alert.informativeText = L(
            "Open the Screenshot app, click Options and choose Other Location, then pick the Snapfly folder in Pictures. Turn off Show Floating Thumbnail too, so screenshots hang at once.")
        alert.addButton(withTitle: L("Open Screenshot"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Inbox.folder])
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }

    /// Watching the clipboard is opt in, from the menu bar only.
    private func setClipboard(_ on: Bool) {
        ClipboardWatcher.isEnabled = on
        if on { clipboardWatcher.start() } else { clipboardWatcher.stop() }
        updateStatusIcon()
    }

    /// Quitting from the menu or logging out runs applicationWillTerminate.
    /// A plain kill does not, so settings are also restored on those signals.
    private func restoreSettingsOnTermination() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                if Inbox.isEnabled { Inbox.restore() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Showing and hiding

    /// An empty line goes away, unless it was opened on purpose.
    private func itemsChanged() {
        guard line.liveCount == 0, !keepOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.line.liveCount == 0, !self.keepOpen else { return }
            self.wanted = false
            self.refresh()
        }
    }

    /// The line comes down on that screen for a moment, then tucks away.
    /// Without a screen, it uses the one under the pointer.
    private func comeDown(on screen: NSScreen?) {
        panel.placeOnScreen(screen)
        updateCapacity()
        wanted = true
        refresh()
        if Self.peeksAtNew { reveal(peekFor: 2.5) }
    }

    // MARK: The capture flying to the line

    /// A new screenshot lifts off from where it was taken and flies to its
    /// place on the line. Without a known capture area it simply drops in.
    private func hangCapture(_ url: URL) {
        let from = captureRect(of: url)
        let screen = from.flatMap { from in
            NSScreen.screens.first { NSMouseInRect(CGPoint(x: from.midX, y: from.midY), $0.frame, false) }
        }
        // Every capture brings the line down before it hangs, on the screen it
        // was taken on. On a full line the oldest photo then falls in view as
        // the new one flies in.
        comeDown(on: screen)
        guard let id = line.hang(url, flying: from != nil) else {
            // Nothing hung after all, so an empty line goes away again.
            itemsChanged()
            return
        }
        guard let from else { return }
        // Let the line come down and lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: from)
        }
    }

    private func fly(_ id: UUID, from: CGRect) {
        // With Reduce Motion on, the capture fades in where it hangs instead.
        guard !Motion.reduced, isPresent, isRevealed, CaptureFlight.flightsInProgress < 2, let screen = panel.screen,
              let to = cardFrame(for: id),
              let item = line.items.first(where: { $0.id == id }) else {
            line.land(id)
            return
        }
        // Sharp enough while it starts out at the captured size, which a
        // full Retina screen would otherwise take at full resolution.
        let pixels = Int(max(from.width, from.height) * screen.backingScaleFactor)
        guard let image = makeThumbnail(item.url, maxPixels: min(1500, max(400, pixels)))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            line.land(id)
            return
        }
        CaptureFlight.fly(image: image, from: from, to: to, tilt: tilt(of: id), on: screen) { [weak self] in
            self?.line.land(id)
        }
    }

    /// A discarded card falls over the whole screen, from where it hangs.
    private func fall(_ item: Pegged) {
        guard !Motion.reduced, isPresent, isRevealed, !item.flying, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        CaptureFlight.fall(image: image, card: card, tilt: tilt(of: item.id), on: screen)
    }

    /// Sent photos fly from the line into the app in front, a little apart,
    /// and land where the paste shows up. Returns how long until the last
    /// one lands; the first few are enough to say it.
    private func send(_ photos: [Pegged]) -> TimeInterval {
        guard !Motion.reduced, isPresent, isRevealed, let screen = panel.screen else { return 0 }
        let landing = Paste.landingPoint(on: screen)
        var last: TimeInterval?
        for (n, item) in photos.prefix(5).enumerated() {
            guard let card = cardFrame(for: item.id),
                  let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            // As small as an attachment, keeping the photo's shape.
            let width: CGFloat = 56
            let height = width * card.height / max(card.width, 1)
            let target = CGRect(x: landing.x - width / 2, y: landing.y - height / 2, width: width, height: height)
            let delay = 0.07 * Double(n)
            CaptureFlight.send(image: image, card: card, to: target, tilt: tilt(of: item.id), on: screen, after: delay)
            last = delay
        }
        return last.map { $0 + CaptureFlight.sendDuration } ?? 0
    }

    /// Where a card will hang, in screen coordinates, using the same layout
    /// as the line view.
    private func cardFrame(for id: UUID) -> CGRect? {
        guard let index = line.items.firstIndex(where: { $0.id == id }) else { return nil }
        let width = panel.frame.width
        let x = Layout.x(index: index, count: line.items.count, width: width,
                         visible: line.visibleCount, scroll: line.scroll, spread: line.spread)
        let viewTop = panel.drop + Layout.ropeY(x: x, width: width) - Layout.pinAbove
        let cardTop = viewTop + PeggedView.cardOffsetBelowTop
        let size = PeggedView.cardSize(for: line.items[index].thumb.size)
        return CGRect(x: panel.frame.minX + x - size.width / 2,
                      y: panel.frame.maxY - cardTop - size.height,
                      width: size.width, height: size.height)
    }

    /// How a card leans where it hangs, for the flights to match it.
    private func tilt(of id: UUID) -> CGFloat {
        guard let index = line.items.firstIndex(where: { $0.id == id }) else { return 0 }
        return CGFloat(Layout.tilt(of: line.items[index], index: index, count: line.items.count, spread: line.spread))
    }

    /// Decides whether the panel is ordered in at all: something to show,
    /// and no full screen app on that screen.
    private func refresh() {
        let blocked = panel.screen.map(FullScreen.blocksLine(on:))
            ?? LinePanel.screenUnderPointer().map(FullScreen.blocksLine(on:)) ?? false
        if wanted && !blocked {
            present()
        } else {
            dismiss()
        }
        // The cursor is watched while there is a line, even tucked away,
        // to notice it pushing against the top edge.
        if wanted { startMouseTracking() } else { stopMouseTracking() }
    }

    private func present() {
        guard !isPresent else { return }
        isPresent = true
        panel.alphaValue = 1
        // The window itself only comes in while the line is down; see setRevealed.
        if isRevealed { panel.orderFrontRegardless() }
    }

    private func dismiss() {
        guard isPresent else { return }
        isPresent = false
        setRevealed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isPresent else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reveal(pinned: Bool = false, peekFor seconds: TimeInterval = 0) {
        guard isPresent else { return }
        if pinned { self.pinned = true }
        if seconds > 0 { peekUntil = Date().addingTimeInterval(seconds) }
        awaySince = nil
        setRevealed(true)
    }

    private func setRevealed(_ on: Bool) {
        guard on != isRevealed else { return }
        isRevealed = on
        line.revealed = on
        // It always comes down showing the newest.
        if on { line.scroll = 0 }
        // Tucked away, the line leaves no window behind: an invisible strip
        // over the top of the screen would still sit above other apps for
        // anything that checks what is on top, like screen automation.
        if on {
            if isPresent { panel.orderFrontRegardless() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.isRevealed else { return }
                self.panel.orderOut(nil)
            }
        }
        if !on {
            pinned = false
            peekUntil = .distantPast
            SearchBar.shared.close()
            line.spread = false
            panel.ignoresMouseEvents = true
            // A grip that went away under the pointer never hears it let go.
            TagView.isMovingLine = false
            // What was picked is on the clipboard by now. Next time the line
            // comes down, a ⌘-click starts afresh.
            line.pickedIDs = []
        }
    }

    /// Search: the line comes down, with a bar under it to type into.
    private func openSearch() {
        if !isRevealed { toggle() }
        guard isRevealed else {
            NSSound.beep()
            return
        }
        SearchBar.shared.show(for: line, at: CGPoint(x: panel.frame.midX, y: panel.frame.minY + 6))
    }

    @objc private func toggle() {
        if isRevealed {
            setRevealed(false)
            if line.liveCount == 0 {
                keepOpen = false
                wanted = false
                refresh()
            }
        } else {
            keepOpen = true
            wanted = true
            panel.placeOnScreen()
            updateCapacity()
            refresh()
            reveal(pinned: true)
        }
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel.ignoresMouseEvents = true
    }

    /// How long the cursor rests against the top edge before the line comes
    /// down. Short enough to feel instant, long enough that a quick trip to
    /// the menu bar does not trigger it.
    private static let revealDelay: TimeInterval = 0.25

    /// The menu bar strip at the top of a screen. With an auto-hiding menu
    /// bar the visible frame reaches the top, so the system thickness is used.
    static func menuBarBand(of screen: NSScreen) -> NSRect {
        var h = screen.frame.maxY - screen.visibleFrame.maxY
        if h < 1 { h = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }

    /// A click anywhere in the top bar of any screen, a menu or an icon, puts the line away.
    private func watchMenuBarClicks() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = NSEvent.mouseLocation
                guard NSScreen.screens.contains(where: { NSMouseInRect(p, Self.menuBarBand(of: $0), false) }) else { return }
                self.menuBarSuppressed = true
                self.hotZoneSince = nil
                if self.isRevealed {
                    self.pinned = false
                    self.setRevealed(false)
                }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in handler(e); return e }) {
            clickMonitors.append(local)
        }
    }
    /// How long the cursor is away before the line tucks back up.
    private static let retractDelay: TimeInterval = 0.5

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()

        let screenUnderPointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inMenuBar = screenUnderPointer.map { NSMouseInRect(mouse, Self.menuBarBand(of: $0), false) } ?? false
        if !inMenuBar { menuBarSuppressed = false }

        guard isRevealed else {
            // Resting in the menu bar brings the line down on that screen.
            // Pushing against the top edge is part of it, and it also works
            // when another display sits above and the pointer never stops.
            if Self.opensFromMenuBar, let screen = screenUnderPointer, inMenuBar, !menuBarSuppressed,
               !FullScreen.blocksLine(on: screen) {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    if panel.screen != screen {
                        panel.placeOnScreen()
                        updateCapacity()
                    }
                    refresh()
                    reveal()
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        updateMousePassThrough(mouse)
        if line.style == .stack { spreadStack(near: mouse) }

        // The line's zone runs from its lowest point up to the top of the
        // screen, menu bar included, so moving up never hides it.
        var zone = panel.frame
        if let screen = panel.screen { zone.size.height = screen.frame.maxY - zone.minY }
        let inside = NSMouseInRect(mouse, zone, false)
        if inside && pinned { pinned = false }

        let busy = pinned || GrabView.isDragging || GrabView.isShowingMenu || TagView.isMovingLine
            || line.pressedID != nil || now < peekUntil || line.isSearching
        if inside || busy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                setRevealed(false)
            }
        }
    }

    /// A card stack spreads out while the pointer is at it, and closes
    /// again once it has moved away.
    private func spreadStack(near mouse: NSPoint) {
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        let cards = line.hitRects.values.reduce(line.tagRect) { $0.union($1) }
        let near = !cards.isNull && cards.insetBy(dx: -28, dy: -28).contains(flipped)
        if near != line.spread { line.spread = near }
    }

    /// The panel spans the whole width of the screen, so it only accepts the
    /// mouse while the cursor is over a photo or the tag. Everywhere else,
    /// clicks go to whatever is underneath.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard !GrabView.isDragging, !TagView.isMovingLine else { return }
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        var overPhoto = line.hitRects.values.contains { $0.insetBy(dx: -4, dy: -4).contains(flipped) }
            || line.tagRect.insetBy(dx: -4, dy: -4).contains(flipped)
        // A line longer than the screen also takes the band the photos hang
        // in, gaps included, so a swipe anywhere along it moves it.
        if !overPhoto, line.items.count > line.visibleCount, Line.keepOnLine != nil {
            let band = line.hitRects.values.reduce(CGRect.null) { $0.union($1) }
            overPhoto = !band.isNull && flipped.y >= band.minY - 4 && flipped.y <= band.maxY + 4
        }
        if panel.ignoresMouseEvents == overPhoto {
            panel.ignoresMouseEvents = !overPhoto
        }
    }

    // MARK: Shortcut

    private func registerShortcut(_ role: Shortcut.Role) {
        hotKeys[role] = nil
        guard let shortcut = Shortcut.current(role) else { return }
        hotKeys[role] = HotKey(shortcut, for: role) { [weak self] in
            switch role {
            case .toggle: self?.toggle()
            case .send: self?.line.pasteNewest()
            case .search: self?.openSearch()
            case .capture: Capture.shared.start()
            case .record:
                if Recording.shared.isRecording {
                    Recording.shared.stop()
                } else {
                    Capture.shared.start(mode: .record)
                }
            }
        }
    }

    private func changeShortcut(_ role: Shortcut.Role) {
        // All off while recording, so pressing one records it instead of
        // doing what it does.
        hotKeys = [:]
        ShortcutRecorder.shared.record { [weak self] result in
            guard let self else { return }
            for other in Shortcut.Role.allCases where other != role { self.registerShortcut(other) }
            if let result {
                let previous = Shortcut.current(role)
                Shortcut.save(result, for: role)
                self.registerShortcut(role)
                // Taken by another app, or the other shortcut: keep the one that worked.
                if result != nil && self.hotKeys[role] == nil {
                    NSSound.beep()
                    Shortcut.save(previous, for: role)
                }
            }
            self.registerShortcut(role)
            self.preferences?.refresh()
        }
    }

    private func setKeep(_ n: Int?) {
        guard n != Line.keepOnLine else { return }
        Line.keepOnLine = n
        updateCapacity()
        line.trim()
    }

    private func setStyle(_ style: Layout.Style) {
        guard style != Layout.style else { return }
        Layout.style = style
        line.spread = false
        line.style = style
    }

    private func setSize(_ size: Layout.Size) {
        guard size != Layout.size else { return }
        Layout.size = size
        panel.placeOnScreen(panel.screen)
        updateCapacity()
        line.reloadThumbnails()
    }

    private func updateCapacity() {
        let usable = panel.frame.width - 200
        let fits = max(3, min(12, Int(usable / Layout.spacing)))
        line.visibleCount = fits
        line.maxItems = max(fits, Line.keepOnLine ?? fits)
    }

    // MARK: Settings

    private func setUpPreferences() {
        let preferences = Preferences(line: line)
        preferences.actions = Preferences.Actions(
            setInbox: { [weak self] in self?.setInbox($0) },
            setClipboard: { [weak self] in self?.setClipboard($0) },
            setKeep: { [weak self] in self?.setKeep($0) },
            setSize: { [weak self] in self?.setSize($0) },
            setStyle: { [weak self] in self?.setStyle($0) },
            addFolder: { [weak self] in self?.chooseExtraFolder() },
            foldersChanged: { [weak self] in self?.startWatcher() },
            changeShortcut: { [weak self] in self?.changeShortcut($0) },
            fullScreenChanged: { [weak self] in self?.refresh() },
            setUpScreenshots: { [weak self] in self?.guideScreenshots() },
            openScreenshotsFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.watcher.folder)
            })
        self.preferences = preferences
    }

    private func openSettings() {
        guard let preferences else { return }
        SettingsWindow.shared.show(preferences)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()
        let menu = NSMenu()
        // Items say themselves whether they can be used, like Take everything
        // down on an empty line.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The shirt fills in while copied images are hung, so it shows at a
    /// glance that the clipboard is being watched. While the screen is
    /// recorded it is a stop button, as the Screenshot app's is.
    private func updateStatusIcon() {
        let on = ClipboardWatcher.isEnabled
        let recording = Recording.shared.isRecording
        let description = recording ? L("Snapfly, recording the screen")
            : on ? L("Snapfly, hanging copied images") : "Snapfly"
        let symbol = recording ? "stop.circle" : on ? "tshirt.fill" : "tshirt"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = description
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Recording.shared.isRecording {
            let stopItem = ClosureMenuItem(L("Stop Recording")) { Recording.shared.stop() }
            if let shortcut = Shortcut.current(.record), shortcut.key.count == 1 {
                stopItem.keyEquivalent = shortcut.key
                stopItem.keyEquivalentModifierMask = shortcut.modifiers
            }
            menu.addItem(stopItem)
        } else {
            let captureItem = ClosureMenuItem(L("Take Screenshot")) {
                // Once the menu has faded, so it is not in the picture.
                Capture.shared.start(after: 0.2)
            }
            if let shortcut = Shortcut.current(.capture), shortcut.key.count == 1 {
                captureItem.keyEquivalent = shortcut.key
                captureItem.keyEquivalentModifierMask = shortcut.modifiers
            }
            menu.addItem(captureItem)
            let timerItem = NSMenuItem(title: L("Take Screenshot with Timer"), action: nil, keyEquivalent: "")
            let seconds = NSMenu()
            for n in Capture.timerChoices {
                seconds.addItem(ClosureMenuItem(Self.secondsTitle(n)) {
                    Capture.shared.start(after: 0.2, mode: .timer(n))
                })
            }
            timerItem.submenu = seconds
            menu.addItem(timerItem)
            let recordItem = ClosureMenuItem(L("Record Screen")) {
                Capture.shared.start(after: 0.2, mode: .record)
            }
            if let shortcut = Shortcut.current(.record), shortcut.key.count == 1 {
                recordItem.keyEquivalent = shortcut.key
                recordItem.keyEquivalentModifierMask = shortcut.modifiers
            }
            menu.addItem(recordItem)
        }
        menu.addItem(.separator())

        let toggleItem = ClosureMenuItem(isRevealed ? L("Hide line") : L("Show line")) { [weak self] in
            self?.toggle()
        }
        if let shortcut = Shortcut.current(.toggle), shortcut.key.count == 1 {
            toggleItem.keyEquivalent = shortcut.key
            toggleItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(toggleItem)

        let searchItem = ClosureMenuItem(L("Search…")) { [weak self] in self?.openSearch() }
        if let shortcut = Shortcut.current(.search), shortcut.key.count == 1 {
            searchItem.keyEquivalent = shortcut.key
            searchItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        searchItem.isEnabled = line.liveCount > 0
        menu.addItem(searchItem)

        let historyItem = ClosureMenuItem(L("History…"), key: "y") { HistoryWindow.shared.show() }
        historyItem.isEnabled = History.days != nil
        menu.addItem(historyItem)

        let clearItem = ClosureMenuItem(L("Take everything down")) { [weak self] in
            self?.line.clear()
        }
        clearItem.isEnabled = line.liveCount > 0
        menu.addItem(clearItem)

        menu.addItem(.separator())

        // Everything else lives in the settings window.
        menu.addItem(ClosureMenuItem(L("Settings…"), key: ",") { [weak self] in
            self?.openSettings()
        })

        menu.addItem(ClosureMenuItem(L("Open screenshots folder")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.watcher.folder)
        })

        // The app never connects to anything, so it cannot tell when a new
        // version is out. The releases page can.
        // From the App Store, updates come through it.
        if !Edition.appStore {
            menu.addItem(ClosureMenuItem(L("Check for Updates…")) {
                NSWorkspace.shared.open(AppDelegate.updatesURL)
            })
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit Snapfly"), key: "q") {
            NSApp.terminate(nil)
        })
    }

    /// A literal key for each choice, so each language can say it its way.
    private static func secondsTitle(_ n: Int) -> String {
        switch n {
        case 3: L("3 Seconds")
        case 10: L("10 Seconds")
        default: L("5 Seconds")
        }
    }

    /// Where new versions are published.
    static let updatesURL = URL(string: "https://github.com/mgrd281/Screenshots/releases")!

    /// Who makes the app, for the About pane.
    static let author = "Mgrdegh Ghazarian"

    static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change the login setting")
            alert.informativeText = L("Move Snapfly to the Applications folder and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Quick Look

    /// With no window of ours in front, Quick Look finds its controller here.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLook.shared.take(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLook.shared.release(panel)
    }

}
