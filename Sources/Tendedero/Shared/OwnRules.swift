import Foundation

/// A rule of the owner's own, beside the kinds of private detail: a word to
/// cover wherever it appears, like a shop's name; a label whose value is
/// covered, like "Kundennummer"; or, for whoever knows them, a pattern. The
/// rules are kept with the app's settings and read on both the Mac and the
/// iPhone.
struct OwnRule: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        /// The text itself, wherever it appears, whole words only.
        case word
        /// What follows the text: the rest of its line, or the line below.
        case label
        /// A regular expression. Covered as a whole match.
        case pattern

        var title: String {
            switch self {
            case .word: L("Word")
            case .label: L("After a label")
            case .pattern: L("Pattern")
            }
        }

        /// What to type, shown in the empty field.
        var prompt: String {
            switch self {
            case .word: L("A word, like your shop’s name")
            case .label: L("A label, like Customer number")
            case .pattern: L("A pattern, like SKU-[0-9]+")
            }
        }
    }

    var id = UUID()
    var text = ""
    var kind = Kind.word

    /// Empty rules wait to be typed; they cover nothing.
    var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A pattern that cannot be read covers nothing, and the settings say so.
    var isReadable: Bool {
        guard kind == .pattern, !isBlank else { return true }
        return (try? NSRegularExpression(pattern: text, options: [.caseInsensitive])) != nil
    }
}

enum OwnRules {
    static let key = "ownRules"

    static var all: [OwnRule] {
        get { load() }
        set { save(newValue) }
    }

    static func load(from defaults: UserDefaults = .standard) -> [OwnRule] {
        guard let data = defaults.data(forKey: key),
              let rules = try? JSONDecoder().decode([OwnRule].self, from: data) else { return [] }
        return rules
    }

    static func save(_ rules: [OwnRule], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Posted when a rule is added outside Settings, like a word to cover
    /// always from Hide Part, so the photos are read again and Settings
    /// shows it.
    static let changed = Notification.Name("ownRulesChanged")

    /// A word to cover always, unless a rule for it is there already, in
    /// any case.
    static func add(word: String, to defaults: UserDefaults = .standard) {
        let text = word.trimmingCharacters(in: .whitespaces)
        var rules = load(from: defaults)
        guard !text.isEmpty, !rules.contains(where: {
            $0.kind == .word && $0.text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(text) == .orderedSame
        }) else { return }
        rules.append(OwnRule(text: text, kind: .word))
        save(rules, to: defaults)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Changes whenever a rule that covers something changes, so the copies
    /// covered under the old rules are drawn again.
    static var fingerprint: String {
        all.filter { !$0.isBlank }.map { "\($0.kind.rawValue):\($0.text)" }.joined(separator: "|")
    }
}
