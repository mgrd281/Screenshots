import SwiftUI

/// What Is Covered (Was verdeckt wird), from More, as a live preview: a
/// made-up document on a green stage in which every kind chosen is covered
/// in the owner's look, three of them to page between; then six tiles, one
/// for each group and one for the owner's own details. A group's tile opens
/// a short sheet of switches over the stage, which shrinks to stay whole
/// above it; every switch sweeps a cover over the matching value, paging to
/// a document that shows it first. The "…" menu holds the presets, which
/// write what Check All, Recommended and Uncheck All wrote. The choice is
/// kept where it always was (`Choice.details`), through the one `MoreStore`
/// More's hero and tile read.
struct CoveredKindsView: View {
    @ObservedObject var store: MoreStore
    let openOwnDetails: () -> Void
    @State private var sample: CoverStudioSample
    /// The group whose sheet is open.
    @State private var sheet: CoverGroup?
    /// When each kind's cover starts, for the change under way.
    @State private var delays: [PrivateDetail: Double] = [:]
    @State private var toggled = 0
    @State private var changedMany = 0
    @Environment(\.moreStill) private var still
    @Environment(\.dynamicTypeSize) private var typeSize

    init(store: MoreStore, openOwnDetails: @escaping () -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.openOwnDetails = openOwnDetails
        #if DEBUG
        // The made-up states the simulator's frames open on.
        let group = MoreSample.group
        let opened = group.map { CoverStudioSample.showing($0) }
        _sample = State(initialValue: MoreSample.studioSample ?? opened ?? .bill)
        _sheet = State(initialValue: group)
        #else
        _sample = State(initialValue: .bill)
        _sheet = State(initialValue: nil)
        #endif
    }

    private var summary: CoverSummary { store.summary }

    var body: some View {
        GeometryReader { page in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 20) {
                        CoverStage(store: store, sample: $sample, focus: sheet, delays: delays,
                                   width: max(0, page.size.width - 32),
                                   room: sheet == nil ? nil : Self.room(above: page))
                            .id("stage")
                        tiles
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .defaultScrollAnchor(MoreSample.endAnchor)
                .onChange(of: sheet) { _, open in
                    guard open != nil else { return }
                    withAnimation(still ? MoreMotion.fade : .smooth(duration: 0.35)) {
                        scroller.scrollTo("stage", anchor: .top)
                    }
                }
            }
        }
        .background(SnapflyTokens.hideGround.ignoresSafeArea())
        .morePage(L("What Is Covered"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .sheet(item: $sheet) { group in
            CoverGroupSheet(group: group, store: store, toggle: toggle, apply: { apply($0, on: CoverStudioSample.showing(group)) })
                .presentationDetents([.fraction(0.55), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.55)))
                .presentationCornerRadius(SnapflyTokens.hideSheetRadius)
                .presentationDragIndicator(.visible)
                .presentationBackground(SnapflyTokens.hideCard)
        }
        .onChange(of: sheet) { _, open in
            // The group's document shows as its sheet opens.
            guard let open else { return }
            page(to: CoverStudioSample.showing(open))
        }
        .sensoryFeedback(.selection, trigger: toggled)
        .sensoryFeedback(.impact(weight: .light), trigger: changedMany)
    }

    /// How tall the stage may be while a sheet stands at its first height:
    /// from under the bar to the sheet's top, a little less.
    private static func room(above page: GeometryProxy) -> CGFloat {
        let top = page.frame(in: .global).minY
        let screen = top + page.size.height + page.safeAreaInsets.bottom
        return max(0, screen * 0.45 - top - 16)
    }

    // MARK: The menu

    /// Recommended, all on or all off, the one the choice is checked.
    private var menu: some View {
        Menu {
            ForEach(CoverPreset.allCases) { preset in
                Toggle(isOn: Binding(get: { summary.preset == preset }, set: { on in
                    if on { apply(preset.kinds, on: sample) }
                })) {
                    Text(preset.menuTitle)
                }
                .accessibilityIdentifier("more-preset-\(preset.rawValue)")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("More Options"))
        .accessibilityIdentifier("more-covered-menu")
    }

    // MARK: The tiles

    private var tiles: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(CoverGroup.allCases) { groupTile($0) }
                    ownTile
                }
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        groupTile(.people)
                        groupTile(.money)
                    }
                    GridRow {
                        groupTile(.health)
                        groupTile(.documents)
                    }
                    GridRow {
                        groupTile(.access)
                        ownTile
                    }
                }
            }
        }
    }

    private func groupTile(_ group: CoverGroup) -> some View {
        let on = summary.count(in: group)
        return Button {
            sheet = group
        } label: {
            StudioTile {
                SymbolTile(symbol: group.symbol)
                Spacer(minLength: 8)
                GroupRing(share: summary.share(of: group), count: on)
            } title: {
                Text(group.shortTitle)
            } detail: {
                Text(summary.status(of: group))
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.shortTitle + ", " + String(format: L("%d of %d active"), on, group.kinds.count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("more-group-\(group)")
    }

    private var ownTile: some View {
        Button(action: openOwnDetails) {
            StudioTile {
                Group {
                    if let initials = store.own.initials {
                        Text(verbatim: initials)
                            .font(.subheadline.weight(.bold))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.callout.weight(.semibold))
                    }
                }
                .foregroundStyle(SnapflyTokens.moreGlyph)
                .frame(width: OwnDetailTile.base, height: OwnDetailTile.base)
                .background(SnapflyTokens.hideAccentSoft, in: Circle())
                Spacer(minLength: 8)
                Image(systemName: "lock")
                    .font(.callout)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
            } title: {
                Text(L("Own Details"))
            } detail: {
                Text(L("Always covered"))
            }
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Own Details") + ", " + L("Always covered"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("more-own-details")
    }

    // MARK: Changing

    /// The document turned to, on its own or before a cover sweeps on it.
    private func page(to target: CoverStudioSample) {
        guard target != sample else { return }
        withAnimation(still ? MoreMotion.fade : .smooth(duration: 0.3)) { sample = target }
    }

    /// One kind turned, with a selection haptic: on a document that shows
    /// it, paging there first.
    private func toggle(_ kind: PrivateDetail) {
        let target = CoverStudioSample.showing(kind, from: sample)
        delays = [kind: target == sample || still ? 0 : 0.3]
        page(to: target)
        store.choose(summary.toggling(kind))
        toggled += 1
    }

    /// A preset or a group's button: the covers one after another down the
    /// document, with one light tap.
    private func apply(_ kinds: Set<PrivateDetail>, on target: CoverStudioSample) {
        let changed = CoverSummary.changed(from: store.chosen, to: kinds)
        guard !changed.isEmpty else { return }
        let paged = target != sample
        page(to: target)
        var delays = still ? [:] : CoverSummary.sweep(changed, on: target)
        if paged && !still { delays = delays.mapValues { $0 + 0.3 } }
        self.delays = delays
        store.choose(kinds)
        changedMany += 1
    }
}

// MARK: - The stage

/// The green stage: which document it is, the document itself on white
/// paper, tilted a little, with dots to page by, and how many kinds are
/// covered with the preset they make. Grey with nothing covered. While a
/// group's sheet is open, the words above and below fade and the paper
/// shrinks, so the stage stays whole above the sheet.
private struct CoverStage: View {
    @ObservedObject var store: MoreStore
    @Binding var sample: CoverStudioSample
    let focus: CoverGroup?
    let delays: [PrivateDetail: Double]
    /// How wide it is.
    let width: CGFloat
    /// How tall it may be while a sheet is open; nil while none is.
    let room: CGFloat?
    @Environment(\.moreStill) private var still
    /// How far a sideways drag has moved the documents.
    @GestureState(resetTransaction: Transaction(animation: .smooth(duration: 0.3))) private var drag: CGFloat = 0

    private static let padding: CGFloat = 18
    private static let compactPadding: CGFloat = 12
    /// The dots' row with the room above it.
    private static let dots: CGFloat = 32
    /// The paper as tall as it shows, its tilt and shadow included.
    private static let paperRoom = CoverSampleDocument.size.height + 12

    var body: some View {
        let summary = store.summary
        let compact = room != nil
        let layout = Self.layout(width: width, room: room)
        VStack(spacing: 0) {
            topRow
                .frame(height: compact ? 0 : nil, alignment: .top)
                .opacity(compact ? 0 : 1)
                .clipped()
                .padding(.bottom, compact ? 0 : 12)
            pages(scale: layout.scale)
            if layout.dots {
                dots
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            bottomRow(summary)
                .frame(height: compact ? 0 : nil, alignment: .bottom)
                .opacity(compact ? 0 : 1)
                .clipped()
                .padding(.top, compact ? 0 : 14)
        }
        .padding(compact ? Self.compactPadding : Self.padding)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: SnapflyTokens.moreStageRadius, style: .continuous)
                .fill(summary.isOff ? SnapflyTokens.moreHeroOff : SnapflyTokens.moreHero)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SnapflyTokens.moreStageRadius, style: .continuous)
                .strokeBorder(summary.isOff ? Color.clear : SnapflyTokens.moreHeroEdge, lineWidth: 1)
        }
        .animation(still ? MoreMotion.fade : .smooth(duration: 0.35), value: compact)
        .animation(MoreMotion.style(still), value: summary.isOff)
    }

    /// How large the paper is and whether the dots fit: as large as the
    /// stage is wide, and while a sheet is open as fits the room above it,
    /// not under three quarters; without the dots where they don't fit.
    static func layout(width: CGFloat, room: CGFloat?) -> (scale: CGFloat, dots: Bool) {
        let wide = min(1, (width - 2 * padding) / (CoverSampleDocument.size.width + 12))
        guard let room else { return (wide, true) }
        let withDots = (room - 2 * compactPadding - dots) / paperRoom
        if withDots >= 0.75 { return (min(wide, withDots), true) }
        let without = (room - 2 * compactPadding) / paperRoom
        return (min(wide, max(0.75, without)), false)
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text(sample.title)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
                .lineLimit(1)
            Spacer(minLength: 8)
            StageBadge(title: L("Example"))
        }
        .foregroundStyle(.white)
    }

    private func bottomRow(_ summary: CoverSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) { count(summary); Spacer(minLength: 8); badge(summary) }
            VStack(alignment: .leading, spacing: 8) { count(summary); badge(summary) }
        }
    }

    private func count(_ summary: CoverSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            RollingNumber(value: summary.count)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text(String(format: L("/ %d covered"), CoverSummary.total))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SnapflyTokens.moreStageMint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("%d of %d"), summary.count, CoverSummary.total))
        .accessibilityIdentifier("more-covered-count")
    }

    private func badge(_ summary: CoverSummary) -> some View {
        StageBadge(title: summary.presetTitle)
            .contentTransition(.opacity)
            .animation(MoreMotion.change(still), value: summary.presetTitle)
            .accessibilityIdentifier("more-covered-badge")
    }

    // MARK: The documents

    @ViewBuilder
    private func pages(scale: CGFloat) -> some View {
        let size = CoverSampleDocument.size
        Group {
            if still {
                // Reduce Motion: one at a time, cross-fading.
                paper(sample, scale: scale)
                    .id(sample)
                    .transition(.opacity)
                    .gesture(DragGesture(minimumDistance: 24).onEnded { swipe in
                        let step = swipe.translation.width < 0 ? 1 : -1
                        move(by: step)
                    })
            } else {
                // All three side by side, moved by the document shown, so
                // the stage always shows the one it names, and a page turned
                // to before a sweep is there to sweep on.
                GeometryReader { box in
                    let width = box.size.width
                    HStack(spacing: 0) {
                        ForEach(CoverStudioSample.allCases) { page in
                            paper(page, scale: scale)
                                .frame(width: width)
                        }
                    }
                    .offset(x: -CGFloat(sample.rawValue) * width + drag)
                    .frame(width: width, alignment: .leading)
                }
                .environment(\.layoutDirection, .leftToRight)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .updating($drag) { swipe, drag, _ in
                        // Sideways only; up and down scroll the page.
                        guard abs(swipe.translation.width) > abs(swipe.translation.height) else { return }
                        drag = edged(swipe.translation.width)
                    }
                    .onEnded { swipe in
                        let width = swipe.predictedEndTranslation.width
                        guard abs(swipe.translation.width) > abs(swipe.translation.height), abs(width) > 60 else { return }
                        turn(by: width < 0 ? 1 : -1)
                    })
                // The paper's shadow shows past the top and the foot, never
                // the next document past the sides.
                .mask(Rectangle().padding(.vertical, -60))
            }
        }
        .frame(height: (size.height + 12) * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("Example %@, %d of %d details covered"), sample.title,
                                   sample.covered(by: store.chosen), sample.fields.count))
        .accessibilityAdjustableAction { direction in
            move(by: direction == .increment ? 1 : -1)
        }
        .accessibilityIdentifier("more-sample-document")
    }

    private func paper(_ page: CoverStudioSample, scale: CGFloat) -> some View {
        let size = CoverSampleDocument.size
        return CoverSampleDocument(sample: page, chosen: store.chosen, style: store.look, focus: focus,
                                   delays: page == sample ? delays : [:])
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 20, y: 18)
            .rotationEffect(.degrees(-1.5))
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: (size.height + 12) * scale)
    }

    /// A drag past the first or the last document gives way less.
    private func edged(_ width: CGFloat) -> CGFloat {
        let last = sample == CoverStudioSample.allCases.last
        let first = sample == CoverStudioSample.allCases.first
        return (width < 0 && last) || (width > 0 && first) ? width / 3 : width
    }

    /// A swipe: the next or the previous document, stopping at the ends.
    private func turn(by step: Int) {
        guard let next = CoverStudioSample(rawValue: sample.rawValue + step) else { return }
        withAnimation(.smooth(duration: 0.3)) { sample = next }
    }

    private func move(by step: Int) {
        let all = CoverStudioSample.allCases
        guard let index = all.firstIndex(of: sample) else { return }
        let next = all[(index + step + all.count) % all.count]
        withAnimation(still ? MoreMotion.fade : .smooth(duration: 0.3)) { sample = next }
    }

    /// The dots under the paper: the one shown a capsule, the others dots,
    /// each a way to its document.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(CoverStudioSample.allCases) { page in
                Button {
                    withAnimation(still ? MoreMotion.fade : .smooth(duration: 0.3)) { sample = page }
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(page == sample ? 1 : 0.45))
                        .frame(width: page == sample ? 18 : 6, height: 6)
                        .frame(height: SnapflyTokens.touch / 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .studioGlass(in: Capsule())
        // In the order the documents lie, in every language.
        .environment(\.layoutDirection, .leftToRight)
        .animation(still ? MoreMotion.fade : .snappy, value: sample)
    }
}

/// A word on the stage in a glass capsule: Liquid Glass from iOS 26, a thin
/// material before; a solid green with Reduce Transparency.
private struct StageBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .studioGlass(in: Capsule())
    }
}

extension View {
    /// Glass on the green stage, for its badges and dots.
    @ViewBuilder fileprivate func studioGlass<S: Shape>(in shape: S) -> some View {
        modifier(StudioGlass(shape: shape))
    }
}

private struct StudioGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        if solid {
            content.background(Color(red: 31 / 255, green: 90 / 255, blue: 71 / 255), in: shape)
        } else {
            glass(content)
        }
    }

    @ViewBuilder private func glass(_ content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - The tiles

/// A tile of What Is Covered, as More's tiles: what it is and how it stands
/// at the top, its name and its state under them.
private struct StudioTile<Top: View, Title: View, Detail: View>: View {
    @ViewBuilder let top: () -> Top
    @ViewBuilder let title: () -> Title
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 0) { top() }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                title()
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideText)
                detail()
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 112)
        .moreCard()
        .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
    }
}

/// How much of a group is on: a ring of 26 pt with the count in it.
private struct GroupRing: View {
    let share: Double
    let count: Int
    @Environment(\.moreStill) private var still

    var body: some View {
        ZStack {
            Circle()
                .stroke(SnapflyTokens.moreRingTrack, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, share)))
                .stroke(SnapflyTokens.moreRingProgress, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(count, format: .number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SnapflyTokens.hideText)
                .contentTransition(still ? .opacity : .numericText(value: Double(count)))
        }
        .frame(width: 26, height: 26)
        .animation(still ? MoreMotion.fade : .snappy, value: share)
        .accessibilityHidden(true)
    }
}

// MARK: - A group's sheet

/// A group's switches, in a sheet over the page: its name and a way to
/// close, how many are on with a way to turn them all, then the kinds, in
/// parts for People and Companies. A row turns its kind wherever it is
/// touched.
private struct CoverGroupSheet: View {
    let group: CoverGroup
    @ObservedObject var store: MoreStore
    let toggle: (PrivateDetail) -> Void
    let apply: (Set<PrivateDetail>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = store.summary
        let whole = summary.isWhole(group)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    Text(group.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SnapflyTokens.hideText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(SnapflyTokens.moreNeutralGlyph)
                            .frame(width: 30, height: 30)
                            .background(SnapflyTokens.moreNeutralTile, in: Circle())
                            .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Close"))
                    .accessibilityIdentifier("more-sheet-close")
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(String(format: L("%d of %d active"), summary.count(in: group), group.kinds.count))
                        .font(.subheadline)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(summary.count(in: group))))
                        .accessibilityIdentifier("more-sheet-count")
                    Spacer(minLength: 8)
                    Button {
                        apply(summary.setting(group, on: !whole))
                    } label: {
                        Text(whole ? L("Turn All Off") : L("Turn All On"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SnapflyTokens.hideAccent)
                            .frame(minHeight: SnapflyTokens.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more-sheet-all")
                }
                ForEach(group.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = section.title {
                            Text(title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(SnapflyTokens.hideSecondary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(section.kinds.enumerated()), id: \.element) { index, kind in
                                if index > 0 { MoreDivider(leading: 58) }
                                KindRow(kind: kind, on: store.chosen.contains(kind)) { toggle(kind) }
                            }
                        }
                        .background(SnapflyTokens.moreSheetRow,
                                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
                        if let footer = section.footer {
                            Text(footer)
                                .font(.footnote)
                                .foregroundStyle(SnapflyTokens.hideSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }
}

/// A kind and its switch, 52 pt at least: its symbol on mint when on, on
/// grey when off.
private struct KindRow: View {
    let kind: PrivateDetail
    let on: Bool
    let toggle: () -> Void
    @Environment(\.moreStill) private var still

    var body: some View {
        HStack(spacing: 12) {
            // The rest of the row turns it too; the switch keeps its own tap.
            HStack(spacing: 12) {
                SymbolTile(symbol: kind.symbol, base: 32,
                           ground: on ? SnapflyTokens.hideAccentSoft : SnapflyTokens.moreNeutralTile,
                           glyph: on ? SnapflyTokens.moreGlyph : SnapflyTokens.moreNeutralGlyph)
                    .animation(MoreMotion.change(still), value: on)
                Text(kind.title)
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            Toggle(isOn: Binding(get: { on }, set: { _ in toggle() })) {
                Text(kind.title)
            }
            .labelsHidden()
            .tint(SnapflyTokens.hideAccent)
            .accessibilityLabel(kind.title)
            .accessibilityValue(on ? L("is covered") : L("is not covered"))
            .accessibilityIdentifier("more-kind-\(kind.rawValue)")
        }
        .padding(.horizontal, 14)
    }
}
