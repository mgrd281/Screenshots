import SwiftUI

/// What Is Covered (Was verdeckt wird), from More: how many kinds of the
/// twenty-two are on, with the preset they make; Recommended, All and None;
/// the five groups as tabs; and each group a card of pills, one per kind,
/// with All On or All Off. A pill turns its kind on or off with a selection
/// haptic; a preset or a group's button runs down the pills it changes, with
/// one light tap. The choice is kept where it always was (`Choice.details`);
/// the presets write what Check All, Recommended and Uncheck All wrote.
struct CoveredKindsView: View {
    @ObservedObject var store: MoreStore
    let openOwnDetails: () -> Void
    /// The group shown alone; nil shows them all.
    @State private var group: CoverGroup?
    /// How long each pill waits as a preset or a group runs down them.
    @State private var cascade: [PrivateDetail: Double] = [:]
    @State private var toggled = 0
    @State private var changedMany = 0
    @Namespace private var tabs
    @Environment(\.moreStill) private var still

    init(store: MoreStore, openOwnDetails: @escaping () -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.openOwnDetails = openOwnDetails
        #if DEBUG
        _group = State(initialValue: MoreSample.group)
        #endif
    }

    private var summary: CoverSummary { store.summary }

    private var shownGroups: [CoverGroup] { group.map { [$0] } ?? CoverGroup.allCases }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PresetControl(selection: summary.preset, choose: { apply($0.kinds) })
                groupTabs
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(shownGroups) { group in
                        card(group)
                        if group == .people { namesNote }
                    }
                }
                .id(group)
                .transition(.opacity)
                ownDetails
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .defaultScrollAnchor(MoreSample.endAnchor)
        .background(SnapflyTokens.hideGround.ignoresSafeArea())
        .morePage(L("What Is Covered"))
        .sensoryFeedback(.selection, trigger: toggled)
        .sensoryFeedback(.impact(weight: .light), trigger: changedMany)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The badge beside the count, or under it at the largest sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) { count }
                VStack(alignment: .leading, spacing: 8) { count }
            }
            Text(L("Categories covered in every picture"))
                .font(.subheadline)
                .foregroundStyle(SnapflyTokens.hideSecondary)
        }
    }

    @ViewBuilder
    private var count: some View {
        Text(String(format: L("%d of %d"), summary.count, CoverSummary.total))
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(SnapflyTokens.hideText)
            .contentTransition(still ? .opacity : .numericText(value: Double(summary.count)))
            .animation(MoreMotion.change(still), value: summary.count)
            .accessibilityIdentifier("more-covered-count")
        MoreBadge(title: summary.presetTitle)
            .contentTransition(.opacity)
            .animation(MoreMotion.change(still), value: summary.presetTitle)
            .accessibilityIdentifier("more-covered-badge")
    }

    /// The groups as tabs, All first; the one chosen in a dark capsule that
    /// slides to the next, scrolled into view.
    private var groupTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tab(nil, title: L("All"))
                    ForEach(CoverGroup.allCases) { group in
                        tab(group, title: group.shortTitle + " " + summary.count(in: group).formatted() + "/"
                                + group.kinds.count.formatted())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -16)
            .onChange(of: group) { _, now in
                withAnimation(MoreMotion.change(still)) {
                    proxy.scrollTo(Self.tabID(now), anchor: .center)
                }
            }
            .onAppear { proxy.scrollTo(Self.tabID(group), anchor: .center) }
        }
    }

    private static func tabID(_ group: CoverGroup?) -> String {
        group.map { "tab-\($0)" } ?? "tab-all"
    }

    private func tab(_ choice: CoverGroup?, title: String) -> some View {
        let on = group == choice
        return Button {
            withAnimation(MoreMotion.change(still)) { group = choice }
        } label: {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(on ? SnapflyTokens.hideCard : SnapflyTokens.hideText)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background {
                    if on {
                        Capsule()
                            .fill(SnapflyTokens.hideText)
                            .matchedGeometryEffect(id: "tab", in: tabs, isSource: true)
                    } else {
                        Capsule().fill(SnapflyTokens.hideCard)
                    }
                }
                .contentShape(Capsule().inset(by: -3))
        }
        .buttonStyle(TilePressStyle())
        .id(Self.tabID(choice))
        .accessibilityLabel(choice?.title ?? L("All"))
        .accessibilityValue(choice.map { String(format: L("%d of %d active"), summary.count(in: $0), $0.kinds.count) } ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(Self.tabID(choice))
    }

    private func card(_ group: CoverGroup) -> some View {
        let count = summary.count(in: group)
        let whole = summary.isWhole(group)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(SnapflyTokens.hideText)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(format: L("%d of %d active"), count, group.kinds.count))
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                        .contentTransition(still ? .opacity : .numericText(value: Double(count)))
                        .animation(MoreMotion.change(still), value: count)
                }
                Spacer(minLength: 8)
                Button {
                    apply(summary.setting(group, on: !whole))
                } label: {
                    Text(whole ? L("All Off") : L("All On"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideAccent)
                        .frame(minHeight: SnapflyTokens.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((whole ? L("All Off") : L("All On")) + ", " + group.title)
                .accessibilityIdentifier("more-group-all-\(group)")
            }
            PillFlow(spacing: 8, lineSpacing: 8) {
                ForEach(group.kinds, id: \.self) { kind in
                    KindPill(kind: kind, on: store.chosen.contains(kind), delay: cascade[kind] ?? 0) {
                        toggle(kind)
                    }
                }
            }
        }
        .moreCard()
    }

    /// What Names, Patient names and Other people each cover.
    private var namesNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([PrivateDetail.names, .patientNames, .otherPeople], id: \.self) { kind in
                Text(kind.title).fontWeight(.semibold) + Text(verbatim: ": " + (kind.subtitle ?? ""))
            }
            Text(L("All three together cover everyone’s names."))
        }
        .font(.footnote)
        .foregroundStyle(SnapflyTokens.hideSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// The way to the owner's own name, address and rules, in Always Hide.
    private var ownDetails: some View {
        Button(action: openOwnDetails) {
            HStack(spacing: 12) {
                SymbolTile(symbol: "person.text.rectangle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Your Own Details"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(L("Your name, address, cards and rules, covered in every picture"))
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .moreCard()
            .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("more-own-details")
    }

    // MARK: Changing

    /// One kind turned, with a selection haptic.
    private func toggle(_ kind: PrivateDetail) {
        cascade = [:]
        withAnimation(MoreMotion.change(still)) { store.choose(summary.toggling(kind)) }
        toggled += 1
    }

    /// A preset or a group's button: the pills it changes one after another,
    /// down the page as it shows, with one light tap.
    private func apply(_ kinds: Set<PrivateDetail>) {
        let shown = Set(shownGroups.flatMap(\.kinds))
        let changed = CoverSummary.changed(from: store.chosen, to: kinds)
        guard !changed.isEmpty else { return }
        cascade = still ? [:] : MoreMotion.cascade(changed.filter(shown.contains))
        withAnimation(MoreMotion.change(still)) { store.choose(kinds) }
        changedMany += 1
    }
}

/// Recommended, All and None, as a segmented control: the one the choice
/// is, raised on a white thumb that slides to the next; none raised when
/// the choice is the owner's own.
struct PresetControl: View {
    let selection: CoverPreset?
    let choose: (CoverPreset) -> Void
    @Namespace private var thumb
    @Environment(\.moreStill) private var still

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CoverPreset.allCases) { preset in
                let on = preset == selection
                Button {
                    choose(preset)
                } label: {
                    Text(preset.title)
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .foregroundStyle(SnapflyTokens.hideText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                Capsule()
                                    .fill(SnapflyTokens.moreThumb)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("more-preset-\(preset.rawValue)")
            }
        }
        .padding(4)
        .background(SnapflyTokens.moreTrack, in: Capsule())
        .animation(MoreMotion.change(still), value: selection)
        .accessibilityElement(children: .contain)
    }
}

/// A kind as a pill: solid green with a check when on, the card inside a
/// grey edge when off. Its colour turns in 0.18 s, the check grows in, and
/// its width and its neighbours follow on `.snappy`; with Reduce Motion the
/// check's room stays, so nothing moves, and the colour fades.
struct KindPill: View {
    let kind: PrivateDetail
    let on: Bool
    /// Its place in a cascade, in seconds.
    let delay: Double
    let toggle: () -> Void
    @Environment(\.moreStill) private var still

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                if on || still {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .opacity(on ? 1 : 0)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                Text(kind.title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(on ? SnapflyTokens.morePillOnText : SnapflyTokens.hideText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .background(on ? SnapflyTokens.morePillOn : SnapflyTokens.hideCard, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : SnapflyTokens.morePillEdge, lineWidth: 1))
            .contentShape(Capsule().inset(by: -3))
            .animation(MoreMotion.pill(delay: delay, still: still), value: on)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel(kind.title)
        .accessibilityValue(on ? L("Active") : L("Off"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("more-pill-\(kind.rawValue)")
    }
}
