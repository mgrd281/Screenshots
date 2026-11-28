import SwiftUI

// The drawing at the top of the Pro screen, on the Mac and the iPhone alike:
// Snapfly's line with three cards on its clips, the receipt, the locked
// feature and a recording, and a green seal with a lock pinned to the middle
// card. The cards hang in, sway a little, and when Pro is bought the lock
// opens and the line answers with one swing. Drawn with shapes in the
// colours each app passes, so it fits light and dark and shows no one's
// details.

/// The colours the Pro hero is drawn in: each app passes its own.
struct ProHeroPalette {
    /// The stage's fill.
    var stage: Color
    /// The stage's 1 pt edge.
    var stageEdge: Color
    /// The line.
    var line: Color
    /// The clips.
    var clip: Color
    /// The receipt and the middle card.
    var paper: Color
    /// Printed lines on paper.
    var paperLine: Color
    /// Bold print, and the cover over a private detail.
    var ink: Color
    /// Marks drawn on the photo, and the feature's symbol.
    var mark: Color
    /// The feature symbol's tile, and the photo's field.
    var markSoft: Color
    /// The recording card.
    var screen: Color
    /// The seal's upper end.
    var sealTop: Color
    /// The seal's lower end (the same as `sealTop` on the Mac).
    var sealBottom: Color
    /// The ring that separates the seal from the card.
    var sealRing: Color
    /// The black opacity of the cards' one shadow.
    var shadow: Double
}

/// The Pro screen's motion graphic. It plays once each time it appears: the
/// line draws in from the reading side, the cards hang on it in reading
/// order, the seal grows in under the middle card, and then the cards sway.
/// With `still` everything is simply at rest. Hidden from VoiceOver; the
/// screen's words say what it shows.
struct ProHero: View {
    let palette: ProHeroPalette
    /// The locked feature, shown on the middle card; without one, a photo
    /// with marks drawn on it.
    let feature: Plan.ProFeature?
    /// The lock opens when this turns true.
    let unlocked: Bool
    /// Reduce Motion, Low Power and captures: at rest at once, nothing moves.
    let still: Bool
    let cornerRadius: CGFloat
    /// The Mac draws its own stage round the hero, so it passes false.
    let drawsStage: Bool

    /// The reading direction, read before the drawing is laid out from the
    /// left: it sets where the line starts and the order the cards come in.
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var drawn: Bool
    @State private var hung: Bool
    @State private var sealed: Bool
    @State private var isOpen: Bool
    /// When the sway began; nil while the cards hang still.
    @State private var swayFrom: Date? = nil
    /// Counts the unlocks, for the line's one swing.
    @State private var swings = 0
    /// Counts the unlocks, for the lock's one bounce.
    @State private var bounces = 0

    init(palette: ProHeroPalette, feature: Plan.ProFeature? = nil, unlocked: Bool = false, still: Bool = false,
         cornerRadius: CGFloat = 32, drawsStage: Bool = true) {
        self.palette = palette
        self.feature = feature
        self.unlocked = unlocked
        self.still = still
        self.cornerRadius = cornerRadius
        self.drawsStage = drawsStage
        _drawn = State(initialValue: still)
        _hung = State(initialValue: still)
        _sealed = State(initialValue: still)
        _isOpen = State(initialValue: unlocked)
    }

    var body: some View {
        let leftToRight = layoutDirection != .rightToLeft
        GeometryReader { space in
            drawing(leftToRight: leftToRight)
                .frame(width: ProHeroGeometry.canvas.width, height: ProHeroGeometry.canvas.height)
                .scaleEffect(ProHeroGeometry.scale(toFit: space.size))
                .frame(width: space.size.width, height: space.size.height)
        }
        .modifier(HeroStage(palette: palette, cornerRadius: cornerRadius, drawn: drawsStage))
        .accessibilityHidden(true)
        .task { await enter() }
        .onDisappear { reset() }
        .onChange(of: unlocked) { _, now in unlock(now) }
        .onChange(of: still) { _, now in calm(now) }
    }

    // MARK: The drawing

    /// The line behind, the cards on it, the middle one in front; laid out
    /// from the left in every language, as a picture is.
    private func drawing(leftToRight: Bool) -> some View {
        let swaying = !still && swayFrom != nil
        return ZStack {
            line(leftToRight: leftToRight)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !swaying)) { context in
                ZStack {
                    hanging(.receipt, leftToRight: leftToRight, at: context.date,
                            card: ReceiptCard(palette: palette))
                    hanging(.recording, leftToRight: leftToRight, at: context.date,
                            card: RecordingCard(palette: palette))
                    hanging(.middle, leftToRight: leftToRight, at: context.date,
                            card: MiddleCard(palette: palette, feature: feature, direction: layoutDirection,
                                             isOpen: isOpen, sealed: sealed, bounces: bounces, still: still))
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The line, drawn in from the side the language is read from.
    private func line(leftToRight: Bool) -> some View {
        let shown: CGFloat = drawn ? 1 : 0
        return ProHeroGeometry.line
            .trim(from: leftToRight ? 0 : 1 - shown, to: leftToRight ? shown : 1)
            .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .opacity(drawn ? 1 : 0)
            .animation(still ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5).delay(0.05), value: drawn)
    }

    /// A card on its clip, with its place in the reading order: when it
    /// hangs in, how it sways, and when it swings as the lock opens.
    private func hanging<Card: View>(_ place: ProHeroGeometry.Place, leftToRight: Bool, at date: Date,
                                     card: Card) -> Hanging<Card> {
        let order = leftToRight ? place.rawValue : 2 - place.rawValue
        // Cards swing the way the line is read, mirrored right to left.
        let side: Double = leftToRight ? 1 : -1
        let sway = still ? 0 : ProHeroGeometry.sway(since: swayFrom, at: date, phase: ProHeroGeometry.phases[order])
        return Hanging(place: place, entering: 16 * side, sway: sway, kick: 6 * side,
                       kickDelay: 0.04 * Double(order + 1), kicks: swings, hung: hung,
                       delay: 0.18 + 0.11 * Double(order), still: still,
                       clip: palette.clip, shadow: palette.shadow, card: card)
    }

    // MARK: Motion

    /// Plays the entrance from the start, then lets the cards sway.
    private func enter() async {
        if still {
            rest()
            return
        }
        // Each part carries its own animation and delay.
        drawn = true
        hung = true
        sealed = true
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        guard !Task.isCancelled, !still, hung, swayFrom == nil else { return }
        swayFrom = Date()
    }

    /// Everything where it rests, at once.
    private func rest() {
        quietly {
            drawn = true
            hung = true
            sealed = true
            swayFrom = nil
        }
    }

    /// Back to the start, so the entrance plays again when it next appears.
    private func reset() {
        quietly {
            swayFrom = nil
            if !still {
                drawn = false
                hung = false
                sealed = false
            }
        }
    }

    /// Reduce Motion or Low Power came on or went off while it shows.
    private func calm(_ now: Bool) {
        if now {
            quietly {
                rest()
                isOpen = unlocked
            }
        } else if hung, swayFrom == nil {
            swayFrom = Date()
        }
    }

    /// The lock opens: its symbol is replaced and bounces once, and the
    /// cards answer with one swing.
    private func unlock(_ now: Bool) {
        guard now != isOpen else { return }
        if still {
            quietly { isOpen = now }
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { isOpen = now }
        if now {
            bounces += 1
            swings += 1
        }
    }

    /// A change that no animation in the drawing picks up.
    private func quietly(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

// MARK: Geometry

/// The hero's drawing in its own units: 340 by 220, scaled to fit the room.
private enum ProHeroGeometry {
    static let canvas = CGSize(width: 340, height: 220)

    /// The line, from end to end, sagging toward its control point.
    static let lineStart = CGPoint(x: 14, y: 18)
    static let lineControl = CGPoint(x: 170, y: 38)
    static let lineEnd = CGPoint(x: 326, y: 18)

    /// How far a card's top hangs under its clip's centre.
    static let drop: CGFloat = 4

    /// How far above its place a card starts as it hangs in.
    static let rise: CGFloat = 56

    /// The sway: how far, how slow, and how long it takes to reach its full
    /// width, so that it never jumps.
    static let swayAmplitude = 1.1
    static let swayPeriod = 5.6
    static let swayEaseIn = 0.8
    /// Where each card is in its sway, by its place in the reading order.
    static let phases = [0, 1.9, 3.7]

    /// The three cards, from the left.
    enum Place: Int {
        case receipt, middle, recording

        /// Where its clip is along the line.
        var x: CGFloat {
            switch self {
            case .receipt: 86
            case .middle: 170
            case .recording: 260
            }
        }

        var size: CGSize {
            switch self {
            case .receipt: CGSize(width: 78, height: 102)
            case .middle: CGSize(width: 112, height: 140)
            case .recording: CGSize(width: 86, height: 66)
            }
        }

        /// How it leans when it rests, in degrees.
        var rest: Double {
            switch self {
            case .receipt: -6
            case .middle: 0
            case .recording: 7
            }
        }

        /// Its clip, on the line.
        var pivot: CGPoint { ProHeroGeometry.onLine(atX: x) }
    }

    static var line: Path {
        var path = Path()
        path.move(to: lineStart)
        path.addQuadCurve(to: lineEnd, control: lineControl)
        return path
    }

    /// Where the line passes above a given x: the curve solved for its
    /// parameter, so each clip sits exactly on it.
    static func onLine(atX x: CGFloat) -> CGPoint {
        let a = lineStart.x - 2 * lineControl.x + lineEnd.x
        let b = 2 * (lineControl.x - lineStart.x)
        let c = lineStart.x - x
        let t: CGFloat
        if abs(a) < 0.0001 {
            t = -c / b
        } else {
            t = (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
        }
        let u = 1 - t
        return CGPoint(x: x, y: u * u * lineStart.y + 2 * u * t * lineControl.y + t * t * lineEnd.y)
    }

    /// A point of the drawing as a share of it, to turn a card about its clip.
    static func anchor(of point: CGPoint) -> UnitPoint {
        UnitPoint(x: point.x / canvas.width, y: point.y / canvas.height)
    }

    /// The one scale that fits the drawing into the room, whole.
    static func scale(toFit size: CGSize) -> CGFloat {
        max(0, min(size.width / canvas.width, size.height / canvas.height))
    }

    /// How far a card has turned in its sway, in degrees, a while after it
    /// began; its width eases in from nothing.
    static func sway(since start: Date?, at date: Date, phase: Double) -> Double {
        guard let start else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(start))
        let ramp = min(1, elapsed / swayEaseIn)
        let width = swayAmplitude * ramp * ramp * (3 - 2 * ramp)
        return width * sin(2 * Double.pi * (elapsed + phase) / swayPeriod)
    }

    /// The arrow on the photo, pointing at the marked sun: a shaft and an
    /// open head, in the photo's own units.
    static var arrow: Path {
        let start = CGPoint(x: 22, y: 74), tip = CGPoint(x: 47, y: 51)
        let angle = atan2(Double(tip.y - start.y), Double(tip.x - start.x))
        let head = 7.0, spread = Double.pi / 6
        let left = CGPoint(x: Double(tip.x) - head * cos(angle + spread), y: Double(tip.y) - head * sin(angle + spread))
        let right = CGPoint(x: Double(tip.x) - head * cos(angle - spread), y: Double(tip.y) - head * sin(angle - spread))
        var path = Path()
        path.move(to: start)
        path.addLine(to: tip)
        path.move(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
        return path
    }
}

// MARK: The stage

/// The rounded stage the hero stands on, which also keeps the cards inside
/// it as they hang in; the Mac draws its own instead.
private struct HeroStage: ViewModifier {
    let palette: ProHeroPalette
    let cornerRadius: CGFloat
    let drawn: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if drawn {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(palette.stage, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.stageEdge, lineWidth: 1))
        } else {
            content
        }
    }
}

// MARK: A card on the line

/// One card with its clip, turning about the clip where it grips the line:
/// it drops in from above with a swing, sways, and swings once more when
/// the lock opens. The card casts one shadow; the clip none.
private struct Hanging<Card: View>: View {
    let place: ProHeroGeometry.Place
    /// The extra turn it comes in with, in degrees.
    let entering: Double
    /// Its sway at this moment, in degrees.
    let sway: Double
    /// How far it swings as the lock opens, in degrees.
    let kick: Double
    let kickDelay: Double
    let kicks: Int
    let hung: Bool
    let delay: Double
    let still: Bool
    let clip: Color
    let shadow: Double
    let card: Card

    var body: some View {
        let pivot = place.pivot
        let size = place.size
        let anchor = ProHeroGeometry.anchor(of: pivot)
        let kick = self.kick
        let kickDelay = self.kickDelay
        ZStack {
            card
                .frame(width: size.width, height: size.height)
                .compositingGroup()
                .shadow(color: .black.opacity(shadow), radius: 8, y: 4)
                .position(x: pivot.x, y: pivot.y + ProHeroGeometry.drop + size.height / 2)
            Capsule()
                .fill(clip)
                .frame(width: 7, height: 15)
                .position(pivot)
        }
        .frame(width: ProHeroGeometry.canvas.width, height: ProHeroGeometry.canvas.height)
        .rotationEffect(.degrees(hung ? place.rest : place.rest + entering), anchor: anchor)
        .rotationEffect(.degrees(sway), anchor: anchor)
        .keyframeAnimator(initialValue: 0.0, trigger: kicks) { layer, turn in
            layer.rotationEffect(.degrees(turn), anchor: anchor)
        } keyframes: { _ in
            LinearKeyframe(0.0, duration: kickDelay)
            SpringKeyframe(kick, duration: 0.24, spring: Spring(response: 0.42, dampingRatio: 0.72))
            SpringKeyframe(0.0, spring: Spring(response: 0.42, dampingRatio: 0.72))
        }
        .offset(y: hung ? 0 : -ProHeroGeometry.rise)
        .opacity(hung ? 1 : 0)
        .animation(still ? nil : .spring(response: 0.42, dampingFraction: 0.72).delay(delay), value: hung)
    }
}

// MARK: The cards

/// Card A, a receipt: the shop, three lines with the middle one covered,
/// and the total.
private struct ReceiptCard: View {
    let palette: ProHeroPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(palette.ink).frame(width: 34, height: 6)
            Capsule().fill(palette.paperLine).frame(height: 4).padding(.top, 8)
            Capsule().fill(palette.ink).frame(width: 42, height: 7).padding(.top, 6)
            Capsule().fill(palette.paperLine).frame(height: 4).padding(.top, 6)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Capsule().fill(palette.paperLine).frame(width: 20, height: 4)
                Spacer(minLength: 0)
                Capsule().fill(palette.ink).frame(width: 24, height: 6)
            }
        }
        .padding(9)
        .frame(width: 78, height: 102)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Card B, in the middle: the locked feature, or a photo with marks drawn
/// on it, and the seal pinned under it.
private struct MiddleCard: View {
    let palette: ProHeroPalette
    let feature: Plan.ProFeature?
    /// The reading direction, so that the feature's symbol turns round as it
    /// does in the screen's list of features.
    let direction: LayoutDirection
    let isOpen: Bool
    let sealed: Bool
    let bounces: Int
    let still: Bool

    var body: some View {
        ZStack {
            if let feature {
                // The tile sits a little above the middle, clear of the seal.
                VStack(spacing: 0) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(palette.mark)
                        .environment(\.layoutDirection, direction)
                        .frame(width: 54, height: 54)
                        .background(palette.markSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    Capsule().fill(palette.ink.opacity(0.8)).frame(width: 64, height: 5).padding(.top, 10)
                    Capsule().fill(palette.paperLine).frame(width: 44, height: 4).padding(.top, 7)
                }
                .padding(.top, 23)
                .frame(width: 112, height: 140, alignment: .top)
            } else {
                MarkedPhoto(palette: palette)
            }
        }
        .frame(width: 112, height: 140)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            Seal(palette: palette, isOpen: isOpen, bounces: bounces, still: still)
                .scaleEffect(sealed ? 1 : 0.6)
                .opacity(sealed ? 1 : 0)
                .animation(still ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(0.6), value: sealed)
                .position(x: 56, y: 142)
        }
    }
}

/// The photo on the middle card without a feature: hills under a sky, the
/// sun marked with a dashed box and an arrow, as Draw and Crop would.
private struct MarkedPhoto: View {
    let palette: ProHeroPalette

    var body: some View {
        ZStack {
            palette.markSoft
            Ellipse()
                .fill(palette.mark.opacity(0.3))
                .frame(width: 120, height: 84)
                .position(x: 74, y: 120)
            Ellipse()
                .fill(palette.mark.opacity(0.5))
                .frame(width: 110, height: 70)
                .position(x: 14, y: 124)
            Circle()
                .fill(palette.paper.opacity(0.8))
                .frame(width: 14, height: 14)
                .position(x: 70, y: 30)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(palette.mark, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 36, height: 32)
                .position(x: 70, y: 30)
            ProHeroGeometry.arrow
                .stroke(palette.mark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 98, height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Card C, a recording: a play button, a dashed zoom frame and how far it
/// has played.
private struct RecordingCard: View {
    let palette: ProHeroPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                .frame(width: 22, height: 15)
                .position(x: 67, y: 15.5)
            // A triangle looks centred a point to the right of its box.
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .position(x: 44, y: 30)
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 70, height: 3)
                .position(x: 43, y: 56.5)
            Capsule()
                .fill(palette.mark)
                .frame(width: 28, height: 3)
                .position(x: 22, y: 56.5)
        }
        .frame(width: 86, height: 66)
        .background(palette.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The seal: a lock on a green disc, ringed to stand off the card. It opens
/// once Pro is bought.
private struct Seal: View {
    let palette: ProHeroPalette
    let isOpen: Bool
    let bounces: Int
    let still: Bool

    var body: some View {
        Image(systemName: isOpen ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(still ? ContentTransition.identity : ContentTransition.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: bounces)
            .frame(width: 54, height: 54)
            .background(LinearGradient(colors: [palette.sealTop, palette.sealBottom],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .padding(3.5)
            .background(palette.sealRing, in: Circle())
    }
}
