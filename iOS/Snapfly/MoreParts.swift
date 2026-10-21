import SwiftUI

// MARK: Motion

/// More's motion, each with its still answer for Reduce Motion: a short
/// cross-fade, nothing moving.
enum MoreMotion {
    /// A still change: 0.15 s on an ease-out.
    static let fade = Animation.easeOut(duration: 0.15)

    /// The page's parts coming in, the first time More shows in a launch:
    /// rising 8 pt and fading in, 40 ms apart, in under 0.4 s.
    static func appear(_ index: Int, still: Bool) -> Animation {
        still ? fade : .easeOut(duration: 0.26).delay(Double(index) * 0.04)
    }

    /// The hero's covers drawn in from the reading side, 80 ms apart.
    static func draw(_ index: Int, still: Bool) -> Animation {
        still ? fade : .easeOut(duration: 0.35).delay(0.12 + Double(index) * 0.08)
    }

    /// A new cover look shown: a cross-fade of a quarter of a second.
    static func style(_ still: Bool) -> Animation {
        still ? fade : .easeInOut(duration: 0.25)
    }

    /// A count, a meter or a choice changing.
    static func change(_ still: Bool) -> Animation {
        still ? fade : .snappy
    }

    /// Covers growing over a whole line, with no overshoot.
    static func grow(_ still: Bool) -> Animation {
        still ? fade : .spring(duration: 0.35, bounce: 0)
    }
}

/// Played already this launch: coming back to More shows it at rest.
enum MoreIntro {
    static var played = false
}

/// Rises 8 pt and fades in as More first shows; at once after that, and a
/// fade alone with Reduce Motion.
struct MoreAppear: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.moreStill) private var still

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || still ? 0 : 8)
            .animation(MoreMotion.appear(index, still: still), value: shown)
    }
}

/// A tile, a chip or a button that gives to 97% under the finger, on a
/// quick spring; with Reduce Motion it dims instead. No haptic.
struct TilePressStyle: ButtonStyle {
    @Environment(\.moreStill) private var still

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !still ? 0.97 : 1)
            .opacity(configuration.isPressed && still ? 0.7 : 1)
            .animation(still ? MoreMotion.fade : .spring(response: 0.22, dampingFraction: 0.9),
                       value: configuration.isPressed)
    }
}

// MARK: Pieces

/// More's card: white, corners of 22; at night a dark grey.
struct MoreCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SnapflyTokens.hideCard,
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
    }
}

extension View {
    func moreCard(padding: CGFloat = 16) -> some View { modifier(MoreCard(padding: padding)) }

    /// The page's bar: an inline title on the page's own ground, so no
    /// words show through it, and no tab bar under the page, so its
    /// minimised button never sits over a row.
    func morePage(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SnapflyTokens.hideGround, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}

/// A section's title on More: title 3 semibold, a heading for VoiceOver.
struct MoreHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideText)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short word in a capsule: the preset's name, or Always On.
struct MoreBadge: View {
    let title: String
    var ground = SnapflyTokens.hideAccentSoft
    var ink = SnapflyTokens.hideAccent

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ground, in: Capsule())
    }
}

/// A number that rolls to its new value; with Reduce Motion it fades.
struct RollingNumber: View {
    let value: Int
    @Environment(\.moreStill) private var still

    var body: some View {
        Text(value, format: .number)
            .monospacedDigit()
            .contentTransition(still ? .opacity : .numericText(value: Double(value)))
            .animation(MoreMotion.change(still), value: value)
    }
}

/// A thin meter of how much is on.
struct MoreMeter: View {
    let share: Double
    @Environment(\.moreStill) private var still

    var body: some View {
        Capsule()
            .fill(SnapflyTokens.hideSeparator)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(SnapflyTokens.moreGlyph)
                        .frame(width: CGFloat(max(0, min(1, share))) * proxy.size.width)
                }
            }
            .clipShape(Capsule())
            .animation(MoreMotion.change(still), value: share)
            .accessibilityHidden(true)
    }
}

/// A coloured dot before a state's words: green when on, grey when off.
struct StatusDot: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? SnapflyTokens.moreGlyph : SnapflyTokens.hideSecondary.opacity(0.6))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: Covers drawn small

/// A cover in a look, drawn as a covered copy draws it on white paper
/// (`Finder.cover`): ink with softened corners; ink with the kind's word on
/// it; the blur's soft smudges where words would be; pixels darker toward
/// the middle of the line; a row of dots; or the white carried across. The
/// soft looks take their colours from around a place, and on paper that is
/// white, so the same rules give the same pictures here. For More's
/// pictures of a document, never for a copy.
struct CoverSwatch: View {
    let style: CoverStyle
    var kind: PrivateDetail?
    /// Its chance numbers, the same every time, as a copy seeds them by the place.
    var seed = 1

    var body: some View {
        Canvas { context, size in
            Self.draw(style, kind: kind, seed: seed, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private static let ink = Color(white: 0.12)
    /// What words on white would be: the renderer's `contrasting`.
    private static let tone: CGFloat = 1 - 0.9 * 0.65

    static func draw(_ style: CoverStyle, kind: PrivateDetail?, seed: Int, in context: inout GraphicsContext,
                     size: CGSize) {
        let place = CGRect(origin: .zero, size: size)
        guard place.width >= 1, place.height >= 1 else { return }
        // How tall the letters covered are, as the renderer reckons them from a line.
        let text = place.height / 1.4
        let corner = min(place.height / 4, place.width / 2, 8)
        let shape = Path(roundedRect: place, cornerRadius: corner, style: .continuous)
        var random = SwatchRandom(seed)
        switch style {
        case .ink:
            context.fill(shape, with: .color(ink))
        case .label:
            context.fill(shape, with: .color(ink))
            label(kind?.label ?? L("Hidden"), in: place, text: text, context: &context)
        case .blur:
            context.clip(to: shape)
            context.fill(shape, with: .color(.white))
            smear(place, text: text, random: &random, context: &context)
        case .pixels:
            context.clip(to: Path(roundedRect: place, cornerRadius: min(place.height / 6, place.width / 2, 4),
                                  style: .continuous))
            pixels(place, text: text, random: &random, context: &context)
        case .dots:
            context.clip(to: shape)
            context.fill(shape, with: .color(.white))
            dots(place, text: text, context: &context)
        case .erase:
            context.fill(shape, with: .color(.white))
        }
    }

    private static func label(_ word: String, in place: CGRect, text: CGFloat, context: inout GraphicsContext) {
        let first = min(text * 0.64, 12)
        guard first >= 3 else { return }
        var size = first
        var resolved = context.resolve(Text(word).font(.system(size: size, weight: .bold)).foregroundStyle(.white.opacity(0.92)))
        let room = place.width - size * 1.2
        let width = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).width
        if width > room {
            guard room > 0 else { return }
            size *= room / width
            guard size >= max(3, first * 0.55) else { return }
            resolved = context.resolve(Text(word).font(.system(size: size, weight: .bold)).foregroundStyle(.white.opacity(0.92)))
        }
        context.draw(resolved, at: CGPoint(x: place.midX, y: place.midY), anchor: .center)
    }

    /// Soft round spots where words would be, word by word.
    private static func smear(_ place: CGRect, text: CGFloat, random: inout SwatchRandom,
                              context: inout GraphicsContext) {
        var x = place.minX + text * 0.3
        let end = place.maxX - text * 0.3
        while end - x > text * 0.4 {
            let word = min(end - x, text * (1.2 + random.unit() * 3))
            var spot = x + text * 0.3
            repeat {
                let alpha = Double(0.22 * (0.85 + random.unit() * 0.3))
                let blob = CGRect(x: spot - text * 0.6, y: place.midY - text * 0.6, width: text * 1.2, height: text * 1.2)
                let color = Color(white: Double(tone))
                context.fill(Path(ellipseIn: blob),
                             with: .radialGradient(Gradient(stops: [.init(color: color.opacity(alpha), location: 0),
                                                                    .init(color: color.opacity(alpha * 0.55), location: 0.5),
                                                                    .init(color: color.opacity(0), location: 1)]),
                                                   center: CGPoint(x: blob.midX, y: blob.midY), startRadius: 0,
                                                   endRadius: blob.width / 2))
                spot += text * 0.4
            } while spot < x + word - text * 0.3
            x += word + text * (0.2 + random.unit() * 0.18)
        }
    }

    /// Square tiles, a third of a line's height, darker toward its middle.
    private static func pixels(_ place: CGRect, text: CGFloat, random: inout SwatchRandom,
                               context: inout GraphicsContext) {
        let tile = max(1.5, text * 1.4 / 3.2)
        let columns = max(1, Int((place.width / tile).rounded(.up)))
        let rows = max(1, Int((place.height / tile).rounded(.up)))
        for row in 0..<rows {
            for column in 0..<columns {
                let u = min(1, (CGFloat(column) + 0.5) * tile / place.width)
                let v = min(1, (CGFloat(row) + 0.5) * tile / place.height)
                let middle = CGFloat(pow(Double(1 - abs(v - 0.5) * 2), 0.7))
                let ends = min(1, (1 - abs(u - 0.5) * 2) * 4)
                let weight = 0.8 * middle * ends * (0.3 + 0.7 * random.unit())
                let shade: CGFloat = max(0, min(1, 1 + (tone - 1) * weight + random.unit() * 0.06 - 0.03))
                context.fill(Path(CGRect(x: place.minX + CGFloat(column) * tile, y: place.minY + CGFloat(row) * tile,
                                         width: tile + 0.5, height: tile + 0.5)),
                             with: .color(Color(white: Double(shade))))
            }
        }
    }

    /// A row of round dots across, dark on the white.
    private static func dots(_ place: CGRect, text: CGFloat, context: inout GraphicsContext) {
        let diameter = max(1, text * 0.46)
        let gap = diameter * 0.7
        let room = place.width - text * 0.5
        let count = max(1, Int((room + gap) / (diameter + gap)))
        let total = CGFloat(count) * diameter + CGFloat(count - 1) * gap
        let start = place.midX - total / 2
        for k in 0..<count {
            context.fill(Path(ellipseIn: CGRect(x: start + CGFloat(k) * (diameter + gap), y: place.midY - diameter / 2,
                                                width: diameter, height: diameter)),
                         with: .color(Color(white: 0.18).opacity(0.92)))
        }
    }
}

/// The same chance numbers from the same seed, as the renderer's `Seeded`.
private struct SwatchRandom {
    private var state: UInt64

    init(_ seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x94D0_49BB_1331_11EB
    }

    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

/// A look shown, and the next cross-fading in when it changes.
struct StyleFade<Content: View>: View {
    let style: CoverStyle
    @ViewBuilder let content: (CoverStyle) -> Content
    @Environment(\.moreStill) private var still

    var body: some View {
        ZStack {
            content(style)
                .id(style)
                .transition(.opacity)
        }
        .animation(MoreMotion.style(still), value: style)
    }
}

// MARK: Little documents

/// A sheet of paper drawn small: lines of grey words, and covers in a look
/// over some of them. White in light and dark alike, as a document is.
/// Drawn left to right, as the document reads.
struct PaperSketch: View {
    /// A line: how far across it reaches, from 0 to 1, and whether it is covered.
    struct Line: Hashable {
        let width: CGFloat
        let covered: Bool
        var title = false
    }

    let style: CoverStyle
    let lines: [Line]
    /// From 0 to 1: how far the covers are drawn in, each its own way along.
    var drawn = true
    var lineHeight: CGFloat = 4
    var spacing: CGFloat = 5
    @Environment(\.moreStill) private var still

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                GeometryReader { proxy in
                    let width = proxy.size.width * line.width
                    if line.covered {
                        let order = lines[..<index].filter(\.covered).count
                        CoverSwatch(style: style, kind: nil, seed: index + 3)
                            .frame(width: width, height: lineHeight * 1.6)
                            .offset(y: -lineHeight * 0.3)
                            .scaleEffect(x: drawn || still ? 1 : 0.001, anchor: .leading)
                            .opacity(still && !drawn ? 0 : 1)
                            .animation(MoreMotion.draw(order, still: still), value: drawn)
                    } else {
                        Capsule()
                            .fill(line.title ? SnapflyTokens.morePaperText.opacity(0.75) : SnapflyTokens.morePaperLine)
                            .frame(width: width, height: lineHeight)
                    }
                }
                .frame(height: lineHeight)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// More's picture of a document in the look chosen: a bill with a name, an
/// IBAN and a phone number covered.
struct PaperThumbnail: View {
    let style: CoverStyle
    var drawn = true

    static let lines: [PaperSketch.Line] = [
        .init(width: 0.5, covered: false, title: true), .init(width: 0.85, covered: false),
        .init(width: 0.7, covered: true), .init(width: 0.92, covered: false), .init(width: 0.88, covered: true),
        .init(width: 0.6, covered: false), .init(width: 0.55, covered: true), .init(width: 0.8, covered: false),
    ]

    var body: some View {
        StyleFade(style: style) { style in
            PaperSketch(style: style, lines: Self.lines, drawn: drawn)
        }
        .padding(10)
        .frame(width: 70, height: 92, alignment: .top)
        .background(SnapflyTokens.morePaper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}
