import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A short made-up page that shows what one of the owner's rules covers, as
/// the sheet for the rule shows it while the rule is typed. The engine
/// covers it as it covers a picture, so it shows what the rule will do. Its
/// words are made up; only the rule's own text is the owner's.
struct RuleSample: Equatable {
    struct Line: Equatable {
        let text: String
        /// The parts of it the rule covers.
        let covered: [Range<String.Index>]
        /// Covered as a whole, as the line under a label.
        let whole: Bool

        /// The line with what is covered taken out, as VoiceOver says it.
        var spoken: String {
            if whole { return L("covered") }
            var said = text
            for range in covered.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                said.replaceSubrange(range, with: L("covered"))
            }
            return said
        }
    }

    let lines: [Line]

    /// Whether the rule covers anything on the page.
    var coversSomething: Bool { lines.contains { $0.whole || !$0.covered.isEmpty } }

    /// The made-up number after a label.
    static let value = "48 213"

    /// The page for a rule: a word in a sentence and again in capitals, a
    /// label with a number after it, or under it where its reach is the line
    /// below. None for a pattern, or for a rule with nothing typed.
    static func of(_ rule: OwnRule) -> RuleSample? {
        var rule = rule
        rule.isEnabled = true
        let text = rule.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let strings: [String]
        switch rule.kind {
        case .word:
            strings = [String(format: L("Meeting with %@ on Monday"), text),
                       String(format: L("%@ · Invoice 117"), text.uppercased())]
        case .label:
            let label = text.hasSuffix(":") ? String(text.dropLast()) : text
            strings = rule.reach == .nextLine
                ? [L("Invoice 117"), label, value, L("Thank you for your order.")]
                : [L("Invoice 117"), label + ": " + value, L("Thank you for your order.")]
        case .pattern, .name, .address, .card, .account:
            return nil
        }
        // One line under another, as a page is read.
        let boxes = strings.indices.map { CGRect(x: 0.1, y: 0.9 - CGFloat($0) * 0.03, width: 0.8, height: 0.02) }
        let hits = Finder.findings(strings, boxes: boxes, part: { _, _ in nil }, [], rules: [rule]).hits
            .filter { $0.kind == nil }
        return RuleSample(lines: strings.enumerated().map { i, string in
            let mine = hits.filter { $0.line == i }
            return Line(text: string, covered: mine.compactMap { $0.range.flatMap { Range($0, in: string) } },
                        whole: mine.contains { $0.range == nil })
        })
    }
}
