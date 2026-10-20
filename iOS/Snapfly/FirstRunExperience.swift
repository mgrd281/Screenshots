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
    /// The story's clock as the bars over it read it.
    @State private var clock = StoryClock()
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

    /// The height everything but the page takes: the bars, the words, the
    /// stage's margins, what is under it and the actions.
    private static let reserved: CGFloat = 424
    /// The page's size in the camera, so there is room for the shutter.
    private static let inCamera: CGFloat = 0.8
    private static let stageShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

    var body: some View {
        GeometryReader { space in
            // The page stands, as tall as the room between the words and
            // what is under it allows.
            let room = (space.size.height - Self.reserved) / FirstRun.pageRatio
            let width = max(170, min(space.size.width - 72, 300, room))
            ScrollView {
                VStack(spacing: 0) {
                    StoryProgress(clock: clock)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .opacity(state.scene == .complete || voiceOver ? 0 : 1)
                    words
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
                    Spacer(minLength: 8)
                    stage(width: width)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .background { ground(width: width) }
                        .overlay {
                            if !calm {
                                CaptureFlash(trigger: state.scan >= .straight)
                                    .clipShape(Self.stageShape)
                            }
                        }
                        .overlay(Self.stageShape.strokeBorder(Color.primary.opacity(0.06)))
                        .padding(.horizontal, 16)
                    Spacer(minLength: 8)
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

    /// What each scene shows, in a line under its headline.
    static func subline(of scene: FirstRun.Scene) -> String {
        switch scene {
        case .reveal: L("Names, emails and bank details are found and covered.")
        case .control: L("Tap a category to show or cover it.")
        case .scan: L("Scan a page: it is straightened, read and covered.")
        case .share: L("Only the protected copy leaves your iPhone.")
        case .complete: L("Protect invoices, screenshots and documents before you share them.")
        }
    }

    private var words: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                Text(Self.headline(of: state.scene))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(Self.subline(of: state.scene))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
            .id(state.scene)
            .transition(wordsChange)
        }
    }

    /// One scene's words give way to the next in place: the old ones leave
    /// first, quickly, so the two are never read over each other, and the
    /// new ones come into focus as they rise.
    private var wordsChange: AnyTransition {
        guard !calm else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8))
                .combined(with: .modifier(active: Blurred(radius: 6), identity: Blurred(radius: 0)))
                .animation(.easeOut(duration: 0.32).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    // MARK: The page

    /// The invoice, alone at first, then before the camera, then small and
    /// ready to share.
    private func stage(width: CGFloat) -> some View {
        paper(width: width)
            .scaleEffect(state.scene >= .share ? 0.74 : state.scene == .scan ? Self.inCamera : 1)
            .frame(maxWidth: .infinity)
    }

    /// What the page stands on: the brand's soft green, and while it is
    /// scanned the camera's view, filling the stage.
    private func ground(width: CGFloat) -> some View {
        // The room under the page in the camera, where the shutter sits.
        let room = width * FirstRun.pageRatio * (1 - Self.inCamera) / 2 + 18
        return ZStack {
            Self.stageShape.fill(SnapflyTokens.surface)
            if state.scene == .scan {
                ScanCamera(room: room, taken: state.scan >= .straight, calm: calm)
                    .clipShape(Self.stageShape)
                    .transition(.opacity)
            }
        }
    }

    private func paper(width: CGFloat) -> some View {
        let edges = state.scan == .edges || state.scan == .straight
        return SampleInvoice(width: width, state: state, calm: calm,
                             interactive: state.scene >= .control && state.scene < .complete,
                             toggle: toggle)
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
            .overlay { if !calm { ReadingLight(trigger: state.sweeps) } }
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
            .overlay(Circle().strokeBorder(SnapflyTokens.surface, lineWidth: 3))
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
            clock = StoryClock(elapsed: moment)
            return
        }
        if voiceOver {
            state = FirstRun.state(at: FirstRun.completeStart)
            clock = StoryClock(elapsed: FirstRun.completeStart)
            return
        }
        var story = 0.0
        var last = Date()
        clock = StoryClock(elapsed: 0, since: last, running: true)
        for beat in FirstRun.script {
            while story < beat.at {
                try? await Task.sleep(for: .seconds(min(beat.at - story, 0.05)))
                if Task.isCancelled { return }
                let now = Date()
                let waiting = held(at: now)
                if !waiting { story += now.timeIntervalSince(last) }
                last = now
                // The bars stop and go on with the story.
                if clock.running == waiting { clock = StoryClock(elapsed: story, since: now, running: !waiting) }
            }
            perform(beat.event)
        }
        clock = StoryClock(elapsed: story)
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
        case .scene(.scan): calm ? SnapflyMotion.calm : Animation.easeOut(duration: 0.35)
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

/// The made-up invoice, printed as a real one is: a studio's letterhead,
/// whom it is for, its number and date, what was done and what it costs,
/// the account it is paid from and its small print. White in light and dark
/// alike, left to right in every language, and set in print sizes that grow
/// with the page; its details are found and covered as the story says. A
/// tap on a detail turns its category on or off.
private struct SampleInvoice: View {
    let width: CGFloat
    let state: FirstRun.State
    let calm: Bool
    let interactive: Bool
    let toggle: (FirstRun.Category) -> Void

    /// Standing, as a sheet of A4.
    private var height: CGFloat { width * FirstRun.pageRatio }
    /// Print sizes are given for a page 300 pt wide.
    private var scale: CGFloat { width / 300 }

    var body: some View {
        // Each part takes its share of the page's height, so every detail
        // sits where the reading light finds it (`FirstRun.Field.depth`).
        VStack(alignment: .leading, spacing: 0) {
            letterhead
                .band(height * 0.075, .leading)
                .overlay(alignment: .bottom) { hairline }
            gap(0.025)
            parties
                .frame(height: height * 0.11, alignment: .top)
            gap(0.025)
            Text(L("Invoice"))
                .font(printed(18, .bold))
                .band(height * 0.06, .leading)
            gap(0.025)
            items
            gap(0.005)
            sum(L("Subtotal"), "125,97 €")
                .band(height * 0.03, .trailing)
            sum(L("VAT") + " 19 %", "23,93 €")
                .band(height * 0.03, .trailing)
            gap(0.015)
            total
                .band(height * 0.05, .leading)
                .overlay(alignment: .top) { rule(strong: true) }
            gap(0.06)
            Text(L("Payment by direct debit"))
                .font(printed(6.5))
                .foregroundStyle(.secondary)
                .band(height * 0.03, .bottomLeading)
            payment
                .band(height * 0.04, .leading)
            gap(0.05)
            Text(L("Thank you for your order."))
                .font(printed(7.5))
                .band(height * 0.04, .leading)
            gap(0.075)
            footer
                .band(height * 0.045, .leading)
                .overlay(alignment: .top) { hairline }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, width * 0.075)
        .padding(.top, height * 0.05)
        .frame(width: width, height: height, alignment: .top)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Sample invoice"))
        .accessibilityValue(summary)
    }

    /// The studio's mark and name, its website, and "Sample".
    private var letterhead: some View {
        HStack(spacing: 7 * scale) {
            Text(verbatim: String(L("Example Studio").prefix(1)))
                .font(printed(13, .bold))
                .foregroundStyle(.white)
                .frame(width: 24 * scale, height: 24 * scale)
                .background(SnapflyTokens.ink, in: RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 1.5 * scale) {
                Text(L("Example Studio"))
                    .font(printed(10.5, .semibold))
                Text(verbatim: "www.example.com")
                    .font(printed(6.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(L("Sample"))
                .font(printed(6, .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2.5 * scale)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    /// Whom it is for, the name over the email; its number and date beside.
    private var parties: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                heading(L("Bill to"))
                    .band(height * 0.03, .leading)
                value(FirstRun.field(.name), printed(10, .semibold))
                    .band(height * 0.04, .leading)
                value(FirstRun.field(.email), printed(9))
                    .band(height * 0.04, .leading)
            }
            Grid(alignment: .leading, horizontalSpacing: 6 * scale, verticalSpacing: 0) {
                GridRow {
                    Text(L("Invoice no."))
                        .foregroundStyle(.secondary)
                        .frame(height: height * 0.03)
                    Text(verbatim: "RE-2026-0417")
                        .frame(height: height * 0.03)
                }
                GridRow {
                    Text(L("Date"))
                        .foregroundStyle(.secondary)
                        .frame(height: height * 0.04)
                    Text(verbatim: "14.10.2026")
                        .frame(height: height * 0.04)
                }
            }
            .font(printed(7).monospacedDigit())
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// What was done: a heading row and two items, under rules.
    private var items: some View {
        VStack(spacing: 0) {
            item(L("Description"), L("Qty"), L("Amount"), heading: true)
                .band(height * 0.03, .leading)
                .overlay(alignment: .bottom) { hairline }
            item(L("Logo design"), "1", "99,00 €")
                .band(height * 0.04, .leading)
            item(L("Business cards, 250"), "1", "26,97 €")
                .band(height * 0.04, .leading)
                .overlay(alignment: .bottom) { hairline }
        }
    }

    private func item(_ what: String, _ count: String, _ price: String, heading: Bool = false) -> some View {
        HStack(spacing: 6 * scale) {
            Text(what)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(count)
                .frame(width: 30 * scale, alignment: .trailing)
            Text(price)
                .frame(width: 56 * scale, alignment: .trailing)
        }
        .font(heading ? printed(6, .semibold) : printed(7.5).monospacedDigit())
        .textCase(heading ? Text.Case.uppercase : nil)
        .tracking(heading ? 0.4 : 0)
        .foregroundStyle(heading ? Color.secondary : Color.primary)
    }

    /// A line of the sums, on the trailing side under the amounts.
    private func sum(_ label: String, _ amount: String) -> some View {
        HStack(spacing: 6 * scale) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(verbatim: amount)
                .frame(width: 56 * scale, alignment: .trailing)
        }
        .font(printed(7).monospacedDigit())
    }

    private var total: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("Total"))
                .font(printed(9, .semibold))
            Spacer(minLength: 8)
            Text(verbatim: FirstRun.field(.amount).value)
                .font(printed(12.5, .bold).monospacedDigit())
        }
    }

    /// The account the amount is paid from.
    private var payment: some View {
        HStack(spacing: 8 * scale) {
            Text(FirstRun.field(.iban).label)
                .font(printed(7, .semibold))
                .foregroundStyle(.secondary)
            value(FirstRun.field(.iban), printed(8.5).monospacedDigit())
        }
    }

    /// The small print at the foot of the page.
    private var footer: some View {
        HStack(spacing: 8) {
            Text(L("Example Studio") + " · www.example.com")
            Spacer(minLength: 8)
            Text(verbatim: "1/1")
        }
        .font(printed(5.5))
        .foregroundStyle(.secondary)
    }

    /// A heading on the page, in small capitals.
    private func heading(_ text: String) -> some View {
        Text(text)
            .font(printed(6, .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    /// A printed rule: a hairline, or the line over the total.
    private func rule(strong: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(strong ? 0.8 : 0.12))
            .frame(height: strong ? 1 : 0.5)
    }

    private var hairline: some View { rule(strong: false) }

    private func gap(_ share: CGFloat) -> some View {
        Color.clear.frame(height: height * share)
    }

    /// The system's text at a print size, grown with the page.
    private func printed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    /// A private detail: lit in the brand's green once found, as selected
    /// text is, then the ink growing over it from the reading side, solid
    /// all the way; with Reduce Motion the ink is simply there.
    private func value(_ field: FirstRun.Field, _ font: Font) -> some View {
        let covered = state.isCovered(field)
        let found = state.isFound(field)
        let mark = RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
        return Text(verbatim: field.value)
            .font(font)
            .overlay {
                ZStack {
                    mark.fill(SnapflyTokens.protect.opacity(0.14))
                        .overlay(mark.strokeBorder(SnapflyTokens.protect, lineWidth: 1.25))
                        .padding(.horizontal, -3 * scale)
                        .padding(.vertical, -1.5 * scale)
                        .scaleEffect(found || calm ? 1 : 0.92)
                        .opacity(found ? 1 : 0)
                    mark.fill(SnapflyTokens.ink)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: covered || calm ? nil : 0)
                        }
                        .opacity(calm && !covered ? 0 : 1)
                        .padding(.horizontal, -2 * scale)
                        .padding(.vertical, -1 * scale)
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

private extension View {
    /// A part of the sample page: the whole width inside its margins, and
    /// its share of the page's height.
    func band(_ height: CGFloat, _ alignment: Alignment) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .frame(height: height)
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

/// The camera's view as the scanner shows it, filling the stage: the dark
/// of the camera, and its shutter, pressed as the page is taken.
private struct ScanCamera: View {
    /// The room under the page, where the shutter sits.
    let room: CGFloat
    let taken: Bool
    let calm: Bool

    var body: some View {
        let shutter = min(34, room - 14)
        ZStack(alignment: .bottom) {
            SnapflyTokens.ink
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
                Circle()
                    .fill(Color.white)
                    .padding(5)
                    .keyframeAnimator(initialValue: 1.0, trigger: calm ? false : taken) { button, scale in
                        button.scaleEffect(scale)
                    } keyframes: { _ in
                        CubicKeyframe(0.82, duration: 0.08)
                        SpringKeyframe(1, duration: 0.3, spring: .snappy)
                    }
            }
            .frame(width: shutter, height: shutter)
            .padding(.bottom, (room - shutter) / 2)
        }
        .accessibilityHidden(true)
    }
}

/// The camera's flash as the page is taken: white over the stage for a
/// moment, once.
private struct CaptureFlash: View {
    let trigger: Bool

    var body: some View {
        Color.white
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { flash, opacity in
                flash.opacity(opacity)
            } keyframes: { _ in
                LinearKeyframe(0.4, duration: 0.05)
                LinearKeyframe(0, duration: 0.3)
            }
            .allowsHitTesting(false)
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

/// The page's edges as the scanner finds them: the page lit in the brand's
/// green with a handle at each corner, closing in on the corners as it
/// locks on, and following them as the page is straightened.
private struct EdgeLock: View {
    var straightened: Double
    var lock: Double

    var body: some View {
        ZStack {
            EdgeShape(straightened: straightened, lock: lock, handles: false)
                .fill(SnapflyTokens.protect.opacity(0.16))
            EdgeShape(straightened: straightened, lock: lock, handles: false)
                .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            EdgeShape(straightened: straightened, lock: lock, handles: true)
                .fill(Color.white)
            EdgeShape(straightened: straightened, lock: lock, handles: true)
                .stroke(SnapflyTokens.protect, lineWidth: 2)
        }
    }
}

private struct EdgeShape: Shape {
    var straightened: Double
    var lock: Double
    let handles: Bool

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
        if handles {
            for corner in corners {
                path.addEllipse(in: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
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
        HStack(spacing: 20) {
            destination("sparkles", "ChatGPT")
            destination("message.fill", "WhatsApp")
            destination("envelope.fill", L("Email"))
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

// MARK: The story's progress

/// The story's clock as the bars read it: where it stood when it last went
/// on or stopped, and whether it is going.
struct StoryClock: Equatable {
    var elapsed = 0.0
    var since = Date()
    var running = false

    func time(at date: Date) -> Double {
        running ? elapsed + date.timeIntervalSince(since) : elapsed
    }
}

/// How far the story is: a bar for each scene before the end, filling as it
/// plays and standing still while it waits for the owner.
private struct StoryProgress: View {
    let clock: StoryClock

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.running)) { context in
            let filled = FirstRun.progress(at: clock.time(at: context.date))
            HStack(spacing: 4) {
                ForEach(filled.indices, id: \.self) { index in
                    ProgressView(value: filled[index])
                        .progressViewStyle(.linear)
                }
            }
        }
        .tint(SnapflyTokens.protect)
        .frame(maxWidth: 400)
        .accessibilityHidden(true)
    }
}

/// A view out of focus, for words coming into it.
private struct Blurred: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

// MARK: Reading

/// The scanner's light reading its view once, top to bottom, each time its
/// trigger changes (`sweep.light`): a soft band of the brand's green with a
/// sharp edge where it reads, moving at an even pace.
private struct ReadingLight: View {
    let trigger: Int

    private struct Sweep {
        var progress: CGFloat = 0
        var opacity = 0.0
    }

    var body: some View {
        GeometryReader { place in
            let band = place.size.height * 0.14
            VStack(spacing: 0) {
                LinearGradient(colors: [SnapflyTokens.protect.opacity(0), SnapflyTokens.protect.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
                Rectangle()
                    .fill(SnapflyTokens.protect)
                    .frame(height: 1.5)
            }
            .keyframeAnimator(initialValue: Sweep(), trigger: trigger) { light, sweep in
                light.offset(y: sweep.progress * place.size.height - band).opacity(sweep.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0.02, duration: 0.01)
                    LinearKeyframe(0.98, duration: 0.9)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 0.55)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
