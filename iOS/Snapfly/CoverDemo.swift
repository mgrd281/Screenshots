import SwiftUI

/// The first launch, before access: Snapfly at work before a word is said.
/// A made-up screenshot lands, a green line reads it, its name, phone
/// number, email and IBAN are found and then covered one after another, and
/// a shield settles on its corner. Only then do the words and Allow Access
/// rise in under it. A tap skips to the end, and on the card plays it again;
/// with Reduce Motion or VoiceOver everything is there at once.
struct WelcomeScreen: View {
    let allow: () -> Void
    /// The card has landed.
    @State private var entered = false
    /// How many details are found, and how many covered.
    @State private var found = 0
    @State private var covered = 0
    /// All four covered, and the shield on the card.
    @State private var protected = false
    /// Each reading of the card, for the green line.
    @State private var readings = 0
    /// The words under the card, then Allow Access, have risen in.
    @State private var words = false
    @State private var actions = false
    /// Each play: the first as the screen shows, then one for each tap.
    @State private var plays = 0
    /// The next play goes straight to its end.
    @State private var skipping = false
    /// Each time the shield lands, for its haptic.
    @State private var landings = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        GeometryReader { space in
            ScrollView {
                VStack(spacing: 0) {
                    Button { actions ? replay() : skip() } label: {
                        CoverDemo(found: found, covered: covered, protected: protected,
                                  readings: readings, reads: !reduceMotion)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("A sample screenshot: its name, phone number, email and IBAN are covered one after another."))
                    .accessibilityHint(L("Plays the example again."))
                    // It lands: rising and tipping up into place.
                    .rotation3DEffect(.degrees(entered ? 0 : 16), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.6)
                    .offset(y: entered ? 0 : 36)
                    .opacity(entered ? 1 : 0)
                    if words { introduction }
                    if actions { access }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: space.size.height)
                .contentShape(Rectangle())
                .onTapGesture { skip() }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .task(id: plays) { try? await play() }
        .sensoryFeedback(.success, trigger: landings)
    }

    /// What Snapfly does, once it has been seen.
    private var introduction: some View {
        VStack(spacing: 10) {
            Text(L("Covered before you send"))
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(L("Snapfly covers names, addresses and other private details in your screenshots, right on this iPhone."))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360)
        .padding(.top, 40)
        .transition(.opacity.combined(with: .offset(y: 16)))
    }

    /// Allow Access, wide, and the promise under it.
    private var access: some View {
        VStack(spacing: 14) {
            Button(action: allow) {
                Text(L("Allow Access"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(ProtectButtonStyle())
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(L("Your screenshots are read on this iPhone, and nothing leaves it unless you choose."))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340)
        .padding(.top, 32)
        .transition(.opacity.combined(with: .offset(y: 16)))
    }

    // MARK: Playing

    /// Lands the card, reads it, finds each detail as the line reaches it,
    /// covers them in turn, sets the shield on, and then, the first time,
    /// lets the words and Allow Access rise in.
    private func play() async throws {
        if skipping || reduceMotion || voiceOver {
            settle(animated: skipping && !reduceMotion)
            skipping = false
            return
        }
        if entered {
            withAnimation(.easeOut(duration: 0.2)) {
                found = 0
                covered = 0
                protected = false
            }
            try await Task.sleep(for: .milliseconds(300))
        } else {
            try await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) { entered = true }
            try await Task.sleep(for: .milliseconds(600))
        }
        readings += 1
        // Each detail is found as the line reaches it.
        for (turn, wait) in zip(1...4, [250, 245, 115, 120]) {
            try await Task.sleep(for: .milliseconds(wait))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { found = turn }
        }
        try await Task.sleep(for: .milliseconds(380))
        for turn in 1...4 {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.34)) { covered = turn }
            try await Task.sleep(for: .milliseconds(170))
        }
        try await Task.sleep(for: .milliseconds(260))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { protected = true }
        landings += 1
        guard !actions else { return }
        try await Task.sleep(for: .milliseconds(550))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { words = true }
        try await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { actions = true }
    }

    /// Everything as it ends.
    private func settle(animated: Bool) {
        let end = {
            entered = true
            found = 4
            covered = 4
            protected = true
            words = true
            actions = true
        }
        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86), end)
        } else {
            end()
        }
    }

    private func skip() {
        guard !actions else { return }
        skipping = true
        plays += 1
    }

    private func replay() {
        plays += 1
    }
}

/// The made-up screenshot: a contact as a phone shows it, with a status
/// bar, a name under its picture and three rows. Its details belong to no
/// one (a placeholder name, `example.com` and the standard example IBAN).
/// Drawn light in light and dark alike, as a screenshot is what it is, with
/// the real cover ink.
struct CoverDemo: View {
    let found: Int
    let covered: Int
    let protected: Bool
    let readings: Int
    /// Whether the green line reads it; not with Reduce Motion.
    let reads: Bool

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color(.systemGray3), in: Circle())
                    detail(Text(verbatim: "Erika Mustermann").font(.title3.weight(.semibold)), turn: 1)
                }
                VStack(spacing: 0) {
                    row("phone.fill", "+49 151 23456789", turn: 2)
                    Divider().padding(.leading, 40)
                    row("envelope.fill", "erika@example.com", turn: 3)
                    Divider().padding(.leading, 40)
                    row("creditcard.fill", "DE89 3704 0044 0532 0130 00", turn: 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .frame(maxWidth: 320)
        .background(Color(.systemBackground))
        .overlay { if reads { ReadingLine(trigger: readings) } }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .overlay(alignment: .topTrailing) { shield }
        .environment(\.colorScheme, .light)
        .background {
            // The soft green the stacked photos sit on, a little brighter once safe.
            Ellipse()
                .fill(SnapflyTokens.surface)
                .frame(width: 360, height: 280)
                .blur(radius: 30)
                .scaleEffect(protected ? 1.06 : 0.94)
                .opacity(protected ? 1 : 0.6)
                .accessibilityHidden(true)
        }
    }

    /// The time and the signal, so it reads as a screenshot.
    private var statusBar: some View {
        HStack {
            Text(verbatim: "9:41")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .accessibilityHidden(true)
    }

    private func row(_ symbol: String, _ value: String, turn: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            detail(Text(verbatim: value).font(.subheadline.monospacedDigit()), turn: turn)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    /// A private detail: green brackets round it once it is found, then
    /// the ink growing over it from the reading side, solid all the way.
    private func detail(_ text: Text, turn: Int) -> some View {
        text
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay {
                ZStack {
                    Brackets()
                        .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .background(SnapflyTokens.protect.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(-5)
                        .scaleEffect(found >= turn ? 1 : 1.12)
                        .opacity(found >= turn && covered < turn ? 1 : 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SnapflyTokens.ink)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: covered >= turn ? nil : 0)
                        }
                        .padding(-3)
                }
            }
    }

    /// The protected shield on the card's corner, white on the green.
    private var shield: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(SnapflyTokens.protect, in: Circle())
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 3))
            .symbolEffect(.bounce, options: .nonRepeating, value: protected)
            .scaleEffect(protected ? 1 : 0.3)
            .opacity(protected ? 1 : 0)
            .padding(-12)
            .accessibilityHidden(true)
    }
}

/// The four corners of a find, as the scan viewfinder draws them.
private struct Brackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.height * 0.4, 10)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        var path = Path()
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
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
