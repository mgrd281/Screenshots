import SwiftUI

/// The first thing a new owner sees: a made-up contact card with a name, a
/// phone number, an email and an IBAN, read by a green line and then covered
/// one detail after another, the way Snapfly covers a real screenshot. It
/// plays once as it shows, again on a tap, and is shown at rest with Reduce
/// Motion. Its details belong to no one.
struct CoverDemo: View {
    /// How many of the four details are covered so far.
    @State private var covered = 0
    /// All four covered and the summary shown.
    @State private var done = false
    /// Each reading of the card, for the green line.
    @State private var readings = 0
    /// Each play, the first as it shows and one more for every tap.
    @State private var plays = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    /// One detail after another (`stagger.demo`), each grown in this long.
    private static let stagger = 0.18
    private static let growth = 0.32

    var body: some View {
        VStack(spacing: 16) {
            Button { plays += 1 } label: { card }
                .buttonStyle(.plain)
                .accessibilityLabel(L("A sample screenshot: its name, phone number, email and IBAN are covered one after another."))
                .accessibilityHint(L("Plays the example again."))
            summary
        }
        .background {
            // The soft green the stacked photos sit on.
            Ellipse()
                .fill(SnapflyTokens.surface)
                .frame(width: 300, height: 190)
                .blur(radius: 18)
                .accessibilityHidden(true)
        }
        .task(id: plays) { try? await play() }
        .sensoryFeedback(trigger: done) { _, now in now ? .success : nil }
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "person.fill").font(.footnote).foregroundStyle(.secondary))
                detail(Text(verbatim: "Erika Mustermann").font(.headline), turn: 1)
            }
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.primary.opacity(0.10)).frame(width: 170, height: 6)
                Capsule().fill(Color.primary.opacity(0.10)).frame(width: 120, height: 6)
            }
            row("phone.fill", Text(verbatim: "+49 151 23456789"), turn: 2)
            row("envelope.fill", Text(verbatim: "erika@example.com"), turn: 3)
            row("creditcard.fill", Text(verbatim: "DE89 3704 0044 0532 0130 00"), turn: 4)
            Capsule().fill(Color.primary.opacity(0.10)).frame(width: 140, height: 6)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(maxWidth: 300)
        .background(SnapflyTokens.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .overlay { if !reduceMotion { ReadingLine(trigger: readings) } }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func row(_ symbol: String, _ value: Text, turn: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            detail(value.font(.subheadline.monospacedDigit()), turn: turn)
        }
    }

    /// A private detail, and the cover that grows over it from the reading
    /// side when its turn comes.
    private func detail(_ text: Text, turn: Int) -> some View {
        text
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay {
                GeometryReader { place in
                    // The covers of the drawn pictures: plain to see on the card, light or dark.
                    RoundedRectangle(cornerRadius: min(place.size.height / 4, 8), style: .continuous)
                        .fill(Color.primary.opacity(0.85))
                        .padding(-3)
                        .scaleEffect(x: covered >= turn ? 1 : 0.001, anchor: direction == .rightToLeft ? .trailing : .leading)
                        .opacity(covered >= turn ? 1 : 0)
                }
            }
    }

    // MARK: The summary

    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(SnapflyTokens.protect)
                .symbolEffect(.bounce.up, options: .nonRepeating, value: done)
            Text(L("Name, phone number, email and IBAN covered."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: 300)
        .opacity(done ? 1 : 0)
        .offset(y: done || reduceMotion ? 0 : 8)
        .accessibilityHidden(!done)
    }

    // MARK: Playing

    /// Clears the card, reads it with the green line, covers the four
    /// details in turn, then says what was covered.
    private func play() async throws {
        if reduceMotion {
            covered = 4
            done = true
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            covered = 0
            done = false
        }
        try await Task.sleep(for: .milliseconds(plays == 0 ? 450 : 250))
        readings += 1
        try await Task.sleep(for: .milliseconds(900))
        for turn in 1...4 {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: Self.growth)) { covered = turn }
            try await Task.sleep(for: .seconds(Self.stagger))
        }
        try await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { done = true }
    }
}

/// A green line that reads its view once, top to bottom, each time its
/// trigger changes (`sweep.scan`), brightest in its middle.
private struct ReadingLine: View {
    let trigger: Int

    private struct Sweep {
        var progress: CGFloat = 0
        var opacity = 0.0
    }

    var body: some View {
        GeometryReader { place in
            Capsule()
                .fill(LinearGradient(colors: [SnapflyTokens.protect.opacity(0), SnapflyTokens.protect, SnapflyTokens.protect.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 2.5)
                .shadow(color: SnapflyTokens.protect.opacity(0.7), radius: 5)
                .keyframeAnimator(initialValue: Sweep(), trigger: trigger) { line, sweep in
                    line.offset(y: sweep.progress * place.size.height).opacity(sweep.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.progress) {
                        LinearKeyframe(0.02, duration: 0.01)
                        CubicKeyframe(0.98, duration: 0.9)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.15)
                        LinearKeyframe(1, duration: 0.55)
                        LinearKeyframe(0, duration: 0.2)
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
