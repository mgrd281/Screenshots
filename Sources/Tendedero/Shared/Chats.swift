import Foundation

/// Where a covered picture goes straight from Snapfly: ChatGPT, Claude,
/// WhatsApp, Gmail, GMX and WEB.DE, and more to choose in Settings:
/// Perplexity, Grok, DeepSeek, Qwen, Messenger, Instagram, Outlook, Yahoo
/// Mail, Facebook, Airbnb, Visual Studio Code and Antigravity. The Mac shows
/// them under each photo on the line (`ChatTarget.swift` there); the iPhone
/// under scanned pages and beside the picture in Protect Picture, all but
/// those whose iPhone app takes no picture from another app.
enum ChatTarget: String, CaseIterable, Identifiable {
    case chatGPT, claude, perplexity, grok, deepSeek, qwen, whatsApp, messenger, instagram, gmail, outlook, yahoo
    case gmx, webDe, facebook, airbnb, vsCode, antigravity

    /// The six that show until chosen otherwise; the others wait to be
    /// turned on in Settings.
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

    /// Its icon where no logo of it can be shown: a short mark in a neutral
    /// circle, in plain letters.
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

    /// Whether a website, with its subdomains, is this chat's.
    func owns(host: String?) -> Bool {
        guard var host = host?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Chosen

    /// Whether its icon shows, from Settings: on the Mac under a photo, on the
    /// iPhone after a scan and in Protect Picture. On unless turned off.
    /// Whoever turned off the Mac's single switch of before keeps ChatGPT and
    /// Claude off until they choose again.
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

    /// How many are turned on.
    static func shownCount(in defaults: UserDefaults = .standard) -> Int {
        allCases.filter { shows($0, in: defaults) }.count
    }

    // MARK: Their order

    private static let orderKey = "chatOrder"

    /// In the order they were dragged into in Settings; at first, and for any
    /// the order does not name, as listed here.
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

    // MARK: On the iPhone

    /// Whether it has a place on the iPhone: not Visual Studio Code and
    /// Antigravity, editors for a computer with no app there, nor Airbnb,
    /// whose app takes no picture from another.
    var onPhone: Bool {
        self != .vsCode && self != .antigravity && self != .airbnb
    }

    /// How a covered picture reaches its app on the iPhone, never through a
    /// website.
    enum PhoneHandoff: Equatable {
        /// Handed to the app itself, the one way it documents: WhatsApp
        /// opens one picture sent as a file only it takes (`.wai`).
        case direct
        /// The system's share sheet, where the app takes pictures and the
        /// owner taps it.
        case shareSheet
    }

    /// How these pictures reach it: WhatsApp takes one straight away; more
    /// than one, and every other app, through the share sheet.
    func phoneHandoff(pictures: Int) -> PhoneHandoff {
        self == .whatsApp && pictures == 1 ? .direct : .shareSheet
    }

    /// Those that can be chosen on the iPhone, in their order.
    static func phoneChoices(in defaults: UserDefaults = .standard) -> [ChatTarget] {
        ordered(in: defaults).filter(\.onPhone)
    }

    /// Those turned on for the iPhone, in their order.
    static func onPhoneNow(in defaults: UserDefaults = .standard) -> [ChatTarget] {
        phoneChoices(in: defaults).filter { shows($0, in: defaults) }
    }
}
