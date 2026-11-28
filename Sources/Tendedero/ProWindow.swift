import AppKit
import SwiftUI

// MARK: The window

/// Snapfly Pro in a window of its own, opened by a locked feature or from
/// Settings › About: the drawn line with three cards and a lock that opens
/// once the App Store has said yes, beside what Pro is, the features it adds,
/// the ways to pay as the App Store gives them and one button; along its foot
/// the terms, the privacy policy, how to withdraw and how to cancel. A fixed
/// size, over the line, which floats. Escape closes it, Return presses the
/// one prominent button.
@MainActor
final class ProWindow: NSObject, NSWindowDelegate {
    static let shared = ProWindow()

    /// Room for the drawing beside the words, the plans and the buttons.
    static let size = NSSize(width: 820, height: 620)

    private(set) var window: NSWindow?
    /// The feature asked about, and whether the window is open.
    fileprivate let model = ProModel()

    /// Opens the window, naming the locked feature that asked for it.
    func show(for feature: Plan.ProFeature? = nil) {
        model.feature = feature
        model.isShown = true
        if window == nil {
            let host = NSHostingController(rootView: ProRoot(model: model, close: { [weak self] in self?.close() }))
            // The window sets the size; the view fills it.
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            // Hidden in the title bar, still read by VoiceOver and the Window menu.
            window.title = L("Snapfly Pro")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.setContentSize(Self.size)
            // Over the line, which floats.
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Snapfly lives in the menu bar, so it comes forward on purpose.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        ProStore.shared.closed()
        // Once the window is away its view goes too, so the drawing stops
        // and the next opening plays from the start.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let pro = ProWindow.shared
                if pro.window?.isVisible != true { pro.model.isShown = false }
            }
        }
    }
}

/// What the window shows besides the App Store's answers.
@MainActor
private final class ProModel: ObservableObject {
    /// The locked feature that opened the window; nil from Settings.
    @Published var feature: Plan.ProFeature?
    /// Whether the window is open: its view is there only while it is.
    @Published var isShown = false
    /// Everything at rest at once, for the picture the captures take.
    var still = false
}

/// The window's view while it is open, nothing while it is closed.
private struct ProRoot: View {
    @ObservedObject var model: ProModel
    let close: () -> Void

    var body: some View {
        if model.isShown {
            ProView(model: model, close: close)
        } else {
            Color.clear
                .frame(width: ProWindow.size.width, height: ProWindow.size.height)
        }
    }
}

// MARK: The gate

/// Where a Pro feature asks whether it may run.
@MainActor
enum ProGate {
    /// Whether a feature is open; when it is not, says so: the Pro window the first time a day, a note after that.
    static func allows(_ feature: Plan.ProFeature) -> Bool {
        if Plan.allows(feature, subscribed: Plan.subscribedLately) { return true }
        if ProNudge.takeScreen() {
            ProWindow.shared.show(for: feature)
        } else {
            Notice.show(ProNudge.note(for: feature), onClick: { ProWindow.shared.show(for: feature) })
        }
        return false
    }

    /// Silent, for what runs on its own.
    nonisolated static func isOpen(_ feature: Plan.ProFeature) -> Bool {
        Plan.allows(feature, subscribed: Plan.subscribedLately)
    }
}

// MARK: The view

/// The drawing on its stage at the leading side; at the trailing side the
/// locked feature's chip, the title with "Pro" in the accent, what Pro is
/// for, the features in their three groups, then the ways to pay, what
/// happens once Subscribe is pressed, who sells it and the buttons. The
/// legal links run along the foot. Its parts come in once each time the
/// window opens; with Reduce Motion or Low Power Mode everything is simply
/// there, and the drawing keeps still.
private struct ProView: View {
    @ObservedObject var model: ProModel
    let close: () -> Void

    @ObservedObject private var store = ProStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The parts are in.
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                heroColumn
                column
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: ProWindow.size.width, height: ProWindow.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onChange(of: store.phase) { _, now in
            if now == .welcome { announce(StressedText.plain(L("Welcome to Snapfly *Pro*"))) }
        }
        .onChange(of: store.note) { _, now in
            if let words = now { announce(words) }
        }
        .task { await store.prepare() }
        .onAppear { shown = true }
    }

    /// Reduce Motion, Low Power Mode, or the captures: nothing moves.
    private var calm: Bool {
        reduceMotion || model.still || ProSample.still || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Pro is open here: just bought, on, or kept from before Pro began.
    private var unlocked: Bool {
        [.welcome, .subscribed, .keeps].contains(store.phase)
    }

    /// The hero in the Mac's colours: the accent for the marks and the seal,
    /// white paper, the system's greys for the line and its clips.
    private static var palette: ProHeroPalette {
        ProHeroPalette(stage: Color.accentColor.opacity(0.10), stageEdge: Color.primary.opacity(0.06),
                       line: Color.primary.opacity(0.35), clip: Color.primary.opacity(0.55), paper: .white,
                       paperLine: Color(white: 0.86), ink: Color(white: 0.12), mark: Color.accentColor,
                       markSoft: Color.accentColor.opacity(0.15), screen: Color(white: 0.14),
                       sealTop: Color.accentColor, sealBottom: Color.accentColor,
                       sealRing: Color(nsColor: .windowBackgroundColor), shadow: 0.18)
    }

    // MARK: The drawing

    /// The stage, reaching up under the clear title bar, with the drawing in
    /// its middle and the promise at its foot.
    private var heroColumn: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ProHero(palette: Self.palette, feature: model.feature, unlocked: unlocked, still: calm,
                    cornerRadius: 0, drawsStage: false)
                .frame(height: 250)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
            promise
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Self.palette.stage))
        .overlay(shape.strokeBorder(Self.palette.stageEdge, lineWidth: 1))
        .padding(12)
        .frame(width: 340)
    }

    /// Covering stays free, said where the drawing is.
    private var promise: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.accentColor)
            Text(L("Covering private details stays free, always."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityElement(children: .combine)
    }

    // MARK: The words

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .modifier(ProAppear(shown: shown, index: 0, calm: calm))
            features
                .padding(.top, 16)
                .modifier(ProAppear(shown: shown, index: 1, calm: calm))
            offering
                .modifier(ProAppear(shown: shown, index: 2, calm: calm))
            buttons
                .padding(.top, 14)
                .modifier(ProAppear(shown: shown, index: 3, calm: calm))
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // VoiceOver reads the title and the offer before the drawing's promise.
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
        .animation(Motion.spring(response: 0.25, damping: 0.85, reduced: calm), value: store.phase)
        .animation(Motion.spring(response: 0.25, damping: 0.85, reduced: calm), value: store.note)
    }

    /// The locked feature's chip, the title and what Pro is for.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let feature = model.feature, !unlocked {
                chip(for: feature)
                    .padding(.bottom, 10)
            }
            StressedText(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .id(title)
                .transition(.opacity)
            Text(subtitle)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    /// "Studio is part of Snapfly Pro.": the lock in the accent, the words
    /// in ink, so they read in every accent colour.
    private func chip(for feature: Plan.ProFeature) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.accentColor)
            Text(ProNudge.note(for: feature))
                .foregroundStyle(.primary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch store.phase {
        case .welcome: L("Welcome to Snapfly *Pro*")
        case .subscribed: L("You have Snapfly *Pro*")
        case .keeps: L("Everything stays yours")
        default: L("Snapfly *Pro*")
        }
    }

    /// With Pro on, the line about its renewal stands with the buttons
    /// below, so it is said once.
    private var subtitle: String {
        switch store.phase {
        case .welcome, .subscribed: L("Every Pro feature is open on your Mac now.")
        case .keeps: L("You used Snapfly before Pro began, so every feature stays open for you, without Pro.")
        default: L("For everyone who sends orders, receipts and guides from the Mac every day.")
        }
    }

    // MARK: The features

    /// Every Pro feature in its group, the one asked about marked and
    /// scrolled to.
    private var features: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ProCatalog.Group.allCases, id: \.self) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, group == ProCatalog.Group.allCases.first ? 0 : 14)
                            .padding(.bottom, 6)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(group.features, id: \.self) { feature in
                                ProFeatureRow(feature: feature, asked: feature == model.feature)
                                    .id(feature)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the marked row's fill, which reaches past the words.
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, -6)
            .onAppear {
                guard let feature = model.feature else { return }
                scroller.scrollTo(feature, anchor: .center)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Paying

    /// The ways to pay, the subscription, or why this copy cannot
    /// subscribe; then what happens once Subscribe is pressed, who sells it,
    /// and the App Store's last word.
    private var offering: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.phase {
            case .loading:
                placeholders
                    .padding(.top, 14)
            case .offers, .buying, .pending:
                plans
                    .padding(.top, 14)
            case .unavailable:
                unavailableRow
                    .padding(.top, 14)
            case .welcome, .subscribed:
                manageRow
                    .padding(.top, 14)
            case .elsewhere:
                elsewhereRow
                    .padding(.top, 14)
            case .keeps:
                EmptyView()
            }
            if let words = finePrint {
                Text(words)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if store.phase != .keeps {
                Text(ProOffers.seller)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, finePrint == nil ? 10 : 4)
            }
            if let note = store.note {
                noteRow(note)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
    }

    /// One tile for each way to pay, side by side, all as tall as the tallest.
    private var plans: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(store.offers) { offer in
                ProPlanTile(offer: offer, chosen: offer.id == store.chosen?.id,
                            savings: offer.period == .year ? store.savings : nil, calm: calm) {
                    choose(offer)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Two quiet tiles while the App Store is asked, in the place the real
    /// ones take, so nothing moves when the prices come.
    private var placeholders: some View {
        HStack(alignment: .top, spacing: 12) {
            ProPlanPlaceholder()
            ProPlanPlaceholder()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Asking the App Store for the prices…"))
    }

    private var unavailableRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(L("Prices could not be loaded. Check the connection and try again."))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Try Again")) {
                Task { await store.prepare() }
            }
        }
        .font(.system(size: 13))
        .modifier(ProQuietBox())
    }

    /// The renewal, and Apple's own pages for cancelling and withdrawing.
    private var manageRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let line = store.subscription?.line {
                Text(line)
                    .font(.system(size: 13))
            }
            HStack(spacing: 8) {
                Button(L("Cancel Subscription")) { NSWorkspace.shared.open(ProLinks.appleSubscriptions) }
                Button(L("Withdraw from Contract")) { NSWorkspace.shared.open(ProLinks.appleWithdrawal) }
            }
        }
        .modifier(ProQuietBox())
    }

    private var elsewhereRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L("Snapfly Pro is bought in Snapfly from the Mac App Store. This copy comes from the website, so it cannot subscribe."))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .modifier(ProQuietBox())
    }

    /// What is billed and how to stop it, said before Subscribe; while the
    /// family is asked, what happens then.
    private var finePrint: String? {
        switch store.phase {
        case .offers, .buying:
            guard let offer = store.chosen else { return nil }
            return ProOffers.renewal(offer) + " " + ProOffers.cancelling
        case .pending:
            return L("Someone in your family is asked to approve it. Pro opens once they do.")
        default:
            return nil
        }
    }

    private func noteRow(_ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(note)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }

    // MARK: The buttons

    /// Restore Purchases at the leading edge; Not Now and the one prominent
    /// button at the trailing edge. With Pro open, Done alone, and Escape
    /// still closes.
    private var buttons: some View {
        HStack(spacing: 8) {
            if [.offers, .unavailable, .loading].contains(store.phase) {
                Button {
                    Task { await store.restore() }
                } label: {
                    // Where the words run long, as in German, it takes a
                    // second line rather than cut the buttons' words short.
                    Text(L("Restore Purchases"))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .disabled(store.restoring)
            }
            Spacer(minLength: 8)
            if closesOnly {
                // Escape closes it too, as Done does.
                Button(action: close) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            } else {
                // Not while the App Store's own sheet hangs from the window.
                Button(L("Not Now"), action: close)
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.phase == .buying)
                    .fixedSize()
            }
            // Its words are the contract's, so they are never shortened.
            primary
                .fixedSize()
        }
    }

    /// Pro is open, or cannot be bought in this copy: nothing to put off.
    private var closesOnly: Bool {
        [.welcome, .subscribed, .keeps, .elsewhere].contains(store.phase)
    }

    @ViewBuilder private var primary: some View {
        switch store.phase {
        case .offers:
            prominent(L("Subscribe")) { subscribe() }
        case .buying:
            Button(action: {}) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Subscribe"))
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(true)
        case .loading, .unavailable:
            prominent(L("Subscribe"), enabled: false) {}
        case .pending:
            prominent(L("Waiting for approval"), enabled: false) {}
        case .welcome, .subscribed, .keeps, .elsewhere:
            prominent(L("Done"), action: close)
        }
    }

    private func prominent(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }

    // MARK: The foot

    /// The terms, the privacy policy, the withdrawal policy, and Apple's own
    /// pages to withdraw and to cancel; in two rows where one is too narrow.
    private var footer: some View {
        let links = ProFooterLink.all
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                linkRow(links[...])
                VStack(spacing: 4) {
                    linkRow(links[..<3])
                    linkRow(links[3...])
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 16)
        }
    }

    private func linkRow(_ links: ArraySlice<ProFooterLink>) -> some View {
        HStack(spacing: 8) {
            ForEach(links) { link in
                if link.id != links.first?.id {
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    // Small words, but a pointer target as tall as any other.
                    Text(link.title)
                        .frame(minHeight: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.link)
                .accessibilityAddTraits(.isLink)
            }
        }
        .font(.system(size: 11))
        .fixedSize()
    }

    // MARK: Actions

    private func choose(_ offer: ProOffer) {
        guard store.phase == .offers else { return }
        store.chosenID = offer.id
    }

    private func subscribe() {
        Task { await ProStore.shared.subscribe(in: ProWindow.shared.window) }
    }

    private func announce(_ words: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

// MARK: Pieces

/// One Pro feature: its symbol on an ink tile, its name and what it does.
/// The one a locked feature asked about sits on a faint accent fill that
/// reaches past it, so it does not move.
private struct ProFeatureRow: View {
    let feature: Plan.ProFeature
    let asked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feature.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InkTile.glyph)
                .frame(width: 24, height: 24)
                .background(InkTile.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(feature.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(asked ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(-6)
        .accessibilityElement(children: .combine)
    }
}

/// One way to pay, chosen as the AI assistants are: its name and the
/// check, the price billed, the most prominent, what it is for, then the
/// free trial or what the year saves, and what a year comes to each month.
/// Chosen, an accent ring and a faint accent fill.
private struct ProPlanTile: View {
    /// As tall as a year's tile with both of its lines, so the tiles,
    /// the quiet tiles before them and the boxes after them line up.
    static let height: CGFloat = 112

    let offer: ProOffer
    let chosen: Bool
    let savings: Int?
    let calm: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ProOffers.name(of: offer.period))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(chosen ? Color.accentColor : Color.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                }
                Text(offer.displayPrice)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
                Text(ProOffers.unit(of: offer.period))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let line = highlight {
                    Text(line)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.top, 4)
                }
                if let perMonth = ProOffers.perMonthLine(offer) {
                    Text(perMonth)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, highlight == nil ? 4 : 0)
                }
            }
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(chosen ? Color.accentColor.opacity(0.08)
                                          : Color.primary.opacity(hovering ? 0.06 : 0.03)))
            .overlay(shape.strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: chosen ? 2 : 1))
            .contentShape(shape)
            .animation(Motion.spring(response: 0.25, damping: 0.85, reduced: calm), value: chosen)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The free trial first; else what the year saves, from 5%.
    private var highlight: String? {
        if let trial = ProOffers.trialLine(offer) { return trial }
        if let percent = savings { return ProOffers.savingsLine(percent) }
        return nil
    }
}

/// A tile while the prices are asked for: its words as faint bars, and a
/// small spinner where the check goes. Nothing shimmers.
private struct ProPlanPlaceholder: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 52, height: 8)
                Spacer(minLength: 4)
                ProgressView()
                    .controlSize(.small)
            }
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 76, height: 14)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 36, height: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: ProPlanTile.height, alignment: .topLeading)
        .background(shape.fill(Color.primary.opacity(0.03)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// The plain tile's look, for what stands in the plans' place: the prices
/// that could not be had, the subscription, this copy from the website.
private struct ProQuietBox: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return content
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: ProPlanTile.height, alignment: .leading)
            .background(shape.fill(Color.primary.opacity(0.03)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// A link along the window's foot.
private struct ProFooterLink: Identifiable {
    let id: String
    let title: String
    let url: URL

    /// In the order the law's own words come: the terms, privacy, the
    /// withdrawal policy, then withdrawing and cancelling at Apple.
    static var all: [ProFooterLink] {
        [
            ProFooterLink(id: "terms", title: L("Terms of Use"), url: ProLinks.terms()),
            ProFooterLink(id: "privacy", title: L("Privacy Policy"), url: ProLinks.privacy()),
            ProFooterLink(id: "withdrawal", title: L("Withdrawal Policy"), url: ProLinks.withdrawal()),
            ProFooterLink(id: "withdraw", title: L("Withdraw from Contract"), url: ProLinks.appleWithdrawal),
            ProFooterLink(id: "cancel", title: L("Cancel Subscription"), url: ProLinks.appleSubscriptions),
        ]
    }
}

/// The window's parts coming in each time it opens, after the drawing's
/// line has begun: rising 8 pt and fading in on `spring.reveal`, 40 ms
/// apart; with Reduce Motion, there at once.
private struct ProAppear: ViewModifier {
    let shown: Bool
    let index: Int
    let calm: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || calm ? 0 : 8)
            .animation(calm ? nil : Motion.spring(response: 0.42, damping: 0.82, reduced: false)
                .delay(0.15 + Double(index) * 0.04), value: shown)
    }
}

/// Words with some stressed, marked between asterisks in each language, as
/// "Snapfly *Pro*": the stressed ones in the accent, with nothing behind
/// them. The Mac's copy of the iPhone's, which stresses in its green.
struct StressedText: View {
    let marked: String

    init(_ marked: String) {
        self.marked = marked
    }

    /// The words as they are read, without the marks.
    static func plain(_ marked: String) -> String {
        marked.replacingOccurrences(of: "*", with: "")
    }

    /// Between the marks, every other part is stressed.
    var body: Text {
        let parts = marked.components(separatedBy: "*")
        return parts.indices.reduce(Text(verbatim: "")) { text, index in
            var part = Text(verbatim: parts[index])
            if index % 2 == 1 { part = part.foregroundStyle(Color.accentColor) }
            return Text("\(text)\(part)")
        }
    }
}

// MARK: Captures

#if DEBUG
/// The Pro window drawn into a picture at launch, for the captures CI takes
/// without a Mac to look at: `-SnapflyProPreview <absolute path to a PNG>`
/// with `-SnapflyPro <phase>`, and `-SnapflyProFeature <feature>` and
/// `-SnapflyProDark` where wanted. Nothing else of Snapfly starts; the
/// window is drawn still, written out, and Snapfly quits.
enum ProPreview {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var requested: Bool { arguments.contains("-SnapflyProPreview") }

    /// Where the picture goes.
    private static var path: String? {
        guard let index = arguments.firstIndex(of: "-SnapflyProPreview"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The dark appearance instead of the light one.
    private static var dark: Bool { arguments.contains("-SnapflyProDark") }

    @MainActor
    static func run() {
        guard let path, path.hasPrefix("/") else {
            fail("-SnapflyProPreview needs the absolute path of the PNG to write.")
        }
        guard ProSample.requested else {
            let phases = ProPhase.allCases.map(\.rawValue).joined(separator: ", ")
            fail("-SnapflyPro needs one of the phases: \(phases).")
        }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        ProWindow.shared.model.still = true
        ProWindow.shared.show(for: ProSample.feature)
        let file = URL(fileURLWithPath: path)
        // Time for the prices, the fonts and the first frames to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { ProPreview.capture(to: file) }
        }
    }

    /// Draws the window's content as it is into a PNG, then quits.
    @MainActor
    private static func capture(to file: URL) {
        guard let view = ProWindow.shared.window?.contentView else {
            ProPreview.fail("The Pro window has no view to draw.")
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let picture = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            ProPreview.fail("The Pro window has no room to draw in.")
        }
        view.cacheDisplay(in: bounds, to: picture)
        guard let data = picture.representation(using: .png, properties: [:]) else {
            ProPreview.fail("The Pro window could not be made into a PNG.")
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        } catch {
            ProPreview.fail("The PNG could not be written to \(file.path): \(error.localizedDescription)")
        }
        print("ProPreview: wrote \(file.path) (\(Int(bounds.width)) × \(Int(bounds.height)) pt, phase \(ProSample.phase?.rawValue ?? "none")).")
        exit(0)
    }

    private static func fail(_ reason: String) -> Never {
        print("ProPreview: \(reason)")
        exit(1)
    }
}
#else
/// Only in debug builds.
enum ProPreview {
    static let requested = false

    @MainActor
    static func run() {}
}
#endif
