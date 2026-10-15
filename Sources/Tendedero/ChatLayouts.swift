import Foundation

/// Where the chat button sits, by itself, over the chats Snapfly knows: just
/// above their own send button. On a new, empty chat the message box of
/// ChatGPT, Claude and the like sits in the middle of the page, with
/// suggestions under it; once a chat has started it moves to the bottom.
/// In a browser the page's address tells the two apart.
///
/// These are measured on the chats as they look today and ship with the
/// app. Where the user has dragged the button, that always wins; where
/// Accessibility can say where the message box is, that does too.
struct ChatLayout: Equatable {
    /// Where the button's trailing edge goes across the window.
    enum Across: Equatable {
        /// This far in from the window's trailing edge, where chats like
        /// WhatsApp keep their send button.
        case trailing(CGFloat)
        /// At the trailing end of a message box at most this wide, centered
        /// in what the sidebar leaves of a window wide enough to show one.
        case centered(width: CGFloat, sidebar: CGFloat)
    }

    /// Where the button's bottom edge goes up the window.
    enum Up: Equatable {
        /// This far above the window's bottom edge.
        case bottom(CGFloat)
        /// This far above the middle of the page, under the browser's or
        /// the app's own bar.
        case middle(CGFloat)
    }

    let across: Across
    let up: Up
    /// The height of the bar above the page: tabs and address in a browser,
    /// the title bar in an app.
    var bar: CGFloat = 88

    /// The button's bottom trailing corner, in the same coordinates as the
    /// window, which counts from the bottom.
    func corner(in window: CGRect) -> CGPoint {
        let x: CGFloat
        switch across {
        case let .trailing(inset):
            x = window.maxX - inset
        case let .centered(width, sidebar):
            // Chats fold their sidebar away in narrow windows.
            let left = window.minX + (window.width >= 900 ? sidebar : 0)
            let room = window.maxX - left
            let box = min(width, room - 32)
            x = left + (room + box) / 2
        }
        let y: CGFloat
        switch up {
        case let .bottom(rise):
            y = window.minY + rise
        case let .middle(rise):
            y = window.minY + (window.height - bar) / 2 + rise
        }
        return CGPoint(x: x, y: y)
    }
}

enum ChatLayouts {
    /// The layout of a chat website, by its address, if Snapfly knows it.
    static func layout(for url: URL) -> ChatLayout? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let new = isNewChat(url)
        switch host {
        case "chatgpt.com", "chat.openai.com":
            return ChatLayout(across: .centered(width: 768, sidebar: 260),
                              up: new ? .middle(40) : .bottom(104))
        case "claude.ai":
            return ChatLayout(across: .centered(width: 768, sidebar: 288),
                              up: new ? .middle(66) : .bottom(140))
        case "gemini.google.com":
            return ChatLayout(across: .centered(width: 760, sidebar: 72),
                              up: new ? .middle(64) : .bottom(132))
        case "perplexity.ai":
            return ChatLayout(across: .centered(width: 720, sidebar: 72),
                              up: new ? .middle(60) : .bottom(112))
        case "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "chat.mistral.ai":
            return ChatLayout(across: .centered(width: 768, sidebar: 0),
                              up: new ? .middle(60) : .bottom(112))
        case "web.whatsapp.com":
            return ChatLayout(across: .trailing(14), up: .bottom(72))
        case "web.telegram.org", "messenger.com":
            return ChatLayout(across: .trailing(16), up: .bottom(66))
        case "discord.com":
            return ChatLayout(across: .trailing(24), up: .bottom(84))
        case "app.slack.com", "teams.microsoft.com":
            return ChatLayout(across: .trailing(28), up: .bottom(124))
        default:
            return nil
        }
    }

    /// The layout of a chat app, by its bundle identifier. An app's address
    /// cannot be read, so it is the layout of a chat already going.
    static func layout(forApp id: String) -> ChatLayout? {
        let bar: CGFloat = 52
        switch id {
        case "com.openai.chat":
            return ChatLayout(across: .centered(width: 720, sidebar: 0), up: .bottom(96), bar: bar)
        case "com.anthropic.claudefordesktop":
            return ChatLayout(across: .centered(width: 768, sidebar: 0), up: .bottom(140), bar: bar)
        case "ai.perplexity.mac":
            return ChatLayout(across: .centered(width: 720, sidebar: 0), up: .bottom(112), bar: bar)
        case "net.whatsapp.WhatsApp", "desktop.WhatsApp":
            return ChatLayout(across: .trailing(14), up: .bottom(70), bar: bar)
        case "com.apple.MobileSMS":
            return ChatLayout(across: .trailing(18), up: .bottom(52), bar: bar)
        case "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams":
            return ChatLayout(across: .trailing(28), up: .bottom(124), bar: bar)
        case "com.hnc.Discord":
            return ChatLayout(across: .trailing(24), up: .bottom(84), bar: bar)
        case "ru.keepcoder.Telegram", "org.telegram.desktop", "org.whispersystems.signal-desktop",
             "com.facebook.archon", "jp.naver.line.mac", "com.viber.osx", "com.skype.skype":
            return ChatLayout(across: .trailing(16), up: .bottom(64), bar: bar)
        default:
            return nil
        }
    }

    /// A chat not started yet, with its message box in the middle of the
    /// page: chatgpt.com/ rather than chatgpt.com/c/…, claude.ai/new rather
    /// than claude.ai/chat/…, gemini.google.com/app rather than /app/….
    static func isNewChat(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let parts = path.split(separator: "/").map(String.init)
        guard var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        switch host {
        case "chatgpt.com", "chat.openai.com":
            // GPTs and projects have chats under /c/ too.
            return !parts.contains("c")
        case "claude.ai":
            return parts.isEmpty || parts == ["new"] || parts.first == "project"
        case "gemini.google.com":
            return parts.isEmpty || parts == ["app"] || parts.first == "gem" && parts.count <= 2
        default:
            return parts.isEmpty || parts == ["new"]
        }
    }
}
