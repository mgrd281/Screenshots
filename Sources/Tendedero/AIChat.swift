import AppKit

/// ChatGPT and Claude, to send photos straight into from the line: their
/// app when it is on this Mac, else their website in the browser. Their
/// icons on a photo are the apps' own, as macOS shows them in the Dock;
/// Snapfly carries no logo of theirs.
enum AIChat: String, CaseIterable, Identifiable {
    case chatGPT, claude

    var id: String { rawValue }

    /// The name as the company writes it, in every language.
    var name: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }

    var appID: String {
        switch self {
        case .chatGPT: "com.openai.chat"
        case .claude: "com.anthropic.claudefordesktop"
        }
    }

    /// The websites it answers on, the first being where a new chat opens.
    var hosts: [String] {
        switch self {
        case .chatGPT: ["chatgpt.com", "chat.openai.com"]
        case .claude: ["claude.ai"]
        }
    }

    /// The page that starts a new chat.
    var newChat: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .claude: URL(string: "https://claude.ai/new")!
        }
    }

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

    // MARK: On the photos

    /// From Settings › Line. On unless turned off.
    static var onPhotos: Bool {
        get { !UserDefaults.standard.bool(forKey: "aiChatsOnPhotosOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "aiChatsOnPhotosOff") }
    }

    /// The ones whose icon shows on a photo under the pointer: with their
    /// app on this Mac, and the setting on.
    @MainActor
    static var onPhotosNow: [AIChat] {
        onPhotos ? installed : []
    }

    /// Where the app is installed, if it is.
    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)
    }

    /// The chats whose app is on this Mac, looked up again every few
    /// seconds at most, so a photo under the pointer stays quick.
    @MainActor
    static var installed: [AIChat] {
        if let found, Date().timeIntervalSince(found.at) < 5 { return found.chats }
        let chats = allCases.filter { $0.appURL != nil }
        found = (Date(), chats)
        return chats
    }

    @MainActor private static var found: (at: Date, chats: [AIChat])?
    @MainActor private static var icons: [String: NSImage] = [:]

    /// The app's own icon, as the Finder and the Dock show it; nil without
    /// the app.
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

    /// Brings the chat to the front, ready to paste into: its app, opened or
    /// brought back with the chat it shows, else the website, on the chat
    /// open in the browser in front or on a new one. Calls back once the
    /// chat is in front and has had a moment to put its message box in
    /// reach; if it never comes, a note says so instead.
    @MainActor
    func open(then ready: @escaping () -> Void) {
        let front = Paste.frontApp?.bundleIdentifier
        if appURL != nil {
            if front == appID { return ready() }
        } else if let front, ChatButton.browserIDs.contains(front), owns(host: ChatButton.pageInFront()?.host) {
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
        if let app = appURL {
            openApp(at: app, then: finish)
        } else {
            openWebsite(then: finish)
        }
    }

    /// Opens the app, or brings it back with a window, and waits for it in
    /// front: a little longer when it has to start first.
    @MainActor
    private func openApp(at app: URL, then finish: @escaping (Bool) -> Void) {
        let bundle = appID
        let started = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard error == nil else { return finish(false) }
                    Self.wait(within: 15, every: 0.1, for: { Paste.frontApp?.bundleIdentifier == bundle }) { front in
                        guard front else { return finish(false) }
                        Self.settle(within: started ? 0.6 : 2, least: started ? 0.2 : 0.8) { finish(true) }
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
        let browser = NSWorkspace.shared.urlForApplication(toOpen: newChat).flatMap { Bundle(url: $0)?.bundleIdentifier }
        guard NSWorkspace.shared.open(newChat) else { return finish(false) }
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
