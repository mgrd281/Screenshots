import SwiftUI

/// Always Hide (Immer verbergen), from More: what Snapfly covers in every
/// picture, whatever kinds are chosen. Under the title, what keeps it
/// private; then the owner's details, each on its kind's colour, a number
/// by its last four digits and a name with the ways it is also found; then
/// the owner's rules, each with its switch; with nothing yet, a start with
/// the name and two kinds of rule. Edit reorders and deletes, a swipe
/// deletes, and a tap opens a row's sheet (`DetailSheet`, `RuleSheet`).
struct AlwaysHideView: View {
    @StateObject private var store: AlwaysHideStore
    @State private var detailRequest: DetailRequest?
    @State private var ruleRequest: RuleRequest?
    @State private var editMode = EditMode.inactive
    #if DEBUG
    @State private var sampleOpened = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var change: Animation { SnapflyMotion.change(reduceMotion) }

    /// The owner's own, or for previews a made-up set held in memory.
    init(store: @autoclosure @escaping () -> AlwaysHideStore = AlwaysHideStore()) {
        _store = StateObject(wrappedValue: store())
    }

    var body: some View {
        List {
            intro
            if store.isEmpty {
                HideStart(addName: { detailRequest = .new(.name) }, addRule: { ruleRequest = .new($0) })
            } else {
                details
                rules
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .scrollContentBackground(.hidden)
        .background(SnapflyTokens.hideGround)
        .environment(\.editMode, $editMode)
        .animation(change, value: store.isEmpty)
        .navigationTitle(L("Always Hide"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !store.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .environment(\.editMode, $editMode)
                        .accessibilityIdentifier("always-hide-edit")
                }
            }
        }
        // The pages under More keep the tab bar's minimised button off their rows.
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $detailRequest) { request in
            DetailSheet(request: request) { kept in
                withAnimation(change) { store.put(detail: kept) }
            } remove: {
                withAnimation(change) { store.remove(detail: request.draft.id) }
            }
        }
        .sheet(item: $ruleRequest) { request in
            RuleSheet(request: request) { kept in
                withAnimation(change) { store.put(rule: kept) }
            } remove: {
                withAnimation(change) { store.remove(rule: request.draft.id) }
            }
        }
        .onAppear {
            // A name saved as a word before there were details becomes the name detail.
            if OwnRules.adoptName() { store.reload() }
            openSample()
        }
        .onChange(of: store.isEmpty) { _, empty in
            if empty { editMode = .inactive }
        }
        .onDisappear { editMode = .inactive }
    }

    // MARK: Parts

    /// What the screen does, and what keeps it private.
    private var intro: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Snapfly covers these in every picture, on top of your categories."))
                    .font(.subheadline)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrivacyStrip()
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var details: some View {
        Section {
            ForEach(store.details) { detail in
                HideDetailRow(detail: detail) { detailRequest = .edit(detail) }
                    .listRowBackground(HideRowBackground(top: detail.id == store.details.first?.id, bottom: false))
            }
            .onDelete { offsets in withAnimation(change) { store.deleteDetails(at: offsets) } }
            .onMove { from, to in store.moveDetails(from: from, to: to) }
            HideAddRow(title: L("Add Detail"), identifier: "always-hide-add-detail") { detailRequest = .new(.name) }
                .listRowBackground(HideRowBackground(top: store.details.isEmpty, bottom: true))
        } header: {
            HideHeader(title: L("Your Details"))
        }
    }

    private var rules: some View {
        Section {
            ForEach(store.rules) { rule in
                HideRuleRow(rule: rule) {
                    ruleRequest = .edit(rule)
                } enable: { on in
                    withAnimation(change) { store.setEnabled(on, rule: rule.id) }
                }
                .listRowBackground(HideRowBackground(top: rule.id == store.rules.first?.id, bottom: false))
            }
            .onDelete { offsets in withAnimation(change) { store.deleteRules(at: offsets) } }
            .onMove { from, to in store.moveRules(from: from, to: to) }
            HideAddRow(title: L("Add Rule"), identifier: "always-hide-add-rule") { ruleRequest = .new(.word) }
                .listRowBackground(HideRowBackground(top: store.rules.isEmpty, bottom: true))
        } header: {
            HideHeader(title: L("Your Rules"),
                       trailing: store.rules.isEmpty ? nil : String(format: L("%d active"), store.activeRules))
        } footer: {
            HideFooter()
        }
    }

    /// For screenshots made in CI and the UI tests: the sheet the sample
    /// asks for, once the page is there.
    private func openSample() {
        #if DEBUG
        guard !sampleOpened else { return }
        sampleOpened = true
        if AlwaysHideSample.opensEditing { editMode = .active }
        let detail = AlwaysHideSample.detail(from: store.details)
        let rule = AlwaysHideSample.rule
        guard detail != nil || rule != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            if let detail { detailRequest = detail }
            if let rule { ruleRequest = rule }
        }
        #endif
    }
}

// MARK: What it keeps

/// What Always Hide shows and changes: the owner's details and rules, kept
/// as they change. For screenshots made in CI and the UI tests, a made-up
/// set held in memory alone (`AlwaysHideSample`), never kept.
@MainActor
final class AlwaysHideStore: ObservableObject {
    @Published private(set) var details: [OwnRule]
    @Published private(set) var rules: [OwnRule]
    /// A sample's: changed in memory, never written anywhere.
    private let inMemory: Bool

    init() {
        #if DEBUG
        if let sample = AlwaysHideSample.content {
            details = sample.details
            rules = sample.rules
            inMemory = true
            return
        }
        #endif
        details = OwnRules.all.filter(\.kind.isDetail)
        rules = OwnRules.load()
        inMemory = false
    }

    /// Made-up details and rules, changed in memory alone, never kept.
    init(holding details: [OwnRule], rules: [OwnRule]) {
        self.details = details
        self.rules = rules
        inMemory = true
    }

    var isEmpty: Bool { details.isEmpty && rules.isEmpty }

    /// How many rules cover something now.
    var activeRules: Int { rules.filter(\.isActive).count }

    func reload() {
        guard !inMemory else { return }
        details = OwnRules.all.filter(\.kind.isDetail)
        rules = OwnRules.load()
    }

    func put(detail: OwnRule) {
        if let i = details.firstIndex(where: { $0.id == detail.id }) { details[i] = detail } else { details.append(detail) }
        keep()
    }

    func remove(detail id: UUID) {
        details.removeAll { $0.id == id }
        keep()
    }

    func put(rule: OwnRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = rule } else { rules.append(rule) }
        keep()
    }

    func remove(rule id: UUID) {
        rules.removeAll { $0.id == id }
        keep()
    }

    func setEnabled(_ on: Bool, rule id: UUID) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].isEnabled = on
        keep()
    }

    func deleteDetails(at offsets: IndexSet) {
        details.remove(atOffsets: offsets)
        keep()
    }

    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        keep()
    }

    func moveDetails(from offsets: IndexSet, to place: Int) {
        details.move(fromOffsets: offsets, toOffset: place)
        keep()
    }

    func moveRules(from offsets: IndexSet, to place: Int) {
        rules.move(fromOffsets: offsets, toOffset: place)
        keep()
    }

    /// The rules to the settings, the details to the keychain.
    private func keep() {
        guard !inMemory else { return }
        OwnRules.all = rules + details
    }
}

/// What keeps the owner's details private, each said only while the code
/// makes it so (`OwnDetailStore`): Always Hide's strip, and the line over a
/// detail's button.
enum AlwaysHidePromise: CaseIterable {
    case onThisPhone, noBackup, neverSent

    var holds: Bool {
        switch self {
        case .onThisPhone: OwnDetailStore.staysOnThisDevice
        case .noBackup: OwnDetailStore.staysOutOfBackups
        case .neverSent: OwnDetailStore.neverSent
        }
    }

    var title: String {
        switch self {
        case .onThisPhone: L("Only on this iPhone")
        case .noBackup: L("No backup")
        case .neverSent: L("Never sent")
        }
    }

    var symbol: String {
        switch self {
        case .onThisPhone: "iphone"
        case .noBackup: "icloud.slash"
        case .neverSent: "lock.fill"
        }
    }

    static var shown: [AlwaysHidePromise] { allCases.filter(\.holds) }

    /// The line over a detail's button, as much of it as holds.
    static var sentence: String? {
        switch (onThisPhone.holds, noBackup.holds, neverSent.holds) {
        case (true, true, true): L("Stays on this iPhone alone. No backup, never sent.")
        case (true, false, true): L("Stays on this iPhone alone and is never sent.")
        case (true, _, false): L("Stays on this iPhone alone.")
        case (false, _, true): L("Never sent.")
        case (false, _, false): nil
        }
    }
}

// MARK: Rows

/// One of the owner's details: its kind's symbol on its colour, its value,
/// a number by its last four digits, its kind, and for a name the ways it is
/// also found, two of them and how many more. A tap opens it to change it.
struct HideDetailRow: View {
    let detail: OwnRule
    let open: () -> Void
    @ScaledMetric(relativeTo: .body) private var tile = OwnDetailTile.base

    /// The ways the name is also found, besides as it is written.
    private var others: [String] {
        detail.kind == .name ? Array(OwnDetails.nameVariants(detail.text).dropFirst()) : []
    }

    private var kindLine: String {
        let caption = detail.caption.trimmingCharacters(in: .whitespaces)
        let brand = detail.kind == .card ? OwnDetails.brand(of: OwnDetails.digits(detail.text))?.name : nil
        return ([detail.kind.title] + [caption.isEmpty ? brand : caption].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                OwnDetailTile(kind: detail.kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: OwnDetails.masked(detail))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(SnapflyTokens.hideText)
                        .lineLimit(3)
                    Text(kindLine)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                    if !others.isEmpty {
                        AlsoFinds(variants: others)
                            .padding(.top, 4)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: tile)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("always-hide-detail")
    }

    private var spoken: String {
        let said = detail.kind == .name ? "\(kindLine), \(OwnDetails.masked(detail))" : OwnDetails.spoken(detail)
        guard !others.isEmpty else { return said }
        return said + ". " + L("Also finds") + " " + others.joined(separator: ", ")
    }
}

/// "Also finds" and two of the other ways of a name, with how many more.
private struct AlsoFinds: View {
    let variants: [String]

    var body: some View {
        ChipFlow(spacing: 8) {
            Text(L("Also finds"))
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
            ForEach(variants.prefix(2), id: \.self) { variant in
                HideChip(text: variant)
            }
            if variants.count > 2 {
                HideChip(text: String(format: L("+%d"), variants.count - 2))
            }
        }
    }
}

/// One of the owner's rules: its symbol, its word or label, what it covers,
/// a label's sample, and its switch. A tap on the words opens it to change it.
struct HideRuleRow: View {
    let rule: OwnRule
    let open: () -> Void
    let enable: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    HideRuleTile(kind: rule.kind)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: rule.text.trimmingCharacters(in: .whitespaces))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(rule.isEnabled ? SnapflyTokens.hideText : SnapflyTokens.hideSecondary)
                            .lineLimit(3)
                        Text(Self.subtitle(of: rule))
                            .font(.footnote)
                            .foregroundStyle(SnapflyTokens.hideSecondary)
                        if rule.kind == .label {
                            LabelChip(label: rule.text)
                                .padding(.top, 4)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: rule.text + ", " + Self.subtitle(of: rule)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("always-hide-rule")
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: enable)) {
                Text(String(format: L("Rule “%@” active"), rule.text.trimmingCharacters(in: .whitespaces)))
            }
            .labelsHidden()
            .tint(SnapflyTokens.hideSwitch)
            .accessibilityIdentifier("always-hide-rule-switch")
        }
        .padding(.vertical, 4)
    }

    /// What a rule covers, after its kind: "Word · anywhere in the picture".
    static func subtitle(of rule: OwnRule) -> String {
        switch (rule.kind, rule.reach) {
        case (.label, .automatic): L("Label · automatic")
        case (.label, .restOfLine): L("Label · rest of the line")
        case (.label, .nextLine): L("Label · next line")
        case (.pattern, _): L("Pattern · anywhere in the picture")
        default: L("Word · anywhere in the picture")
        }
    }
}

/// A label with a covered value after it, as a rule's row shows it.
private struct LabelChip: View {
    let label: String

    var body: some View {
        let shown = label.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        CoveredLineText(segments: [(String(format: L("%@:"), shown) + " ", false), ("00000", true)])
            .font(.footnote)
            .foregroundStyle(SnapflyTokens.hideSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SnapflyTokens.hideGround, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// The last row of a section: a plus and what it adds, in green.
private struct HideAddRow: View {
    let title: String
    let identifier: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var tile = OwnDetailTile.base

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: tile, height: tile)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 0)
            }
            .foregroundStyle(SnapflyTokens.hideAccent)
            .frame(minHeight: SnapflyTokens.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// A row's own part of its section's card: white, its corners round where
/// the section begins and ends.
struct HideRowBackground: View {
    let top: Bool
    let bottom: Bool

    var body: some View {
        let radius = SnapflyTokens.hideRowRadius
        UnevenRoundedRectangle(topLeadingRadius: top ? radius : 0, bottomLeadingRadius: bottom ? radius : 0,
                               bottomTrailingRadius: bottom ? radius : 0, topTrailingRadius: top ? radius : 0,
                               style: .continuous)
            .fill(SnapflyTokens.hideCard)
    }
}

/// A section's title, and what it counts.
private struct HideHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .accessibilityIdentifier("always-hide-active-count")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(SnapflyTokens.hideSecondary)
        .textCase(nil)
    }
}

/// What covering one's own details is, and is not: a help that still wants
/// a look before sharing.
private struct HideFooter: View {
    var body: some View {
        Text(L("Applies to every picture, also when written differently. Still check the result before you share it."))
            .font(.footnote)
            .foregroundStyle(SnapflyTokens.hideSecondary)
    }
}

/// What keeps the owner's details private, each where the code makes it
/// so: side by side, one under another where they do not fit.
private struct PrivacyStrip: View {
    var body: some View {
        let promises = AlwaysHidePromise.shown
        if !promises.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { items(promises) }
                VStack(alignment: .leading, spacing: 8) { items(promises) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SnapflyTokens.hideAccentSoft,
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("always-hide-privacy")
        }
    }

    private func items(_ promises: [AlwaysHidePromise]) -> some View {
        ForEach(promises, id: \.self) { promise in
            Label {
                Text(promise.title)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: promise.symbol)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideAccent)
        }
    }
}

// MARK: With nothing yet

/// Always Hide with nothing yet: the owner's name first, the one detail
/// worth adding before any other, then a word or a label to start a rule.
private struct HideStart: View {
    let addName: () -> Void
    let addRule: (OwnRule.Kind) -> Void
    @ScaledMetric(relativeTo: .body) private var tile = OwnDetailTile.base

    var body: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "person.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .frame(width: tile * 2, height: tile * 2)
                    .background(SnapflyTokens.hideAccentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(L("Start with your name"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SnapflyTokens.hideText)
                        .accessibilityAddTraits(.isHeader)
                    Text(L("Snapfly then also finds it written another way, like surname first or in capitals."))
                        .font(.subheadline)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: addName) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                        Text(L("Add Name"))
                    }
                }
                .buttonStyle(HidePrimaryButtonStyle())
                .accessibilityIdentifier("always-hide-add-name")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(HideRowBackground(top: true, bottom: true))
        }
        Section {
            HideTemplateRow(kind: .word, title: L("Word"), detail: L("Like your company’s name")) { addRule(.word) }
                .listRowBackground(HideRowBackground(top: true, bottom: false))
            HideTemplateRow(kind: .label, title: L("After Label"), detail: L("Like Customer number")) { addRule(.label) }
                .listRowBackground(HideRowBackground(top: false, bottom: true))
        } header: {
            HideHeader(title: L("Or start with a rule"))
        } footer: {
            HideFooter()
        }
    }
}

/// A kind of rule to start with, as Always Hide offers it with nothing yet.
private struct HideTemplateRow: View {
    let kind: OwnRule.Kind
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HideRuleTile(kind: kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: SnapflyTokens.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(kind == .word ? "always-hide-template-word" : "always-hide-template-label")
    }
}

// MARK: Made-up content

/// For screenshots made in CI and the UI tests: Always Hide open on a
/// made-up name, address, card, account and rules, or on none, and maybe a
/// sheet over it, as `-SnapflyAlwaysHide <state>` asks; kept in memory
/// alone. Nothing of it is in a release build. The card and the IBAN are
/// the ones banks print as examples.
enum AlwaysHideSample {
    #if DEBUG
    /// What was asked for: filled, empty, editing, name, address, card,
    /// account, word, label, labelNext or editCard.
    static let state: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SnapflyAlwaysHide"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var requested: Bool { state != nil }

    static let name = OwnRule(text: OwnDetails.nameText(given: "Max", surname: "Mustermann"), kind: .name)
    static let address = OwnRule(text: "Musterstraße 12", kind: .address, postcode: "12345", city: "Musterstadt")
    static let card = OwnRule(text: "4242424242424242", kind: .card)
    static let account = OwnRule(text: "DE89370400440532013000", kind: .account)

    static var content: (details: [OwnRule], rules: [OwnRule])? {
        guard let state else { return nil }
        guard state != "empty" else { return ([], []) }
        return ([name, address, card, account], rules)
    }

    static let rules = [OwnRule(text: "Musterfirma", kind: .word),
                        OwnRule(text: "Kundennummer", kind: .label, reach: .restOfLine),
                        OwnRule(text: "Aktenzeichen", kind: .label, reach: .nextLine, isEnabled: false)]

    static var opensEditing: Bool { state == "editing" }

    /// The detail's sheet the sample opens, from the details it shows.
    static func detail(from details: [OwnRule]) -> DetailRequest? {
        switch state ?? "" {
        case "name": return DetailRequest(draft: name, isNew: true, choosing: true)
        case "address": return DetailRequest(draft: address, isNew: true, choosing: true)
        case "card": return DetailRequest(draft: card, isNew: true, choosing: true)
        case "account": return DetailRequest(draft: account, isNew: true, choosing: true)
        case "editCard": return details.first { $0.kind == .card }.map { DetailRequest.edit($0) }
        default: return nil
        }
    }

    /// The made-up set, for previews.
    @MainActor static var store: AlwaysHideStore {
        AlwaysHideStore(holding: [name, address, card, account], rules: rules)
    }

    /// The rule's sheet the sample opens.
    static var rule: RuleRequest? {
        switch state ?? "" {
        case "word": RuleRequest(draft: OwnRule(text: "Projekt Nordlicht", kind: .word), isNew: true)
        case "label": RuleRequest(draft: OwnRule(text: "Kundennummer", kind: .label), isNew: true)
        case "labelNext": RuleRequest(draft: OwnRule(text: "Aktenzeichen", kind: .label, reach: .nextLine), isNew: true)
        default: nil
        }
    }
    #else
    static let requested = false
    #endif
}

#if DEBUG
#Preview("Always Hide") {
    NavigationStack { AlwaysHideView(store: AlwaysHideSample.store) }
}

#Preview("Always Hide, dark") {
    NavigationStack { AlwaysHideView(store: AlwaysHideSample.store) }
        .preferredColorScheme(.dark)
}

#Preview("Always Hide, XXXL") {
    NavigationStack { AlwaysHideView(store: AlwaysHideSample.store) }
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Nothing yet") {
    NavigationStack { AlwaysHideView(store: AlwaysHideStore(holding: [], rules: [])) }
}

#Preview("Nothing yet, dark, XXXL") {
    NavigationStack { AlwaysHideView(store: AlwaysHideStore(holding: [], rules: [])) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Rows") {
    List {
        HideDetailRow(detail: OwnRule(text: OwnDetails.nameText(given: "Max", surname: "Mustermann"), kind: .name)) {}
        HideDetailRow(detail: OwnRule(text: "4242424242424242", kind: .card)) {}
        HideDetailRow(detail: OwnRule(text: "DE89370400440532013000", kind: .account)) {}
        HideRuleRow(rule: OwnRule(text: "Kundennummer", kind: .label, reach: .restOfLine)) {} enable: { _ in }
        HideRuleRow(rule: OwnRule(text: "Musterfirma", kind: .word, isEnabled: false)) {} enable: { _ in }
    }
}

#Preview("Rows, dark, XXXL") {
    List {
        HideDetailRow(detail: OwnRule(text: OwnDetails.nameText(given: "Erika", surname: "Musterfrau"), kind: .name)) {}
        HideRuleRow(rule: OwnRule(text: "Kundennummer", kind: .label)) {} enable: { _ in }
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.xxxLarge)
}
#endif
