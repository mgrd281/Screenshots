import Foundation

/// A question kept ready to go with a photo into ChatGPT or Claude, like
/// "Summarize this in a few lines." It lands in the chat's message box
/// after the photo; nothing is sent until Return is pressed there.
struct AIQuestion: Codable, Hashable, Identifiable {
    var id = UUID()
    var text = ""

    /// Empty questions wait to be typed; they are not offered.
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum AIQuestions {
    static let key = "aiQuestions"

    /// The questions everyone starts with, in the user's language: a chat
    /// answers in the language it is asked in.
    static var standard: [AIQuestion] {
        [L("Summarize this in a few lines."), L("Translate this into my language."), L("What should I reply to this?"),
         L("What is wrong here, and how do I fix it?"), L("Explain this step by step.")].map { AIQuestion(text: $0) }
    }

    /// The questions as written in Settings, or the standard ones until
    /// they are changed there.
    static var all: [AIQuestion] {
        get { load() }
        set { save(newValue) }
    }

    /// Whether the questions were changed in Settings.
    static func isCustomised(in defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: key) != nil
    }

    static func load(from defaults: UserDefaults = .standard) -> [AIQuestion] {
        guard let data = defaults.data(forKey: key),
              let questions = try? JSONDecoder().decode([AIQuestion].self, from: data) else { return standard }
        return questions
    }

    static func save(_ questions: [AIQuestion], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(questions), forKey: key)
    }

    /// Back to the standard questions.
    static func restore(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The ones offered on a photo: written, not blank.
    static func offered(from defaults: UserDefaults = .standard) -> [AIQuestion] {
        load(from: defaults).filter { !$0.isBlank }
    }
}
