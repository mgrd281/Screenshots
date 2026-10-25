import Foundation

/// How well a page's smallest print reads, from how sure the reading is of
/// it: the lines of the smallest text, about as tall as the shortest line of
/// a few letters or more, and the mean of how sure Vision was of each. A
/// low score says the small print came out unsharp and is worth taking
/// again closer (`ScanIssue.Kind.smallPrint`).
enum ScanReadability {
    /// A line read, where it is from 0 to 1 from the bottom left, and how
    /// sure the reading was of it, from 0 to 1.
    struct Line: Equatable, Sendable {
        let text: String
        let box: CGRect
        let confidence: Float
    }

    /// The small print reads well from this score on.
    static let enough: Float = 0.9
    /// Lines up to this many times as tall as the shortest are small print too.
    static let smallShare = 1.3

    /// The score of the page's smallest print, and where its lines read
    /// least surely are; nil without lines of a few letters or more.
    static func score(_ lines: [Line]) -> (score: Float, area: CGRect?)? {
        let counted = lines.filter { ScanContent.letters(in: $0.text) >= ScanContent.shortest && $0.box.height > 0 }
        guard let shortest = counted.map(\.box.height).min() else { return nil }
        let small = counted.filter { Double($0.box.height) <= Double(shortest) * smallShare }
        let score = small.map(\.confidence).reduce(0, +) / Float(small.count)
        let unsure = small.filter { $0.confidence < enough }.map(\.box)
        let area = unsure.dropFirst().reduce(unsure.first) { $0?.union($1) }
        return (score, area)
    }

    /// The hint for a page whose small print reads too unsurely, with the
    /// place of its least sure lines; nil when it reads well.
    static func issue(_ lines: [Line]) -> ScanIssue? {
        guard let measured = score(lines), measured.score < enough else { return nil }
        return ScanIssue(.smallPrint, area: measured.area)
    }
}
