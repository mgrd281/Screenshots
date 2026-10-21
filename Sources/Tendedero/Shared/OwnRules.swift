import Foundation
#if canImport(Security)
import Security
#endif

/// A rule of the owner's own, beside the kinds of private detail: a word to
/// cover wherever it appears, like a shop's name; a label whose value is
/// covered, like "Kundennummer"; or, for whoever knows them, a pattern. A
/// rule can be turned off and on again. Or one of the owner's own details,
/// looked for in the ways it is written and covered whatever kinds are
/// chosen: their name, their address, a bank card or a bank account
/// (`OwnDetails`). The rules are kept with the app's settings, the details
/// in the keychain, on this device alone; both are read on the Mac and the
/// iPhone.
struct OwnRule: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        /// The text itself, wherever it appears, whole words only.
        case word
        /// What follows the text: the rest of its line, or the line below.
        case label
        /// A regular expression. Covered as a whole match.
        case pattern
        /// The owner's name, in every way it is written.
        case name
        /// The owner's street with its house number, and postcode with town.
        case address
        /// A bank card's number, whole or by its last four digits.
        case card
        /// A bank account's IBAN, and a German or Austrian account's number.
        case account

        /// The rules typed as text, under the owner's details.
        static let rules: [Kind] = [.word, .label, .pattern]
        /// The owner's own details.
        static let details: [Kind] = [.name, .address, .card, .account]

        var isDetail: Bool { Self.details.contains(self) }

        var title: String {
            switch self {
            case .word: L("Word")
            case .label: L("After a label")
            case .pattern: L("Pattern")
            case .name: L("Name")
            case .address: L("Address")
            case .card: L("Bank Card")
            case .account: L("Bank Account")
            }
        }

        /// What to type, shown in the empty field.
        var prompt: String {
            switch self {
            case .word: L("A word, like your shop’s name")
            case .label: L("A label, like Customer number")
            case .pattern: L("A pattern, like SKU-[0-9]+")
            case .name: L("First and last name")
            case .address: L("Street and house number")
            case .card: L("Card number")
            case .account: L("IBAN")
            }
        }

        /// A detail's symbol.
        var symbol: String {
            switch self {
            case .name: "person.fill"
            case .address: "house.fill"
            case .card: "creditcard.fill"
            case .account: "building.columns.fill"
            case .word: "textformat"
            case .label: "tag"
            case .pattern: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    /// What a label covers of what follows it.
    enum Reach: String, Codable, CaseIterable {
        /// The rest of its line, or the line below where nothing follows it
        /// on its line, as every label rule did before there was a choice.
        case automatic
        /// The rest of its line alone.
        case restOfLine
        /// The line below alone.
        case nextLine
    }

    var id = UUID()
    var text = ""
    var kind = Kind.word
    /// An address's postcode, and its town.
    var postcode = ""
    var city = ""
    /// The owner's own name for a card or an account, like "Girokonto".
    var caption = ""
    /// A label's reach; the other kinds have none.
    var reach = Reach.automatic
    /// Off, a rule covers nothing until it is turned on again. The owner's
    /// details have no switch: they are always on.
    var isEnabled = true

    /// Empty rules wait to be typed; they cover nothing.
    var isBlank: Bool {
        switch kind {
        case .address: [text, postcode, city].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .card: OwnDetails.digits(text).isEmpty
        case .account: OwnDetails.compact(iban: text).isEmpty
        default: text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Whether it covers something now: typed, and turned on, as a detail
    /// always is.
    var isActive: Bool { !isBlank && (kind.isDetail || isEnabled) }

    /// A pattern that cannot be read covers nothing, and the settings say so.
    var isReadable: Bool {
        guard kind == .pattern, !isBlank else { return true }
        return (try? NSRegularExpression(pattern: text, options: [.caseInsensitive])) != nil
    }
}

extension OwnRule {
    /// A rule kept before the details came, or before rules could be turned
    /// off, reads as it was: on, and a label with the reach it always had.
    /// A reach a later version made, that this one does not know, is that.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try values.decode(Kind.self, forKey: .kind)
        postcode = try values.decodeIfPresent(String.self, forKey: .postcode) ?? ""
        city = try values.decodeIfPresent(String.self, forKey: .city) ?? ""
        caption = try values.decodeIfPresent(String.self, forKey: .caption) ?? ""
        reach = try values.decodeIfPresent(String.self, forKey: .reach).flatMap(Reach.init(rawValue:)) ?? .automatic
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

enum OwnRules {
    static let key = "ownRules"

    /// The rules and the owner's details, as one list, as the covering
    /// reads them. Set, the rules go to the settings and the details to the
    /// keychain.
    static var all: [OwnRule] {
        get { load() + OwnDetailStore.details }
        set {
            save(newValue)
            OwnDetailStore.details = newValue.filter(\.kind.isDetail)
        }
    }

    /// The rules kept with the settings, never a detail. One a later
    /// version made, of a kind this one does not know, is left out.
    static func load(from defaults: UserDefaults = .standard) -> [OwnRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return decoded(data).filter { !$0.kind.isDetail }
    }

    static func save(_ rules: [OwnRule], to defaults: UserDefaults = .standard) {
        // The details never go where a backup or another app could read them.
        if let data = try? JSONEncoder().encode(rules.filter { !$0.kind.isDetail }) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Rules read one by one, so one that cannot be read loses no other.
    static func decoded(_ data: Data) -> [OwnRule] {
        ((try? JSONDecoder().decode([Lossy].self, from: data)) ?? []).compactMap(\.rule)
    }

    private struct Lossy: Decodable {
        let rule: OwnRule?

        init(from decoder: Decoder) throws {
            rule = try? OwnRule(from: decoder)
        }
    }

    /// Posted when a rule is added outside Settings, like a word to cover
    /// always from Hide Part, so the photos are read again and Settings
    /// shows it.
    static let changed = Notification.Name("ownRulesChanged")

    /// A word to cover always, unless a rule for it is there already, in
    /// any case; one turned off is turned on again.
    static func add(word: String, to defaults: UserDefaults = .standard) {
        let text = word.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        var rules = load(from: defaults)
        if let i = rules.firstIndex(where: {
            $0.kind == .word && $0.text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(text) == .orderedSame
        }) {
            guard !rules[i].isEnabled else { return }
            rules[i].isEnabled = true
        } else {
            rules.append(OwnRule(text: text, kind: .word))
        }
        save(rules, to: defaults)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Changes whenever a rule or a detail that covers something changes,
    /// or a rule is turned off or on, so the copies covered under the old
    /// ones are drawn again. The details only by a check sum of them, so
    /// none is written into a key.
    static var fingerprint: String { fingerprint(of: all) }

    static func fingerprint(of all: [OwnRule]) -> String {
        let kept = all.filter(\.isActive)
        let rules = kept.filter { !$0.kind.isDetail }.map { rule in
            rule.kind == .label && rule.reach != .automatic
                ? "label.\(rule.reach.rawValue):\(rule.text)" : "\(rule.kind.rawValue):\(rule.text)"
        }
        let details = kept.filter(\.kind.isDetail)
        return (rules + (details.isEmpty ? [] : ["details:" + OwnDetails.checksum(details)])).joined(separator: "|")
    }

    /// The owner's name, once: a word rule kept before there were details,
    /// the only one that reads as a person's name, becomes the name detail,
    /// as Snapfly asked for the owner's name to be saved that way. True
    /// when it moved.
    @discardableResult
    static func adoptName(in defaults: UserDefaults = .standard) -> Bool {
        let done = "ownNameAdopted"
        guard !defaults.bool(forKey: done) else { return false }
        guard let adopted = adopting(load(from: defaults), details: OwnDetailStore.details) else {
            defaults.set(true, forKey: done)
            return false
        }
        // The word stays until the keychain holds the name, so it is never
        // lost; without the keychain, as before the iPhone is first
        // unlocked, it moves another time.
        guard OwnDetailStore.keep(adopted.details, strictly: true) else { return false }
        save(adopted.rules, to: defaults)
        defaults.set(true, forKey: done)
        // What shows the rules, like Settings on the Mac, reads them again;
        // a moment later, as this may run while the choice is first read.
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
        return true
    }

    /// The rules and details once the owner's name moved from the one to the
    /// other; nil when there is no name to move, or no telling which.
    static func adopting(_ rules: [OwnRule], details: [OwnRule]) -> (rules: [OwnRule], details: [OwnRule])? {
        guard !details.contains(where: { $0.kind == .name }) else { return nil }
        let names = rules.filter { $0.kind == .word && !Finder.ownNames(in: [$0]).isEmpty }
        guard names.count == 1, let name = names.first else { return nil }
        let detail = OwnRule(id: name.id, text: name.text.trimmingCharacters(in: .whitespaces), kind: .name)
        return (rules.filter { $0.id != name.id }, [detail] + details)
    }
}

/// The owner's details, kept in the keychain for this device alone: never in
/// iCloud, and in a backup only in a form that opens on this same device,
/// readable once it was first unlocked. Read once, then from memory, from
/// any thread.
enum OwnDetailStore {
    private static let service = "Snapfly details"
    private static let account = "details"
    private static let kept = Kept()

    // What keeps the details private, as this store keeps them, for the
    // screens that say so (Always Hide on the iPhone). Each is true only
    // while the code below makes it so.

    /// For this device alone: the keychain's ThisDeviceOnly class, never
    /// synchronizable, so never in iCloud Keychain or on another device.
    static let staysOnThisDevice = true
    /// Out of every backup: not so. A ThisDeviceOnly item is copied into a
    /// backup, sealed so that it opens on this same device alone; only the
    /// WhenPasscodeSet class stays out, and it cannot be read while the
    /// iPhone is locked, nor kept on one without a passcode.
    static let staysOutOfBackups = false
    /// Never sent: no request carries them, and the words of a picture that
    /// go to the AI assistant have them hidden first (`Finder.masking`).
    static let neverSent = true

    static var details: [OwnRule] {
        get { kept.value { read() } }
        set { keep(newValue) }
    }

    /// Keeps the details, as setting them does; false when the keychain
    /// did not take them, as before the iPhone is first unlocked. They are
    /// then in memory until Snapfly quits, so they cover what they may, or,
    /// kept strictly, not at all.
    @discardableResult
    static func keep(_ details: [OwnRule], strictly: Bool = false) -> Bool {
        kept.change(to: details.filter(\.kind.isDetail), current: read, strictly: strictly) { write($0) }
    }

    /// What was read, and a lock round it.
    private final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        private var details: [OwnRule]?

        /// None while the keychain cannot be read, as before the iPhone is
        /// first unlocked; read again next time, never taken for none kept.
        func value(_ read: () -> [OwnRule]?) -> [OwnRule] {
            lock.lock()
            defer { lock.unlock() }
            if let details { return details }
            guard let read = read() else { return [] }
            details = read
            return read
        }

        /// Written only when it changed, so typing a rule leaves the keychain
        /// alone; kept in memory once written, or, not strictly, either way.
        /// False when the keychain did not take them.
        func change(to new: [OwnRule], current read: () -> [OwnRule]?, strictly: Bool,
                    write: ([OwnRule]) -> Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            // What could not be read counts as changed.
            guard new != (details ?? read()) else { return true }
            let written = write(new)
            if written || !strictly { details = new }
            return written
        }
    }

    #if canImport(Security)
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The details kept, none when there are none; nil when the keychain
    /// could not be read.
    private static func read() -> [OwnRule]? {
        var asked = query
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(asked as CFDictionary, &found)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = found as? Data else { return nil }
        return OwnRules.decoded(data).filter(\.kind.isDetail)
    }

    private static func write(_ details: [OwnRule]) -> Bool {
        let removed = SecItemDelete(query as CFDictionary)
        guard !details.isEmpty, let data = try? JSONEncoder().encode(details) else {
            return removed == errSecSuccess || removed == errSecItemNotFound
        }
        var item = query
        item[kSecValueData as String] = data
        #if !os(macOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    #else
    // Without a keychain, as in the tests on Linux, the details stay in memory.
    private static func read() -> [OwnRule]? { [] }
    private static func write(_ details: [OwnRule]) -> Bool { true }
    #endif
}
