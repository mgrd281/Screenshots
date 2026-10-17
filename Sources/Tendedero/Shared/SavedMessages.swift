import Foundation

/// A message kept ready to go with photos, like "Here is the invoice for
/// your order {order}". Its blanks fill in from the photo; nothing is sent
/// until it is.
struct SavedMessage: Codable, Hashable, Identifiable {
    var id = UUID()
    var text = ""

    /// Empty messages wait to be typed; they are not offered.
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum SavedMessages {
    static let key = "savedMessages"

    static var all: [SavedMessage] {
        get { load() }
        set { save(newValue) }
    }

    static func load(from defaults: UserDefaults = .standard) -> [SavedMessage] {
        guard let data = defaults.data(forKey: key),
              let messages = try? JSONDecoder().decode([SavedMessage].self, from: data) else { return [] }
        return messages
    }

    static func save(_ messages: [SavedMessage], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(messages), forKey: key)
    }

    /// The blanks a message can hold, and the part of the photo's order
    /// each is filled with.
    static let blanks: [(token: String, part: OrderCard.Part)] = [
        ("{order}", .order), ("{total}", .total), ("{date}", .date), ("{name}", .name), ("{tracking}", .tracking),
    ]

    /// Said in place of a blank that stays empty, so the gap shows before
    /// the message goes.
    static let gap = "…"

    /// The kind of private detail behind each part of an order.
    static func kind(of part: OrderCard.Part) -> PrivateDetail {
        switch part {
        case .order: .orders
        case .date: .dates
        case .total: .amounts
        case .name: .names
        case .address: .addresses
        case .email: .emails
        case .phone: .phones
        case .tracking: .tracking
        case .code: .barcodes
        }
    }

    /// Whether a message has blanks to fill.
    static func hasBlanks(_ text: String) -> Bool {
        blanks.contains { text.contains($0.token) }
    }

    /// The message with its blanks filled from the photo's order. A blank of
    /// a kind that is covered stays empty, so the message never says what
    /// the photo hides, and so does one the photo does not show.
    static func fill(_ text: String, with fields: [OrderCard.Field], covering: Set<PrivateDetail>) -> String {
        var text = text
        for blank in blanks where text.contains(blank.token) {
            let value = covering.contains(kind(of: blank.part)) ? nil : fields.first { $0.part == blank.part }?.value
            text = text.replacingOccurrences(of: blank.token, with: value ?? gap)
        }
        return text
    }
}
