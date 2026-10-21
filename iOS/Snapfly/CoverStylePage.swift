import SwiftUI

/// Cover Style (Stil der Abdeckung), from More: a made-up bill covered in the
/// look chosen, as the two switches have it; the six looks three to a row,
/// each on a little document, the one chosen in a green ring that moves to
/// the next; then Keep the last four digits and Strongest protection, and
/// what every look keeps. Kept where they always were (`CoverStyle.current`,
/// `Finder`).
struct CoverStylePage: View {
    @ObservedObject var store: MoreStore
    @Namespace private var ring
    @Environment(\.moreStill) private var still
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CoverPreview(style: store.look, keepsLastDigits: store.keepsLastDigits, strongest: store.strongest)
                looks
                switches
                Text(L("Every look hides for good: blur, pixels, dots and erased are drawn from the colors around what is covered, never from it, so it cannot be brought back."))
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .defaultScrollAnchor(MoreSample.endAnchor)
        .background(SnapflyTokens.hideGround.ignoresSafeArea())
        .morePage(L("Cover Style"))
    }

    private var looks: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(CoverStyle.allCases) { style in
                look(style)
            }
        }
    }

    private func look(_ style: CoverStyle) -> some View {
        let chosen = style == store.look
        return Button {
            withAnimation(MoreMotion.change(still)) { store.setLook(style) }
        } label: {
            VStack(spacing: 8) {
                PaperSketch(style: style,
                            lines: [.init(width: 0.55, covered: false, title: true), .init(width: 0.8, covered: true),
                                    .init(width: 0.95, covered: false), .init(width: 0.65, covered: true)],
                            lineHeight: 4, spacing: 7)
                    .padding(10)
                    .frame(height: 66, alignment: .top)
                    .frame(maxWidth: .infinity)
                    .background(SnapflyTokens.morePaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SnapflyTokens.hideSeparator))
                    .padding(4)
                    .overlay {
                        if chosen {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(SnapflyTokens.moreGlyph, lineWidth: 2.5)
                                .matchedGeometryEffect(id: "ring", in: ring)
                        }
                    }
                Text(style.title)
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? SnapflyTokens.hideText : SnapflyTokens.hideSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(chosen ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
        .accessibilityIdentifier("more-style-\(style.rawValue)")
    }

    private var switches: some View {
        VStack(spacing: 0) {
            toggle(L("Keep the last four digits"),
                   detail: store.strongest ? L("Strongest protection covers whole lines, these digits too.")
                       : L("Cards, accounts and phone numbers stay recognisable."),
                   isOn: Binding(get: { store.keepsLastDigits }, set: { on in
                       withAnimation(MoreMotion.grow(still)) { store.setKeepsLastDigits(on) }
                   }),
                   id: "more-toggle-digits")
            MoreDivider(leading: 16)
            toggle(L("Strongest protection"), detail: L("Whole lines, with more room around them."),
                   isOn: Binding(get: { store.strongest }, set: { on in
                       withAnimation(MoreMotion.grow(still)) { store.setStrongest(on) }
                   }),
                   id: "more-toggle-strongest")
        }
        .background(SnapflyTokens.hideCard,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .contentTransition(.opacity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(SnapflyTokens.hideAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .accessibilityIdentifier(id)
    }
}

/// A made-up bill, "Invoice to" with a name, an IBAN and a phone number,
/// covered in a look as a copy would be: the last four digits left with
/// Keep the last four digits; whole lines, with more room, with Strongest
/// protection. White paper in light and dark alike. Covers grow and shrink
/// with no overshoot, the digits slide in from the trailing side, and a new
/// look cross-fades; with Reduce Motion it all fades.
struct CoverPreview: View {
    let style: CoverStyle
    let keepsLastDigits: Bool
    let strongest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Invoice to"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SnapflyTokens.morePaperLabel)
                .textCase(.uppercase)
            ForEach(Array(CoverSampleLine.invoice.enumerated()), id: \.element.id) { index, line in
                PreviewLine(line: line, seed: index + 11, style: style, keepsLastDigits: keepsLastDigits,
                            strongest: strongest)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnapflyTokens.morePaper,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous)
            .strokeBorder(SnapflyTokens.hideSeparator))
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Invoice to") + ", " + style.title)
        .accessibilityIdentifier("more-style-preview")
    }
}

/// One line of the bill and its cover.
private struct PreviewLine: View {
    let line: CoverSampleLine
    let seed: Int
    let style: CoverStyle
    let keepsLastDigits: Bool
    let strongest: Bool
    @State private var label: CGFloat = 0
    @State private var covered: CGFloat = 0
    @State private var kept: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(\.moreStill) private var still

    private static let gap: CGFloat = 8

    var body: some View {
        // Laid out where the last four digits part, always, so nothing
        // moves but the cover.
        let parts = line.split(keepsLastDigits: true, strongest: false)
        let showsDigits = keepsLastDigits && !strongest && !parts.kept.isEmpty
        HStack(spacing: Self.gap) {
            if let title = line.label {
                Text(title)
                    .foregroundStyle(SnapflyTokens.morePaperLabel)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { label = $0 }
            }
            HStack(spacing: 0) {
                Text(verbatim: parts.covered)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { covered = $0 }
                Text(verbatim: parts.kept)
                    .offset(x: showsDigits || still ? 0 : 10)
                    .opacity(showsDigits ? 1 : 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { kept = $0 }
            }
            .foregroundStyle(SnapflyTokens.morePaperText)
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .overlay(alignment: .leading) {
            StyleFade(style: style) { style in
                CoverSwatch(style: style, kind: line.kind, seed: seed)
            }
            .frame(width: max(0, cover.width), height: cover.height)
            .offset(x: cover.x)
        }
    }

    /// Where the cover goes: over the value, less the digits it leaves, with
    /// a little room round it; over the whole line, with more room, with
    /// Strongest protection.
    private var cover: (x: CGFloat, width: CGFloat, height: CGFloat) {
        let start = line.label == nil ? 0 : label + Self.gap
        if strongest {
            return (-8, start + covered + kept + 16, height + 10)
        }
        // Its room past the words ends where the digits it leaves begin.
        let trailing: CGFloat = keepsLastDigits && kept > 0 ? 4 : kept + 8
        return (start - 4, covered + trailing, height + 4)
    }
}
