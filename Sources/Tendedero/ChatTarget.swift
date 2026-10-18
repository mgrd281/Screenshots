import AppKit

/// Where a photo goes straight from the line: ChatGPT, Claude, WhatsApp and
/// Gmail. Their website in the browser, or their app when it is on this Mac
/// and Settings says so. Their icons on a photo are the app's own, as macOS
/// draws it in the Dock, wherever the app is on this Mac; else a short mark
/// in a neutral circle. Snapfly carries no logo of theirs.
enum ChatTarget: String, CaseIterable, Identifiable {
    case chatGPT, claude, whatsApp, gmail

    var id: String { rawValue }

    /// The name as the company writes it, in every language.
    var name: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .whatsApp: "WhatsApp"
        case .gmail: "Gmail"
        }
    }

    /// An AI chat: what goes in is covered as in any AI chat, and it can be
    /// asked a question with the photo.
    var isAI: Bool {
        switch self {
        case .chatGPT, .claude: true
        case .whatsApp, .gmail: false
        }
    }

    /// The bundle IDs its app goes by; Gmail has none of its own.
    var appIDs: [String] {
        switch self {
        case .chatGPT: ["com.openai.chat"]
        case .claude: ["com.anthropic.claudefordesktop"]
        case .whatsApp: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]
        case .gmail: []
        }
    }

    var appID: String? { appIDs.first }

    /// The names an app made from its website goes by, like a Chrome app.
    private var appNames: [String] {
        switch self {
        case .chatGPT: ["ChatGPT"]
        case .claude: ["Claude"]
        case .whatsApp: ["WhatsApp"]
        case .gmail: ["Gmail"]
        }
    }

    /// The websites it answers on, the first being where a new chat opens.
    var hosts: [String] {
        switch self {
        case .chatGPT: ["chatgpt.com", "chat.openai.com"]
        case .claude: ["claude.ai"]
        case .whatsApp: ["web.whatsapp.com"]
        case .gmail: ["mail.google.com"]
        }
    }

    /// The page that starts a new chat, or a new message in Gmail.
    var newChat: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .claude: URL(string: "https://claude.ai/new")!
        case .whatsApp: URL(string: "https://web.whatsapp.com/")!
        case .gmail: URL(string: "https://mail.google.com/mail/?view=cm&fs=1")!
        }
    }

    /// Gmail starts a message of its own each time, so a Gmail page already
    /// in front is not the place.
    var startsFresh: Bool { self == .gmail }

    /// Whether a website, with its subdomains, is this chat's.
    func owns(host: String?) -> Bool {
        guard var host = host?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether a photo can go into it: a picture or a PDF, not a recording.
    static func takes(_ item: Pegged) -> Bool {
        !item.isRecording
    }

    /// Its icon where its app is not on this Mac: a short mark in a neutral
    /// circle, in plain letters, since Snapfly carries no logo of theirs.
    var mark: String {
        switch self {
        case .chatGPT: "GPT"
        case .claude: "Cl"
        case .whatsApp: "WA"
        case .gmail: "Gm"
        }
    }

    // MARK: On the photos

    /// Whether its icon shows on a photo, from Settings › Line. On unless
    /// turned off. Whoever turned off the single switch of before keeps
    /// ChatGPT and Claude off until they choose again.
    static func shows(_ chat: ChatTarget, in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: chat.offKey) != nil { return !defaults.bool(forKey: chat.offKey) }
        return chat.isAI ? !defaults.bool(forKey: "aiChatsOnPhotosOff") : true
    }

    static func setShows(_ on: Bool, _ chat: ChatTarget, in defaults: UserDefaults = .standard) {
        defaults.set(!on, forKey: chat.offKey)
    }

    private var offKey: String { "aiChatOff.\(rawValue)" }

    /// The ones whose icon shows on a photo under the pointer. They show
    /// whether or not the app is on this Mac: the website is always there.
    @MainActor
    static var onPhotosNow: [ChatTarget] {
        allCases.filter { shows($0) }
    }

    /// From Settings › Line: a click opens the chat in its app, when it is on
    /// this Mac. Off, it opens on the website, in the browser. Off at first.
    static var opensInApp: Bool {
        get { UserDefaults.standard.bool(forKey: "aiChatsOpenInApp") }
        set { UserDefaults.standard.set(newValue, forKey: "aiChatsOpenInApp") }
    }

    /// Where its app is installed, if it is: by its bundle ID, else by name in
    /// the folders apps live in, which finds an app made from the website,
    /// like a Chrome app. Looked up again every few seconds at most, so a
    /// photo under the pointer stays quick.
    @MainActor
    var appURL: URL? {
        if let known = Self.located[self], Date().timeIntervalSince(known.at) < 5 { return known.url }
        let url = appIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            ?? Self.appFolders.lazy.flatMap { folder in
                appNames.map { folder.appendingPathComponent($0 + ".app") }
            }.first { FileManager.default.fileExists(atPath: $0.path) }
        Self.located[self] = (Date(), url)
        return url
    }

    /// The bundle ID of the app that is on this Mac.
    @MainActor
    var installedAppID: String? {
        appURL.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? appID
    }

    @MainActor private static var located: [ChatTarget: (at: Date, url: URL?)] = [:]

    private static let appFolders: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
                home.appendingPathComponent("Applications/Chrome Apps.localized", isDirectory: true),
                home.appendingPathComponent("Applications/Edge Apps.localized", isDirectory: true)]
    }()

    @MainActor private static var icons: [String: NSImage] = [:]

    /// The app's own icon, as the Finder and the Dock show it, wherever its
    /// app is on this Mac; nil without it, and the circle shows the mark
    /// instead.
    @MainActor
    var icon: NSImage? {
        guard let path = appURL?.path else { return nil }
        if let icon = Self.icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        Self.icons[path] = icon
        return icon
    }

    // MARK: Opening

    /// The send waiting for its chat; a newer one takes its place.
    @MainActor private static var waiting: UUID?

    /// Brings the chat to the front, ready to paste into: the one in front
    /// already, in its app or on its website in a browser; else its app,
    /// opened or brought back with the chat it shows; else its website, on
    /// a new chat. Calls back once the chat is in front and has had a moment
    /// to put its message box in reach; if it never comes, a note says so
    /// instead.
    @MainActor
    func open(then ready: @escaping () -> Void) {
        let front = Paste.frontApp?.bundleIdentifier
        // Opening in the browser, the app in front is not the place.
        if !startsFresh, Self.opensInApp, let front, front == installedAppID { return ready() }
        // Asking a browser for its page takes a moment: only a browser.
        if !startsFresh, let front, ChatButton.browserIDs.contains(front),
           owns(host: ChatButton.pageInFront()?.host) {
            return ready()
        }
        let token = UUID()
        Self.waiting = token
        let title = name
        let note = Notice.show(String(format: L("Opening %@…"), title), working: true)
        let finish = { (shown: Bool) in
            Notice.end(note)
            guard Self.waiting == token else { return }
            Self.waiting = nil
            if shown {
                ready()
            } else {
                Notice.show(String(format: L("Could not open %@. The photos stay on the line."), title))
            }
        }
        if Self.opensInApp, let app = appURL {
            openApp(at: app, then: finish)
        } else {
            openWebsite(then: finish)
        }
    }

    /// Opens the app, or brings it back with a window, and waits for it in
    /// front with its window on screen: a little longer when it has to start
    /// first, since its chat then still has to load.
    @MainActor
    private func openApp(at app: URL, then finish: @escaping (Bool) -> Void) {
        let bundle = installedAppID ?? ""
        let started = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard error == nil else { return finish(false) }
                    Self.wait(within: 20, every: 0.1, for: {
                        guard let front = Paste.frontApp, front.bundleIdentifier == bundle else { return false }
                        return ChatButton.frontWindow(of: front.processIdentifier) != nil
                    }) { shown in
                        guard shown else { return finish(false) }
                        Self.settle(within: started ? 0.6 : 3, least: started ? 0.2 : 1.2) { finish(true) }
                    }
                }
            }
        }
    }

    /// Opens a new chat on the website in the browser, and waits for its
    /// page in front, where the browser says which page it shows.
    @MainActor
    private func openWebsite(then finish: @escaping (Bool) -> Void) {
        let chat = self
        // The browser the Mac opens websites with, not an app that claims
        // this address: the chat's own app may.
        let browserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.apple.com/")!)
        let browser = browserURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        if let browserURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([newChat], withApplicationAt: browserURL, configuration: configuration) { _, error in
                guard error != nil else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { finish(false) } }
            }
        } else if !NSWorkspace.shared.open(newChat) {
            return finish(false)
        }
        Self.wait(within: 20, every: 0.25, for: {
            guard let front = Paste.frontApp?.bundleIdentifier,
                  front == browser || ChatButton.browserIDs.contains(front) else { return false }
            // A browser that can't say which page it shows is trusted to.
            guard let page = ChatButton.pageInFront() else { return true }
            return chat.owns(host: page.host)
        }) { shown in
            guard shown else { return finish(false) }
            // The page loads and gives its message box the keyboard.
            Self.settle(within: 4, least: 1.2) { finish(true) }
        }
    }

    /// Calls back once a condition holds, or with false once the time is up.
    @MainActor
    private static func wait(within limit: TimeInterval, every interval: TimeInterval,
                             for condition: @escaping () -> Bool, then done: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(limit)
        func check() {
            if condition() { return done(true) }
            guard Date() < deadline else { return done(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                MainActor.assumeIsolated { check() }
            }
        }
        check()
    }

    /// A moment for the chat to put its message box in reach: until a field
    /// to type in has the keyboard, or the time is up.
    @MainActor
    private static func settle(within most: TimeInterval, least: TimeInterval, then done: @escaping () -> Void) {
        let start = Date()
        wait(within: most, every: 0.1, for: {
            Date().timeIntervalSince(start) >= least && Paste.isTypingInField
        }) { _ in done() }
    }
}
