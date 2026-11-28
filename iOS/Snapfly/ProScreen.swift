import StoreKit
import SwiftUI

// MARK: Asking for it

/// What asked for the Pro screen: a locked feature, or More's row.
struct ProRequest: Identifiable, Equatable {
    let id = UUID()
    /// The feature that was locked, named on the screen; nil from More.
    let feature: Plan.ProFeature?
}

/// The Pro screen over the whole app, as a locked feature or More asks for
/// it; at launch for the captures CI takes (`-SnapflyPro <phase>`).
@MainActor
final class ProPresenter: ObservableObject {
    static let shared = ProPresenter()
    @Published var shown: ProRequest? = ProSample.requested ? ProRequest(feature: ProSample.feature) : nil

    func show(_ feature: Plan.ProFeature? = nil) {
        shown = ProRequest(feature: feature)
    }
}

/// Whether the Pro screen keeps still: Reduce Motion, Low Power Mode, or
/// the captures played as Reduce Motion would.
@propertyWrapper
struct ProCalm: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var wrappedValue: Bool { reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || ProSample.still }
}

// MARK: The screen

/// Snapfly Pro, full screen: the drawn line with three cards and a lock
/// that opens once the App Store has said yes; what Pro is, the ways to pay
/// as the App Store gives them, the features it adds and the promise that
/// covering stays free; then the terms, the privacy policy, how to
/// withdraw and cancel, and who sells it. One green button at the foot,
/// with what happens once it is pressed said just above it. Its parts come
/// in once each time it opens; with Reduce Motion or Low Power Mode it is
/// still, everything at once.
struct ProScreen: View {
    let request: ProRequest
    @ObservedObject private var store = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.purchase) private var purchase
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileScale: CGFloat = 1
    @ProCalm private var calm
    /// The parts are in.
    @State private var shown = false
    /// The App Store's own sheet for cancelling.
    @State private var managing = false
    /// Subscribe pressed, for its light tap.
    @State private var presses = 0
    /// The captures' starting place is taken, once.
    @State private var placed = false

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .top) {
                ScrollViewReader { scroller in
                    ScrollView {
                        page(height: space.size.height)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                    .onAppear { startPlace(scroller) }
                }
                closeButton
            }
        }
        .background(SnapflyTokens.hideGround.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
        .sensoryFeedback(trigger: store.phase) { _, now in now == .welcome ? .success : nil }
        .onChange(of: store.phase) { _, now in
            guard now == .welcome else { return }
            AccessibilityNotification.Announcement(StressedText.plain(L("Welcome to Snapfly *Pro*"))).post()
        }
        .onChange(of: store.note) { _, now in
            if let words = now { AccessibilityNotification.Announcement(words).post() }
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .task { await store.prepare() }
        .onAppear { shown = true }
        .onDisappear { store.closed() }
    }

    /// Everything that scrolls: room for the close button, the hero, then
    /// the words, the plans or the subscription, the features and the foot.
    private func page(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 52)
                .id("top")
            ProHero(palette: palette, feature: request.feature, unlocked: unlocked, still: calm)
                .frame(height: min(250, max(186, height * 0.29)))
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                    .modifier(ProAppear(shown: shown, index: 0, calm: calm))
                middle
                    .modifier(ProAppear(shown: shown, index: 1, calm: calm))
                features
                    .padding(.top, 32)
                    .id("features")
                    .modifier(ProAppear(shown: shown, index: 2, calm: calm))
                footer
                    .padding(.top, 28)
                    .id("footer")
                    .modifier(ProAppear(shown: shown, index: 3, calm: calm))
            }
            .animation(SnapflyMotion.change(calm), value: store.phase)
            Color.clear
                .frame(height: 32)
        }
    }

    /// Where the captures ask the screen to start: the features or its foot.
    private func startPlace(_ scroller: ScrollViewProxy) {
        guard !placed, let spot = ProSample.scroll else { return }
        placed = true
        Task { @MainActor in
            // Once the cover has laid out its page, so the place is there to go to.
            try? await Task.sleep(for: .milliseconds(300))
            scroller.scrollTo(spot, anchor: .top)
        }
    }

    /// Pro is open here: just bought, on, or kept from before Pro began.
    private var unlocked: Bool {
        [.welcome, .subscribed, .keeps].contains(store.phase)
    }

    /// The hero in the iPhone's colours: More's deep green stage, white
    /// paper, the protecting green for the marks and the seal.
    private var palette: ProHeroPalette {
        ProHeroPalette(stage: SnapflyTokens.moreHero, stageEdge: SnapflyTokens.moreHeroEdge,
                       line: Color.white.opacity(0.5), clip: Color.white.opacity(0.9),
                       paper: SnapflyTokens.morePaper, paperLine: SnapflyTokens.morePaperLine,
                       ink: SnapflyTokens.morePaperText, mark: SnapflyTokens.protect,
                       markSoft: SnapflyTokens.proMint, screen: SnapflyTokens.proScreen,
                       sealTop: SnapflyTokens.protectLight, sealBottom: SnapflyTokens.protectPressed,
                       sealRing: SnapflyTokens.moreHero, shadow: 0.28)
    }

    // MARK: The words

    private var title: String {
        switch store.phase {
        case .welcome: L("Welcome to Snapfly *Pro*")
        case .subscribed: L("You have Snapfly *Pro*")
        case .keeps: L("Everything stays yours")
        default: L("Snapfly *Pro*")
        }
    }

    private var subtitle: String {
        switch store.phase {
        case .welcome: L("Every Pro feature is open on your Mac now.")
        case .subscribed: store.subscription?.line ?? L("Every Pro feature is open on your Mac now.")
        case .keeps: L("You used Snapfly before Pro began, so every feature stays open for you, without Pro.")
        default: L("For everyone who sends orders, receipts and guides from the Mac every day.")
        }
    }

    /// The feature that was locked, then the title, large and heavy with
    /// Pro in green, and a line under it.
    private var header: some View {
        VStack(spacing: 10) {
            if let feature = request.feature, !unlocked {
                lockedChip(feature)
                    .transition(.opacity)
            }
            ZStack(alignment: .top) {
                VStack(spacing: 10) {
                    StressedText(title)
                        .font(.largeTitle.weight(.heavy))
                        .kerning(-0.6)
                        .foregroundStyle(SnapflyTokens.hideText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .id(title + subtitle)
                .transition(wordsChange)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
    }

    /// "Studio is part of Snapfly Pro.", on the mint, over the title. Its
    /// corners are More's chips': a capsule's on one line, soft on two.
    private func lockedChip(_ feature: Plan.ProFeature) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
            Text(ProNudge.note(for: feature))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SnapflyTokens.hideAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SnapflyTokens.hideAccentSoft,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.moreButtonRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One scene's words give way to the next in place, as on the first
    /// run (`words.change`): the old ones leave quickly, the new ones come
    /// into focus as they rise; with calm, a fade.
    private var wordsChange: AnyTransition {
        guard !calm else { return .opacity.animation(SnapflyMotion.calm) }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8))
                .combined(with: .modifier(active: ProBlurred(radius: 6), identity: ProBlurred(radius: 0)))
                .animation(.easeOut(duration: 0.32).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    // MARK: The plans, or the subscription

    @ViewBuilder
    private var middle: some View {
        if store.phase.showsOffers {
            VStack(spacing: 12) {
                plans
                // At the largest text sizes what Subscribe does is said under
                // the prices, so the bar at the foot keeps to its button.
                if typeSize.isAccessibilitySize, let words = finePrint {
                    finePrintText(words)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
        } else if store.phase == .subscribed || store.phase == .welcome {
            manage
                .padding(.top, 24)
                .padding(.horizontal, 16)
        }
    }

    /// Tiles side by side, as tall as each other, or one under the other at
    /// the largest text sizes.
    private func tiles<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout(content)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var plans: some View {
        switch store.phase {
        case .loading:
            asking
        case .unavailable:
            unavailable
        default:
            tiles {
                ForEach(store.offers) { offer in
                    PlanTile(offer: offer, chosen: offer.id == store.chosen?.id,
                             savings: offer.period == .year ? store.savings : nil, calm: calm) {
                        store.chosenID = offer.id
                    }
                }
            }
            .disabled(store.phase != .offers)
            // One tap for a new choice, none for the first one made as the prices come.
            .sensoryFeedback(trigger: store.chosenID) { old, now in old != nil && now != nil ? .selection : nil }
        }
    }

    /// Two quiet tiles where the prices will be, still, and the App Store
    /// asked, in words too.
    private var asking: some View {
        VStack(spacing: 14) {
            tiles {
                PlanPlaceholder()
                PlanPlaceholder()
            }
            HStack(spacing: 8) {
                ProgressView()
                Text(L("Asking the App Store for the prices…"))
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// No prices: why, and the way to ask again.
    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(SnapflyTokens.hideWarning)
                .accessibilityHidden(true)
            Text(L("Prices could not be loaded. Check the connection and try again."))
                .font(.subheadline)
                .foregroundStyle(SnapflyTokens.hideText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await store.prepare() }
            } label: {
                Text(L("Try Again"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .frame(minHeight: SnapflyTokens.touch)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("pro-try-again")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(SnapflyTokens.hideCard,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
    }

    /// Pro is on: Apple's own ways to cancel it and to withdraw.
    private var manage: some View {
        VStack(spacing: 0) {
            manageRow(L("Cancel Subscription"), symbol: "xmark.circle", id: "pro-manage-cancel") {
                managing = true
            }
            MoreDivider()
            manageRow(L("Withdraw from Contract"), symbol: "arrow.uturn.backward.circle", id: "pro-manage-withdraw") {
                openURL(ProLinks.appleWithdrawal)
            }
        }
        .background(SnapflyTokens.hideCard,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
    }

    /// A row as More's Features have them.
    private func manageRow(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolTile(symbol: symbol, base: 32, ground: SnapflyTokens.moreNeutralTile,
                           glyph: SnapflyTokens.moreNeutralGlyph)
                Text(title)
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }

    // MARK: The features

    /// Every Pro feature in its group, the one that was locked on the mint,
    /// then the promise that covering stays free.
    private var features: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoreHeading(title: L("What Pro adds"))
                .padding(.horizontal, 16)
            ForEach(ProCatalog.Group.allCases, id: \.self) { group in
                Text(group.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(group.features.enumerated()), id: \.element) { index, feature in
                        if index > 0 {
                            MoreDivider(leading: 16 + min(OwnDetailTile.base * tileScale, OwnDetailTile.largest) + 14)
                        }
                        featureRow(feature)
                    }
                }
                .background(SnapflyTokens.hideCard)
                .clipShape(RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
                .padding(.horizontal, 16)
            }
            promise
                .padding(.top, 20)
                .padding(.horizontal, 24)
        }
    }

    private func featureRow(_ feature: Plan.ProFeature) -> some View {
        let asked = feature == request.feature
        return HStack(alignment: .top, spacing: 14) {
            SymbolTile(symbol: feature.symbol,
                       ground: asked ? SnapflyTokens.protect : SnapflyTokens.hideAccentSoft,
                       glyph: asked ? Color.white : SnapflyTokens.moreGlyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideText)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(asked ? SnapflyTokens.hideAccentSoft : Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var promise: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(SnapflyTokens.protectTint)
                .accessibilityHidden(true)
            Text(L("Covering private details stays free, always."))
                .foregroundStyle(SnapflyTokens.hideText)
        }
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: The foot

    /// Restore Purchases, the terms, Apple's withdrawal and cancelling,
    /// and who sells Pro.
    private var footer: some View {
        VStack(spacing: 4) {
            if !unlocked {
                restoreButton
            }
            linkRow([
                ProFooterLink(id: "pro-terms", title: L("Terms of Use"), opensPage: true) { openURL(ProLinks.terms()) },
                ProFooterLink(id: "pro-privacy", title: L("Privacy Policy"), opensPage: true) { openURL(ProLinks.privacy()) },
                ProFooterLink(id: "pro-withdrawal", title: L("Withdrawal Policy"), opensPage: true) {
                    openURL(ProLinks.withdrawal())
                },
            ])
            linkRow([
                ProFooterLink(id: "pro-withdraw", title: L("Withdraw from Contract"), opensPage: true) {
                    openURL(ProLinks.appleWithdrawal)
                },
                ProFooterLink(id: "pro-cancel", title: L("Cancel Subscription"), opensPage: false) { managing = true },
            ])
            Text(ProOffers.seller)
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var restoreButton: some View {
        Button {
            Task { await store.restore() }
        } label: {
            HStack(spacing: 6) {
                if store.restoring {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(L("Restore Purchases"))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideAccent)
            .frame(minHeight: SnapflyTokens.touch)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(store.restoring || store.phase == .buying)
        .accessibilityIdentifier("pro-restore")
    }

    /// Links on one line with dots between them, or one under the other
    /// where the line has no room.
    private func linkRow(_ links: [ProFooterLink]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    if index > 0 {
                        Text(verbatim: "·")
                            .foregroundStyle(SnapflyTokens.hideSecondary)
                            .accessibilityHidden(true)
                    }
                    footerButton(link)
                }
            }
            VStack(spacing: 0) {
                ForEach(links) { link in
                    footerButton(link)
                }
            }
        }
        .font(.footnote)
        .padding(.horizontal, 16)
    }

    private func footerButton(_ link: ProFooterLink) -> some View {
        Button(action: link.action) {
            Text(link.title)
                .foregroundStyle(SnapflyTokens.hideAccent)
                .multilineTextAlignment(.center)
                .frame(minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(link.opensPage ? .isLink : [])
        .accessibilityIdentifier(link.id)
    }

    // MARK: The bar at the foot

    /// The one green button, a note over it when there is one, and what
    /// pressing it does, under it.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let note = store.note {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(SnapflyTokens.protectTint)
                        .accessibilityHidden(true)
                    Text(note)
                        .foregroundStyle(SnapflyTokens.hideText)
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
            // One line of words up to the largest size before the accessibility
            // sizes, so the bar never covers the page.
            mainButton
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if !typeSize.isAccessibilitySize, let words = finePrint {
                finePrintText(words)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(SnapflyTokens.hideGround.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SnapflyTokens.hideSeparator)
                .frame(height: 0.5)
        }
        .animation(SnapflyMotion.change(calm), value: store.note)
        .animation(SnapflyMotion.change(calm), value: store.phase)
    }

    @ViewBuilder
    private var mainButton: some View {
        switch store.phase {
        case .offers:
            pill(L("Subscribe")) {
                presses += 1
                Task { await store.subscribe(with: purchase) }
            }
        case .buying:
            pill(L("Subscribe"), busy: true, waiting: true)
        case .loading, .unavailable:
            pill(L("Subscribe"), waiting: true)
        case .pending:
            pill(L("Waiting for approval"), waiting: true)
        case .welcome, .subscribed, .keeps, .elsewhere:
            pill(L("Done")) { dismiss() }
        }
    }

    /// The protecting green, as wide as the bar, as Try It Now is; while it
    /// waits, More's waiting grey with dark grey words, never pale words on
    /// a pale green.
    @ViewBuilder
    private func pill(_ title: String, busy: Bool = false, waiting: Bool = false,
                      action: @escaping () -> Void = {}) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .tint(waiting ? SnapflyTokens.hideButtonOffText : Color.white)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        if waiting {
            button
                .buttonStyle(ProWaitingPillStyle())
                .disabled(true)
                .accessibilityIdentifier("pro-main")
        } else {
            button
                .buttonStyle(ProtectButtonStyle())
                .accessibilityIdentifier("pro-main")
        }
    }

    private func finePrintText(_ words: String) -> some View {
        Text(words)
            .font(.footnote)
            .foregroundStyle(SnapflyTokens.hideSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }

    /// What Subscribe does, said before it is pressed; or who is asked.
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

    /// Close, in the trailing corner: an xmark in a grey circle, with a
    /// finger's room round it.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .frame(width: 30, height: 30)
                .background(SnapflyTokens.hideButtonOff, in: Circle())
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Close"))
        .accessibilityIdentifier("pro-close")
        // VoiceOver meets it first, where it sits, above the page.
        .accessibilitySortPriority(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // The page scrolls away under the ground, never under the clock or the button.
        .background(SnapflyTokens.hideGround.ignoresSafeArea(edges: .top))
    }
}

// MARK: Pieces

/// One way to pay, as a tile to choose: its name and the check, the price
/// billed, the most prominent, what it is for, then the free trial or what
/// the year saves, and what a year comes to each month. Chosen, a green
/// ring round it.
private struct PlanTile: View {
    let offer: ProOffer
    let chosen: Bool
    let savings: Int?
    let calm: Bool
    let choose: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ProOffers.name(of: offer.period))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                    Spacer(minLength: 4)
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chosen ? SnapflyTokens.moreGlyph : SnapflyTokens.hideSecondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                Text(offer.displayPrice)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SnapflyTokens.hideText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(ProOffers.unit(of: offer.period))
                    .font(.subheadline)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                if let line = highlight {
                    Text(line)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.moreGlyph)
                }
                if let perMonth = ProOffers.perMonthLine(offer) {
                    Text(perMonth)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity, alignment: .topLeading)
            .background(SnapflyTokens.hideCard, in: shape)
            .overlay(shape.strokeBorder(chosen ? SnapflyTokens.moreGlyph : SnapflyTokens.hideSeparator,
                                        lineWidth: chosen ? 2.5 : 1))
            .contentShape(shape)
            .animation(SnapflyMotion.toggle(calm), value: chosen)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
        .accessibilityIdentifier("pro-plan-\(offer.id)")
    }

    /// The free trial first; else what the year saves, from 5%.
    private var highlight: String? {
        if let trial = ProOffers.trialLine(offer) { return trial }
        if let percent = savings { return ProOffers.savingsLine(percent) }
        return nil
    }
}

/// A tile while the prices are asked for: its words as quiet grey bars,
/// still, nothing shimmering.
private struct PlanPlaceholder: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(SnapflyTokens.hideButtonOff)
                .frame(width: 56, height: 10)
            Capsule()
                .fill(SnapflyTokens.hideButtonOff)
                .frame(width: 92, height: 20)
            Capsule()
                .fill(SnapflyTokens.hideButtonOff)
                .frame(width: 44, height: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity, alignment: .topLeading)
        .background(SnapflyTokens.hideCard, in: shape)
        .overlay(shape.strokeBorder(SnapflyTokens.hideSeparator, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The pill while Subscribe cannot be pressed yet, or the family is asked:
/// More's waiting button, dark grey words on grey, 6.5:1, as tall as the
/// green pill it stands for (`ProtectButtonStyle`).
private struct ProWaitingPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(SnapflyTokens.hideButtonOffText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(minHeight: SnapflyTokens.touch)
            .background(SnapflyTokens.hideButtonOff, in: Capsule())
            .contentShape(Capsule())
    }
}

/// A link at the screen's foot: a page on the web, or Apple's own sheet.
private struct ProFooterLink: Identifiable {
    let id: String
    let title: String
    /// Opens a page in Safari, so VoiceOver calls it a link.
    let opensPage: Bool
    let action: () -> Void
}

/// The screen's parts coming in each time it opens, after the hero's line
/// has begun: rising 8 pt and fading in, 40 ms apart (`more.appear`); with
/// calm, a short fade.
private struct ProAppear: ViewModifier {
    let shown: Bool
    let index: Int
    let calm: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || calm ? 0 : 8)
            .animation(calm ? SnapflyMotion.calm : .easeOut(duration: 0.26).delay(0.15 + Double(index) * 0.04),
                       value: shown)
    }
}

/// A view out of focus, for words coming into it.
private struct ProBlurred: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
