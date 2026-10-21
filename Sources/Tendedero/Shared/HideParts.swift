import SwiftUI

// What Always Hide shows on the Mac and on the iPhone alike: the colour of
// each kind of the owner's details, chips that wrap, and words with some of
// them covered.

/// Each kind of the owner's details by a colour of its own, the same in
/// light and dark, its symbol white on it: 5.4:1, 4.8:1, 3.6:1, 5.3:1.
enum DetailTint {
    static func of(_ kind: OwnRule.Kind) -> Color {
        switch kind {
        case .address: Color(red: 31 / 255, green: 111 / 255, blue: 224 / 255)
        case .card: Color(red: 217 / 255, green: 102 / 255, blue: 11 / 255)
        case .account: Color(red: 124 / 255, green: 77 / 255, blue: 219 / 255)
        case .name, .word, .label, .pattern: Color(red: 7 / 255, green: 122 / 255, blue: 86 / 255)
        }
    }
}

/// What a rule covers, in the words both apps use.
enum RuleWords {
    /// After its kind: "Word · anywhere in the picture".
    static func subtitle(of rule: OwnRule) -> String {
        switch (rule.kind, rule.reach) {
        case (.label, .automatic): L("Label · automatic")
        case (.label, .restOfLine): L("Label · rest of the line")
        case (.label, .nextLine): L("Label · next line")
        case (.pattern, _): L("Pattern · anywhere in the picture")
        default: L("Word · anywhere in the picture")
        }
    }

    /// A label's reach, by its name.
    static func title(_ reach: OwnRule.Reach) -> String {
        switch reach {
        case .automatic: L("Automatic")
        case .restOfLine: L("Rest of the Line")
        case .nextLine: L("Next Line")
        }
    }

    /// What a label's reach covers.
    static func detail(_ reach: OwnRule.Reach) -> String {
        switch reach {
        case .automatic: L("What follows it, else the line below")
        case .restOfLine: L("What follows it on its line")
        case .nextLine: L("The line under it")
        }
    }

    /// A rule's symbol: "Aa" for a word, a tag for a label.
    static func symbol(_ kind: OwnRule.Kind) -> String {
        switch kind {
        case .label: "tag.fill"
        case .pattern: "chevron.left.forwardslash.chevron.right"
        default: "textformat"
        }
    }
}

/// Words with some of them covered, as a covered copy shows them: a bar
/// of the words' own colour over what is covered.
struct CoveredLineText: View {
    private let segments: [(text: String, covered: Bool)]

    init(segments: [(String, Bool)]) {
        self.segments = segments.map { (text: $0.0, covered: $0.1) }
    }

    /// A line of a rule's made-up page.
    init(line: RuleSample.Line) {
        guard !line.whole else {
            segments = [(text: line.text, covered: true)]
            return
        }
        var parts: [(text: String, covered: Bool)] = []
        var at = line.text.startIndex
        for range in line.covered.sorted(by: { $0.lowerBound < $1.lowerBound }) where range.lowerBound >= at {
            if at < range.lowerBound { parts.append((text: String(line.text[at..<range.lowerBound]), covered: false)) }
            parts.append((text: String(line.text[range]), covered: true))
            at = range.upperBound
        }
        if at < line.text.endIndex { parts.append((text: String(line.text[at...]), covered: false)) }
        segments = parts
    }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var whole = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            if segment.covered {
                part.foregroundColor = Self.cover
                part.backgroundColor = Self.cover
            }
            whole += part
        }
        return whole
    }

    /// The bar over covered words: the words' colour, nearly solid.
    static let cover = Color.primary.opacity(0.85)
}

/// Chips one after another, on as many lines as they need. SwiftUI's
/// Layout by its full name, since the Mac has a Layout of its own.
struct ChipFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let places = arrange(subviews, in: proposal.width ?? .infinity)
        let width = places.map { $0.origin.x + $0.size.width }.max() ?? 0
        let height = places.map { $0.origin.y + $0.size.height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let places = arrange(subviews, in: bounds.width)
        for (subview, place) in zip(subviews, places) {
            subview.place(at: CGPoint(x: bounds.minX + place.origin.x, y: bounds.minY + place.origin.y),
                          proposal: ProposedViewSize(place.size))
        }
    }

    /// Where each chip goes, from the leading edge, in one pass both for
    /// measuring and for placing, so the lines come out the same. Half a
    /// point to spare, as a width measured comes back rounded.
    private func arrange(_ subviews: Subviews, in limit: CGFloat) -> [CGRect] {
        var places: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            if x > 0, x + size.width > limit + 0.5 {
                y += row + spacing
                x = 0
                row = 0
            }
            places.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return places
    }
}
