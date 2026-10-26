import SwiftUI

/// More (Mehr), Settings as a tab: a short overview with a page for each
/// part. The hero card says how much is covered, in the look chosen, with
/// three chips to the look, the owner's details and their rules; then
/// Protection, four tiles (What Is Covered, Always Hide, Cover Style,
/// Detection); Features, one list (AI Assistant, Send to Apps, the back tap,
/// Mac and iCloud); and Help, with the version. Every setting is kept where
/// it always was (`MoreStore`).
struct SettingsView: View {
    /// As the More tab, with a large title and no Done; else a sheet.
    var inTab = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = MoreStore()
    @ObservedObject private var sendApps = SendApps.shared
    @ObservedObject private var sync = SyncCenter.shared
    @State private var path = SettingsView.firstPath
    /// The page's parts and the hero's covers are in: at once after the
    /// first time in a launch.
    @State private var shown = MoreIntro.played
    /// The assistant set up, by its name, read again as More shows.
    @State private var assistant: String?
    @Namespace private var zoom
    @Environment(\.moreStill) private var still
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumber: CGFloat = 52

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 32) {
                    hero.modifier(MoreAppear(shown: shown, index: 0))
                    protection.modifier(MoreAppear(shown: shown, index: 1))
                    features.modifier(MoreAppear(shown: shown, index: 2))
                    help.modifier(MoreAppear(shown: shown, index: 3))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .defaultScrollAnchor(MoreSample.endAnchor)
            .background(SnapflyTokens.hideGround.ignoresSafeArea())
            .navigationTitle(inTab ? L("More") : L("Settings"))
            .navigationBarTitleDisplayMode(inTab ? .large : .inline)
            // The large title stays the system's: a solid bar under it hides
            // it on iOS 26. The pages under it have their own solid bar.
            .toolbar {
                if !inTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                }
            }
            .navigationDestination(for: MoreRoute.self) { route in
                destination(route)
            }
            .onAppear {
                // Back from Always Hide or another page, where something may have changed.
                store.reload()
                assistant = AIAccount.isSetUp ? AIAccount.provider.name : nil
                if !shown {
                    shown = true
                    MoreIntro.played = true
                }
            }
        }
    }

    /// Where More opens: Always Hide or one of its pages, as screenshots
    /// made in CI and the UI tests ask; else at its top.
    private static var firstPath: [MoreRoute] {
        #if DEBUG
        if AlwaysHideSample.requested { return [MoreRoute(page: .alwaysHide)] }
        if let page = MoreSample.page { return [MoreRoute(page: page)] }
        #endif
        return []
    }

    private func open(_ page: MorePage, from source: String? = nil) {
        path.append(MoreRoute(page: page, source: source))
    }

    @ViewBuilder
    private func destination(_ route: MoreRoute) -> some View {
        Group {
            switch route.page {
            case .covered:
                CoveredKindsView(store: store) { open(.alwaysHide) }
            case .alwaysHide:
                AlwaysHideView()
            case .style:
                CoverStylePage(store: store)
            case .detection:
                DetectionView(store: store) { open(.preparing) }
            case .assistant:
                AssistantSettings().formPage()
            case .apps:
                ChooseApps().formPage()
            case .backTap:
                BackTapSettings().formPage()
            case .macAndCloud:
                MacAndCloudView(sync: sync)
            case .preparing:
                PreparingView().formPage()
            }
        }
        .moreZoom(from: route.source, in: zoom, still: still)
    }

    // MARK: The hero

    private var hero: some View {
        let summary = store.summary
        let off = summary.isOff
        return VStack(alignment: .leading, spacing: 16) {
            // The badge beside the state, or under it at the largest sizes.
            AnyLayout(typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                      : AnyLayout(HStackLayout(spacing: 8))) {
                Label {
                    Text(off ? L("Protection Off") : L("Protection On"))
                } icon: {
                    Image(systemName: off ? "shield.slash.fill" : "checkmark.shield.fill")
                }
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                MoreBadge(title: summary.presetTitle, ground: .white.opacity(0.16), ink: .white)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("more-hero-status")

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        RollingNumber(value: summary.count)
                            .font(.system(size: heroNumber, weight: .bold))
                        Text(verbatim: "/ " + CoverSummary.total.formatted())
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .foregroundStyle(.white)
                    Text(L("Categories covered in every picture"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: L("%d of %d"), summary.count, CoverSummary.total) + ", "
                                    + L("Categories covered in every picture"))
                .accessibilityIdentifier("more-hero-count")
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    // What Is Covered grows out of the little document.
                    Button {
                        open(.covered, from: "sample-document")
                    } label: {
                        PaperThumbnail(style: store.look, drawn: shown)
                    }
                    .buttonStyle(TilePressStyle())
                    .moreZoomSource("sample-document", in: zoom, radius: 8)
                    .rotationEffect(.degrees(6))
                    .padding(.trailing, 4)
                    .accessibilityLabel(L("What Is Covered"))
                    .accessibilityIdentifier("more-hero-document")
                }
            }

            // Side by side, or one above another at the larger sizes; built
            // once, so each chip is the one place its page grows out of.
            if typeSize > .xLarge {
                VStack(spacing: 8) { chips }
            } else {
                HStack(spacing: 8) { chips }
            }
        }
        .padding(20)
        .background(off ? SnapflyTokens.moreHeroOff : SnapflyTokens.moreHero,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.moreHeroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SnapflyTokens.moreHeroRadius, style: .continuous)
                .strokeBorder(off ? Color.clear : SnapflyTokens.moreHeroEdge, lineWidth: 1)
        }
        .animation(MoreMotion.style(still), value: off)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Your Protection"))
    }

    @ViewBuilder
    private var chips: some View {
        chip(L("Style"), store.look.title, page: .style, id: "chip-style")
        chip(L("Own Details"), store.own.details.formatted(), page: .alwaysHide, id: "chip-details")
        chip(L("Rules"), store.own.activeRules.formatted(), page: .alwaysHide, id: "chip-rules")
    }

    private func chip(_ title: String, _ value: String, page: MorePage, id: String) -> some View {
        Button {
            open(page, from: id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
            .background(Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.moreButtonRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.moreButtonRadius, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .moreZoomSource(id, in: zoom, radius: SnapflyTokens.moreButtonRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ", " + value)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("more-\(id)")
    }

    // MARK: Protection

    private var protection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: L("Protection"))
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { tiles }
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        coveredTile
                        alwaysHideTile
                    }
                    GridRow {
                        styleTile
                        detectionTile
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        coveredTile
        alwaysHideTile
        styleTile
        detectionTile
    }

    private var coveredTile: some View {
        let summary = store.summary
        return tile(L("What Is Covered"), page: .covered, id: "tile-covered") {
            SymbolTile(symbol: "eye.slash")
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                MoreMeter(share: summary.share)
                Text(String(format: L("%d of %d active"), summary.count, CoverSummary.total))
                    .contentTransition(still ? .opacity : .numericText(value: Double(summary.count)))
                    .animation(MoreMotion.change(still), value: summary.count)
            }
        }
    }

    private var alwaysHideTile: some View {
        tile(L("Always Hide"), page: .alwaysHide, id: "tile-always-hide") {
            Group {
                if let initials = store.own.initials {
                    Text(verbatim: initials)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SnapflyTokens.moreGlyph)
                } else {
                    Image(systemName: "person.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.moreGlyph)
                }
            }
            .frame(width: OwnDetailTile.base, height: OwnDetailTile.base)
            .background(SnapflyTokens.hideAccentSoft, in: Circle())
            .accessibilityHidden(true)
        } detail: {
            Text(store.own.line)
        }
    }

    private var styleTile: some View {
        tile(L("Cover Style"), page: .style, id: "tile-style") {
            StyleFade(style: store.look) { style in
                PaperSketch(style: style,
                            lines: [.init(width: 0.9, covered: false), .init(width: 0.7, covered: true),
                                    .init(width: 0.8, covered: false)],
                            lineHeight: 3, spacing: 5)
            }
            .padding(8)
            .frame(width: 56, height: OwnDetailTile.base, alignment: .top)
            .background(SnapflyTokens.morePaper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SnapflyTokens.hideSeparator))
            .accessibilityHidden(true)
        } detail: {
            Text(store.look.title)
                .contentTransition(.opacity)
                .animation(MoreMotion.style(still), value: store.look)
        }
    }

    private var detectionTile: some View {
        tile(L("Detection"), page: .detection, id: "tile-detection") {
            SymbolTile(symbol: "text.viewfinder")
        } detail: {
            HStack(spacing: 8) {
                StatusDot(on: store.intelligenceOn)
                Text(store.intelligenceOn ? L("Apple Intelligence on") : L("Apple Intelligence off"))
            }
        }
    }

    private func tile<Symbol: View, Detail: View>(_ title: String, page: MorePage, id: String,
                                                  @ViewBuilder symbol: () -> Symbol,
                                                  @ViewBuilder detail: () -> Detail) -> some View {
        Button {
            open(page, from: id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                symbol()
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                        .fixedSize(horizontal: false, vertical: true)
                    detail()
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 112)
            .moreCard()
            .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .moreZoomSource(id, in: zoom, radius: SnapflyTokens.hideRowRadius)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("more-\(id)")
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: L("Features"))
            VStack(spacing: 0) {
                feature(L("AI Assistant"), symbol: "sparkles", value: assistant ?? L("Off"), page: .assistant)
                MoreDivider()
                feature(L("Send to Apps"), symbol: "paperplane", value: sendApps.chosen.count.formatted(), page: .apps)
                MoreDivider()
                feature(L("Double Tap the Back"), symbol: "hand.tap", value: nil, page: .backTap)
                if sync.isAvailable {
                    MoreDivider()
                    feature(L("Mac and iCloud"), symbol: "laptopcomputer.and.iphone",
                            value: sync.settings.on ? L("On") : L("Off"), page: .macAndCloud)
                }
            }
            .background(SnapflyTokens.hideCard,
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
        }
    }

    private func feature(_ title: String, symbol: String, value: String?, page: MorePage) -> some View {
        Button {
            open(page)
        } label: {
            HStack(spacing: 12) {
                SymbolTile(symbol: symbol, base: 32, ground: SnapflyTokens.moreNeutralTile,
                           glyph: SnapflyTokens.moreNeutralGlyph)
                Text(title)
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                        .lineLimit(1)
                }
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
        .accessibilityIdentifier("more-feature-\(page)")
    }

    // MARK: Help

    private var help: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: L("Help"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { helpButtons }
                VStack(spacing: 12) { helpButtons }
            }
            Text(versionLine)
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityIdentifier("more-version")
        }
    }

    @ViewBuilder
    private var helpButtons: some View {
        helpButton(L("Introduction"), symbol: "hand.wave", id: "more-introduction") {
            if inTab { AppTabs.shared.selection = .photos } else { dismiss() }
            // It shows on the screenshots: without Photos, the Photos tab asks
            // for them first, and no introduction waits to show up later.
            guard Library.mayReadNow else { return }
            // Once the sheet or the tab has gone, on the screenshots themselves.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                PhoneGuide.shared.start()
            }
        }
        helpButton(L("Watch the Demo"), symbol: "play.circle", id: "more-demo") {
            if !inTab { dismiss() }
            // Over everything, once a sheet has gone.
            Task { @MainActor in
                if !inTab { try? await Task.sleep(for: .seconds(0.4)) }
                FirstRunCoordinator.shared.replay()
            }
        }
    }

    private func helpButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.moreGlyph)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(12)
            .background(SnapflyTokens.hideCard,
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.moreButtonRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.moreButtonRadius, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .accessibilityIdentifier(id)
    }

    /// "Version 1.1.0 (214)", as the build has it.
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return String(format: L("Version %@ (%@)"), version, build)
    }
}

/// A line between rows of a card, from where the words start.
struct MoreDivider: View {
    var leading: CGFloat = 60
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(SnapflyTokens.hideSeparator)
            .frame(height: 1 / displayScale)
            .padding(.leading, leading)
    }
}

extension View {
    /// A pushed page of before, a list on the system's grouped background:
    /// its bar on that ground, so no words show through it, and no tab bar
    /// under it.
    func formPage() -> some View {
        self
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }

    /// A tile or a chip a page grows out of, from iOS 18 on.
    @ViewBuilder func moreZoomSource(_ id: String, in namespace: Namespace.ID, radius: CGFloat) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// The page grown out of what opened it, from iOS 18 on; the system's
    /// push with Reduce Motion, before iOS 18, or from a row.
    @ViewBuilder func moreZoom(from source: String?, in namespace: Namespace.ID, still: Bool) -> some View {
        if #available(iOS 18, *), let source, !still {
            navigationTransition(.zoom(sourceID: source, in: namespace))
        } else {
            self
        }
    }
}

/// How to cover the newest screenshot with a double tap on the back.
struct BackTapSettings: View {
    var body: some View {
        Form {
            Section {
                step(1, L("Take a screenshot as usual."))
                step(2, L("Double tap the back of your iPhone: the latest screenshot is covered and copied, ready to paste into a chat."))
                step(3, String(format: L("To set it up once, open Settings › Accessibility › Touch › Back Tap › Double Tap, and choose %@."),
                               L("Cover the Latest Screenshot")))
            } footer: {
                Text(L("Everything happens on this iPhone. Nothing is sent anywhere."))
            }
        }
        .navigationTitle(L("Double Tap the Back"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}
