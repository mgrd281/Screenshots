import Foundation

/// A screenshot going to an AI chat the moment it hangs, when Settings,
/// under Line, names one. It is pasted into the message box, covered as in
/// any AI chat and after the check before sending, and waits for Return:
/// nothing is sent to the chat until you press it.
enum CaptureToChat {
    /// Where the chat opens when the one in front is not it.
    enum Place: String, CaseIterable, Identifiable {
        /// Into the chat of that site in front, else a new one.
        case inFront
        /// A new chat each time, whatever is in front.
        case new

        var id: String { rawValue }
    }

    private static let chatKey = "captureChat"
    private static let placeKey = "captureChatPlace"

    /// The AI chat each screenshot goes to; nil is none, as it begins.
    static var chat: ChatTarget? {
        get { UserDefaults.standard.string(forKey: chatKey).flatMap(ChatTarget.init(rawValue:)).flatMap { $0.isAI ? $0 : nil } }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: chatKey) }
    }

    static var place: Place {
        get { UserDefaults.standard.string(forKey: placeKey).flatMap(Place.init(rawValue:)) ?? .inFront }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: placeKey) }
    }

    /// The AI chats to choose from, in their usual order.
    static var choices: [ChatTarget] { ChatTarget.allCases.filter(\.isAI) }
}
