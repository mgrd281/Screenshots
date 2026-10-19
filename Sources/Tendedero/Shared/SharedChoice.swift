import Foundation
import Security

/// What the iPhone's share extension covers: the kinds, the look and the
/// owner's own rules chosen in the app, kept in a keychain item of the group
/// the app and its extension share, as the extension cannot read the app's
/// settings. Only the choice is kept, never a picture or a word read. The
/// Mac does not use it.
struct SharedChoice: Codable, Equatable {
    var kinds: [String]
    var style: String
    var rules: [OwnRule]

    init(details: Set<PrivateDetail>, look: CoverStyle, rules: [OwnRule]) {
        kinds = details.map(\.rawValue).sorted()
        style = look.rawValue
        self.rules = rules
    }

    var details: Set<PrivateDetail> { Set(kinds.compactMap(PrivateDetail.init(rawValue:))) }
    /// Ink for a look this version does not know.
    var look: CoverStyle { CoverStyle(rawValue: style) ?? .ink }

    private static let service = "de.ghazarian.Snapfly.choice"
    private static let account = "choice"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Kept for the extension, readable once the iPhone was first unlocked.
    static func keep(_ choice: SharedChoice) {
        guard let data = try? JSONEncoder().encode(choice) else { return }
        let values: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, values as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(values) { $1 } as CFDictionary, nil)
        }
    }

    /// The choice the app last kept, or nil before it kept one.
    static var kept: SharedChoice? {
        var asked = query
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(SharedChoice.self, from: data)
    }
}
