import AppKit

/// Cover Everything in AI Chats, from Settings › Privacy: what is sent or
/// copied while an AI chat is in front, like ChatGPT or Claude, has every
/// kind of detail covered, whatever is checked. What is typed there may be
/// kept and read on the chat's servers, so it is the one place Snapfly can
/// cover more on its own. It only ever covers more than Settings, never less.
@MainActor
enum CoveringProfile {
    /// Off unless turned on.
    nonisolated static var coversAllInAIChats: Bool {
        get { UserDefaults.standard.bool(forKey: "coverAllInAIChats") }
        set { UserDefaults.standard.set(newValue, forKey: "coverAllInAIChats") }
    }

    /// Every kind there is, as covered in AI chats.
    nonisolated static let everything = Set(PrivateDetail.allCases)

    /// The AI chat apps: ChatGPT, Claude and Perplexity.
    nonisolated static let aiApps: Set<String> = ["com.openai.chat", "com.anthropic.claudefordesktop", "ai.perplexity.mac"]

    /// The AI chat websites, each with its subdomains.
    nonisolated static let aiSites = [
        "chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "perplexity.ai",
        "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "chat.mistral.ai",
    ]

    /// Whether an app, or a website open in a browser, is an AI chat.
    nonisolated static func isAIChat(app: String?, host: String?) -> Bool {
        if let app, aiApps.contains(app) { return true }
        guard var host = host?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return aiSites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// What to cover where something goes: what is checked, or every kind in
    /// an AI chat with Cover Everything on.
    nonisolated static func details(_ chosen: Set<PrivateDetail>, inAIChat: Bool, coversAll: Bool) -> Set<PrivateDetail> {
        inAIChat && coversAll ? chosen.union(everything) : chosen
    }

    /// Whether an AI chat is in front: its app, or its website in a browser,
    /// as the send button over chats knows it, else asked of the browser.
    static var aiChatInFront: Bool {
        guard let app = Paste.frontApp?.bundleIdentifier else { return false }
        if aiApps.contains(app) { return true }
        let host = ChatButton.shared?.siteInFront ?? ChatButton.pageInFront()?.host
        return isAIChat(app: nil, host: host)
    }

    /// What to cover in what is sent or copied now, for the app in front.
    static var detailsNow: Set<PrivateDetail> {
        let chosen = PrivateDetails.details
        // Asking a browser for its page takes a moment: only when it counts.
        guard coversAllInAIChats, chosen != everything else { return chosen }
        return details(chosen, inAIChat: aiChatInFront, coversAll: true)
    }
}
