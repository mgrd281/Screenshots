import AppKit

/// Where a photo goes straight from the line: ChatGPT, Claude, WhatsApp,
/// Gmail, GMX and WEB.DE, and more to choose in Settings: Perplexity, Grok,
/// DeepSeek, Qwen, Messenger, Instagram, Outlook, Yahoo Mail, Facebook,
/// Airbnb, Visual Studio Code and Antigravity. Each opens on its website, in
/// the browser Settings names, or in its app when it is on this Mac and
/// Settings says so for it. All but ChatGPT and Claude show their logo, which
/// the owner supplied (`assets/chat-logos`); ChatGPT and Claude show their
/// app's own icon, as macOS draws it in the Dock, wherever the app is on
/// this Mac, with no logo of theirs in Snapfly. Without either, a short mark
/// in a neutral circle.
enum ChatTarget: String, CaseIterable, Identifiable {
    case chatGPT, claude, perplexity, grok, deepSeek, qwen, whatsApp, messenger, instagram, gmail, outlook, yahoo
    case gmx, webDe, facebook, airbnb, vsCode, antigravity

    /// The six that show under a photo until chosen otherwise; the others
    /// wait to be turned on in Settings.
    var isStandard: Bool {
        switch self {
        case .chatGPT, .claude, .whatsApp, .gmail, .gmx, .webDe: true
        default: false
        }
    }

    var id: String { rawValue }

    /// The name as the company writes it, in every language.
    var name: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .perplexity: "Perplexity"
        case .grok: "Grok"
        case .deepSeek: "DeepSeek"
        case .qwen: "Qwen"
        case .whatsApp: "WhatsApp"
        case .messenger: "Messenger"
        case .instagram: "Instagram"
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        case .yahoo: "Yahoo Mail"
        case .gmx: "GMX"
        case .webDe: "WEB.DE"
        case .facebook: "Facebook"
        case .airbnb: "Airbnb"
        case .vsCode: "Visual Studio Code"
        case .antigravity: "Antigravity"
        }
    }

    /// An AI chat: what goes in is covered as in any AI chat, and it can be
    /// asked a question with the photo.
    var isAI: Bool {
        switch self {
        case .chatGPT, .claude, .perplexity, .grok, .deepSeek, .qwen: true
        default: false
        }
    }

    /// The bundle IDs its app goes by; some have none on the Mac, and are
    /// found by their name instead, if they are there.
    var appIDs: [String] {
        switch self {
        case .chatGPT: ["com.openai.chat"]
        case .claude: ["com.anthropic.claudefordesktop"]
        case .perplexity: ["ai.perplexity.mac"]
        case .whatsApp: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]
        case .messenger: ["com.facebook.archon", "com.facebook.archon.developerID"]
        case .outlook: ["com.microsoft.Outlook"]
        case .vsCode: ["com.microsoft.VSCode"]
        case .antigravity: ["com.google.antigravity"]
        case .grok, .deepSeek, .qwen, .instagram, .gmail, .yahoo, .gmx, .webDe, .facebook, .airbnb: []
        }
    }

    var appID: String? { appIDs.first }

    /// The names an app made from its website goes by, like a Chrome app.
    private var appNames: [String] {
        switch self {
        case .chatGPT: ["ChatGPT"]
        case .claude: ["Claude"]
        case .perplexity: ["Perplexity"]
        case .grok: ["Grok"]
        case .deepSeek: ["DeepSeek"]
        case .qwen: ["Qwen", "Qwen Chat"]
        case .whatsApp: ["WhatsApp"]
        case .messenger: ["Messenger"]
        case .instagram: ["Instagram"]
        case .gmail: ["Gmail"]
        case .outlook: ["Outlook", "Microsoft Outlook"]
        case .yahoo: ["Yahoo Mail"]
        case .gmx: ["GMX"]
        case .webDe: ["WEB.DE", "WEB.DE Mail"]
        case .facebook: ["Facebook"]
        case .airbnb: ["Airbnb"]
        case .vsCode: ["Visual Studio Code"]
        case .antigravity: ["Antigravity"]
        }
    }

    /// The websites it answers on, the first being where a new chat opens.
    var hosts: [String] {
        switch self {
        case .chatGPT: ["chatgpt.com", "chat.openai.com"]
        case .claude: ["claude.ai"]
        case .perplexity: ["perplexity.ai"]
        case .grok: ["grok.com"]
        case .deepSeek: ["chat.deepseek.com"]
        case .qwen: ["chat.qwen.ai"]
        case .whatsApp: ["web.whatsapp.com"]
        case .messenger: ["messenger.com"]
        case .instagram: ["instagram.com"]
        case .gmail: ["mail.google.com"]
        case .outlook: ["outlook.office.com", "outlook.live.com", "outlook.office365.com"]
        case .yahoo: ["mail.yahoo.com"]
        case .gmx: ["gmx.net", "gmx.de"]
        case .webDe: ["web.de"]
        case .facebook: ["facebook.com"]
        case .airbnb: ["airbnb.com", "airbnb.de"]
        case .vsCode: ["vscode.dev"]
        case .antigravity: ["antigravity.google"]
        }
    }

    /// The page that starts a new chat, or a new message in Gmail.
    var newChat: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .claude: URL(string: "https://claude.ai/new")!
        case .perplexity: URL(string: "https://www.perplexity.ai/")!
        case .grok: URL(string: "https://grok.com/")!
        case .deepSeek: URL(string: "https://chat.deepseek.com/")!
        case .qwen: URL(string: "https://chat.qwen.ai/")!
        case .whatsApp: URL(string: "https://web.whatsapp.com/")!
        case .messenger: URL(string: "https://www.messenger.com/")!
        case .instagram: URL(string: "https://www.instagram.com/direct/inbox/")!
        case .gmail: URL(string: "https://mail.google.com/mail/?view=cm&fs=1")!
        case .outlook: URL(string: "https://outlook.office.com/mail/deeplink/compose")!
        case .yahoo: URL(string: "https://mail.yahoo.com/")!
        case .gmx: URL(string: "https://navigator.gmx.net/")!
        case .webDe: URL(string: "https://navigator.web.de/")!
        case .facebook: URL(string: "https://www.facebook.com/messages/")!
        case .airbnb: URL(string: "https://www.airbnb.com/guest/messages")!
        case .vsCode: URL(string: "https://vscode.dev/")!
        case .antigravity: URL(string: "https://antigravity.google/")!
        }
    }

    /// A mailbox, Facebook, Instagram, Airbnb or an editor takes a photo only
    /// once you have a message or a chat open, so the photo is copied,
    /// covered, and left on the line for you to paste.
    var copiesOnly: Bool {
        switch self {
        case .gmx, .webDe, .outlook, .yahoo, .facebook, .instagram, .airbnb, .vsCode, .antigravity: true
        default: false
        }
    }

    /// The file of its logo in `assets/chat-logos`, which the build copies
    /// into the app; ChatGPT and Claude have none.
    var logoFile: String? {
        switch self {
        case .chatGPT, .claude: nil
        case .perplexity: "perplexity"
        case .grok: "grok"
        case .deepSeek: "deepseek"
        case .qwen: "qwen"
        case .whatsApp: "whatsapp"
        case .messenger: "messenger"
        case .instagram: "instagram"
        case .gmail: "gmail"
        case .outlook: "outlook"
        case .yahoo: "yahoo"
        case .gmx: "gmx"
        case .webDe: "webde"
        case .facebook: "facebook"
        case .airbnb: "airbnb"
        case .vsCode: "vscode"
        case .antigravity: "antigravity"
        }
    }

    @MainActor private static var logos: [ChatTarget: NSImage] = [:]

    /// Its logo, from the app's resources; nil without one, like when
    /// running outside the app.
    @MainActor
    var logo: NSImage? {
        guard let file = logoFile else { return nil }
        if let known = Self.logos[self] { return known }
        guard let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "chat-logos"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.logos[self] = image
        return image
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
        case .perplexity: "Px"
        case .grok: "Gk"
        case .deepSeek: "DS"
        case .qwen: "Qw"
        case .whatsApp: "WA"
        case .messenger: "Ms"
        case .instagram: "Ig"
        case .gmail: "Gm"
        case .outlook: "Ol"
        case .yahoo: "Y!"
        case .gmx: "GMX"
        case .webDe: "WEB"
        case .facebook: "Fb"
        case .airbnb: "Ab"
        case .vsCode: "VS"
        case .antigravity: "AG"
        }
    }

    // MARK: On the photos

    /// Whether its icon shows on a photo, from Settings › Line. On unless
    /// turned off. Whoever turned off the single switch of before keeps
    /// ChatGPT and Claude off until they choose again.
    static func shows(_ chat: ChatTarget, in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: chat.offKey) != nil { return !defaults.bool(forKey: chat.offKey) }
        // The others wait to be chosen.
        if !chat.isStandard { return false }
        return chat.isAI ? !defaults.bool(forKey: "aiChatsOnPhotosOff") : true
    }

    static func setShows(_ on: Bool, _ chat: ChatTarget, in defaults: UserDefaults = .standard) {
        defaults.set(!on, forKey: chat.offKey)
    }

    private var offKey: String { "aiChatOff.\(rawValue)" }

    /// The ones turned on for photos, in their order. They show whether or
    /// not the app is on this Mac: the website is always there.
    @MainActor
    static var onPhotosNow: [ChatTarget] {
        ordered().filter { shows($0) }
    }

    /// How many are turned on.
    static func shownCount(in defaults: UserDefaults = .standard) -> Int {
        allCases.filter { shows($0, in: defaults) }.count
    }

    /// The chats under a photo, as its row shows them.
    struct Row: Equatable {
        /// Side by side, in their order.
        var shown: [ChatTarget]
        /// Behind the ⋯ at the row's end, when more are on than it holds.
        var more: [ChatTarget]

        /// The circles in the row, the ⋯ among them.
        var count: Int { shown.count + (more.isEmpty ? 0 : 1) }
    }

    /// As many as a row holds side by side; with more turned on, one fewer,
    /// and a ⋯ in the last place that holds the rest, so any number can be
    /// on and none is out of reach.
    static func row(_ chats: [ChatTarget], holds: Int = PhotoButtons.maxChats) -> Row {
        guard chats.count > holds else { return Row(shown: chats, more: []) }
        let side = max(holds - 1, 0)
        return Row(shown: Array(chats.prefix(side)), more: Array(chats.dropFirst(side)))
    }

    // MARK: Their order

    private static let orderKey = "chatOrder"

    /// In the order they were dragged into under Settings › Line › Icons
    /// under photos; at first, and for any the order does not name, as
    /// listed here.
    static func ordered(in defaults: UserDefaults = .standard) -> [ChatTarget] {
        order(from: defaults.stringArray(forKey: orderKey) ?? [])
    }

    /// The names kept read back: each known one once, then the rest.
    static func order(from names: [String]) -> [ChatTarget] {
        var order: [ChatTarget] = []
        for name in names {
            if let chat = ChatTarget(rawValue: name), !order.contains(chat) { order.append(chat) }
        }
        return order + allCases.filter { !order.contains($0) }
    }

    static func setOrder(_ order: [ChatTarget], in defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: orderKey)
    }

    /// One moved to where another stands, the rest closing up behind it.
    static func moving(_ chat: ChatTarget, to target: ChatTarget, in order: [ChatTarget]) -> [ChatTarget] {
        guard chat != target, let from = order.firstIndex(of: chat), let to = order.firstIndex(of: target) else {
            return order
        }
        var moved = order
        moved.remove(at: from)
        moved.insert(chat, at: to)
        return moved
    }

    // MARK: Where it opens

    /// From Settings › Line, for each: a click opens it in its app, when that
    /// is on this Mac, or else on its website in the browser. Until chosen,
    /// as the one choice for all of before said: the browser at first.
    func opensInApp(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: appKey) != nil { return defaults.bool(forKey: appKey) }
        return defaults.bool(forKey: "aiChatsOpenInApp")
    }

    func setOpensInApp(_ app: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(app, forKey: appKey)
    }

    private var appKey: String { "chatOpensInApp.\(rawValue)" }

    /// Whether a click opens its app now: chosen for it, and on this Mac.
    @MainActor
    var opensApp: Bool { opensInApp() && appURL != nil }

    /// From Settings › Line: the browser websites open in, by its bundle ID;
    /// nil for the one the Mac opens websites with.
    static var browserID: String? {
        get { UserDefaults.standard.string(forKey: "chatBrowser") }
        set { UserDefaults.standard.set(newValue, forKey: "chatBrowser") }
    }

    /// The browser a website opens in: the one chosen, while it is on this
    /// Mac, else the Mac's own choice.
    @MainActor
    static var browserURL: URL? {
        if let id = browserID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        return defaultBrowserURL
    }

    /// The browser the Mac opens websites with, not an app that claims a
    /// chat's address: the chat's own app may.
    @MainActor
    static var defaultBrowserURL: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.apple.com/")!)
    }

    /// A browser to choose in Settings.
    struct Browser: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
    }

    /// The browsers on this Mac that can say which page they show, by name,
    /// with the Mac's own choice among them even when it is another.
    @MainActor
    static var browsers: [Browser] {
        var ids = ChatButton.browserIDs
        if let url = defaultBrowserURL, let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id) { ids.append(id) }
        return ids.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map {
                Browser(id: id, name: appName($0), url: $0)
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name of the browser a website opens in, like "Safari".
    @MainActor
    static var browserName: String {
        browserURL.map(appName) ?? L("the browser")
    }

    /// An app's name as the Finder shows it, without ".app".
    static func appName(_ url: URL) -> String {
        (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
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

    /// A logo fills its circle as it is; an app icon keeps a margin round its
    /// shape, so it is drawn a little larger.
    @MainActor
    var iconScale: CGFloat { logo == nil ? 1.22 : 1 }

    /// Its logo, else the app's own icon, as the Finder and the Dock show
    /// it, wherever its app is on this Mac; nil without either, and the circle
    /// shows the mark instead.
    @MainActor
    var icon: NSImage? {
        if let logo { return logo }
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
        if !startsFresh, opensInApp(), let front, front == installedAppID { return ready() }
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
        if opensInApp(), let app = appURL {
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

    /// Opens a new chat on the website in the browser chosen, and waits for
    /// its page in front, where the browser says which page it shows.
    @MainActor
    private func openWebsite(then finish: @escaping (Bool) -> Void) {
        let chat = self
        let browserURL = Self.browserURL
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
