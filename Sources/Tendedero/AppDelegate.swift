import AppKit
import Carbon
import Combine
import Quartz
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
    /// Photos and PDFs dragged towards the line from other apps.
    private let fileDrags = FileDragWatcher()
    /// Finder's "Send Safely with Snapfly".
    private let services = ServiceProvider()
    /// Files dropped on the menu bar icon.
    private let statusDrop = StatusDrop()
    /// Files are being dragged near the line, which waits for them.
    private var dropping = false
    /// Whether the line was being kept open before the drag came.
    private var keptOpenBeforeDrop = false
    /// Files opened with Snapfly before it had finished launching.
    private var waitingFiles: [URL] = []
    private var launched = false

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
    /// The introduction points at something on the line, which stays down.
    private var guideHolds = false
    private var keptOpenBeforeGuide = false

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
        // The strip takes photos and PDFs dropped on it from other apps.
        let dropView = DropView(frame: .zero)
        host.autoresizingMask = [.width, .height]
        dropView.addSubview(host)
        dropView.onTarget = { [weak self] over in
            if self?.line.dropOver != over { self?.line.dropOver = over }
        }
        dropView.onDrop = { [weak self] urls, point in self?.hangFiles(urls, from: point) ?? false }
        panel = LinePanel(content: dropView)
        panel.placeOnScreen()
        updateCapacity()

        if Inbox.isEnabled || Edition.appStore { Inbox.apply() }
        restoreSettingsOnTermination()
        startWatcher()
        FolderCover.shared.restart()
        clipboardWatcher = ClipboardWatcher { [weak self] url in self?.hangCapture(url) }
        Capture.shared.onCapture = { [weak self] url in self?.hangCapture(url) }
        FullPage.shared.onCapture = { [weak self] url in self?.hangCapture(url) }
        Recording.shared.onFinish = { [weak self] url in self?.hangCapture(url) }
        Recording.shared.onChange = { [weak self] in
            self?.updateStatusIcon()
            CaptureButton.shared.recordingChanged()
        }
        CaptureButton.shared.openSettings = { [weak self] in self?.openSettings() }
        CaptureButton.shared.update()
        Recording.cleanUp()
        History.purge()
        HistoryWindow.shared.onHang = { [weak self] url in self?.hangCapture(url) }
        HistoryWindow.shared.onSendAgain = { [weak self] url in self?.sendAgain(url) }
        let chatButton = ChatButton(line: line)
        chatButton.openSettings = { [weak self] in self?.openSettings() }
        self.chatButton = chatButton
        TimeStamp.onReady = { [weak self] _ in self?.line.readPrivateDetails() }
        if ClipboardWatcher.isEnabled { clipboardWatcher.start() }

        Shortcut.Role.allCases.forEach(registerShortcut)

        setUpStatusItem()
        watchMenuBarClicks()
        setUpFiles()
        setUpGuide()

        setUpPreferences()

        // Written over the file itself: a note says where it is.
        Markup.shared.onSaved = { [weak self] url in
            self?.line.reloadThumbnail(for: url)
            Notice.saved(url)
        }
        Trim.shared.onSaved = { [weak self] url in
            self?.line.reloadThumbnail(for: url)
            Notice.saved(url)
        }
        panel.onScroll = { [weak self] event in
            // Sideways on a trackpad, or the wheel of a mouse.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            self?.line.scroll(by: event.hasPreciseScrollingDeltas ? delta : delta * 12)
        }
        line.onFall = { [weak self] item in self?.fall(item) }
        line.onSend = { [weak self] photos in self?.send(photos) ?? 0 }
        line.onPutBack = { [weak self] in self?.putBack() }
        Calls.shared.onChange = { [weak self] in self?.callChanged() }
        Calls.shared.start()
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

        // The introduction once, then the question about screenshots once.
        if Guide.shared.offersAtLaunch || !Inbox.wasOffered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.welcome() }
        }

        // Whoever used Snapfly before Pro begins keeps every feature.
        Plan.recordFirstLaunch()

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

    /// "Open With › Snapfly", or a file dropped on Snapfly's icon in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard launched else {
            waitingFiles += urls
            return
        }
        hangFiles(urls, from: nil)
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

    /// The introduction, offered once on this Mac, then the question about
    /// screenshots, when it was never asked.
    private func welcome() {
        let ask = { [weak self] in
            guard !Inbox.wasOffered else { return }
            self?.offerInbox()
        }
        if Guide.shared.offersAtLaunch { Guide.shared.offer(then: ask) } else { ask() }
    }

    /// Asked once. Changing system settings is the user's call, never ours.
    private func offerInbox() {
        if Edition.appStore { return welcomeCapture() }
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
    /// starts with Snapfly's own screenshots, which need nothing set up, and
    /// lets the first one be taken right away. Pointing the Screenshot app
    /// at Snapfly's folder stays a choice, from here or Settings.
    private func welcomeCapture() {
        Inbox.wasOffered = true
        Inbox.apply()
        let shortcut = Shortcut.current(.capture) ?? Shortcut.Role.capture.standard
        let alert = NSAlert()
        alert.messageText = L("Take screenshots with Snapfly")
        alert.informativeText = String(format: L(
            "Press %@ or click the screenshot button at the edge of the screen, then drag over an area, click a window, or press Return for the whole screen. It hangs on the line at once, with nothing to set up."),
            shortcut.display)
        alert.addButton(withTitle: L("Try It Now"))
        alert.addButton(withTitle: L("Not now"))
        alert.addButton(withTitle: L("Use the Screenshot App…"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Once the alert has gone, so it is not in the picture.
            Capture.shared.start(after: 0.3)
        case .alertThirdButtonReturn:
            guideScreenshots()
        default:
            break
        }
    }

    /// Where to point the Screenshot app, which the App Store edition may
    /// not do itself, and opens it.
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
        // New on a line that did not come down for it: the dot says so.
        let count = line.liveCount
        if count > lastCount && !isRevealed { unseen = true }
        if count == 0 { unseen = false }
        if count != lastCount {
            lastCount = count
            updateStatusIcon()
        }
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
        // Not during a call: what hangs there is for no shared screen.
        if Self.peeksAtNew && !Calls.shared.keepingAway { reveal(peekFor: 2.5) }
    }

    /// Photos put back from the note after a send: the line comes down to
    /// show them, as it does for files brought on purpose.
    private func putBack() {
        comeDown(on: nil)
        reveal(pinned: true)
    }

    /// A call begins: the line tucks away, unless it was opened on purpose,
    /// and the send button over chats goes. It ends: the button comes back.
    private func callChanged() {
        if Calls.shared.keepingAway, isRevealed, !pinned { setRevealed(false) }
        chatButton?.refresh()
    }

    // MARK: Photos and PDFs from anywhere

    /// Every way a file comes onto the line besides a screenshot: dragged
    /// to the line or the menu bar icon, Finder's menu, Open With, and Add
    /// Files… in the menu bar.
    private func setUpFiles() {
        fileDrags.onMove = { [weak self] point in self?.fileDragMoved(to: point) }
        fileDrags.onEnd = { [weak self] in self?.fileDragEnded() }
        fileDrags.start()
        services.onFiles = { [weak self] urls in self?.hangFiles(urls, from: nil) }
        services.onHide = { [weak self] urls in self?.hideDetails(urls) }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        if let button = statusItem.button {
            statusDrop.button = button
            statusDrop.onDrop = { [weak self] urls, point in self?.hangFiles(urls, from: point) }
            button.window?.registerForDraggedTypes([.fileURL])
            button.window?.delegate = statusDrop
        }
        launched = true
        if !waitingFiles.isEmpty {
            let urls = waitingFiles
            waitingFiles = []
            hangFiles(urls, from: nil)
        }
    }

    /// Files dragged to the top of a screen bring the line down there to
    /// take them, however the line is set to come down: the drag says what
    /// is wanted.
    private func fileDragMoved(to point: CGPoint) {
        guard !dropping, let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              !FullScreen.blocksLine(on: screen) else { return }
        let menuBar = Self.menuBarBand(of: screen)
        // Up in the menu bar, or over the line where it already hangs.
        let near = isRevealed && panel.screen == screen ? point.y >= panel.frame.minY : point.y >= menuBar.minY - 24
        guard near else { return }
        dropping = true
        line.dropping = true
        if panel.screen != screen || !isRevealed {
            panel.placeOnScreen(screen)
            updateCapacity()
        }
        keptOpenBeforeDrop = keepOpen
        keepOpen = true
        wanted = true
        refresh()
        reveal(pinned: true)
        panel.ignoresMouseEvents = false
    }

    /// Dropped or let go. A moment later, so a drop on the line has hung
    /// first; an empty line nothing was dropped on goes away again.
    private func fileDragEnded() {
        guard dropping else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.dropping else { return }
            self.dropping = false
            self.line.dropping = false
            self.line.dropOver = false
            self.keepOpen = self.keptOpenBeforeDrop
            if self.line.liveCount == 0 && !self.keepOpen {
                self.wanted = false
                self.refresh()
            }
        }
    }

    /// Photos and PDFs from anywhere on the Mac. Each flies in from where it
    /// was let go, or drops in, and hangs like a screenshot; the file itself
    /// stays where it is. Returns whether anything could hang.
    @discardableResult
    private func hangFiles(_ urls: [URL], from point: CGPoint?) -> Bool {
        let files = Outside.sort(urls)
        showRefusals(files)
        let accepted = Array(files.accepted.prefix(Outside.maxAtOnce))
        guard !accepted.isEmpty else { return false }
        // The place kept for them closes as they fly into it.
        line.dropping = false
        line.dropOver = false
        let screen = point.flatMap { point in NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } }
        comeDown(on: screen)
        // Brought on purpose: it stays down until the pointer has been to it.
        reveal(pinned: true)
        for (n, url) in accepted.enumerated() {
            Outside.remember(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(n)) { [weak self] in
                self?.hangFile(url, from: point)
            }
        }
        return true
    }

    private func hangFile(_ url: URL, from point: CGPoint?) {
        let from = point.map { CGRect(x: $0.x - 60, y: $0.y - 45, width: 120, height: 90) }
        guard let id = line.hang(url, flying: from != nil) else {
            itemsChanged()
            return
        }
        Guide.shared.happened(.photoHung)
        guard let from else { return }
        // Let the line lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: from)
        }
    }

    /// Add Files… in the menu bar.
    private func chooseFiles() {
        let open = NSOpenPanel()
        open.canChooseFiles = true
        open.canChooseDirectories = false
        open.allowsMultipleSelection = true
        open.allowedContentTypes = [.image, .pdf]
        open.prompt = L("Hang")
        open.message = L("Photos and PDFs hang on the line, ready to send with their private details covered.")
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK else { return }
        hangFiles(open.urls, from: nil)
    }

    /// Says why a file cannot be used, when it cannot: locked, too long, or
    /// not a photo or PDF at all.
    private func showRefusals(_ files: Outside.Sorted) {
        if !files.locked.isEmpty {
            Notice.show(L("This PDF is locked with a password."))
        } else if !files.tooLong.isEmpty {
            Notice.show(String(format: L("This PDF is too long: up to %d pages."), DocumentCover.maxPages))
        } else if !files.refused.isEmpty {
            Notice.show(L("Only photos and PDFs can hang on the line."))
        }
    }

    /// Finder's "Hide Private Details with Snapfly": one photo or PDF at a
    /// time, so the owner decides what its copy hides.
    private func hideDetails(_ urls: [URL]) {
        let files = Outside.sort(urls)
        if files.accepted.count > 1 {
            Notice.show(L("Choose one photo or PDF at a time."))
        } else if let url = files.accepted.first {
            HideEditor.shared.hideInCopy(url)
        } else {
            showRefusals(files)
        }
    }

    // MARK: Send Again

    /// From the History: the photo hangs on the line again and, once the app
    /// that was in front before the History window is back in front, goes
    /// into it, covered like anything that leaves the line. Should no app
    /// come back, it stays copied for ⌘V.
    private func sendAgain(_ url: URL) {
        HistoryWindow.shared.close()
        NSApp.deactivate()
        comeDown(on: nil)
        guard let id = line.hang(url) else {
            itemsChanged()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !Paste.willPaste { Notice.show(L("Covered and copied, ready to paste.")) }
                self.line.paste(id)
            }
        }
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
        // Asked now, while the moment and the page in front are fresh.
        TimeStamp.arrive(url)
        guard let id = line.hang(url, flying: from != nil) else {
            // Nothing hung after all, so an empty line goes away again.
            itemsChanged()
            return
        }
        Guide.shared.happened(.photoHung)
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
        let width = panel.frame.width
        let x = Layout.x(index: index, count: line.items.count, width: width,
                         visible: line.visibleCount, scroll: line.scroll, spread: line.spread)
        return CGFloat(Layout.tilt(of: line.items[index], index: index, count: line.items.count, spread: line.spread,
                                   x: x, width: width))
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
        if on { unseen = false }
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
            // What was picked stays picked, for the send button over a chat.
        }
    }

    /// Search: the line comes down, with a bar under it to type into.
    private func openSearch() {
        if !isRevealed { toggle() }
        guard isRevealed else {
            Notice.show(L("The line is empty."))
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
            if isRevealed { Guide.shared.lineCameDown() }
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
            if Self.opensFromMenuBar, !Calls.shared.keepingAway, let screen = screenUnderPointer, inMenuBar,
               !menuBarSuppressed, !FullScreen.blocksLine(on: screen) {
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
                    if isRevealed { Guide.shared.lineCameDown() }
                }
            } else {
                hotZoneSince = nil
            }
            // Held down for the introduction, it comes back once a click in
            // the menu bar has put it away and the pointer has left there.
            if guideHolds, isPresent, !inMenuBar, !Calls.shared.keepingAway { reveal(pinned: true) }
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
            || line.pressedID != nil || now < peekUntil || line.isSearching || dropping || guideHolds
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
        // While files are dragged to it, the whole strip takes them.
        guard !GrabView.isDragging, !TagView.isMovingLine, !dropping else { return }
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
            case .page: FullPage.shared.start()
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
                    Notice.show(L("Another app already uses this shortcut."))
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
            },
            screenshotsFolder: { [weak self] in self?.watcher.folder },
            menuBarCountChanged: { [weak self] in self?.updateStatusIcon() })
        self.preferences = preferences
    }

    private func openSettings() {
        guard let preferences else { return }
        SettingsWindow.shared.show(preferences)
    }

    private func openPermissions() {
        guard let preferences else { return }
        preferences.showsPermissions = true
        SettingsWindow.shared.show(preferences)
    }

    // MARK: The introduction

    /// Where the introduction's steps point, what they need, and the line
    /// held down while they point at it.
    private func setUpGuide() {
        let guide = Guide.shared
        guide.frame = { [weak self] target in self?.guideFrame(of: target) }
        guide.has = { [weak self] need in self?.guideHas(need) ?? false }
        guide.holdLine = { [weak self] hold in self?.guideHoldsLine(hold) }
        guide.screen = { [weak self] in self?.panel.screen ?? LinePanel.screenUnderPointer() }
    }

    /// The newest photo that has landed on the line.
    private var guidePhoto: Pegged? {
        line.items.last { !$0.falling && !$0.flying }
    }

    /// Where something is on the screen right now, nil while it does not
    /// show: the line tucked away, or no photo on it.
    private func guideFrame(of target: GuideTarget) -> CGRect? {
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        switch target {
        case .none:
            return nil
        case .menuBarIcon:
            guard let button = statusItem.button, let window = button.window, window.isVisible else { return nil }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return frame.isEmpty ? nil : frame
        case .tag:
            guard isPresent, isRevealed, !line.tagRect.isNull, !line.tagRect.isEmpty else { return nil }
            return CGRect(x: panel.frame.minX + line.tagRect.minX, y: panel.frame.maxY - line.tagRect.maxY,
                          width: line.tagRect.width, height: line.tagRect.height)
        case .newestPhoto, .lock, .icons, .pickCircle:
            guard isPresent, isRevealed, let item = guidePhoto, let card = cardFrame(for: item.id) else { return nil }
            switch target {
            case .lock:
                // In the bottom corner where lines of text start.
                guard item.covered else { return nil }
                let size = GrabView.lockHitSize
                return CGRect(x: rtl ? card.maxX - size : card.minX, y: card.minY, width: size, height: size)
            case .icons:
                // The photo with the row under it, which shows while the
                // pointer is over either.
                let reach = ChatTarget.takes(item) && !ChatTarget.onPhotosNow.isEmpty ? PhotoButtons.stripHeight : 0
                return CGRect(x: card.minX, y: card.minY - reach, width: card.width, height: card.height + reach)
            case .pickCircle:
                let size = PhotoButtons.pickSize
                let inset = PhotoButtons.pickInset
                return CGRect(x: rtl ? card.minX + inset : card.maxX - inset - size,
                              y: card.maxY - inset - size, width: size, height: size)
            default:
                return card
            }
        }
    }

    private func guideHas(_ need: GuideStep.Need) -> Bool {
        switch need {
        case .photo:
            return guidePhoto != nil
        case .coveredPhoto:
            return guidePhoto?.covered == true
        case .iconsUnderPhotos:
            guard let item = guidePhoto else { return false }
            return ChatTarget.takes(item) && !ChatTarget.onPhotosNow.isEmpty
        case .twoPhotos:
            return line.liveCount >= 2
        }
    }

    /// Down while a step points at the line, as if opened on purpose; let go,
    /// it goes back up once the pointer leaves it, as usual.
    private func guideHoldsLine(_ hold: Bool) {
        guard hold != guideHolds else { return }
        guideHolds = hold
        if hold {
            keptOpenBeforeGuide = keepOpen
            keepOpen = true
            wanted = true
            if !isRevealed {
                panel.placeOnScreen()
                updateCapacity()
            }
            refresh()
            reveal(pinned: true)
        } else {
            keepOpen = keptOpenBeforeGuide
            pinned = false
            if line.liveCount == 0 && !keepOpen {
                wanted = false
                refresh()
            }
        }
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

    /// The photo on the line fills in while copied images are hung, so it
    /// shows at a glance that the clipboard is being watched. While the
    /// screen is recorded it is a stop button, as the Screenshot app's is.
    /// Beside it, how many photos hang, and on it a dot while something new
    /// hangs that the line has not shown, with Count on the menu bar icon on.
    private func updateStatusIcon() {
        let on = ClipboardWatcher.isEnabled
        let recording = Recording.shared.isRecording
        let counts = Self.countsInMenuBar
        let count = counts ? line.liveCount : 0
        let dot = counts && unseen && !recording
        var description = recording ? L("Snapfly, recording the screen")
            : on ? L("Snapfly, hanging copied images") : "Snapfly"
        if let said = Self.statusCount(count, new: dot) { description += ", " + said }
        let image = recording ? NSImage(systemSymbolName: "stop.circle", accessibilityDescription: description)
            : LineIcon.image(filled: on, dot: dot, description: description)
        image?.isTemplate = true
        guard let button = statusItem.button else { return }
        button.image = image
        button.toolTip = description
        button.setAccessibilityLabel(description)
        if count > 0 {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: count > 99 ? "99+" : "\(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .baselineOffset: 0.5,
            ])
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
        }
    }

    /// Count on the menu bar icon, from Settings › Line. On unless turned off.
    static var countsInMenuBar: Bool {
        get { !UserDefaults.standard.bool(forKey: "menuBarCountOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "menuBarCountOff") }
    }

    /// What the count and the dot say to VoiceOver and in the tip.
    nonisolated static func statusCount(_ count: Int, new: Bool) -> String? {
        guard count > 0 else { return nil }
        let photos = count == 1 ? L("One photo on the line") : String(format: L("%d photos on the line"), count)
        return new ? photos + ", " + L("something new") : photos
    }

    /// Something new hangs that the line has not shown yet.
    private var unseen = false {
        didSet { if unseen != oldValue { updateStatusIcon() } }
    }
    private var lastCount = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Only once something was asked for and not given: nothing nags
        // about what was never needed.
        if Permissions.somethingDenied {
            menu.addItem(ClosureMenuItem(L("Permissions Needed…"), symbol: "exclamationmark.triangle") { [weak self] in
                self?.openPermissions()
            })
            menu.addItem(.separator())
        }

        // First what hangs, then the main act: the photos picked, or the
        // newest, into the app in front, as the send shortcut does.
        let count = line.liveCount
        let status = NSMenuItem(title: count == 0 ? L("Nothing on the line")
                                : count == 1 ? L("One photo on the line")
                                : String(format: L("%d photos on the line"), count),
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let app = Paste.frontApp?.localizedName {
            let sendItem = ClosureMenuItem(String(format: L("Paste into %@"), app), symbol: "paperplane") { [weak self] in
                self?.line.pasteNewest()
            }
            Self.show(Shortcut.current(.send), on: sendItem)
            sendItem.isEnabled = count > 0
            menu.addItem(sendItem)
        }
        menu.addItem(.separator())

        // The ways onto the line.
        if Recording.shared.isRecording {
            let stopItem = ClosureMenuItem(L("Stop Recording"), symbol: "stop.circle") { Recording.shared.stop() }
            Self.show(Shortcut.current(.record), on: stopItem)
            menu.addItem(stopItem)
        } else {
            let captureItem = ClosureMenuItem(L("Take Screenshot"), symbol: "camera.viewfinder") {
                // Once the menu has faded, so it is not in the picture.
                Capture.shared.start(after: 0.2)
            }
            Self.show(Shortcut.current(.capture), on: captureItem)
            menu.addItem(captureItem)
            let timerItem = NSMenuItem(title: L("Take Screenshot with Timer"), action: nil, keyEquivalent: "")
            Self.symbol("timer", on: timerItem)
            let seconds = NSMenu()
            for n in Capture.timerChoices {
                seconds.addItem(ClosureMenuItem(Self.secondsTitle(n)) {
                    Capture.shared.start(after: 0.2, mode: .timer(n))
                })
            }
            timerItem.submenu = seconds
            menu.addItem(timerItem)
            let pageItem = ClosureMenuItem(L("Capture Whole Page"), symbol: "scroll") {
                FullPage.shared.start(after: 0.2)
            }
            Self.show(Shortcut.current(.page), on: pageItem)
            menu.addItem(pageItem)
            let recordItem = ClosureMenuItem(L("Record Screen"), symbol: "record.circle") {
                Capture.shared.start(after: 0.2, mode: .record)
            }
            Self.show(Shortcut.current(.record), on: recordItem)
            menu.addItem(recordItem)
        }
        // Photos and PDFs from anywhere on the Mac, to send protected.
        menu.addItem(ClosureMenuItem(L("Add Files…"), symbol: "folder.badge.plus", key: "o") { [weak self] in
            self?.chooseFiles()
        })
        menu.addItem(.separator())

        // The line itself.
        let toggleItem = ClosureMenuItem(isRevealed ? L("Hide line") : L("Show line"),
                                         symbol: isRevealed ? "arrow.up.to.line" : "arrow.down.to.line") { [weak self] in
            self?.toggle()
        }
        Self.show(Shortcut.current(.toggle), on: toggleItem)
        menu.addItem(toggleItem)

        let searchItem = ClosureMenuItem(L("Search…"), symbol: "magnifyingglass") { [weak self] in self?.openSearch() }
        Self.show(Shortcut.current(.search), on: searchItem)
        searchItem.isEnabled = count > 0
        menu.addItem(searchItem)

        let historyItem = ClosureMenuItem(L("History…"), symbol: "clock.arrow.circlepath", key: "y") {
            HistoryWindow.shared.show()
        }
        historyItem.isEnabled = History.days != nil
        menu.addItem(historyItem)

        let clearItem = ClosureMenuItem(L("Take everything down"), symbol: "eye.slash") { [weak self] in
            self?.line.clear()
        }
        clearItem.isEnabled = count > 0
        menu.addItem(clearItem)
        menu.addItem(.separator())

        // The two switches: what leaves covered, and the button at the edge.
        let privacyItem = ClosureMenuItem(L("Hide private details"), symbol: "hand.raised") { [weak self] in
            self?.togglePrivateDetails()
        }
        privacyItem.state = PrivateDetails.hidden ? .on : .off
        menu.addItem(privacyItem)
        let buttonItem = ClosureMenuItem(L("Screenshot Button"), symbol: "camera.circle") { [weak self] in
            CaptureButton.isEnabled.toggle()
            self?.preferences?.refresh()
        }
        buttonItem.state = CaptureButton.isEnabled ? .on : .off
        menu.addItem(buttonItem)
        menu.addItem(.separator())

        // Everything else lives in the settings window.
        menu.addItem(ClosureMenuItem(L("Settings…"), symbol: "gearshape", key: ",") { [weak self] in
            self?.openSettings()
        })
        menu.addItem(ClosureMenuItem(L("Open screenshots folder"), symbol: "folder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.watcher.folder)
        })
        // Ended before its end, it says it goes on from there.
        let introduction = GuideProgress.load().canContinue ? L("Continue Introduction") : L("Introduction")
        menu.addItem(ClosureMenuItem(introduction, symbol: "hand.wave") {
            // Once the menu has gone, so the first step finds the icon free.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Guide.shared.startIntroduction() }
        })
        menu.addItem(ClosureMenuItem(L("Help & Support…"), symbol: "questionmark.circle") {
            NSWorkspace.shared.open(AppDelegate.supportURL)
        })
        // The app never connects to anything, so it cannot tell when a new
        // version is out. The releases page can.
        // From the App Store, updates come through it.
        if !Edition.appStore {
            menu.addItem(ClosureMenuItem(L("Check for Updates…"), symbol: "arrow.down.circle") {
                NSWorkspace.shared.open(AppDelegate.updatesURL)
            })
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit Snapfly"), key: "q") {
            NSApp.terminate(nil)
        })
    }

    /// The introduction's first step asks for this menu.
    func menuDidClose(_ menu: NSMenu) {
        Guide.shared.happened(.menuBarMenu)
    }

    /// A shortcut's key on its menu item, when it is one key.
    private static func show(_ shortcut: Shortcut?, on item: NSMenuItem) {
        guard let shortcut, shortcut.key.count == 1 else { return }
        item.keyEquivalent = shortcut.key
        item.keyEquivalentModifierMask = shortcut.modifiers
    }

    /// A symbol on a plain menu item, from macOS 26 on, as ClosureMenuItem
    /// gives its own.
    private static func symbol(_ name: String, on item: NSMenuItem) {
        if #available(macOS 26, *) {
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }

    /// The menu's switch for all of Hide private details. Off keeps the kinds
    /// that were chosen, so on brings them back as they were; with none
    /// kept, the recommended ones.
    private static let detailsBeforeKey = "hiddenDetailsBefore"

    private func togglePrivateDetails() {
        if PrivateDetails.hidden {
            UserDefaults.standard.set(PrivateDetails.details.map(\.rawValue).sorted(), forKey: Self.detailsBeforeKey)
            PrivateDetails.details = []
        } else {
            let kept = (UserDefaults.standard.stringArray(forKey: Self.detailsBeforeKey) ?? [])
                .compactMap(PrivateDetail.init(rawValue:))
            PrivateDetails.details = kept.isEmpty ? PrivateDetail.recommended : Set(kept)
        }
        line.readPrivateDetails()
        preferences?.refresh()
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

    /// The support page of the website, in German or Arabic where the Mac
    /// speaks them, else in English.
    static var supportURL: URL {
        let language = String(Locale.preferredLanguages.first?.prefix(2) ?? "")
        let folder = ["de", "ar"].contains(language) ? language + "/" : ""
        return URL(string: "https://mgrd281.github.io/Screenshots/" + folder + "support.html")!
    }

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
