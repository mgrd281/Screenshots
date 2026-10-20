import SwiftUI
import UIKit
import VisionKit

// MARK: Whether it shows

/// Whether the first run shows, and what follows it. It shows once, when
/// Snapfly first opens, and once more only if a newer first run comes;
/// again from Settings › Help & Introduction whenever the owner wants.
@MainActor
final class FirstRunCoordinator: ObservableObject {
    static let shared = FirstRunCoordinator()

    /// A newer first run shows once more; an ordinary update shows none.
    static let version = 1
    private static let key = "firstRunSeen"

    /// When Snapfly started, to measure how soon the first run shows.
    static let launched = Date()

    @Published private(set) var showing: Bool

    private init() {
        showing = UserDefaults.standard.integer(forKey: Self.key) < Self.version || Self.frozenMoment != nil
    }

    /// From Settings: shown again, from its start.
    func replay() {
        withAnimation(.easeOut(duration: 0.25)) { showing = true }
    }

    /// Closed, skipped or tried: seen, and not shown at launch again. Try
    /// It Now opens the real scanner where the iPhone has one, else the
    /// screenshots.
    func finish(trying: Bool) {
        UserDefaults.standard.set(Self.version, forKey: Self.key)
        withAnimation(.easeOut(duration: 0.3)) { showing = false }
        guard trying else { return }
        if VNDocumentCameraViewController.isSupported {
            AppTabs.shared.selection = .scan
            AppTabs.shared.scanRequested = true
        } else {
            AppTabs.shared.selection = .photos
        }
    }

    #if DEBUG
    /// For screenshots made in CI: the story held at a moment, in seconds,
    /// as `-SnapflyFirstRunAt 1.9` asks.
    static let frozenMoment: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SnapflyFirstRunAt"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }()
    #else
    static let frozenMoment: Double? = nil
    #endif
}

// MARK: The first run

/// The first run (`FirstRun`): in under fifteen seconds a made-up invoice
/// is read, its name, email and IBAN covered while its amount stays, the
/// categories are the owner's to turn on and off, a page is scanned,
/// straightened and covered, and the protected copy is ready to share; then
/// Try It Now opens the real scanner. One page moves through it all.
/// Skip Demo leaves at any time. A tap on a category, or on a detail, turns
/// it, and the story waits while the owner tries. With Reduce Motion or Low
/// Power Mode things cross-fade instead of moving; with VoiceOver it starts
/// at its end, the invoice described as it is.
struct SnapflyFirstRunExperience: View {
    @ObservedObject private var coordinator = FirstRunCoordinator.shared
    @State private var state = FirstRun.State()
    /// The app is in front; the story waits while it is not.
    @State private var active = true
    /// The owner's last touch, so the story waits while they try.
    @State private var touched: Date?
    @State private var shownAt: Date?
    /// The page's height, for the scanner's perspective.
    @State private var paperHeight: CGFloat = 0
    /// Haptics: protected, the page's edges found, a category turned.
    @State private var protections = 0
    @State private var locks = 0
    @State private var taps = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// Cross-fades instead of movement.
    private var calm: Bool { reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled }

    var body: some View {
        GeometryReader { space in
            let width = min(space.size.width - 56, 340)
            ScrollView {
                VStack(spacing: 0) {
                    words
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
                    Spacer(minLength: 12)
                    stage(width: width)
                    Spacer(minLength: 12)
                    lower
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 108)
                    actions
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, minHeight: space.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await play() }
        .onChange(of: scenePhase) { _, phase in active = phase == .active }
        .sensoryFeedback(.success, trigger: protections)
        .sensoryFeedback(.impact(weight: .light), trigger: locks)
        .sensoryFeedback(.selection, trigger: taps)
    }

    // MARK: The words

    /// What each scene says, short: the reveal, the owner's control, the
    /// scanner, sharing, and at the end what Snapfly is for.
    static func headline(of scene: FirstRun.Scene) -> String {
        switch scene {
        case .reveal: L("Private stays private.")
        case .control: L("You decide what stays visible.")
        case .scan: L("Scan. Detect. Protect.")
        case .share: L("Protected. Ready to share.")
        case .complete: L("Share your documents. Not your private data.")
        }
    }

    private var words: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Text(Self.headline(of: state.scene))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if state.scene == .complete {
                    Text(L("Protect invoices, screenshots and documents before you share them."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
            .id(state.scene)
            .transition(.opacity.combined(with: .offset(y: calm ? 0 : 8)))
        }
    }

    // MARK: The page

    /// The invoice, alone at first, then before the camera, then small and
    /// ready to share.
    private func stage(width: CGFloat) -> some View {
        let scanning = state.scene == .scan
        let small = state.scene >= .share
        return ZStack {
            if scanning {
                ScanCamera(size: CGSize(width: width, height: paperHeight))
                    .transition(.opacity.combined(with: .scale(scale: calm ? 1 : 0.96)))
            }
            paper(width: width)
                .scaleEffect(small ? 0.74 : scanning ? 0.86 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func paper(width: CGFloat) -> some View {
        let edges = state.scan == .edges || state.scan == .straight
        return SampleInvoice(state: state, calm: calm,
                             interactive: state.scene >= .control && state.scene < .complete,
                             toggle: toggle)
            .frame(width: width)
            .measuredHeight($paperHeight)
            .modifier(Straightened(progress: calm || state.scan >= .straight || state.scan == .none ? 1 : 0,
                                   size: CGSize(width: width, height: paperHeight)))
            .overlay {
                // The page's edges as the scanner finds them, locking on.
                if !calm {
                    EdgeLock(straightened: state.scan >= .straight || state.scan == .none ? 1 : 0,
                             lock: state.scan >= .edges ? 1 : 0)
                        .opacity(edges ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay { if !calm { ReadingLine(trigger: state.sweeps) } }
            .overlay(alignment: .topTrailing) { shield }
            .shadow(color: .black.opacity(state.scene == .scan ? 0.3 : 0.12), radius: state.scene == .scan ? 8 : 16, y: 6)
    }

    /// The protected shield on the page's corner, white on the green.
    private var shield: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(SnapflyTokens.protect, in: Circle())
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 3))
            .symbolEffect(.bounce, options: .nonRepeating, value: state.showsShield)
            .scaleEffect(state.showsShield || calm ? 1 : 0.3)
            .opacity(state.showsShield ? 1 : 0)
            .padding(-12)
            .accessibilityHidden(true)
    }

    // MARK: Under the page

    /// The categories while the owner may turn them; where the copy can go
    /// once it is protected.
    private var lower: some View {
        ZStack {
            if state.scene == .control || state.scene == .scan {
                PrivacyChips(chosen: state.chosen, toggle: toggle)
                    .transition(.opacity.combined(with: .offset(y: calm ? 0 : 10)))
            } else if state.scene >= .share {
                ShareDestinations()
                    .transition(.opacity.combined(with: .offset(y: calm ? 0 : 14)))
            }
        }
    }

    /// Skip Demo while it plays; at its end, Try It Now over Not Now.
    private var actions: some View {
        VStack(spacing: 4) {
            if state.scene == .complete {
                Button {
                    coordinator.finish(trying: true)
                } label: {
                    Text(L("Try It Now"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(ProtectButtonStyle())
                .transition(.opacity.combined(with: .offset(y: calm ? 0 : 12)))
            }
            Button(state.scene == .complete ? L("Not Now") : L("Skip Demo")) {
                coordinator.finish(trying: false)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(minHeight: 104, alignment: .bottom)
    }

    // MARK: Playing

    /// Plays the script on the story's clock, which stands still while the
    /// owner tries the categories and while the app is away.
    private func play() async {
        let shown = Date()
        shownAt = shown
        log.info("First run shown \(Int(shown.timeIntervalSince(FirstRunCoordinator.launched) * 1000), privacy: .public) ms after launch")
        if let moment = FirstRunCoordinator.frozenMoment {
            state = FirstRun.state(at: moment)
            return
        }
        if voiceOver {
            state = FirstRun.state(at: FirstRun.completeStart)
            return
        }
        var story = 0.0
        var last = Date()
        for beat in FirstRun.script {
            while story < beat.at {
                try? await Task.sleep(for: .seconds(min(beat.at - story, 0.05)))
                if Task.isCancelled { return }
                let now = Date()
                if !held(at: now) { story += now.timeIntervalSince(last) }
                last = now
            }
            perform(beat.event)
        }
    }

    private func held(at now: Date) -> Bool {
        !active || touched.map { now.timeIntervalSince($0) < FirstRun.hold } ?? false
    }

    private func perform(_ event: FirstRun.Event) {
        withAnimation(animation(for: event)) { FirstRun.apply(event, to: &state) }
        switch event {
        case .shield(true) where state.scene == .reveal:
            protections += 1
            if let shownAt {
                log.info("First run protected \(Int(Date().timeIntervalSince(shownAt) * 1000), privacy: .public) ms after it showed")
            }
        case .scan(.edges):
            locks += 1
        case .scene(.complete):
            AccessibilityNotification.Announcement(Self.headline(of: .complete)).post()
        default:
            break
        }
    }

    private func animation(for event: FirstRun.Event) -> Animation? {
        switch event {
        case .find: SnapflyMotion.find(calm)
        case .lay, .auto: SnapflyMotion.redact(calm)
        case .shield: SnapflyMotion.success(calm)
        // The page as printed comes back as the camera sees it, without a bounce.
        case .scene(.scan): calm ? SnapflyMotion.calm : .easeOut(duration: 0.35)
        case .scene: SnapflyMotion.document(calm)
        case .scan(.edges): SnapflyMotion.lock(calm)
        case .scan: SnapflyMotion.document(calm)
        case .phase, .sweep, .settle: nil
        }
    }

    /// The owner turns a category, from its chip or its detail; the story
    /// waits while they try, and leaves the categories to them from then on.
    private func toggle(_ category: FirstRun.Category) {
        guard state.scene >= .control, state.scene < .complete else { return }
        let now = Date()
        touched = now
        taps += 1
        withAnimation(SnapflyMotion.redact(calm)) { FirstRun.toggle(category, in: &state) }
        let covered = state.chosen.contains(category)
        AccessibilityNotification.Announcement(category.title + ", " + (covered ? L("Covered") : L("Not covered"))).post()
        Task {
            try? await Task.sleep(for: .seconds(FirstRun.settle))
            if touched == now { FirstRun.apply(.settle, to: &state) }
        }
    }
}

// MARK: The invoice

/// The made-up invoice, printed like a page: white in light and dark alike
/// and left to right in every language, with its details found and covered
/// as the story says. A tap on a detail turns its category on or off.
private struct SampleInvoice: View {
    let state: FirstRun.State
    let calm: Bool
    let interactive: Bool
    let toggle: (FirstRun.Category) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(L("Invoice"))
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                Text(L("Sample"))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Divider().padding(.vertical, 14)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(FirstRun.privateFields) { field in
                    GridRow {
                        Text(field.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        value(field)
                    }
                }
            }
            Divider().padding(.vertical, 14)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(FirstRun.field(.amount).label)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: FirstRun.field(.amount).value)
                    .font(.title3.weight(.bold).monospacedDigit())
            }
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Sample invoice"))
        .accessibilityValue(summary)
    }

    /// A private detail: green corners round it once found, then the ink
    /// growing over it from the reading side, solid all the way; with
    /// Reduce Motion the ink is simply there.
    private func value(_ field: FirstRun.Field) -> some View {
        let covered = state.isCovered(field)
        let found = state.isFound(field)
        return Text(verbatim: field.value)
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay {
                ZStack {
                    Brackets()
                        .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .background(SnapflyTokens.protect.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(-5)
                        .scaleEffect(found || calm ? 1 : 1.12)
                        .opacity(found ? 1 : 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SnapflyTokens.ink)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: covered || calm ? nil : 0)
                        }
                        .opacity(calm && !covered ? 0 : 1)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle().inset(by: -8))
            .onTapGesture {
                if interactive, let category = field.category { toggle(category) }
            }
    }

    /// Each detail as it stands, for VoiceOver.
    private var summary: String {
        FirstRun.fields.map { field in
            field.label + ": " + (state.isCovered(field) ? L("Covered") : field.value)
        }
        .joined(separator: ", ")
    }
}

// MARK: The categories

/// The categories to cover on the sample, as chips: Names, Emails and Bank
/// details. On, the chip is green and its eye shut.
private struct PrivacyChips: View {
    let chosen: Set<FirstRun.Category>
    let toggle: (FirstRun.Category) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips(symbols: true) }
            HStack(spacing: 6) { chips(symbols: false) }
            VStack(spacing: 6) { chips(symbols: false) }
        }
    }

    private func chips(symbols: Bool) -> some View {
        ForEach(FirstRun.Category.allCases, id: \.self) { category in
            chip(category, on: chosen.contains(category), symbol: symbols)
        }
    }

    private func chip(_ category: FirstRun.Category, on: Bool, symbol: Bool) -> some View {
        Button {
            toggle(category)
        } label: {
            HStack(spacing: 6) {
                if symbol {
                    Image(systemName: on ? "eye.slash.fill" : "eye")
                        .font(.footnote.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? SnapflyTokens.protect : Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.1)))
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityValue(on ? L("Covered") : L("Not covered"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: The scanner

/// The camera's view as the scanner shows it: a dark frame round the page,
/// with the scan viewfinder's green corners.
private struct ScanCamera: View {
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(SnapflyTokens.ink)
            .frame(width: size.width + 8, height: max(size.height, 1) + 8)
            .overlay {
                Brackets(arm: 26)
                    .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .padding(16)
            }
            .accessibilityHidden(true)
    }
}

/// The page as the scanner sees it: lying tipped away at 0, straightened at
/// 1, along `FirstRun.corners`.
private struct Straightened: ViewModifier, Animatable {
    var progress: Double
    let size: CGSize

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.projectionEffect(Self.transform(size, progress))
    }

    private static func transform(_ size: CGSize, _ progress: Double) -> ProjectionTransform {
        guard size.width > 0, size.height > 0, progress < 1 else { return ProjectionTransform() }
        let corners = FirstRun.corners(straightened: progress).map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        let m = FirstRun.homography(size, to: corners).map { CGFloat($0) }
        var t = CATransform3DIdentity
        // Core Animation takes points as rows: the matrix, turned.
        t.m11 = m[0]; t.m21 = m[1]; t.m41 = m[2]
        t.m12 = m[3]; t.m22 = m[4]; t.m42 = m[5]
        t.m14 = m[6]; t.m24 = m[7]; t.m44 = m[8]
        return ProjectionTransform(t)
    }
}

/// The page's edges as the scanner finds them: a green outline with a dot
/// at each corner, closing in on the corners as it locks on, and following
/// them as the page is straightened.
private struct EdgeLock: View {
    var straightened: Double
    var lock: Double

    var body: some View {
        ZStack {
            EdgeShape(straightened: straightened, lock: lock, dots: false)
                .fill(SnapflyTokens.protect.opacity(0.12))
            EdgeShape(straightened: straightened, lock: lock, dots: false)
                .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            EdgeShape(straightened: straightened, lock: lock, dots: true)
                .fill(SnapflyTokens.protect)
        }
    }
}

private struct EdgeShape: Shape {
    var straightened: Double
    var lock: Double
    let dots: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(straightened, lock) }
        set {
            straightened = newValue.first
            lock = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Searching, the outline stands a little off the page; locked, on it.
        let spread = CGFloat(0.12 * (1 - lock))
        let corners = FirstRun.corners(straightened: straightened).map { corner -> CGPoint in
            let point = CGPoint(x: rect.minX + corner.x * rect.width, y: rect.minY + corner.y * rect.height)
            return CGPoint(x: point.x + (point.x - center.x) * spread, y: point.y + (point.y - center.y) * spread)
        }
        var path = Path()
        if dots {
            for corner in corners {
                path.addEllipse(in: CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8))
            }
        } else {
            path.addLines(corners)
            path.closeSubpath()
        }
        return path
    }
}

// MARK: Sharing

/// Where the protected copy can go, as the share sheet offers it: a chat
/// with an AI, a messenger, email. A picture of the idea, not a link to any
/// of them: the real share sheet comes with a real copy.
private struct ShareDestinations: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                destination("sparkles", "ChatGPT")
                destination("message.fill", "WhatsApp")
                destination("envelope.fill", L("Email"))
            }
            Text(L("Only the protected copy leaves your iPhone."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Only the protected copy leaves your iPhone."))
    }

    private func destination(_ symbol: String, _ name: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(verbatim: name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: Shared shapes

/// The four corners of a find, as the scan viewfinder draws them.
private struct Brackets: Shape {
    /// How long each corner's arms are; at most 10, or less on a small find.
    var arm: CGFloat?

    func path(in rect: CGRect) -> Path {
        let arm = arm ?? min(rect.height * 0.4, 10)
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
