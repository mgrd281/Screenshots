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
        panel.line = line
        panel.placeOnScreen()
        updateCapacity()

        // The Workspace, when it is on: where screenshots are kept, and the
        // line following the files it moves.
        let desktopWorkspace = Workspace.shared
        desktopWorkspace.onChange = { [weak self] in
            if Inbox.isEnabled || Edition.appStore { Inbox.apply() }
            self?.startWatcher()
        }
        desktopWorkspace.relocated = { [weak self] old, new in self?.line.relocate(from: old, to: new) }
        desktopWorkspace.rebased = { [weak self] old, new in self?.line.rebase(from: old, to: new) }
        desktopWorkspace.removed = { [weak self] in self?.line.prune() }
        desktopWorkspace.start()

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
        TextCard.shared.openSettings = { [weak self] in self?.openAssistantSettings() }
        CaptureButton.shared.update()
        Recording.cleanUp()
        // Syncing with the iPhone, in a build that can, once it is turned on.
        MacSync.start(line: line)
        History.purge()
        HistoryWindow.shared.onHang = { [weak self] url in self?.hangCapture(url) }
        HistoryWindow.shared.onSendAgain = { [weak self] url in self?.sendAgain(url) }
        // A guide hangs as a PDF, picked and ready to send.
        HowToEditor.shared.onHang = { [weak self] url in
            guard let self else { return }
            self.hangCapture(url)
            if let id = self.line.items.last(where: { $0.url == url && !$0.falling })?.id { self.line.pick(id) }
        }
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
        StudioEditor.shared.onSaved = { [weak self] url in self?.hangCapture(url) }
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
        DesktopIcons.shared.start()
        line.frameOfPhoto = { [weak self] id in self?.cardFrame(for: id) }
        line.onSearch = { [weak self] in self?.openSearch() }
        OpenPanelWatch.shared.onAppear = { [weak self] dialog in self?.fileWindowOpened(dialog) }
        OpenPanelWatch.shared.onDisappear = { [weak self] in self?.fileWindowClosed() }

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

        // Each time Snapfly comes to the front, the folders it could not
        // watch are tried again.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reviveWatchers() }
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

    /// Opened again from Finder, Launchpad or Spotlight while it runs:
    /// Settings, a window to find Snapfly by, as it has no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if launched { openSettings() }
        return false
    }

    /// When the menu bar icon cannot be seen, turned off in System Settings
    /// › Menu Bar on macOS 26 or hidden behind the camera's notch on a full
    /// menu bar, Settings opens instead, with a note on how to bring the icon
    /// back, so a launch never shows nothing. While the welcome or a
    /// question shows, it looks again once they are gone.
    private func showSettingsIfIconHidden(tries: Int = 60) {
        guard NSMenu.menuBarVisible(), !iconIsVisible else { return }
        guard NSApp.modalWindow == nil, !Guide.shared.isRunning else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.showSettingsIfIconHidden(tries: tries - 1)
                }
            }
            return
        }
        openSettings()
        if #available(macOS 26, *) {
            Notice.show(L("Snapfly's icon is not in the menu bar. Turn on Snapfly in System Settings › Menu Bar, under Allow in the Menu Bar. Open Snapfly again to come back to Settings."),
                        lasting: 12)
        } else {
            Notice.show(L("The menu bar has no room for Snapfly's icon. Open Snapfly again to come back to Settings."),
                        lasting: 8)
        }
    }

    /// Whether the menu bar icon is on a screen. From macOS 26 Control
    /// Center shows it for Snapfly, and an icon it does not show has no
    /// screen; before, it is Snapfly's own window, covered when the notch
    /// hides it.
    private var iconIsVisible: Bool {
        guard statusItem.isVisible, let window = statusItem.button?.window, let screen = window.screen
        else { return false }
        if #available(macOS 26, *) { return true }
        return window.isVisible && window.occlusionState.contains(.visible) && screen.frame.intersects(window.frame)
    }

    /// Quitting while the screen is recorded, from the menu, by logging out
    /// or with Install and Reopen, saves the recording first, as Stop does.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Recording.shared.isRecording else { return .terminateNow }
        Task { @MainActor in
            await Recording.shared.finishBeforeQuitting()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
                    log.notice("Screenshot landed on the Desktop despite inbox mode: \(url.lastPathComponent, privacy: .private)")
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

    /// Watches again what can be watched now: a folder that could not be
    /// opened, like the Desktop before Snapfly was let in, or that went, like
    /// one on a disk ejected. The Screenshot app may also save somewhere
    /// else since it was last read, with inbox mode off.
    private func reviveWatchers() {
        if !Edition.appStore,
           ScreenshotWatcher.screenshotFolder().standardizedFileURL.path != watcher.folder.standardizedFileURL.path {
            return startWatcher()
        }
        watcher.revive()
        safetyWatcher?.revive()
        folderWatchers.forEach { $0.revive() }
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
    /// A plain kill does not, so settings are also restored on those signals,
    /// and a recording under way is saved first, a few seconds at most.
    private func restoreSettingsOnTermination() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    if Inbox.isEnabled { Inbox.restore() }
                    guard Recording.shared.isRecording else { exit(0) }
                    Task { @MainActor in
                        await Recording.shared.finishBeforeQuitting(within: 5)
                        exit(0)
                    }
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Showing and hiding

    /// An empty line goes away, unless it was opened on purpose.
    private func itemsChanged() {
        // A file window in front matters only while there is a photo for it.
        OpenPanelWatch.shared.watch(line.liveCount > 0)
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

    // MARK: File windows

    /// A file window came up in front, as a website shows to attach a file:
    /// the line comes down on its screen, says how to put a photo in, and
    /// an arrow goes from the newest photo to the window.
    private func fileWindowOpened(_ dialog: CGRect) {
        guard line.liveCount > 0, !Calls.shared.keepingAway else { return }
        let middle = CGPoint(x: dialog.midX, y: dialog.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(middle, $0.frame, false) }
        comeDown(on: screen)
        // Down while the window is open, until the pointer has been to it and left.
        reveal(peekFor: 60)
        guard isRevealed else { return }
        Notice.show(L("Drag a photo into the window, or click its paper plane."), on: screen, lasting: 6)
        // Once the line has come down and laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, OpenPanelWatch.shared.frame != nil, self.isRevealed,
                  let newest = self.line.items.last(where: { !$0.falling }),
                  let card = self.cardFrame(for: newest.id) else { return }
            let start = CGPoint(x: card.midX, y: card.minY - OpenPanelArrow.side)
            // Just above the window's top edge, so it covers nothing of it.
            let end = CGPoint(x: dialog.midX, y: dialog.maxY + OpenPanelArrow.side * 0.75)
            OpenPanelArrow.shared.show(from: start, to: end)
        }
    }

    /// The file window went: the arrow with it, and the line tucks away
    /// once the pointer is elsewhere.
    private func fileWindowClosed() {
        OpenPanelArrow.shared.hide()
        if peekUntil > Date() { peekUntil = Date() }
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
        // Once the menu bar has placed the icon, and after the welcome,
        // which shows on its own.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.showSettingsIfIconHidden() }
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
        guard let from else {
            Guide.shared.happened(.photoHung)
            return
        }
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

    /// Finder's "Hide Private Details with Snapfly": one photo or PDF opens
    /// to decide what its copy hides; several, or a folder, open Cover Files.
    private func hideDetails(_ urls: [URL]) {
        // Several files, or a folder of them, go to Cover Files.
        let folder = { (url: URL) in (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        if urls.count > 1 || urls.contains(where: folder) {
            CoverFiles.shared.open(with: urls)
            return
        }
        let files = Outside.sort(urls)
        if let url = files.accepted.first {
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
                let willPaste = Paste.willPaste
                // Copied once it went: a PDF still being covered says so itself.
                guard self.line.paste(id), !willPaste else { return }
                self.sayCopied(url, covering: CoveringProfile.detailsNow)
            }
        }
    }

    /// Send Again's note where Snapfly may not paste: "covered" only when
    /// something was, as the iPhone says it. A picture covered whole, as its
    /// reading failed, has said so already; a recording goes as it is.
    private func sayCopied(_ url: URL, covering chosen: Set<PrivateDetail>) {
        let recording = Tendedero.isRecording(url)
        let report = recording ? nil : PrivateDetails.report(for: url, covering: chosen)
        let looked = !recording && PrivateDetails.covers(url)
        if let report, !report.isEmpty {
            Notice.show(L("Covered and copied, ready to paste."))
        } else if report != nil, looked {
            Notice.show(L("Nothing to cover was found. Copied as it is, ready to paste."))
        } else if report != nil || !looked {
            Notice.show(L("Copied. Paste it with ⌘V."))
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
        // Its covered copy is being made: old ones may go.
        pruneCoveredCopies()
        sendToChatIfChosen(id)
        guard let from else {
            Guide.shared.happened(.photoHung)
            return
        }
        // Let the line come down and lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: from)
        }
    }

    /// With an AI chat chosen in Settings, the new screenshot goes there once
    /// it has landed on the line: when the chat is in front, with any others
    /// waiting for it; or at once, into the chat in front or a new one.
    private func sendToChatIfChosen(_ id: UUID) {
        guard let chat = CaptureToChat.chat, !Calls.shared.keepingAway else { return }
        let place = CaptureToChat.place
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.line.items.contains(where: { $0.id == id && !$0.falling }) else { return }
            guard place == .whenOpened else {
                return self.line.send(id, to: chat, forceNew: place == .new, keep: CaptureToChat.keepsOnLine)
            }
            let first = self.waitingForChat.isEmpty
            self.waitingForChat.append(id)
            if chat.isInFront { return self.sendWaiting(to: chat) }
            if first { Notice.show(String(format: L("It goes into %@ as soon as you open it."), chat.name)) }
            self.watchForChat()
        }
    }

    /// Screenshots waiting on the line for their AI chat to come to the front.
    private var waitingForChat: [UUID] = []
    private var chatWatch: Timer?

    private func watchForChat() {
        guard chatWatch == nil else { return }
        chatWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Taken down meanwhile, or the chat no longer chosen: they wait no more.
                self.waitingForChat.removeAll { id in !self.line.items.contains { $0.id == id && !$0.falling } }
                guard let chat = CaptureToChat.chat, CaptureToChat.place == .whenOpened,
                      !self.waitingForChat.isEmpty else { return self.stopWatchingForChat() }
                if chat.isInFront { self.sendWaiting(to: chat) }
            }
        }
    }

    private func stopWatchingForChat() {
        chatWatch?.invalidate()
        chatWatch = nil
        waitingForChat = []
    }

    /// All that waited, together, into the conversation open in front.
    private func sendWaiting(to chat: ChatTarget) {
        let ids = waitingForChat
        stopWatchingForChat()
        guard !ids.isEmpty, !Calls.shared.keepingAway else { return }
        line.send(ids, to: chat, keep: CaptureToChat.keepsOnLine)
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
    /// as the line view, mirrored where SwiftUI lays the line out right to
    /// left.
    private func cardFrame(for id: UUID) -> CGRect? {
        guard let index = line.items.firstIndex(where: { $0.id == id }) else { return nil }
        let width = panel.frame.width
        let x = Layout.x(index: index, count: line.items.count, width: width,
                         visible: line.visibleCount, scroll: line.scroll, spread: line.spread)
        let across = line.runsRightToLeft(width: width) ? width - x : x
        let viewTop = panel.drop + Layout.ropeY(x: x, width: width, shift: line.shift(width: width)) - Layout.pinAbove
        let cardTop = viewTop + PeggedView.cardOffsetBelowTop
        let size = PeggedView.cardSize(for: line.items[index].thumb.size)
        return CGRect(x: panel.frame.minX + across - size.width / 2,
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
                                   x: x, width: width, shift: line.shift(width: width)))
    }

    /// Whether a full screen app keeps the line away from its screen, as it
    /// does unless Settings › Line lets it come over one.
    private var lineBlocked: Bool {
        panel.screen.map(FullScreen.blocksLine(on:))
            ?? LinePanel.screenUnderPointer().map(FullScreen.blocksLine(on:)) ?? false
    }

    /// Decides whether the panel is ordered in at all: something to show,
    /// and no full screen app on that screen.
    private func refresh() {
        let blocked = lineBlocked
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
            TagView.letGo()
            line.grip = .still
            // What was picked stays picked, for the send button over a chat.
        }
    }

    /// Search: the line comes down, with a bar under it to type into.
    private func openSearch() {
        if !isRevealed { toggle() }
        guard isRevealed else {
            // Kept away by a full screen app, which toggle has said.
            if !lineBlocked { Notice.show(L("The line is empty.")) }
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
            if isRevealed {
                Guide.shared.lineCameDown()
            } else if lineBlocked {
                // Asked for, it says why it stays up, and where to change that.
                Notice.show(String(format: L("The line stays away from full screen apps. Turn on %1$@ in %2$@."),
                                   L("Over full screen apps"), [L("Settings"), L("Line")].joined(separator: " › ")))
            }
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
        hotKeys[role] = HotKey(shortcut, for: role) { [weak self] in self?.shortcutPressed(role) }
        listenUnderMenus()
    }

    /// The shortcuts that take the screen are heard while another app's
    /// menu is open too, the ones registered: one another app took stays
    /// that app's.
    private func listenUnderMenus() {
        let registered = Dictionary(uniqueKeysWithValues: hotKeys.keys.compactMap { role in
            Shortcut.current(role).map { (role, $0) }
        })
        ShortcutTap.shared.onPress = { [weak self] role in self?.shortcutPressed(role) }
        ShortcutTap.shared.listen(for: registered)
    }

    /// When a shortcut was last done, so one heard twice, by its hot key
    /// and under a menu, is done once.
    private var lastShortcut: (role: Shortcut.Role, at: Date)?

    private func shortcutPressed(_ role: Shortcut.Role) {
        if let last = lastShortcut, last.role == role, Date().timeIntervalSince(last.at) < 0.4 { return }
        lastShortcut = (role, Date())
        switch role {
        case .toggle: toggle()
        case .send: line.pasteNewest()
        case .search: openSearch()
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

    private func changeShortcut(_ role: Shortcut.Role) {
        // All off while recording, so pressing one records it instead of
        // doing what it does.
        hotKeys = [:]
        listenUnderMenus()
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
                if Workspace.shared.isOn { Workspace.shared.reveal() } else { NSWorkspace.shared.open(self.watcher.folder) }
            },
            screenshotsFolder: { [weak self] in Workspace.shared.isOn ? Workspace.shared.root : self?.watcher.folder },
            menuBarCountChanged: { [weak self] in self?.updateStatusIcon() })
        self.preferences = preferences
    }

    private func openSettings() {
        guard let preferences else { return }
        SettingsWindow.shared.show(preferences)
    }

    private func openAssistantSettings() {
        guard let preferences else { return }
        preferences.showsAssistant = true
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
        guide.lacks = { [weak self] need in self?.guideLacks(need) }
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

    /// Why the newest photo lacks what a step needs, for Show Me How's note:
    /// a screen recording, nothing covered, or every icon under the photos
    /// turned off.
    private func guideLacks(_ need: GuideStep.Need) -> String? {
        guard let item = guidePhoto else { return nil }
        switch need {
        case .coveredPhoto, .iconsUnderPhotos:
            if item.isRecording { return L("The newest on the line is a screen recording: this shows on a photo.") }
            if need == .coveredPhoto {
                return L("Nothing is covered on the newest photo: this shows on one with something covered.")
            }
            return String(format: L("No icons are on under the photos. Turn one on in %@."),
                          [L("Settings"), L("Line"), L("Icons under photos")].joined(separator: " › "))
        case .photo, .twoPhotos:
            return nil
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

        // Settings at the top, where it is found at once, with the folder the
        // screenshots are kept in.
        menu.addItem(ClosureMenuItem(L("Settings…"), symbol: "gearshape", key: ",") { [weak self] in
            self?.openSettings()
        })
        let workspaceOn = Workspace.shared.isOn
        menu.addItem(ClosureMenuItem(workspaceOn ? L("Open Workspace") : L("Open screenshots folder"), symbol: "folder") { [weak self] in
            guard let self else { return }
            if workspaceOn { Workspace.shared.reveal() } else { NSWorkspace.shared.open(self.watcher.folder) }
        })
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
        // A step-by-step guide, from the clicks that follow.
        if HowToRecorder.shared.isRecording {
            menu.addItem(ClosureMenuItem(L("Finish Guide"), symbol: "stop.circle") { HowToRecorder.shared.finish() })
            menu.addItem(ClosureMenuItem(L("Cancel Guide"), symbol: "xmark.circle") { HowToRecorder.shared.cancel() })
        } else {
            menu.addItem(ClosureMenuItem(L("Record a Guide"), symbol: "list.number") { HowToRecorder.shared.start() })
            let guides = HowToStore.recent()
            if !guides.isEmpty {
                let recentItem = NSMenuItem(title: L("Recent Guides"), action: nil, keyEquivalent: "")
                Self.symbol("clock", on: recentItem)
                let list = NSMenu()
                for guide in guides.prefix(10) {
                    list.addItem(ClosureMenuItem(HowToRender.name(of: guide)) { HowToEditor.shared.open(guide) })
                }
                recentItem.submenu = list
                menu.addItem(recentItem)
            }
        }
        menu.addItem(.separator())

        // Photos and PDFs from anywhere on the Mac, to send protected.
        menu.addItem(ClosureMenuItem(L("Add Files…"), symbol: "folder.badge.plus", key: "o") { [weak self] in
            self?.chooseFiles()
        })
        // Many PDFs and pictures covered at once, each saved as a copy.
        menu.addItem(ClosureMenuItem(L("Cover Files…"), symbol: "doc.on.doc") { CoverFiles.shared.open() })
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

        // The switches: what leaves covered, the button at the edge, and the
        // desktop's icons.
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
        // The wallpaper over the desktop icons, for clean screenshots.
        let iconsItem = ClosureMenuItem(L("Hide Desktop Icons"), symbol: "menubar.dock.rectangle") {
            DesktopIcons.shared.toggle()
        }
        iconsItem.state = DesktopIcons.isHidden ? .on : .off
        menu.addItem(iconsItem)
        menu.addItem(.separator())

        // Help, then the newest version, just above Quit.
        // Ended before its end, it says it goes on from there.
        let introduction = GuideProgress.load().canContinue ? L("Continue Introduction") : L("Introduction")
        menu.addItem(ClosureMenuItem(introduction, symbol: "hand.wave") {
            // Once the menu has gone, so the first step finds the icon free.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Guide.shared.startIntroduction() }
        })
        menu.addItem(ClosureMenuItem(L("Help & Support…"), symbol: "questionmark.circle") {
            NSWorkspace.shared.open(AppDelegate.supportURL)
        })
        menu.addItem(ClosureMenuItem(L("Check for Updates…"), symbol: "arrow.down.circle") {
            Updater.check()
        })

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

    // MARK: Covered copies

    /// When the covered copies were last thinned out; they are emptied at
    /// each launch.
    private var prunedAt = Date()

    /// Covered copies wait in the temporary folder to be pasted. On a Mac
    /// that runs Snapfly for days, they are thinned out as new ones are
    /// made, an hour apart at most: those made a day ago or more go, but the
    /// ones the line shows, which go out again. Not while one may still be
    /// on its way: with files on the clipboard, or a photo dragged out in
    /// the last minutes.
    private func pruneCoveredCopies() {
        let now = Date()
        guard now.timeIntervalSince(prunedAt) > 3600, !GrabView.isDragging,
              now.timeIntervalSince(GrabView.lastDragEnd) > 300,
              NSPasteboard.general.types?.contains(.fileURL) != true else { return }
        prunedAt = now
        let shown = line.items.filter { !$0.falling }.compactMap { PrivateDetails.shown($0.url) }
        let keeping = Set(shown.map { $0.deletingLastPathComponent().lastPathComponent })
        let limit = now.addingTimeInterval(-24 * 3600)
        DispatchQueue.global(qos: .utility).async {
            AppDelegate.pruneCopies(in: Cover.folder, madeBefore: limit, keeping: keeping)
        }
    }

    /// Takes away the copies in `folder`, each in a folder of its own, made
    /// before `limit`, but those whose folders are named in `keeping`.
    nonisolated static func pruneCopies(in folder: URL, madeBefore limit: Date, keeping: Set<String>) {
        let fm = FileManager.default
        let copies = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for entry in copies where !keeping.contains(entry.lastPathComponent) {
            let made = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
            if made < limit { try? fm.removeItem(at: entry) }
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
