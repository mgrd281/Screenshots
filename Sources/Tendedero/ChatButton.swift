import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// A send button that floats over a chat while photos hang, just above the
/// chat's own send button, so they go in without a trip to the top of the
/// screen. It shows the newest photo and how many will go, and a click
/// sends them as the tag's send button does: the ones picked, or all.
///
/// It appears over chat apps and browsers only, and only while there is
/// something to send. It never takes focus, so the message box keeps the
/// keyboard. Dragged somewhere else, it stays there for that app.
@MainActor
final class ChatButton {
    static private(set) var shared: ChatButton?

    /// From Settings. On unless turned off.
    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "chatButtonOff") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "chatButtonOff")
            shared?.refresh()
        }
    }

    /// Where it sits, from Settings. Choosing again forgets where it was
    /// dragged, so the choice shows.
    static var placement: ChatButtonPlacement {
        get { ChatButtonPlacement(rawValue: UserDefaults.standard.string(forKey: "chatButtonPlacement") ?? "") ?? .sendButton }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "chatButtonPlacement")
            spots = [:]
            shared?.update()
        }
    }

    static var look: ChatButtonLook {
        get { ChatButtonLook(rawValue: UserDefaults.standard.string(forKey: "chatButtonLook") ?? "") ?? .full }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "chatButtonLook")
            shared?.model.look = newValue
        }
    }

    static var symbol: ChatButtonSymbol {
        get { ChatButtonSymbol(rawValue: UserDefaults.standard.string(forKey: "chatButtonSymbol") ?? "") ?? .paperplane }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "chatButtonSymbol")
            shared?.model.symbol = newValue
        }
    }

    static var tint: ChatButtonTint {
        get { ChatButtonTint(rawValue: UserDefaults.standard.string(forKey: "chatButtonTint") ?? "") ?? .accent }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "chatButtonTint")
            shared?.model.tint = newValue
        }
    }

    /// Opens Settings, from the button's menu.
    var openSettings: () -> Void = {}

    private let line: Line
    private let model = ChatButtonModel()
    private let panel: ChatButtonPanel
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// The app and window it sits over right now.
    private var current: (app: String, window: CGRect)?
    /// Where the message box is, read through Accessibility now and then.
    private var fieldFrame: CGRect?
    private var ticks = 0

    /// One chat app it shows over, which can be turned off without
    /// forgetting it.
    struct ChatApp: Codable, Hashable, Identifiable {
        var bundleID: String
        var on = true
        var id: String { bundleID }

        /// Where it is installed, if it is.
        var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

        /// The app's own name, as the Finder shows it.
        var name: String {
            guard let url else { return bundleID }
            return (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        }
    }

    /// Chat apps it knows from the start: ChatGPT, Claude, Perplexity,
    /// WhatsApp, Telegram, Messages, Slack, Discord, Signal, Teams,
    /// Messenger, LINE, Viber and Skype; and the mail apps, Mail and
    /// Outlook, where a photo goes into the message being written.
    static let standardApps = [
        "com.openai.chat", "com.anthropic.claudefordesktop", "ai.perplexity.mac",
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop",
        "com.apple.MobileSMS", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "org.whispersystems.signal-desktop", "com.microsoft.teams2", "com.microsoft.teams",
        "com.facebook.archon", "jp.naver.line.mac", "com.viber.osx", "com.skype.skype",
        "com.apple.mail", "com.microsoft.Outlook",
    ].map { ChatApp(bundleID: $0) }

    /// The chat apps, the standard ones first, then any added in Settings.
    /// Standard ones that came with a later version join a list already
    /// saved, once; one removed after that stays removed.
    static var apps: [ChatApp] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "chatButtonApps"),
                  let saved = try? JSONDecoder().decode([ChatApp].self, from: data) else { return standardApps }
            let offered = Set(UserDefaults.standard.stringArray(forKey: "chatButtonAppsOffered") ?? []).union(firstApps)
            let (list, now) = Self.joining(standardApps, to: saved, offered: offered, id: \.bundleID)
            if now != offered {
                UserDefaults.standard.set(Array(now).sorted(), forKey: "chatButtonAppsOffered")
                UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "chatButtonApps")
            }
            return list
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "chatButtonApps")
            // Saved now, every standard app has been offered.
            UserDefaults.standard.set(standardApps.map(\.bundleID).sorted(), forKey: "chatButtonAppsOffered")
            shared?.update()
        }
    }

    /// The standard apps and websites before mail joined them: a list saved
    /// back then has already offered them, kept or removed.
    private static let firstApps: Set<String> = Set(standardApps.prefix(17).map(\.bundleID))
    private static let firstSites: Set<String> = Set(standardSites.prefix(14).map(\.host))

    /// A saved list with the standard entries it has not offered yet added
    /// at the end, and what it has offered now. What was offered before and
    /// is missing was removed on purpose, and stays out.
    static func joining<T>(_ standard: [T], to saved: [T], offered: Set<String>,
                           id: (T) -> String) -> (list: [T], offered: Set<String>) {
        let have = Set(saved.map(id))
        let new = standard.filter { !offered.contains(id($0)) && !have.contains(id($0)) }
        return (saved + new, offered.union(standard.map(id)))
    }

    /// The browsers it can ask, for the Permissions pane.
    static var browserIDs: [String] { Array(browsers.keys) }

    /// Browsers that can say which page is open, and how to ask them.
    /// It shows there only on the chat websites from Settings.
    private static let browsers: [String: String] = [
        "com.apple.Safari": "URL of current tab of front window",
        "com.apple.SafariTechnologyPreview": "URL of current tab of front window",
        "com.google.Chrome": "URL of active tab of front window",
        "com.google.Chrome.canary": "URL of active tab of front window",
        "company.thebrowser.Browser": "URL of active tab of front window",
        "com.microsoft.edgemac": "URL of active tab of front window",
        "com.brave.Browser": "URL of active tab of front window",
        "com.vivaldi.Vivaldi": "URL of active tab of front window",
        "com.operasoftware.Opera": "URL of active tab of front window",
    ]

    /// In chat apps, from Settings. On unless turned off.
    static var inApps: Bool {
        get { !UserDefaults.standard.bool(forKey: "chatButtonAppsOff") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "chatButtonAppsOff")
            shared?.update()
        }
    }

    /// One chat website, which can be turned off without forgetting it.
    struct Site: Codable, Hashable, Identifiable {
        var host: String
        var on = true
        var id: String { host }
    }

    /// Chat websites it knows from the start, then webmail: Gmail, Outlook,
    /// Yahoo Mail, Telekom Mail, WEB.DE and GMX.
    static let standardSites = [
        "chatgpt.com", "claude.ai", "gemini.google.com", "web.whatsapp.com", "perplexity.ai",
        "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "chat.mistral.ai", "chat.qwen.ai",
        "web.telegram.org", "messenger.com", "discord.com", "app.slack.com", "teams.microsoft.com",
        "mail.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com",
        "mail.yahoo.com", "email.t-online.de", "web.de", "gmx.net", "gmx.de",
    ].map { Site(host: $0) }

    /// The chat websites, the standard ones first, then any added in Settings.
    /// New standard ones join a saved list once, as with the apps.
    static var sites: [Site] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "chatButtonSites"),
                  let saved = try? JSONDecoder().decode([Site].self, from: data) else { return standardSites }
            let offered = Set(UserDefaults.standard.stringArray(forKey: "chatButtonSitesOffered") ?? []).union(firstSites)
            let (list, now) = Self.joining(standardSites, to: saved, offered: offered, id: \.host)
            if now != offered {
                UserDefaults.standard.set(Array(now).sorted(), forKey: "chatButtonSitesOffered")
                UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "chatButtonSites")
            }
            return list
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "chatButtonSites")
            UserDefaults.standard.set(standardSites.map(\.host).sorted(), forKey: "chatButtonSitesOffered")
            shared?.update()
        }
    }

    /// A website as typed, like "https://www.example.com/chat", turned into
    /// its host, "example.com".
    static func host(from text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.contains("://") { text = "https://" + text }
        guard var host = URL(string: text)?.host, host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    init(line: Line) {
        self.line = line
        panel = ChatButtonPanel(model: model)
        Self.shared = self
        panel.content.onClick = { [weak self] in self?.send() }
        panel.content.onPrompt = { [weak self] index in self?.send(prompt: index) }
        panel.content.onLongPress = { [weak self] in self?.askForCaption() }
        panel.content.onDragEnd = { [weak self] in self?.remember() }
        panel.content.menu = makeMenu()

        line.$items.combineLatest(line.$pickedIDs)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.fieldFrame = nil
                self?.ticks = 0
                self?.update()
            }
            .store(in: &cancellables)
    }

    /// The photos a click sends: the ones picked, or all of them.
    private var toSend: [Pegged] {
        let live = line.items.filter { !$0.falling }
        let picked = live.filter { line.pickedIDs.contains($0.id) }
        return picked.isEmpty ? live : picked
    }

    /// Something still to send: picked photos, or one that isn't pinned.
    /// Pinned photos alone stay on the line on purpose and don't call for it.
    private var hasSomethingToSend: Bool {
        line.items.contains { !$0.falling && (!$0.pinned || line.pickedIDs.contains($0.id)) }
    }

    /// Follows the chat's window while there is something to send, and
    /// rests otherwise.
    func refresh() {
        let wanted = Self.isEnabled && hasSomethingToSend
        if wanted, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        } else if !wanted {
            timer?.invalidate()
            timer = nil
        }
        let photos = toSend
        model.count = photos.count
        model.thumbs = photos.suffix(2).map(\.thumb)
        update()
    }

    private func update() {
        // Being dragged: it goes where the pointer takes it.
        if panel.content.isDragging { return }
        // Not during a call: the photo on it is for no shared screen.
        guard timer != nil, Self.isEnabled, hasSomethingToSend, !Calls.shared.keepingAway,
              let app = Paste.frontApp, let id = app.bundleIdentifier,
              let front = Self.frontWindowSeen(of: app.processIdentifier) else {
            hide()
            return
        }
        let window = front.frame
        // The message box moves rarely; once a second is enough to follow it.
        let fresh = ticks % 5 == 0
        ticks += 1
        // Where it was dragged is kept per app, and per website in a browser,
        // apart for a new chat, whose message box sits higher.
        let key: String
        let layout: ChatLayout?
        let aiChat: Bool
        if let chat = Self.apps.first(where: { $0.bundleID == id }) {
            guard Self.inApps, chat.on else { return hide() }
            key = id
            layout = ChatLayouts.layout(forApp: id)
            aiChat = CoveringProfile.isAIChat(app: id, host: nil)
        } else if Self.browsers[id] != nil {
            // The browser is asked off the main thread, once a second and at
            // once when another window or tab comes to the front: switching
            // to another tab or site hides it within a moment, and a chat
            // just started moves it down.
            Self.seen(front.which, in: id)
            let read = Self.page(in: id, since: Date().addingTimeInterval(-Self.pageFresh))?.url
            guard let read, let host = read.host, let site = Self.site(for: host) else { return hide() }
            layout = ChatLayouts.layout(for: read)
            key = layout != nil && ChatLayouts.isNewChat(read) ? site + "#new" : site
            aiChat = CoveringProfile.isAIChat(app: nil, host: host)
        } else {
            return hide()
        }
        showsCoveringAll(aiChat && CoveringProfile.coversAllInAIChats)
        showsPrompts(aiChat && AIPrompts.showsBesideButton()
            ? AIPrompts.offered().enumerated().map { $1.name(number: $0 + 1) } : [])
        if fresh { fieldFrame = Self.messageBox(of: app.processIdentifier, in: window) }
        current = (key, window)
        place(over: window, app: key, layout: layout)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    /// The chat website a host belongs to, if it is one that is turned on:
    /// "chatgpt.com" covers "chatgpt.com" and "www.chatgpt.com".
    private static func site(for host: String) -> String? {
        let host = host.lowercased()
        return sites.first { $0.on && (host == $0.host || host.hasSuffix("." + $0.host)) }?.host
    }

    /// What a browser said its page in front was, and when it was asked.
    struct PageAnswer {
        /// Nil when it would not say, or Snapfly may not ask it.
        var url: URL?
        var asked: Date
    }

    /// The browsers' latest answers, and those being asked now.
    private static var answers: [String: PageAnswer] = [:]
    private static var asking: Set<String> = []
    /// Each browser's front window as last seen, and when it changed.
    private static var windows: [String: (which: String, changed: Date)] = [:]
    /// An answer this old still says which page is in front: the browser
    /// in front is asked again once a second.
    private static let pageFresh: TimeInterval = 2.5

    /// The browser's latest answer to which page it shows, asked for after
    /// `since`; nil until there is one. Once that answer is a second old it
    /// is asked again, through Apple Events and off the main thread, so a
    /// busy browser never holds Snapfly up and is asked once a second at
    /// most. macOS asks once whether Snapfly may; without it, the answer has
    /// no page, and the button stays away from the browser.
    static func page(in browser: String, since: Date) -> PageAnswer? {
        let latest = answers[browser]
        if latest.map({ Date().timeIntervalSince($0.asked) >= 1 }) ?? true { ask(browser) }
        guard let latest, latest.asked >= since else { return nil }
        return latest
    }

    /// Notes the browser's front window. Another window, or another title,
    /// as with another tab in front, has the browser asked again at once,
    /// a quarter of a second apart at most for a title that keeps changing.
    private static func seen(_ which: String, in browser: String) {
        guard windows[browser]?.which != which else { return }
        windows[browser] = (which, Date())
        if answers[browser].map({ Date().timeIntervalSince($0.asked) >= 0.25 }) ?? true { ask(browser) }
    }

    /// Asks the browser in the background, unless it is being asked already.
    private static func ask(_ browser: String) {
        guard let property = browsers[browser], !asking.contains(browser) else { return }
        asking.insert(browser)
        let asked = Date()
        PageReader.shared.ask(browser, property) { url in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ChatButton.asking.remove(browser)
                    if (ChatButton.answers[browser]?.asked ?? .distantPast) < asked {
                        ChatButton.answers[browser] = PageAnswer(url: url, asked: asked)
                    }
                }
            }
        }
    }

    /// The chat website the button sits over in the browser in front, like
    /// "chatgpt.com"; nil over an app, or with no button showing.
    var siteInFront: String? {
        guard let key = current?.app, let id = Paste.frontApp?.bundleIdentifier, Self.browsers[id] != nil else { return nil }
        return key.hasSuffix("#new") ? String(key.dropLast(4)) : key
    }

    /// The page open in the browser in front, for the time stamp and what
    /// is sent: its latest answer while fresh and asked since its window
    /// last changed, else asked now, waiting a second at most.
    static func pageInFront() -> URL? {
        guard let id = Paste.frontApp?.bundleIdentifier, let property = browsers[id] else { return nil }
        if let latest = answers[id], Date().timeIntervalSince(latest.asked) < pageFresh,
           latest.asked >= windows[id]?.changed ?? .distantPast {
            return latest.url
        }
        let asked = Date()
        let url = PageReader.shared.read(id, property)
        answers[id] = PageAnswer(url: url, asked: asked)
        return url
    }

    private func hide() {
        current = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Over an AI chat with Cover Everything there on, a lock by the count,
    /// and a word on it for the tip and VoiceOver.
    private func showsCoveringAll(_ all: Bool) {
        guard model.coversAll != all else { return }
        model.coversAll = all
        panel.content.coversAll = all
    }

    /// Over an AI chat, the prompts' numbers before the photos, each
    /// sending them with its prompt after; elsewhere none.
    private func showsPrompts(_ names: [String]) {
        guard model.prompts != names else { return }
        model.prompts = names
        model.hoveredPrompt = nil
        panel.content.promptNames = names
        panel.content.menu = makeMenu()
    }

    // MARK: Where it sits

    /// A spot is where the button's bottom trailing corner sits, measured
    /// from the window's bottom edge and from its trailing edge or middle,
    /// whichever it was dropped nearer: a send button at the window's edge,
    /// as in WhatsApp, or under a centered message box, as in ChatGPT.
    private struct Spot: Codable {
        var fromTrailing: Bool
        var dx: CGFloat
        var dy: CGFloat
    }

    private static let spotsKey = "chatButtonSpots"

    private static var spots: [String: Spot] {
        get {
            guard let data = UserDefaults.standard.data(forKey: spotsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Spot].self, from: data)) ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: spotsKey) }
    }

    private func place(over window: CGRect, app: String, layout: ChatLayout?) {
        let size = panel.frame.size
        let margin = ChatButtonPanel.margin
        var corner: CGPoint
        let inner = size.width - 2 * margin
        let height = size.height - 2 * margin
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(window) })
        let placement = Self.placement
        if let spot = Self.spots[app] {
            corner = CGPoint(x: (spot.fromTrailing ? window.maxX : window.midX) + spot.dx, y: window.minY + spot.dy)
        } else {
            switch placement {
            case .sendButton:
                if let field = fieldFrame {
                    // Just above the message box, at its trailing end, where
                    // chats keep their send button.
                    corner = CGPoint(x: field.maxX, y: field.maxY + 10)
                } else if let layout {
                    // A chat it knows: where its send button is, measured.
                    corner = layout.corner(in: window)
                } else {
                    // Above where a chat's send button usually is: the trailing
                    // end of a message box centered at the bottom, or the
                    // window's edge.
                    corner = CGPoint(x: window.midX + min(window.width / 2 - 24, 380), y: window.minY + 84)
                }
            case .windowCorner:
                corner = CGPoint(x: window.maxX - 16, y: window.minY + 16)
            case .windowTop:
                // Under the title bar and toolbar.
                corner = CGPoint(x: window.maxX - 16, y: window.maxY - 96 - height)
            case .screenEdge:
                let visible = screen?.visibleFrame ?? window
                corner = CGPoint(x: visible.maxX - 8, y: visible.midY - height / 2)
            }
        }
        // Kept inside the window, or the screen for the screen's edge.
        var bounds = placement == .screenEdge && Self.spots[app] == nil ? .infinite : window.insetBy(dx: 8, dy: 8)
        if let screen {
            bounds = bounds.intersection(screen.visibleFrame.insetBy(dx: 4, dy: 4))
        }
        guard !bounds.isNull, bounds.width > inner, bounds.height > height else { return }
        corner.x = min(max(corner.x, bounds.minX + inner), bounds.maxX)
        corner.y = min(max(corner.y, bounds.minY), bounds.maxY - height)
        panel.setFrameOrigin(CGPoint(x: corner.x - inner - margin, y: corner.y - margin))
    }

    /// Dropped after a drag: that is its place over this app from now on.
    private func remember() {
        guard let current else { return }
        let (app, window) = (current.app, current.window)
        let margin = ChatButtonPanel.margin
        let corner = CGPoint(x: panel.frame.maxX - margin, y: panel.frame.minY + margin)
        let fromTrailing = window.maxX - corner.x < window.width / 4
        let dx = corner.x - (fromTrailing ? window.maxX : window.midX)
        Self.spots[app] = Spot(fromTrailing: fromTrailing, dx: dx, dy: corner.y - window.minY)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(L("Send with a Message…")) { [weak self] in self?.askForCaption() })
        for (index, name) in model.prompts.enumerated() {
            menu.addItem(ClosureMenuItem(String(format: L("Send with “%@”"), name), symbol: "\(index + 1).circle") {
                [weak self] in self?.send(prompt: index)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Put it back")) { [weak self] in
            guard let self, let app = self.current?.app else { return }
            Self.spots[app] = nil
            self.update()
        })
        menu.addItem(ClosureMenuItem(L("Settings…")) { [weak self] in self?.openSettings() })
        return menu
    }

    // MARK: Sending

    /// The capsule while it shows, in screen coordinates, for a card that
    /// belongs to it, like Check Before Sending.
    var capsuleFrame: CGRect? {
        guard panel.isVisible else { return nil }
        let margin = ChatButtonPanel.margin
        return panel.frame.insetBy(dx: margin, dy: margin)
    }

    private func send() {
        let count = toSend.count
        // Waiting on Check Before Sending, it hasn't gone yet.
        guard count > 0, line.paste() else { return }
        showSent()
    }

    /// One of the numbers over an AI chat: the photos, then that prompt
    /// in the message box, as one message waiting for Return.
    private func send(prompt index: Int) {
        let prompts = AIPrompts.offered()
        guard prompts.indices.contains(index), !toSend.isEmpty, line.paste(caption: prompts[index].text) else { return }
        showSent()
    }

    /// When sent photos stay on the line, a check says it went.
    private func showSent() {
        model.sent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.model.sent = false
        }
    }

    /// A press and hold: a line to write a message in, sent after the
    /// photos as one message.
    private func askForCaption() {
        let count = toSend.count
        guard count > 0 else { return }
        let margin = ChatButtonPanel.margin
        CaptionBar.shared.show(above: panel.frame.insetBy(dx: margin, dy: margin), count: count,
                               photo: toSend.last(where: \.isImage)?.url) { [weak self] text in
            guard self?.line.paste(caption: text) == true else { return }
            self?.showSent()
        }
    }

    // MARK: The chat

    /// The app's frontmost ordinary window, from the window server, which
    /// needs no permission and works in the sandbox too.
    static func frontWindow(of pid: pid_t) -> CGRect? {
        frontWindowSeen(of: pid)?.frame
    }

    /// The same, with what tells it from another: its number, and its title
    /// where macOS lets Snapfly read it, which changes with the tab in front.
    private static func frontWindowSeen(of pid: pid_t) -> (frame: CGRect, which: String)? {
        guard let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  b.width > 300, b.height > 200 else { continue }
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            return (CGRect(x: b.minX, y: main.frame.maxY - b.maxY, width: b.width, height: b.height),
                    "\(number) \(title)")
        }
        return nil
    }

    /// The text field being typed in, when Accessibility may say so and it
    /// sits in the lower half of the window, as a message box does. The
    /// store edition cannot ask, and uses the usual spot instead.
    private static func messageBox(of pid: pid_t, in window: CGRect) -> CGRect? {
        guard !Edition.appStore, AXIsProcessTrusted(), let main = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // A busy app must not hold up the main thread.
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let field = value as! AXUIElement
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &role)
        guard let role = role as? String, [kAXTextAreaRole, kAXTextFieldRole].contains(role) else { return nil }
        var position: CFTypeRef?
        var size: CFTypeRef?
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXUIElementCopyAttributeValue(field, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(field, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 40, extent.height < 300 else { return nil }
        let frame = CGRect(x: point.x, y: main.frame.maxY - point.y - extent.height,
                           width: extent.width, height: extent.height)
        guard window.contains(CGPoint(x: frame.midX, y: frame.midY)), frame.midY < window.midY else { return nil }
        return frame
    }
}

/// Asks a browser which page it shows, through Apple Events: one question
/// at a time, each waiting a second at most, on a queue of its own, or
/// where it is asked when the answer cannot wait.
private final class PageReader: @unchecked Sendable {
    static let shared = PageReader()

    private let queue = DispatchQueue(label: "de.ghazarian.Snapfly.page", qos: .userInitiated)
    /// One question at a time, from the queue or from the main thread.
    private let lock = NSLock()
    /// Made once for each browser, and used under the lock alone.
    private var scripts: [String: NSAppleScript] = [:]

    /// Asks in the background; the answer comes on the queue.
    func ask(_ browser: String, _ property: String, then done: @escaping @Sendable (URL?) -> Void) {
        queue.async { done(self.read(browser, property)) }
    }

    /// Asks and waits for the answer: nil when the browser would not say,
    /// was busy, or Snapfly may not ask it.
    func read(_ browser: String, _ property: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let script: NSAppleScript
        if let cached = scripts[browser] {
            script = cached
        } else {
            let source = """
            with timeout of 1 second
                tell application id "\(browser)" to return \(property)
            end timeout
            """
            guard let made = NSAppleScript(source: source) else { return nil }
            scripts[browser] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue, let url = URL(string: text), url.host != nil
        else { return nil }
        return url
    }
}

/// What the button shows.
@MainActor
final class ChatButtonModel: ObservableObject {
    @Published var count = 0
    @Published var thumbs: [NSImage] = []
    @Published var sent = false
    /// Over an AI chat, with every kind covered there.
    @Published var coversAll = false
    @Published var look = ChatButton.look
    @Published var symbol = ChatButton.symbol
    @Published var tint = ChatButton.tint
    /// Over an AI chat: the prompts' names, numbered from 1 before the photos.
    @Published var prompts: [String] = []
    /// The number under the pointer, which opens to show its name.
    @Published var hoveredPrompt: Int?
    /// Where each number and the capsule sit in the label, from its top
    /// left, for the clicks the panel takes itself.
    var promptFrames: [Int: CGRect] = [:]
    var capsuleFrame: CGRect = .zero
    /// The label's whole size as SwiftUI lays it out, which the panel follows.
    let sizeChanged = PassthroughSubject<CGSize, Never>()
}

/// Where the send button over a chat sits.
enum ChatButtonPlacement: String, CaseIterable, Identifiable {
    /// Just above the chat's own send button.
    case sendButton
    /// In the bottom trailing corner of the chat's window.
    case windowCorner
    /// In the top trailing corner, under the toolbar.
    case windowTop
    /// On the trailing edge of the screen, halfway down.
    case screenEdge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sendButton: L("Above the chat's send button")
        case .windowCorner: L("Bottom corner of the window")
        case .windowTop: L("Top corner of the window")
        case .screenEdge: L("Edge of the screen")
        }
    }
}

/// The capsule with the newest photo and the count, or the icon alone.
enum ChatButtonLook: String, CaseIterable, Identifiable {
    case full, compact
    var id: String { rawValue }
}

/// The glyph on the button.
enum ChatButtonSymbol: String, CaseIterable, Identifiable {
    case paperplane = "paperplane.fill"
    case arrow = "arrow.up"
    case share = "square.and.arrow.up"
    case photos = "photo.on.rectangle.angled"

    var id: String { rawValue }

    /// Spoken, and shown when the pointer rests on it in Settings.
    var name: String {
        switch self {
        case .paperplane: L("Paper plane")
        case .arrow: L("Arrow")
        case .share: L("Share")
        case .photos: L("Photos")
        }
    }
}

/// The color of the button's circle. System colors only, so each holds up
/// in light and dark; the accent follows System Settings.
enum ChatButtonTint: String, CaseIterable, Identifiable {
    case accent, blue, green, purple, orange, pink, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .accent: .accentColor
        case .blue: Color(nsColor: .systemBlue)
        case .green: Color(nsColor: .systemGreen)
        case .purple: Color(nsColor: .systemPurple)
        case .orange: Color(nsColor: .systemOrange)
        case .pink: Color(nsColor: .systemPink)
        case .graphite: Color(nsColor: .labelColor)
        }
    }

    /// White on the colors; on graphite, the window's own background, so
    /// it reads in light and dark.
    var glyph: Color {
        self == .graphite ? Color(nsColor: .windowBackgroundColor) : .white
    }

    var name: String {
        switch self {
        case .accent: L("System accent")
        case .blue: L("Blue")
        case .green: L("Green")
        case .purple: L("Purple")
        case .orange: L("Orange")
        case .pink: L("Pink")
        case .graphite: L("Graphite")
        }
    }
}

/// A small floating panel that never becomes key, so the chat keeps the
/// keyboard and ⌘V lands in its message box.
private final class ChatButtonPanel: NSPanel {
    /// Room around the capsule for its shadow.
    static let margin: CGFloat = 16

    let content: ChatButtonView

    init(model: ChatButtonModel) {
        content = ChatButtonView(model: model, margin: Self.margin)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = content
        content.onResize = { [weak self] size in
            guard let self, self.frame.size != size else { return }
            let corner = CGPoint(x: self.frame.maxX, y: self.frame.minY)
            self.setFrame(CGRect(x: corner.x - size.width, y: corner.y, width: size.width, height: size.height),
                          display: true)
        }
        content.layoutSubtreeIfNeeded()
        setContentSize(content.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the clicks and drags itself, through AppKit, as the tag does: the
/// panel never becomes key, so only a view of its own takes the first click.
private final class ChatButtonView: NSView {
    var onClick: () -> Void = {}
    /// One of the prompts' numbers, from 0.
    var onPrompt: (Int) -> Void = { _ in }
    var onLongPress: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onResize: (CGSize) -> Void = { _ in }
    private(set) var isDragging = false
    /// Over an AI chat with every kind covered there: the tip says so, and
    /// VoiceOver too.
    var coversAll = false {
        didSet {
            let note = coversAll ? L("Everything is covered in AI chats") : nil
            toolTip = ([L("Paste into the app in front")] + [note].compactMap { $0 }).joined(separator: "\n")
            setAccessibilityValue(note)
        }
    }
    /// Held without moving: a press and hold rather than a click.
    private var hold: Timer?
    private var held = false

    private let host: NSHostingView<ChatButtonLabel>
    private let model: ChatButtonModel
    private let margin: CGFloat
    private var downAt: CGPoint?
    private var startOrigin: CGPoint?
    private var sizeWatch: AnyCancellable?

    init(model: ChatButtonModel, margin: CGFloat) {
        self.model = model
        self.margin = margin
        host = NSHostingView(rootView: ChatButtonLabel(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            host.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("Paste into the app in front"))
        promptNames = []
        toolTip = L("Paste into the app in front")
        // The panel grows and shrinks with the label: the numbers above the
        // capsule, and a number opening into its name.
        sizeWatch = model.sizeChanged.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] size in
            guard let self, size.width > 0 else { return }
            self.onResize(CGSize(width: size.width + 2 * self.margin, height: size.height + 2 * self.margin))
        }
    }

    /// The prompts over an AI chat, each an action for VoiceOver too.
    var promptNames: [String] = [] {
        didSet {
            let message = NSAccessibilityCustomAction(name: L("Send with a Message…")) { [weak self] in
                self?.onLongPress()
                return true
            }
            let prompts = promptNames.enumerated().map { index, name in
                NSAccessibilityCustomAction(name: String(format: L("Send with “%@”"), name)) { [weak self] in
                    self?.onPrompt(index)
                    return true
                }
            }
            setAccessibilityCustomActions([message] + prompts)
        }
    }

    /// A point in the window, as the label measures it: from its top left.
    private func inLabel(_ windowPoint: NSPoint) -> CGPoint {
        let point = host.convert(windowPoint, from: nil)
        return CGPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y)
    }

    /// The number under a click, if it was on one.
    private func prompt(at event: NSEvent) -> Int? {
        let point = inLabel(event.locationInWindow)
        return model.promptFrames.first { $0.value.contains(point) }?.key
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = CGSize(width: host.intrinsicContentSize.width + 2 * margin,
                          height: host.intrinsicContentSize.height + 2 * margin)
        if size.width > 2 * margin { onResize(size) }
    }

    /// Only the capsule and the numbers take the pointer; the shadow's
    /// margin and the room beside the numbers let it through to the chat.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard host.frame.contains(local) else { return nil }
        // Before the label has measured itself, the capsule fills it.
        if model.capsuleFrame.isEmpty { return self }
        let inside = inLabel(convert(local, to: nil))
        let parts = [model.capsuleFrame] + Array(model.promptFrames.values)
        return parts.contains { $0.insetBy(dx: -2, dy: -2).contains(inside) } ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
        isDragging = false
        held = false
        hold?.invalidate()
        hold = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isDragging, self.downAt != nil else { return }
                self.held = true
                self.onLongPress()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !held, let downAt, let startOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - downAt.x, dy = now.y - downAt.y
        if !isDragging, hypot(dx, dy) < 4 { return }
        isDragging = true
        hold?.invalidate()
        window.setFrameOrigin(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            downAt = nil
            startOrigin = nil
            isDragging = false
            held = false
            hold?.invalidate()
            hold = nil
        }
        if held {
            return
        } else if isDragging {
            onDragEnd()
        } else if downAt != nil {
            if let index = prompt(at: event) {
                onPrompt(index)
            } else if model.capsuleFrame.isEmpty || model.capsuleFrame.contains(inLabel(event.locationInWindow)) {
                onClick()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// The newest photo, how many go, and the glyph on its color; or the
/// glyph alone with the count beside it. Settings shows it as a preview.
struct ChatButtonLabel: View {
    @ObservedObject var model: ChatButtonModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// Over an AI chat the numbers stand in their own glass above the
    /// capsule, at its trailing edge, so the capsule keeps its size and its
    /// place over the chat.
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !model.prompts.isEmpty {
                prompts
                    .transition(.opacity)
            }
            capsule
        }
        .animation(Motion.spring(response: 0.3, damping: 0.85, reduced: reduceMotion), value: model.hoveredPrompt)
        .animation(.easeOut(duration: 0.2), value: model.prompts)
        .fixedSize()
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LabelSize.self, value: geometry.size)
        })
        .coordinateSpace(.named(Self.space))
        .onPreferenceChange(PromptFrames.self) { frames in model.promptFrames = frames }
        .onPreferenceChange(CapsuleFrame.self) { frame in model.capsuleFrame = frame }
        .onPreferenceChange(LabelSize.self) { size in model.sizeChanged.send(size) }
        .accessibilityHidden(true)
    }

    private var capsule: some View {
        Group {
            switch model.look {
            case .full: full
            case .compact: compact
            }
        }
        .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.spring(response: 0.3, damping: 0.8, reduced: reduceMotion), value: hovering)
        .animation(.easeOut(duration: 0.15), value: model.sent)
        .animation(.easeOut(duration: 0.2), value: model.coversAll)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: CapsuleFrame.self, value: geometry.frame(in: .named(Self.space)))
        })
    }

    private static let space = "chatButton"

    /// Over an AI chat, the prompts' numbers in a glass capsule of their own.
    private var prompts: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.prompts.enumerated()), id: \.offset) { index, name in
                PromptNumber(number: index + 1, name: name, open: model.hoveredPrompt == index)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: PromptFrames.self,
                                               value: [index: geometry.frame(in: .named(Self.space))])
                    })
                    .onHover { inside in
                        if inside {
                            model.hoveredPrompt = index
                        } else if model.hoveredPrompt == index {
                            model.hoveredPrompt = nil
                        }
                    }
            }
        }
        .padding(4)
        .controlGlass(capsule: true)
    }

    private var full: some View {
        HStack(spacing: 8) {
            ZStack {
                if model.thumbs.isEmpty {
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                ForEach(Array(model.thumbs.enumerated()), id: \.offset) { index, image in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        // The one behind leans away, like a small stack.
                        .rotationEffect(.degrees(index == model.thumbs.count - 1 ? 0 : -8))
                        .offset(x: index == model.thumbs.count - 1 ? 0 : -3)
                }
            }
            .frame(width: 28, height: 28)
            count
            glyph(size: 28)
        }
        .padding(4)
        .padding(.leading, 2)
        .controlGlass(capsule: true)
    }

    private var compact: some View {
        HStack(spacing: 6) {
            count
            glyph(size: 30)
        }
        .padding(4)
        .padding(.leading, 6)
        .controlGlass(capsule: true)
    }

    /// The count, led by a lock over an AI chat where every kind is covered.
    private var count: some View {
        HStack(spacing: 3) {
            if model.coversAll {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Text(verbatim: "\(model.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func glyph(size: CGFloat) -> some View {
        Image(systemName: model.sent ? "checkmark" : model.symbol.rawValue)
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(model.tint.glyph)
            .frame(width: size, height: size)
            .background(model.tint.color, in: Circle())
            .contentTransition(.symbolEffect(.replace))
    }
}

/// One prompt's number beside the send button: a small round chip that
/// opens into a capsule with the prompt's name while the pointer is on it.
private struct PromptNumber: View {
    let number: Int
    let name: String
    let open: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "\(number)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if open {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, open ? 9 : 0)
        .frame(minWidth: 24, minHeight: 24)
        .background(Color.primary.opacity(open ? 0.14 : 0.07), in: Capsule())
        .contentShape(Capsule())
    }
}

/// Where each prompt's number sits, for the clicks the panel takes itself.
private struct PromptFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where the capsule sits in the label, for the clicks.
private struct CapsuleFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// The label's whole size, for the panel around it.
private struct LabelSize: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
