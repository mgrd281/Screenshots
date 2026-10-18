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
    /// Where the copy is covered, from 0 to 1 from its bottom left, for the
    /// lock to show; empty for a PDF.
    private(set) var places: [CGRect] = []

    init() {}

    init(_ areas: [Finder.Area], hand: Int = 0, places: [CGRect] = []) {
        for area in areas {
            if let kind = area.kind { kinds[kind, default: 0] += 1 } else { rules += 1 }
        }
        self.hand = hand
        self.places = places
    }

    /// Places in the whole picture, from 0 to 1 from its bottom left, as
    /// they are in the copy: cut to the part kept, and under a band above
    /// the picture, which then takes `share` of the copy's height. What the
    /// cut leaves out is left out.
    static func places(_ rects: [CGRect], crop: CGRect?, share: CGFloat = 1) -> [CGRect] {
        rects.compactMap { rect in
            var place = rect
            if let crop, crop.width > 0, crop.height > 0 {
                place = CGRect(x: (place.minX - crop.minX) / crop.width, y: (place.minY - crop.minY) / crop.height,
                               width: place.width / crop.width, height: place.height / crop.height)
            }
            place = place.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !place.isNull, place.width > 0, place.height > 0 else { return nil }
            return CGRect(x: place.minX, y: place.minY * share, width: place.width, height: place.height * share)
        }
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
