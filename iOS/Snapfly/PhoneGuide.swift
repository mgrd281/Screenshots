import SwiftUI

/// The screens the iPhone's introduction shows on.
enum PhoneGuideScreen: Equatable {
    case library, shot
}

/// What it points at.
enum PhoneGuideTarget: Hashable {
    /// The newest screenshot in the grid.
    case firstShot
    /// The ways out beside a covered screenshot: the apps, Photos, Files.
    case actions
}

/// The introduction on the iPhone, on its real screens: a screenshot to
/// tap, then the covered copy's buttons, with the screen dimmed round what
/// it points at and a card beside it. Tapping the real thing moves on;
/// Next, Back and the cross are always there, and nothing is held back
/// meanwhile. Offered once, as the first screenshots show; again from
/// Settings.
@MainActor
final class PhoneGuide: ObservableObject {
    static let shared = PhoneGuide()

    /// A newer introduction is offered once more.
    static let version = 1

    enum Step: String, CaseIterable {
        case pick, send

        var screen: PhoneGuideScreen { self == .pick ? .library : .shot }
        var target: PhoneGuideTarget { self == .pick ? .firstShot : .actions }
        var symbol: String { self == .pick ? "hand.tap" : "square.and.arrow.up" }

        var title: String {
            switch self {
            case .pick: L("Tap a screenshot")
            case .send: L("Covered and ready")
            }
        }

        var text: String {
            switch self {
            case .pick: L("Snapfly covers its private details at once, right on this iPhone.")
            case .send: L("Share it into any chat, copy it, or save the covered copy to Photos. The screenshot itself stays as it was.")
            }
        }
    }

    enum Stage: Equatable {
        case welcome
        case step(Step)
        case done

        /// Where it shows; the last card shows wherever you are.
        var screen: PhoneGuideScreen? {
            switch self {
            case .welcome: .library
            case .step(let step): step.screen
            case .done: nil
            }
        }
    }

    /// Something done on the real thing.
    enum Event {
        case openedShot
        /// Copied, shared or saved.
        case used
    }

    @Published private(set) var stage: Stage?
    /// The step was seen through: a check for a moment.
    @Published private(set) var passed = false
    /// The screen showing, so the card shows on its own screen only. Back
    /// from a screenshot before its buttons were tried, it asks for one again.
    @Published var screen = PhoneGuideScreen.library {
        didSet {
            if screen == .library, stage == .step(.send) { go(to: .pick) }
        }
    }

    /// Opens the newest screenshot, for Next on the first step; set by the
    /// grid, which knows it.
    var openNewest: (() -> Bool)?
    /// Goes back to the grid, for Back on the second step.
    var closeShot: (() -> Void)?

    private init() {}

    /// When the first screenshots show: the welcome card, once.
    func offerIfDue() {
        var progress = GuideProgress.load()
        guard stage == nil, progress.offers(version: Self.version) else { return }
        progress.version = Self.version
        progress.save()
        stage = .welcome
        announce(L("Welcome! Discover Snapfly.") + " " + L("We'll show you the most important features, right in the app and step by step."))
    }

    /// From the welcome card or Settings.
    func start() {
        var progress = GuideProgress.load()
        progress.version = max(progress.version, Self.version)
        progress.restart()
        progress.save()
        go(to: screen == .shot ? .send : .pick)
    }

    func next() {
        guard case .step(let step) = stage else { return }
        see(step)
        switch step {
        case .pick:
            // The next step is under a screenshot: the newest opens for it,
            // and the step moves on as it shows.
            if openNewest?() != true { finish() }
        case .send:
            finish()
        }
    }

    func back() {
        guard case .step(.send) = stage else { return }
        // Leaving the screenshot moves the step back as the grid shows.
        if let closeShot { closeShot() } else { go(to: .pick) }
    }

    /// The cross, or Skip for Now on the welcome card.
    func end() {
        if case .step(let step) = stage {
            var progress = GuideProgress.load()
            progress.stoppedAt = step.rawValue
            progress.save()
        }
        withAnimation(.easeOut(duration: 0.2)) { stage = nil }
    }

    func happened(_ event: Event) {
        guard case .step(let step) = stage, !passed else { return }
        switch (step, event) {
        case (.pick, .openedShot):
            see(step)
            go(to: .send)
        case (.send, .used):
            see(step)
            passed = true
            announce(L("Done."))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard self.stage == .step(.send) else { return }
                self.finish()
            }
        default:
            break
        }
    }

    /// Which step of how many.
    var place: (number: Int, count: Int)? {
        guard case .step(let step) = stage, let index = Step.allCases.firstIndex(of: step) else { return nil }
        return (index + 1, Step.allCases.count)
    }

    private func go(to step: Step) {
        passed = false
        var progress = GuideProgress.load()
        progress.stoppedAt = step.rawValue
        progress.save()
        withAnimation(.easeOut(duration: 0.2)) { stage = .step(step) }
        let number = (Step.allCases.firstIndex(of: step) ?? 0) + 1
        announce([String(format: L("Step %1$d of %2$d"), number, Step.allCases.count), step.title, step.text]
            .joined(separator: ". "))
    }

    private func finish() {
        var progress = GuideProgress.load()
        progress.finished = true
        progress.stoppedAt = nil
        progress.save()
        passed = false
        withAnimation(.easeOut(duration: 0.2)) { stage = .done }
        announce(L("You're all set") + ". " + Self.doneText)
    }

    private func see(_ step: Step) {
        var progress = GuideProgress.load()
        progress.see(step.rawValue)
        progress.save()
    }

    static var doneText: String {
        L("Choose what gets hidden in Settings, at the top of your screenshots. There, too: covering the newest screenshot with a double tap on the back of your iPhone.")
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

// MARK: - On the screens

private struct PhoneGuideAnchors: PreferenceKey {
    static var defaultValue: [PhoneGuideTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [PhoneGuideTarget: Anchor<CGRect>], nextValue: () -> [PhoneGuideTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// What the introduction may point at, when `on`.
    func phoneGuideTarget(_ target: PhoneGuideTarget, on: Bool = true) -> some View {
        anchorPreference(key: PhoneGuideAnchors.self, value: .bounds) { on ? [target: $0] : [:] }
    }

    /// The introduction's shade and card over this screen, when it shows here.
    func phoneGuide(on screen: PhoneGuideScreen) -> some View {
        overlayPreferenceValue(PhoneGuideAnchors.self) { anchors in
            GeometryReader { proxy in
                PhoneGuideLayer(guide: PhoneGuide.shared, screen: screen,
                                frames: anchors.mapValues { proxy[$0] }, size: proxy.size)
            }
        }
    }
}

/// The shade with its hole round what is pointed at, which every tap goes
/// through, and the card: beside it where there is room, else at the
/// bottom, clear of the screen's edges and the home indicator.
private struct PhoneGuideLayer: View {
    @ObservedObject var guide: PhoneGuide
    let screen: PhoneGuideScreen
    let frames: [PhoneGuideTarget: CGRect]
    let size: CGSize
    @State private var cardHeight: CGFloat = 220
    @State private var lastHole = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86)
    }

    var body: some View {
        if let stage = guide.stage, guide.screen == screen, stage.screen.map({ $0 == screen }) ?? true {
            let target = frame(for: stage)
            let hole = target.map { GuidePlacement.hole(around: $0, room: 6, corner: 12) }
            let width = min(size.width - 32, 420)
            let placed = placement(width: width, target: target)
            ZStack(alignment: .topLeading) {
                GuideShade(hole: hole?.rect ?? lastHole, corner: hole?.corner ?? 12, open: hole != nil)
                    .fill(Color.black.opacity(stage == .done ? 0.2 : 0.4), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if let hole {
                    RoundedRectangle(cornerRadius: hole.corner, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: hole.rect.width, height: hole.rect.height)
                        .offset(x: hole.rect.minX, y: hole.rect.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                PhoneGuideCard(guide: guide, stage: stage)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: PhoneCardHeight.self, value: g.size.height)
                    })
                    .offset(x: placed.minX, y: placed.minY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onPreferenceChange(PhoneCardHeight.self) { cardHeight = $0 }
            .onChange(of: hole?.rect) { _, now in if let now { lastHole = now } }
            .animation(motion, value: hole?.rect)
            .animation(motion, value: placed)
            .transition(.opacity)
        }
    }

    private func frame(for stage: PhoneGuide.Stage) -> CGRect? {
        guard case .step(let step) = stage else { return nil }
        return frames[step.target]
    }

    /// Beside what it points at when it fits there, else at the bottom.
    private func placement(width: CGFloat, target: CGRect?) -> CGRect {
        let card = CGSize(width: width, height: cardHeight)
        let area = CGRect(origin: .zero, size: size)
        if let target {
            let placed = GuidePlacement.place(card, at: target, in: area, gap: 14, margin: 16)
            if placed.side == .below || placed.side == .above { return placed.frame }
        }
        return CGRect(x: (size.width - width) / 2, y: max(16, size.height - cardHeight - 16),
                      width: width, height: cardHeight)
    }
}

private struct PhoneCardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The card, in the system's material: a symbol and a title, a line or
/// two, how far along it is, and Back and Next as small buttons on the
/// trailing side, each on one line.
private struct PhoneGuideCard: View {
    @ObservedObject var guide: PhoneGuide
    let stage: PhoneGuide.Stage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch stage {
            case .welcome:
                welcome
            case .step(let step):
                stepCard(step)
            case .done:
                done
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Welcome! Discover Snapfly."))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(L("We'll show you the most important features, right in the app and step by step."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L("Skip for Now")) { guide.end() }
                    .buttonStyle(.bordered)
                Button(L("Start Introduction")) { guide.start() }
                    .buttonStyle(.borderedProminent)
            }
            .modifier(SmallButtons())
        }
    }

    private func stepCard(_ step: PhoneGuide.Step) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                symbol(guide.passed ? "checkmark" : step.symbol)
                Text(step.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    guide.end()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("End Introduction"))
            }
            Text(step.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let place = guide.place {
                    dots(number: place.number, count: place.count)
                }
                Spacer(minLength: 8)
                if step == .send {
                    Button(L("Back")) { guide.back() }
                        .buttonStyle(.bordered)
                }
                Button(L("Next")) { guide.next() }
                    .buttonStyle(.bordered)
            }
            .modifier(SmallButtons())
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                symbol("checkmark")
                Text(L("You're all set"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(PhoneGuide.doneText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("Done")) { guide.end() }
                    .buttonStyle(.borderedProminent)
                    .modifier(SmallButtons())
            }
        }
    }

    /// The card's buttons: the system's regular size, in subheadline, each
    /// on one line, shrinking a little rather than wrapping.
    private struct SmallButtons: ViewModifier {
        func body(content: Content) -> some View {
            content
                .controlSize(.regular)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonBorderShape(.capsule)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 36, height: 36)
            .background(Color.accentColor.opacity(0.12), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private func dots(number: Int, count: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, count), id: \.self) { i in
                Capsule()
                    .fill(i == number ? Color.accentColor : Color.primary.opacity(i < number ? 0.35 : 0.15))
                    .frame(width: i == number ? 16 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("Step %1$d of %2$d"), number, count))
    }
}
