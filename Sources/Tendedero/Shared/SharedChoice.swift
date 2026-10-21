import Foundation
import Security

/// What the iPhone's share extension covers: the kinds, the look and the
/// owner's own rules and details chosen in the app, kept in a keychain item
/// of the group the app and its extension share, as the extension cannot
/// read the app's settings: for this iPhone alone, never in iCloud, and in
/// a backup only in a form that opens on this same iPhone. Only the choice
/// is kept, never a picture or a word read. The Mac does not use it.
struct SharedChoice: Codable, Equatable {
    var kinds: [String]
    var style: String
    var rules: [OwnRule]
    /// Kept since Names, Patient names and Other people each cover their
    /// own people; nil in a choice kept before.
    var parted: Bool?

    init(details: Set<PrivateDetail>, look: CoverStyle, rules: [OwnRule]) {
        kinds = details.map(\.rawValue).sorted()
        style = look.rawValue
        self.rules = rules
        parted = true
    }

    /// The kinds, a choice kept before brought up to date as the app does
    /// it, for a picture shared before the app was opened again.
    var details: Set<PrivateDetail> {
        let details = Set(kinds.compactMap(PrivateDetail.init(rawValue:)))
        return parted == true ? details : PrivateDetail.parting(details)
    }
    /// Ink for a look this version does not know.
    var look: CoverStyle { CoverStyle(rawValue: style) ?? .ink }

    private static let service = "de.ghazarian.Snapfly.choice"
    private static let account = "choice"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Kept for the extension, readable once the iPhone was first unlocked,
    /// and never moved to another device: it holds the owner's details.
    static func keep(_ choice: SharedChoice) {
        guard let data = try? JSONEncoder().encode(choice) else { return }
        let values: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
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
