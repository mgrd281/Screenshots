import SwiftUI

/// Always Hide on the Mac, its own pane in Settings, as on the iPhone: what
/// Snapfly covers in every picture besides the kinds checked under Privacy.
/// The owner's details, each with its kind's colour and a number by its
/// last four digits; their rules, each with what it covers and its switch;
/// and a sheet to add or change either.
struct AlwaysHidePane: View {
    @ObservedObject var prefs: Preferences
    @State private var detailRequest: DetailDraft?
    @State private var ruleRequest: RuleDraft?

    private var details: [OwnRule] { prefs.rules.filter(\.kind.isDetail) }
    private var rules: [OwnRule] { prefs.rules.filter { !$0.kind.isDetail } }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Snapfly covers these in every picture, on top of your categories."))
                    promises
                }
                .padding(.vertical, 4)
            }
            Section {
                if details.isEmpty {
                    start
                }
                ForEach(details) { detail in
                    DetailRow(detail: detail) {
                        detailRequest = DetailDraft(draft: detail, isNew: false)
                    } remove: {
                        prefs.removeRule(detail, named: DetailRow.name(of: detail))
                    }
                }
                Menu(L("Add Detail")) {
                    ForEach(OwnRule.Kind.details, id: \.self) { kind in
                        Button {
                            detailRequest = DetailDraft(draft: OwnRule(kind: kind), isNew: true)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text(L("Your Details"))
            } footer: {
                Text(L("Covered in every picture, whatever is checked under Privacy. They stay on this Mac alone, in its keychain, and are never sent."))
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(rules) { rule in
                    RuleRow(rule: rule) {
                        ruleRequest = RuleDraft(draft: rule, isNew: false)
                    } enable: { on in
                        prefs.setEnabled(on, rule: rule.id)
                    } remove: {
                        prefs.removeRule(rule, named: RuleRow.name(of: rule))
                    }
                }
                Menu(L("Add Rule")) {
                    ForEach(OwnRule.Kind.rules, id: \.self) { kind in
                        Button(RuleSheet.segment(kind)) {
                            ruleRequest = RuleDraft(draft: OwnRule(kind: kind), isNew: true)
                        }
                    }
                }
                .fixedSize()
            } header: {
                HStack {
                    Text(L("Your Rules"))
                    Spacer()
                    if !rules.isEmpty {
                        Text(String(format: L("%d active"), OwnRules.activeCount(rules)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } footer: {
                Text(L("Applies to every picture, also when written differently. Still check the result before you share it."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { prefs.adoptName() }
        .onDisappear { prefs.saveRules() }
        .sheet(item: $detailRequest) { request in
            DetailSheet(request: request) { kept in
                prefs.keep(kept)
                detailRequest = nil
            } cancel: {
                detailRequest = nil
            }
        }
        .sheet(item: $ruleRequest) { request in
            RuleSheet(request: request) { kept in
                prefs.keep(kept)
                ruleRequest = nil
            } cancel: {
                ruleRequest = nil
            }
        }
    }

    /// What keeps the details private, each said only while the keychain
    /// code makes it so (`OwnDetailStore`).
    private var promises: some View {
        HStack(spacing: 16) {
            if OwnDetailStore.staysOnThisDevice {
                Label(L("Only on this Mac"), systemImage: "laptopcomputer")
            }
            if OwnDetailStore.neverSent {
                Label(L("Never sent"), systemImage: "lock.fill")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// With no details yet, the owner's name first.
    private var start: some View {
        HStack(spacing: 12) {
            DetailTile(kind: .name)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Start with your name"))
                Text(L("Snapfly then also finds it written another way, like surname first or in capitals."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(L("Add Name")) {
                detailRequest = DetailDraft(draft: OwnRule(kind: .name), isNew: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: Rows

/// A detail's or a rule's sheet, as it is asked for: a new one, or one kept.
private struct DetailDraft: Identifiable {
    let id = UUID()
    var draft: OwnRule
    var isNew: Bool
}

private struct RuleDraft: Identifiable {
    let id = UUID()
    var draft: OwnRule
    var isNew: Bool
}

/// A kind of detail's symbol, white on its colour.
private struct DetailTile: View {
    let kind: OwnRule.Kind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(DetailTint.of(kind), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What is wrong, in callout: the warning's symbol in orange, the words in
/// the text colour, since system orange is too light for words on a light
/// ground.
private struct HideWarning: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.callout)
    }
}

/// A rule's symbol, quiet: "Aa" for a word, a tag for a label.
private struct RuleTile: View {
    let kind: OwnRule.Kind

    var body: some View {
        Image(systemName: RuleWords.symbol(kind))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One of the owner's details: its kind's symbol on its colour, its value
/// on one line, a number by its last four digits, and its kind; Edit… and a
/// way to take it away. The ways a name is also found stay with the matcher.
private struct DetailRow: View {
    let detail: OwnRule
    let edit: () -> Void
    let remove: () -> Void

    private var kindLine: String {
        let caption = detail.caption.trimmingCharacters(in: .whitespaces)
        let brand = detail.kind == .card ? OwnDetails.brand(of: OwnDetails.digits(detail.text))?.name : nil
        return ([detail.kind.title] + [caption.isEmpty ? brand : caption].compactMap { $0 }).joined(separator: " · ")
    }

    private var spoken: String {
        detail.kind == .name ? "\(kindLine), \(OwnDetails.masked(detail))" : OwnDetails.spoken(detail)
    }

    /// The detail as its remove button and the note after it name it: the
    /// name or the address, or a card or an account by its last digits.
    static func name(of detail: OwnRule) -> String {
        switch detail.kind {
        case .card, .account: OwnDetails.spoken(detail)
        default: OwnDetails.masked(detail)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            DetailTile(kind: detail.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: OwnDetails.masked(detail))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(kindLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken))
            Spacer(minLength: 8)
            Button(L("Edit…"), action: edit)
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(L("Remove"))
            .accessibilityLabel(Preferences.removeLabel(Self.name(of: detail)))
        }
        .padding(.vertical, 4)
    }
}

/// One of the owner's rules: its symbol, its word or label, its kind and
/// what it covers, and its switch; Edit… and a way to take it away.
private struct RuleRow: View {
    let rule: OwnRule
    let edit: () -> Void
    let enable: (Bool) -> Void
    let remove: () -> Void

    private var shown: String { Self.name(of: rule) }

    /// The rule as its row, its remove button and the note after it name it.
    static func name(of rule: OwnRule) -> String {
        rule.text.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(spacing: 12) {
            RuleTile(kind: rule.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: shown)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(2)
                Text(RuleWords.subtitle(of: rule))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !rule.isReadable {
                    HideWarning(text: L("This pattern cannot be read."))
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: enable)) {
                Text(String(format: L("Rule “%@” active"), shown))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            Button(L("Edit…"), action: edit)
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(L("Remove"))
            .accessibilityLabel(Preferences.removeLabel(Self.name(of: rule)))
        }
        .padding(.vertical, 4)
    }
}

// MARK: Sheets

/// One of the owner's details, added or changed: its kind, chosen while it
/// is new; its fields, the first focused, a name by its first and last
/// name; what is wrong with what was typed; and Add once it can be kept.
private struct DetailSheet: View {
    let request: DetailDraft
    let done: (OwnRule) -> Void
    let cancel: () -> Void

    @State private var kind: OwnRule.Kind
    @State private var given: String
    @State private var surname: String
    @State private var street: String
    @State private var postcode: String
    @State private var city: String
    @State private var card: String
    @State private var iban: String
    @State private var caption: String
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case given, surname, street, postcode, city, card, iban
    }

    init(request: DetailDraft, done: @escaping (OwnRule) -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.done = done
        self.cancel = cancel
        let draft = request.draft
        let name: (given: [String], surname: [String]) = draft.kind == .name
            ? OwnDetails.nameParts(draft.text) : (given: [], surname: [])
        _kind = State(initialValue: draft.kind.isDetail ? draft.kind : .name)
        _given = State(initialValue: name.given.joined(separator: " "))
        _surname = State(initialValue: name.surname.joined(separator: " "))
        _street = State(initialValue: draft.kind == .address ? draft.text : "")
        _postcode = State(initialValue: draft.kind == .address ? draft.postcode : "")
        _city = State(initialValue: draft.kind == .address ? draft.city : "")
        _card = State(initialValue: draft.kind == .card ? OwnDetails.digits(draft.text) : "")
        _iban = State(initialValue: draft.kind == .account ? OwnDetails.compact(iban: draft.text) : "")
        _caption = State(initialValue: draft.caption)
    }

    /// The detail as typed so far, as it would be kept.
    private var draft: OwnRule {
        var made = request.draft
        made.kind = kind
        made.postcode = ""
        made.city = ""
        made.caption = kind == .card || kind == .account ? caption : ""
        switch kind {
        case .name: made.text = OwnDetails.nameText(given: given, surname: surname)
        case .address:
            made.text = street
            made.postcode = postcode
            made.city = city
        case .card: made.text = card
        case .account: made.text = iban
        case .word, .label, .pattern: break
        }
        return OwnDetails.cleaned(made)
    }

    private var firstField: Field {
        switch kind {
        case .address: .street
        case .card: .card
        case .account: .iban
        default: .given
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.isNew ? L("New Detail") : kind.title)
                .font(.headline)
            if request.isNew {
                Picker(L("New Detail"), selection: $kind) {
                    ForEach(OwnRule.Kind.details, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 8) {
                fields
                    .textFieldStyle(.roundedBorder)
                note
            }
            HStack {
                Spacer()
                Button(L("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(request.isNew ? L("Add") : L("Save")) { done(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focus = firstField }
        .onChange(of: kind) { _, _ in focus = firstField }
    }

    @ViewBuilder private var fields: some View {
        switch kind {
        case .name:
            HStack(spacing: 8) {
                TextField(L("First Name"), text: $given, prompt: Text(L("First Name")))
                    .focused($focus, equals: .given)
                TextField(L("Last Name"), text: $surname, prompt: Text(L("Last Name")))
                    .focused($focus, equals: .surname)
            }
        case .address:
            TextField(L("Street and house number"), text: $street, prompt: Text(L("Street and house number")))
                .focused($focus, equals: .street)
            HStack(spacing: 8) {
                TextField(L("Postcode"), text: $postcode, prompt: Text(L("Postcode")))
                    .focused($focus, equals: .postcode)
                    .frame(width: 110)
                TextField(L("Town"), text: $city, prompt: Text(L("Town")))
                    .focused($focus, equals: .city)
            }
        case .card:
            HStack(spacing: 8) {
                TextField(L("Card number"), text: Binding(get: { OwnDetails.grouped(card: card) },
                                                          set: { card = String(OwnDetails.digits($0).prefix(19)) }),
                          prompt: Text(L("Card number")))
                    .font(.body.monospacedDigit())
                    .focused($focus, equals: .card)
                if let brand = OwnDetails.brand(of: card) {
                    Text(verbatim: brand.name)
                        .foregroundStyle(.secondary)
                }
            }
            TextField(L("Name for it (optional)"), text: $caption, prompt: Text(L("Name for it (optional)")))
        case .account:
            TextField(L("IBAN"), text: Binding(get: { OwnDetails.grouped(iban: iban) },
                                               set: { iban = String(OwnDetails.compact(iban: $0).prefix(34)) }),
                      prompt: Text(L("IBAN")))
                .font(.body.monospaced())
                .focused($focus, equals: .iban)
            TextField(L("Name for it (optional)"), text: $caption, prompt: Text(L("Name for it (optional)")))
        case .word, .label, .pattern:
            EmptyView()
        }
    }

    /// What is wrong with what was typed; else how it is also found.
    @ViewBuilder private var note: some View {
        if let problem {
            HideWarning(text: problem)
        } else if let hint {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var problem: String? {
        switch kind {
        case .card: OwnDetails.cardProblem(card)
        case .account: OwnDetails.ibanProblem(iban)
        default: nil
        }
    }

    private var hint: String? {
        switch kind {
        case .address: L("Also found with “Str.” for “Straße”, in capitals, and as postcode with town.")
        case .card: L("Also found in any grouping, and where only the last four digits show.")
        case .account: L("Also found with and without spaces, and where only the last digits show.")
        default: nil
        }
    }
}

/// One of the owner's rules, added or changed: a word, a label or a
/// pattern; its one field, focused; for a label, what is covered after it,
/// Automatic first, as every label rule did before there was a choice; and
/// a made-up page that shows what the rule covers, covered by the engine
/// itself (`RuleSample`), as it is typed.
private struct RuleSheet: View {
    let request: RuleDraft
    let done: (OwnRule) -> Void
    let cancel: () -> Void

    @State private var kind: OwnRule.Kind
    /// What was typed for each kind, so going to another keeps it.
    @State private var texts: [OwnRule.Kind: String]
    @State private var reach: OwnRule.Reach
    @FocusState private var focused: Bool

    init(request: RuleDraft, done: @escaping (OwnRule) -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.done = done
        self.cancel = cancel
        let kind = OwnRule.Kind.rules.contains(request.draft.kind) ? request.draft.kind : .word
        _kind = State(initialValue: kind)
        _texts = State(initialValue: [kind: request.draft.text])
        _reach = State(initialValue: request.draft.reach)
    }

    private var text: Binding<String> {
        Binding { texts[kind] ?? "" } set: { texts[kind] = $0 }
    }

    /// The rule as typed so far, as it would be kept.
    private var draft: OwnRule {
        var made = request.draft
        made.kind = kind
        made.text = (texts[kind] ?? "").trimmingCharacters(in: .whitespaces)
        made.reach = kind == .label ? reach : .automatic
        return made
    }

    private var canSave: Bool { draft.canSave }

    static func segment(_ kind: OwnRule.Kind) -> String {
        switch kind {
        case .label: L("After Label")
        case .pattern: L("Pattern")
        default: L("Word")
        }
    }

    private var placeholder: String {
        switch kind {
        case .label: L("Like Customer number")
        case .pattern: L("A pattern, like SKU-[0-9]+")
        default: L("Like your company’s name")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.isNew ? L("New Rule") : L("Edit Rule"))
                .font(.headline)
            Picker(L("Kind of Rule"), selection: $kind) {
                ForEach(OwnRule.Kind.rules, id: \.self) { kind in
                    Text(Self.segment(kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 8) {
                TextField(Self.segment(kind), text: text, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focused)
                hint
            }
            if kind == .label { reaches }
            preview
            HStack {
                Spacer()
                Button(L("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(L("Save Rule")) { done(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focused = true }
        .onChange(of: kind) { _, _ in focused = true }
    }

    @ViewBuilder private var hint: some View {
        if !draft.isReadable {
            HideWarning(text: L("This pattern cannot be read."))
        } else if kind != .pattern {
            Text(kind == .label ? L("Found where a line begins with it, in capitals or small letters.")
                 : L("Covered everywhere, whether written in capitals or small letters."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// What a label covers: automatically, the rest of its line, or the line below.
    private var reaches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What is covered?"))
                .font(.subheadline.weight(.semibold))
            Picker(L("What is covered?"), selection: $reach) {
                ForEach(OwnRule.Reach.allCases, id: \.self) { option in
                    Text(RuleWords.title(option)).tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            Text(RuleWords.detail(reach))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The made-up page, as the rule covers it.
    private var preview: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(L("Preview"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(L("Example"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if let sample = RuleSample.of(draft) {
                    ForEach(Array(sample.lines.enumerated()), id: \.offset) { _, line in
                        CoveredLineText(line: line)
                            .accessibilityLabel(Text(verbatim: line.spoken))
                    }
                    if kind == .label, reach == .automatic {
                        Text(L("With nothing after it, the line below is covered."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(kind == .pattern ? L("There is no preview for a pattern.") : L("Type something to see what is covered."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
