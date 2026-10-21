import SwiftUI

/// Always Hide (Immer verbergen), from More: what Snapfly covers in every
/// picture, whatever kinds are chosen. Under an inline title, what it does
/// and, in one quiet line, what keeps it private; then the owner's details,
/// each on its kind's colour with a number by its last four digits; then the
/// owner's rules, each with its switch and how many are on; with nothing
/// yet, a start with the name and two kinds of rule. Edit reorders and
/// deletes, a swipe deletes, and a tap opens a row's sheet (`DetailSheet`,
/// `RuleSheet`).
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

    /// The owner's own.
    init() {
        _store = StateObject(wrappedValue: AlwaysHideStore())
    }

    /// For previews, a made-up set held in memory.
    init(store: AlwaysHideStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        List {
            if store.isEmpty {
                HideStart(addName: { detailRequest = .new(.name, choosing: false) },
                          addRule: { ruleRequest = .new($0) })
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
        .navigationBarTitleDisplayMode(.inline)
        // The bar is the page's own ground, so nothing shows through it.
        .toolbarBackground(SnapflyTokens.hideGround, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !store.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? L("Done") : L("Edit")) {
                        withAnimation(change) { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .fontWeight(editMode.isEditing ? .semibold : .regular)
                    .tint(SnapflyTokens.hideAccent)
                    .accessibilityIdentifier("always-hide-edit")
                }
            }
        }
        // The pages under More keep the tab bar's minimised button off their rows.
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $detailRequest) { request in
            DetailSheet(request: request) { kept in
                withAnimation(change) { store.put(detail: kept) }
            }
        }
        .sheet(item: $ruleRequest) { request in
            RuleSheet(request: request) { kept in
                withAnimation(change) { store.put(rule: kept) }
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

    private var details: some View {
        Section {
            ForEach(store.details) { detail in
                HideDetailRow(detail: detail) { detailRequest = .edit(detail) }
                    .listRowBackground(HideRowBackground(top: detail.id == store.details.first?.id, bottom: false))
            }
            .onDelete { offsets in withAnimation(change) { store.deleteDetails(at: offsets) } }
            .onMove { from, to in store.moveDetails(from: from, to: to) }
            HideAddRow(title: L("Add Detail"), identifier: "always-hide-add-detail") {
                detailRequest = .new(.name, choosing: true)
            }
            .listRowBackground(HideRowBackground(top: store.details.isEmpty, bottom: true))
        } header: {
            VStack(alignment: .leading, spacing: 0) {
                HideIntro()
                HideHeader(title: L("Your Details"))
                    .padding(.top, 24)
            }
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
        self.rules = rules.filter { !$0.isBlank }
        inMemory = true
    }

    var isEmpty: Bool { details.isEmpty && rules.isEmpty }

    /// How many rules cover something now, as their switches show.
    var activeRules: Int { OwnRules.activeCount(rules) }

    func reload() {
        guard !inMemory else { return }
        details = OwnRules.all.filter(\.kind.isDetail)
        rules = OwnRules.load()
    }

    /// A detail as its sheet keeps it; never one that covers nothing.
    func put(detail: OwnRule) {
        guard detail.canSave else { return }
        if let i = details.firstIndex(where: { $0.id == detail.id }) { details[i] = detail } else { details.append(detail) }
        keep()
    }

    func remove(detail id: UUID) {
        details.removeAll { $0.id == id }
        keep()
    }

    /// A rule as its sheet keeps it; never an empty one.
    func put(rule: OwnRule) {
        guard rule.canSave else { return }
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
/// makes it so (`OwnDetailStore`): the line under Always Hide's words, and
/// the line over a detail's button.
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

    /// What holds, in one line: "Nur auf diesem iPhone · Nie gesendet".
    static var line: String? {
        let held = allCases.filter(\.holds).map(\.title)
        return held.isEmpty ? nil : held.joined(separator: " · ")
    }

    /// The line over a detail's button.
    static var hint: String {
        onThisPhone.holds ? L("Stays on this iPhone alone. Other spellings are found too.")
            : L("Other spellings are found too.")
    }
}

// MARK: Rows

/// What the page does, and what keeps it private, in one quiet line.
private struct HideIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Snapfly covers these in every picture, on top of your categories."))
                .font(.subheadline)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let line = AlwaysHidePromise.line {
                Label {
                    Text(line)
                } icon: {
                    Image(systemName: "lock")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideAccent)
                .labelStyle(TightLabelStyle())
                .accessibilityIdentifier("always-hide-privacy")
            }
        }
        .textCase(nil)
    }
}

/// An icon and its words, closer than a list's label puts them.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// One of the owner's details: its kind's symbol on its colour, its value
/// on one line, a number by its last four digits, and its kind. A tap opens
/// it to change it.
struct HideDetailRow: View {
    let detail: OwnRule
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var kindLine: String {
        let caption = detail.caption.trimmingCharacters(in: .whitespaces)
        let brand = detail.kind == .card ? OwnDetails.brand(of: OwnDetails.digits(detail.text))?.name : nil
        return ([detail.kind.title] + [caption.isEmpty ? brand : caption].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                OwnDetailTile(kind: detail.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: OwnDetails.masked(detail))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(kindLine)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: SnapflyTokens.hideRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: detail.kind == .name ? "\(kindLine), \(OwnDetails.masked(detail))"
                                 : OwnDetails.spoken(detail)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("always-hide-detail")
    }
}

/// One of the owner's rules: its symbol, its word or label, its kind and
/// what it covers, and its switch. A tap on the words opens it to change it.
struct HideRuleRow: View {
    let rule: OwnRule
    let open: () -> Void
    let enable: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var shown: String { rule.text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    HideRuleTile(kind: rule.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: shown)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(rule.isEnabled ? SnapflyTokens.hideText : SnapflyTokens.hideSecondary)
                        Text(RuleWords.subtitle(of: rule))
                            .font(.footnote)
                            .foregroundStyle(SnapflyTokens.hideSecondary)
                    }
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: SnapflyTokens.hideRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: shown + ", " + RuleWords.subtitle(of: rule)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("always-hide-rule")
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: enable)) {
                Text(String(format: L("Rule “%@” active"), shown))
            }
            .labelsHidden()
            .tint(SnapflyTokens.hideAccent)
            .accessibilityIdentifier("always-hide-rule-switch")
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    /// What a rule covers, after its kind: "Wort · überall im Bild".
    static func subtitle(of rule: OwnRule) -> String { RuleWords.subtitle(of: rule) }
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
                    .frame(width: tile)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SnapflyTokens.hideAccent)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.footnote)
                    .monospacedDigit()
                    .accessibilityIdentifier("always-hide-active-count")
            }
        }
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
        } header: {
            HideIntro()
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SnapflyTokens.hideRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
    /// What was asked for: filled, empty, editing, picker, name, address,
    /// card, account, editCard, word, label or labelNext.
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
                        OwnRule(text: "Kundennummer", kind: .label),
                        OwnRule(text: "Aktenzeichen", kind: .label, reach: .nextLine, isEnabled: false)]

    static var opensEditing: Bool { state == "editing" }

    /// The detail's sheet the sample opens, from the details it shows: the
    /// list of kinds, or a kind's fields as if chosen from it.
    static func detail(from details: [OwnRule]) -> DetailRequest? {
        switch state ?? "" {
        case "picker": return .new(.name, choosing: true)
        case "name": return .chosen(name)
        case "address": return .chosen(address)
        case "card": return .chosen(card)
        case "account": return .chosen(account)
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
        HideRuleRow(rule: OwnRule(text: "Kundennummer", kind: .label)) {} enable: { _ in }
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
