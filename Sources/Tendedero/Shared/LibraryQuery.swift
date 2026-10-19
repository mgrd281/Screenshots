import Foundation

/// Finding screenshots in the library: by the words they say, as read
/// ahead of time on this device, by what they hold, and in an order. Pure,
/// so it is checked without a picture or Photos.
struct LibraryQuery: Equatable {
    /// Which screenshots show.
    enum Filter: String, CaseIterable {
        /// All of them.
        case all
        /// Those read ahead of time that hold a private detail.
        case privateDetails
        /// Those protected here lately.
        case protected
        /// Those not protected here lately.
        case unprotected
    }

    enum Order: String, CaseIterable {
        case newest, oldest
    }

    /// One screenshot as the library knows it.
    struct Item: Equatable {
        let id: String
        var created: Date?
        /// Its words, as read ahead of time; nil while it was not read.
        var text: String?
        /// The kinds of private detail found in it, as raw values.
        var kinds: [String] = []
        var protected = false
    }

    var search = ""
    var filter = Filter.all
    var order = Order.newest

    /// Whether anything narrows the screenshots down.
    var narrows: Bool { !words.isEmpty || filter != .all }

    /// The words searched for, folded so case and accents do not matter.
    var words: [String] {
        Self.fold(search).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The screenshots that match, in the order chosen: each word searched
    /// for must be in what it says.
    func apply(_ items: [Item]) -> [Item] {
        let words = self.words
        let kept = items.filter { item in
            switch filter {
            case .all: break
            case .privateDetails: if item.kinds.isEmpty { return false }
            case .protected: if !item.protected { return false }
            case .unprotected: if item.protected { return false }
            }
            guard !words.isEmpty else { return true }
            guard let text = item.text else { return false }
            let said = Self.fold(text)
            return words.allSatisfy { said.contains($0) }
        }
        // Undated ones last, and otherwise in the order given.
        let indexed = Array(kept.enumerated())
        return indexed.sorted { a, b in
            switch (a.element.created, b.element.created) {
            case let (x?, y?) where x != y: return order == .newest ? x > y : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
