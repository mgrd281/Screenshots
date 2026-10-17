import SwiftUI

enum Layout {
    /// How big the photos hang, from Size in the menu bar. The clip, the rope
    /// and the glass frame keep their size; the photos and the room they take
    /// grow or shrink. Medium is the original size.
    enum Size: String, CaseIterable {
        case small, medium, large

        var scale: CGFloat {
            switch self {
            case .small: 0.8
            case .medium: 1
            case .large: 1.35
            }
        }
    }

    static var size: Size {
        get { Size(rawValue: UserDefaults.standard.string(forKey: "lineSize") ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lineSize") }
    }

    /// What the photos hang on, from Settings: the original clothesline, a
    /// glass shelf, an island hanging from the top of the screen like the
    /// notch grown, or a stack of cards that spreads out when you reach it.
    enum Style: String, CaseIterable, Identifiable {
        case clothesline, shelf, island, stack

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clothesline: L("Clothesline")
            case .shelf: L("Glass shelf")
            case .island: L("Island")
            case .stack: L("Card stack")
            }
        }

        /// Only on a rope do photos hang from clips, crooked, and sway.
        var swings: Bool { self == .clothesline }
    }

    private static var savedStyle: Style?

    static var style: Style {
        get {
            if let savedStyle { return savedStyle }
            let saved = Style(rawValue: UserDefaults.standard.string(forKey: "lineStyle") ?? "") ?? .clothesline
            savedStyle = saved
            return saved
        }
        set {
            savedStyle = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "lineStyle")
        }
    }

    static var photoMaxHeight: CGFloat { (104 * size.scale).rounded() }
    static var cardWidth: CGFloat { (150 * size.scale).rounded() }
    static var spacing: CGFloat { cardWidth + 24 }
    static var panelHeight: CGFloat { photoMaxHeight + 106 }
    static let ropeTop: CGFloat = 10
    static let pinAbove: CGFloat = 9.5
    /// Distance from the top of a hanging view, the clip, to its card.
    static let cardBelowTop: CGFloat = 26 - 12
    /// The tag's width, and how tall its five tools stand without a clip.
    static let tagWidth: CGFloat = 26
    static let compactToolsHeight: CGFloat = 5 * 22 + 2

    /// How far below the menu bar the line hangs, in points, from dragging
    /// the grip on its tag. 0 is right under the menu bar, where it always
    /// hung. A screen without room for it gets it as low as fits; see
    /// LinePanel.drop.
    static var drop: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "lineDrop")) }
        set { UserDefaults.standard.set(Double(max(0, newValue)), forKey: "lineDrop") }
    }

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    /// Where the photos hang from. Only a rope sags; the island holds them
    /// right under the top of the screen, a shelf and a stack a little lower.
    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        switch style {
        case .clothesline:
            guard width > 0 else { return ropeTop }
            let f = x / width
            return ropeTop + 4 * sag(width: width) * f * (1 - f)
        case .island: return ropeTop + 4
        case .shelf, .stack: return ropeTop + 14
        }
    }

    /// Photos hang `spacing` apart, centred. When there are more than the
    /// `visible` that fit: with Keep on line set, they keep their spacing,
    /// the newest stays where the last one would hang on a full line, and
    /// `scroll` brings older ones in from the left. Otherwise (a line hung
    /// on a wider screen) they move closer together so none is past the edge.
    static func x(index: Int, count: Int, width: CGFloat, visible: Int, scroll: CGFloat,
                  spread: Bool = false) -> CGFloat {
        if style == .stack { return stackX(index: index, count: count, width: width, spread: spread) }
        if Line.keepOnLine != nil && count > visible {
            let newest = width / 2 + CGFloat(visible - 1) * spacing / 2
            return newest - CGFloat(count - 1 - index) * spacing + scroll
        }
        let gaps = CGFloat(max(count - 1, 0))
        let step = gaps > 0 ? min(spacing, max(0, width - 200) / gaps) : spacing
        return width / 2 - gaps * step / 2 + CGFloat(index) * step
    }

    // MARK: The card stack

    /// Where the stack sits, near the right edge with its tag beside it.
    static func stackAnchor(width: CGFloat) -> CGFloat {
        width - cardWidth / 2 - tagWidth - 56
    }

    /// Closed, the photos lie on one another, the older ones peeking out to
    /// the left. Spread, they lay out leftwards from the newest.
    private static func stackX(index: Int, count: Int, width: CGFloat, spread: Bool) -> CGFloat {
        let anchor = stackAnchor(width: width)
        let depth = CGFloat(count - 1 - index)
        guard spread else { return anchor - min(depth, 3) * 8 }
        let room = max(0, anchor - 110)
        let step = count > 1 ? min(spacing, room / CGFloat(count - 1)) : spacing
        return anchor - depth * step
    }

    /// Deep in a closed stack, a photo is hidden under the others.
    static func buried(index: Int, count: Int, spread: Bool) -> Bool {
        style == .stack && !spread && count - 1 - index > 3
    }

    /// How much a photo leans: crooked on a rope, fanned in a closed stack,
    /// upright everywhere else.
    static func tilt(of item: Pegged, index: Int, count: Int, spread: Bool) -> Double {
        switch style {
        case .clothesline: return item.tilt
        case .stack:
            guard !spread else { return 0 }
            let fan: [Double] = [0, -5, -10, -14]
            return fan[min(count - 1 - index, 3)]
        case .shelf, .island: return 0
        }
    }

    // MARK: The tag and what holds the photos

    /// Near the right end of a rope; right after the photos on a shelf or an
    /// island; beside a stack.
    static func tagX(count: Int, width: CGFloat, visible: Int, scroll: CGFloat) -> CGFloat {
        switch style {
        case .clothesline:
            return width - 64
        case .stack:
            return stackAnchor(width: width) + cardWidth / 2 + 22 + tagWidth / 2
        case .shelf, .island:
            guard count > 0 else { return width / 2 }
            let last = x(index: count - 1, count: count, width: width, visible: visible, scroll: scroll)
            return min(last + cardWidth / 2 + 14 + tagWidth / 2, width - 40)
        }
    }

    /// The glass shelf or the island behind the photos and the tag, in the
    /// line view's coordinates. Nil for the other styles.
    static func holder(count: Int, width: CGFloat, visible: Int, scroll: CGFloat) -> CGRect? {
        guard count > 0, style == .shelf || style == .island else { return nil }
        let first = x(index: 0, count: count, width: width, visible: visible, scroll: scroll)
        let tag = tagX(count: count, width: width, visible: visible, scroll: scroll)
        let left = max(12, first - cardWidth / 2 - 14)
        let right = min(width - 12, tag + tagWidth / 2 + 14)
        let cardTop = ropeY(x: first, width: width) - pinAbove + cardBelowTop
        let tallest = max(photoMaxHeight + Frame.inset * 2, compactToolsHeight)
        let top = style == .island ? 0 : cardTop - 14
        return CGRect(x: left, y: top, width: right - left, height: cardTop + tallest + 14 - top)
    }
}

struct LineView: View {
    @ObservedObject var line: Line
    /// Reduce Motion: the line fades in and out instead of sliding, and
    /// photos move without springs.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Moved down with its grip, the strip reaches up to the menu bar
            // and the line hangs this far below its top.
            let drop = max(0, geo.size.height - Layout.panelHeight)
            // Files being dragged here take a place of their own, where the
            // newest photo hangs, and the others make room for it.
            let count = line.items.count + (line.dropping ? 1 : 0)
            let tucked: CGFloat = line.revealed || reduceMotion ? 0 : -(drop + Layout.panelHeight + 12)
            ZStack(alignment: .topLeading) {
                holder(width: width, count: count)

                if line.items.isEmpty && !line.dropping {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 34)
                        .transition(.opacity)
                }

                ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                    photo(item, index: index, count: count, width: width)
                }

                if line.dropping {
                    let x = Layout.x(index: count - 1, count: count, width: width,
                                     visible: line.visibleCount, scroll: line.scroll, spread: line.spread)
                    let top = Layout.ropeY(x: x, width: width) - Layout.pinAbove + PeggedView.cardOffsetBelowTop
                    DropSlot(over: line.dropOver)
                        .position(x: x, y: top + DropSlot.height / 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    DropHint()
                        .fixedSize()
                        .position(x: min(max(x, 160), width - 160), y: top + DropSlot.height + 22)
                        .transition(.opacity)
                }

                if line.style == .stack, !line.spread, line.liveCount > 1 {
                    StackBadge(count: line.liveCount)
                        .position(x: Layout.stackAnchor(width: width) + Layout.cardWidth / 2 - 6,
                                  y: Layout.ropeY(x: 0, width: width) - Layout.pinAbove + PeggedView.cardOffsetBelowTop + 4)
                        .transition(.scale.combined(with: .opacity))
                }

                // The tag hangs near the right end, past where the photos
                // reach and before the line fades out.
                let tagX = Layout.tagX(count: count, width: width, visible: line.visibleCount, scroll: line.scroll)
                LineTag(line: line, style: line.style)
                    .frame(width: LineTag.width, height: LineTag.maxHeight, alignment: .top)
                    .position(x: tagX, y: Layout.ropeY(x: tagX, width: width) - Layout.pinAbove + LineTag.maxHeight / 2)
            }
            .animation(Motion.spring(response: 0.55, damping: 0.78, reduced: reduceMotion), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            .animation(Motion.spring(response: 0.42, damping: 0.8, reduced: reduceMotion), value: line.spread)
            .animation(Motion.spring(response: 0.5, damping: 0.85, reduced: reduceMotion), value: line.style)
            .animation(Motion.spring(response: 0.42, damping: 0.8, reduced: reduceMotion), value: line.dropping)
            .animation(.easeOut(duration: 0.15), value: line.dropOver)
            .padding(.top, drop)
            // Tucked away, the whole line waits above the top edge and slides
            // out from under the menu bar, the way an auto-hiding Dock does.
            .offset(y: tucked)
            .opacity(line.revealed || !reduceMotion ? 1 : 0)
            .animation(revealAnimation, value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
        .onPreferenceChange(TagRectKey.self) { rect in
            line.tagRect = rect
        }
    }

    private var revealAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        return line.revealed ? .spring(response: 0.42, dampingFraction: 0.82) : .easeIn(duration: 0.22)
    }

    /// What the photos hang on: the rope, the glass shelf or the island.
    /// A stack has nothing behind it.
    @ViewBuilder
    private func holder(width: CGFloat, count: Int) -> some View {
        switch line.style {
        case .clothesline:
            Rope(width: width)
        case .shelf, .island:
            if let frame = Layout.holder(count: count, width: width,
                                         visible: line.visibleCount, scroll: line.scroll) {
                Group {
                    if line.style == .shelf { GlassShelf() } else { Island() }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
            }
        case .stack:
            EmptyView()
        }
    }

    private func photo(_ item: Pegged, index: Int, count: Int, width: CGFloat) -> some View {
        let spread = line.spread
        let x: CGFloat = Layout.x(index: index, count: count, width: width,
                                  visible: line.visibleCount, scroll: line.scroll, spread: spread)
        let ropeY: CGFloat = Layout.ropeY(x: x, width: width)
        let height: CGFloat = Layout.panelHeight - ropeY
        let buried = Layout.buried(index: index, count: count, spread: spread)
        // Photos scrolled towards an edge fade out before they reach it.
        let fade: CGFloat = buried ? 0 : min(1, max(0, min(x, width - x) / 90))
        return PeggedView(item: item, line: line,
                          tilt: Layout.tilt(of: item, index: index, count: count, spread: spread),
                          swings: line.style.swings)
            .frame(width: Layout.cardWidth, height: height, alignment: .top)
            .opacity(fade)
            .allowsHitTesting(!buried)
            .position(x: x, y: ropeY - Layout.pinAbove + height / 2)
    }
}

/// The shelf: a pane of Liquid Glass the photos stand on, as the Dock does
/// on macOS 26; frosted glass before it.
private struct GlassShelf: View {
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

/// The island: black, hanging from the top of the screen like the notch
/// grown wide, with rounded shoulders where it meets the menu bar.
private struct Island: View {
    var body: some View {
        IslandShape()
            .fill(Color.black)
            .overlay(
                IslandShape()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

private struct IslandShape: Shape {
    var shoulder: CGFloat = 12
    var radius: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - shoulder, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + shoulder),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + shoulder, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// How many photos a closed stack holds, on its top corner.
private struct StackBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.red, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where files dragged to the line will hang: a card's outline, which turns
/// to the accent while they are over the line, as a place to drop does.
private struct DropSlot: View {
    let over: Bool

    static var height: CGFloat { (Layout.photoMaxHeight * 0.72).rounded() + Frame.inset * 2 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Frame.radius, style: .continuous) }

    var body: some View {
        Color.clear
            .frame(width: Layout.cardWidth - 14 + Frame.inset * 2, height: Self.height)
            .glassFrame(cornerRadius: Frame.radius)
            .overlay(
                shape.strokeBorder(over ? Color.accentColor : Color.secondary.opacity(0.7),
                                   style: StrokeStyle(lineWidth: over ? 2 : 1.5, dash: [6, 4]))
            )
            .overlay(
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(over ? Color.accentColor : Color.secondary)
            )
            .scaleEffect(over ? 1.04 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What letting go does: the photos and PDFs hang, their private details
/// covered when that is chosen.
private struct DropHint: View {
    var body: some View {
        let covers = PrivateDetails.hidden
        Label {
            Text(covers ? L("Drop here – private details get covered") : L("Drop here to hang it"))
        } icon: {
            Image(systemName: covers ? "lock.fill" : "arrow.down")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .controlGlass(capsule: true)
        .allowsHitTesting(false)
    }
}

private struct Hint: View {
    var body: some View {
        Text(L("Take a screenshot and it will hang here"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .controlGlass(capsule: true)
    }
}

/// A thin, neutral line: a mid gray core with a faint highlight and a soft
/// shadow, so it reads on light and dark backgrounds alike. It fades out at
/// both ends so it seems to come from beyond the screen.
struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TagRectKey: PreferenceKey {
    static var defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = value.union(nextValue())
    }
}
