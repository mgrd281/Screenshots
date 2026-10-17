import Foundation

/// What a picture says, boiled down so a picture that says the same can be
/// told again without keeping a word of it: the smallest hashes of its runs
/// of three words, and apart from them, of its numbers. Two orders from one
/// shop share most of their words; their numbers tell them apart.
struct TextPrint: Codable, Hashable, Sendable {
    /// Ascending and without repeats, at most `size` of each.
    var words: [UInt32]
    var numbers: [UInt32]

    /// How many hashes each part keeps.
    static let size = 48
    /// A picture with fewer runs of words than this says too little to tell.
    static let fewestRuns = 6

    /// The print of a picture's lines of text, as read; nil when they say
    /// too little.
    static func of(_ lines: [String]) -> TextPrint? {
        let found = lines.flatMap { Self.tokens(in: $0) }
        guard found.count >= fewestRuns + 2 else { return nil }
        let runs = (0..<(found.count - 2)).map { found[$0...($0 + 2)].joined(separator: " ") }
        let numbers = found.filter { $0.count >= 2 && $0.allSatisfy(\.isNumber) }
        return TextPrint(words: smallest(runs), numbers: smallest(numbers))
    }

    /// Whether two pictures say the same: nearly the same words, and the
    /// same numbers when both have a few.
    func matches(_ other: TextPrint) -> Bool {
        guard Self.likeness(words, other.words) >= 0.7 else { return false }
        guard numbers.count >= 2, other.numbers.count >= 2 else { return true }
        return Self.likeness(numbers, other.numbers) >= 0.6
    }

    /// The words and numbers of a line, folded so case and accents don't count.
    static func tokens(in line: String) -> [String] {
        line.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// How alike two parts are, from 0 to 1: of the smallest hashes of both
    /// together, the share that is in each.
    static func likeness(_ a: [UInt32], _ b: [UInt32]) -> Double {
        var i = 0, j = 0, seen = 0, shared = 0
        while seen < size && (i < a.count || j < b.count) {
            if j == b.count || (i < a.count && a[i] < b[j]) {
                i += 1
            } else if i == a.count || b[j] < a[i] {
                j += 1
            } else {
                shared += 1
                i += 1
                j += 1
            }
            seen += 1
        }
        return seen == 0 ? 0 : Double(shared) / Double(seen)
    }

    /// FNV-1a, mixed so the smallest hashes are a fair sample. Swift's own
    /// hashing changes with every launch, so a print made with it could not
    /// be kept.
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            h ^= UInt32(byte)
            h = h &* 16_777_619
        }
        h ^= h >> 16
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return h
    }

    private static func smallest(_ items: [String]) -> [UInt32] {
        Array(Set(items.map(hash)).sorted().prefix(size))
    }
}
