import Foundation

/// What was covered in a picture, kind by kind, so the lock on the line and
/// the iPhone can say it: names, a QR code, a rule of the owner's own, a part
/// hidden by hand.
struct CoverReport: Equatable {
    /// How many places of each kind.
    private(set) var kinds: [PrivateDetail: Int] = [:]
    /// Places covered by the owner's own rules.
    private(set) var rules = 0
    /// Parts hidden by hand.
    private(set) var hand = 0

    init() {}

    init(_ areas: [Finder.Area], hand: Int = 0) {
        for area in areas {
            if let kind = area.kind { kinds[kind, default: 0] += 1 } else { rules += 1 }
        }
        self.hand = hand
    }

    var total: Int { kinds.values.reduce(0, +) + rules + hand }
    var isEmpty: Bool { total == 0 }

    /// Another page's, for a PDF.
    mutating func add(_ other: CoverReport) {
        kinds.merge(other.kinds, uniquingKeysWith: +)
        rules += other.rules
        hand += other.hand
    }

    /// What was covered, in the order Settings lists it, like "Names ·
    /// QR codes and barcodes · Your own rules". Empty when nothing was.
    var summary: String {
        var parts = PrivateDetail.allCases.filter { kinds[$0, default: 0] > 0 }.map(\.title)
        if rules > 0 { parts.append(L("Your own rules")) }
        if hand > 0 { parts.append(L("Hidden by hand")) }
        return parts.joined(separator: " · ")
    }

    /// "Covered: Names · Emails", for the lock and VoiceOver; nil when
    /// nothing was covered.
    var sentence: String? {
        isEmpty ? nil : String(format: L("Covered: %@"), summary)
    }

    /// What was covered, to keep: the kinds' stored names in Settings'
    /// order, then "rules" and "hand".
    var keys: [String] {
        var keys = PrivateDetail.allCases.filter { kinds[$0, default: 0] > 0 }.map(\.rawValue)
        if rules > 0 { keys.append("rules") }
        if hand > 0 { keys.append("hand") }
        return keys
    }

    /// Kept keys read back in words, as Settings names them.
    static func titles(of keys: [String]) -> [String] {
        keys.compactMap { key in
            switch key {
            case "rules": L("Your own rules")
            case "hand": L("Hidden by hand")
            default: PrivateDetail(rawValue: key)?.title
            }
        }
    }
}
