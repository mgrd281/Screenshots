import SwiftUI

// MARK: A detail

/// A detail's sheet, as it is asked for: a new one, with the four kinds to
/// choose from or the one given, or one kept, to change.
struct DetailRequest: Identifiable {
    let id = UUID()
    var draft: OwnRule
    var isNew: Bool
    /// The kinds offered as tiles, the draft's chosen.
    var choosing: Bool

    static func new(_ kind: OwnRule.Kind, choosing: Bool = true) -> DetailRequest {
        DetailRequest(draft: OwnRule(kind: kind), isNew: true, choosing: choosing)
    }

    static func edit(_ detail: OwnRule) -> DetailRequest {
        DetailRequest(draft: detail, isNew: false, choosing: false)
    }
}

/// One of the owner's details, added or changed: the four kinds as tiles,
/// the chosen one with a green edge and a check; its fields, the first
/// focused, Return going on to the next and then adding it; for a name, the
/// ways it is also found, live as it is typed, the very list the covering
/// looks for (`OwnDetails.nameVariants`); what keeps it private over the
/// button, which waits until what was typed can be right: an IBAN or a
/// card's number that adds up, a name. A kept card's or account's number
/// shows hidden until Show is tapped, and a kept detail can be deleted.
struct DetailSheet: View {
    let request: DetailRequest
    let save: (OwnRule) -> Void
    let remove: () -> Void

    @State private var kind: OwnRule.Kind
    @State private var given: String
    @State private var surname: String
    @State private var street: String
    @State private var postcode: String
    @State private var city: String
    @State private var card: String
    @State private var iban: String
    @State private var revealed = false
    @State private var deleting = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale

    enum Field: String, Hashable {
        case given, surname, street, postcode, city, card, iban
    }

    init(request: DetailRequest, save: @escaping (OwnRule) -> Void, remove: @escaping () -> Void) {
        self.request = request
        self.save = save
        self.remove = remove
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
    }

    /// The detail as typed so far, as it would be kept.
    private var draft: OwnRule {
        var made = request.draft
        // A card's or an account's own name stays with its kind.
        if made.kind != kind { made.caption = "" }
        made.kind = kind
        made.postcode = ""
        made.city = ""
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

    private var canKeep: Bool { OwnDetails.canKeep(draft) }

    private var changed: Bool {
        request.isNew ? !draft.isBlank : draft != OwnDetails.cleaned(request.draft)
    }

    /// The fields of the kind chosen, in the order Return goes through them.
    private var fields: [Field] {
        switch kind {
        case .name: [.given, .surname]
        case .address: [.street, .postcode, .city]
        case .card: [.card]
        case .account: [.iban]
        case .word, .label, .pattern: []
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if request.choosing { kinds }
                        VStack(alignment: .leading, spacing: 8) {
                            fieldsCard
                            note
                        }
                        if kind == .name { variants }
                        if !request.isNew { deleteButton }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .animation(SnapflyMotion.change(reduceMotion), value: kind)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { _, field in
                    guard let field else { return }
                    // Once the keyboard is up, the field in the middle of what is left.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        withAnimation(SnapflyMotion.change(reduceMotion)) { proxy.scrollTo(field, anchor: .center) }
                    }
                }
            }
            .background(SnapflyTokens.hideGround)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(request.isNew ? L("New Detail") : kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .onAppear {
                // A kept number stays hidden until it is shown.
                if request.isNew || kind == .name || kind == .address { focusFirst() }
            }
        }
        .presentationDragIndicator(.visible)
        // What was typed is not lost to a swipe down.
        .interactiveDismissDisabled(changed)
    }

    // MARK: Parts

    private var kinds: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(OwnRule.Kind.details, id: \.self) { tile in
                KindTile(kind: tile, chosen: tile == kind) { choose(tile) }
            }
        }
    }

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            switch kind {
            case .name:
                field(L("First Name"), text: $given, as: .given, content: .givenName)
                separator
                field(L("Last Name"), text: $surname, as: .surname, content: .familyName)
            case .address:
                field(L("Street and house number"), text: $street, as: .street, content: .fullStreetAddress)
                separator
                field(L("Postcode"), text: $postcode, as: .postcode, content: .postalCode, keyboard: .numbersAndPunctuation,
                      capitals: .characters)
                separator
                field(L("Town"), text: $city, as: .city, content: .addressCity)
            case .card:
                number(L("Card number"), grouped: OwnDetails.grouped(card: card), as: .card) { typed in
                    card = String(OwnDetails.digits(typed).prefix(19))
                }
            case .account:
                number(L("IBAN"), grouped: OwnDetails.grouped(iban: iban), as: .iban) { typed in
                    iban = String(OwnDetails.compact(iban: typed).prefix(34))
                }
            case .word, .label, .pattern:
                EmptyView()
            }
        }
        .hideCard()
    }

    private var separator: some View {
        Rectangle()
            .fill(SnapflyTokens.hideSeparator)
            .frame(height: 1 / displayScale)
            .padding(.leading, 16)
    }

    private func field(_ title: String, text: Binding<String>, as field: Field, content: UITextContentType,
                       keyboard: UIKeyboardType = .default, capitals: TextInputAutocapitalization = .words) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .accessibilityHidden(true)
            TextField(title, text: text, prompt: Text(verbatim: ""))
                .font(.body)
                .foregroundStyle(SnapflyTokens.hideText)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitals)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .submitLabel(field == fields.last ? .done : .next)
                .onSubmit { advance(from: field) }
                .accessibilityIdentifier("always-hide-field-" + field.rawValue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
        .id(field)
    }

    /// A card's or an account's number: grouped as typed, the card's network
    /// beside it; kept already, hidden until Show is tapped.
    @ViewBuilder
    private func number(_ title: String, grouped: String, as field: Field, typed: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .accessibilityHidden(true)
            if request.isNew || revealed {
                HStack(spacing: 8) {
                    TextField(title, text: Binding(get: { grouped }, set: typed), prompt: Text(verbatim: ""))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(SnapflyTokens.hideText)
                        .keyboardType(field == .card ? .numbersAndPunctuation : .asciiCapable)
                        .textContentType(field == .card ? .creditCardNumber : nil)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: field)
                        .submitLabel(.done)
                        .onSubmit { advance(from: field) }
                        .accessibilityIdentifier("always-hide-field-" + field.rawValue)
                    if field == .card, let brand = OwnDetails.brand(of: card) {
                        Text(verbatim: brand.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SnapflyTokens.hideSecondary)
                            .transition(.opacity)
                    }
                }
                .animation(SnapflyMotion.change(reduceMotion), value: OwnDetails.brand(of: card))
            } else {
                HStack(spacing: 8) {
                    Text(verbatim: OwnDetails.masked(request.draft))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(SnapflyTokens.hideText)
                    Spacer(minLength: 8)
                    Button {
                        revealed = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.1))
                            focus = field
                        }
                    } label: {
                        Image(systemName: "eye")
                            .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                    }
                    .buttonStyle(.borderless)
                    .tint(SnapflyTokens.hideAccent)
                    .accessibilityLabel(L("Show Number"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
        .id(field)
    }

    /// What is wrong with what was typed; else how it is also found.
    @ViewBuilder
    private var note: some View {
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideWarning)
        } else if let hint {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .padding(.horizontal, 16)
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

    /// The ways the name is also found, as they are typed.
    private var variants: some View {
        let shown = OwnDetails.nameVariants(draft.text)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("Also recognized"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .accessibilityAddTraits(.isHeader)
            if shown.isEmpty {
                Text(L("Type your name to see how it is also found."))
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
            } else {
                ChipFlow(spacing: 8) {
                    ForEach(shown, id: \.self) { variant in
                        HideChip(text: variant)
                    }
                }
                .animation(SnapflyMotion.change(reduceMotion), value: shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .hideCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("always-hide-variants")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleting = true
        } label: {
            Text(L("Delete Detail"))
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .hideCard()
        .confirmationDialog(L("Delete Detail"), isPresented: $deleting, titleVisibility: .hidden) {
            Button(L("Delete Detail"), role: .destructive) {
                remove()
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    /// What keeps it private, as much of it as holds, over the button.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let sentence = AlwaysHidePromise.sentence {
                Label {
                    Text(sentence)
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .frame(maxWidth: .infinity)
            }
            Button(action: submit) {
                Text(request.isNew ? L("Add") : L("Save"))
            }
            .buttonStyle(HidePrimaryButtonStyle())
            .disabled(!canKeep)
            .accessibilityIdentifier("always-hide-save-detail")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(SnapflyTokens.hideGround)
    }

    // MARK: Doing

    private func choose(_ tile: OwnRule.Kind) {
        guard tile != kind else { return }
        withAnimation(SnapflyMotion.change(reduceMotion)) { kind = tile }
        focusFirst()
    }

    private func focusFirst() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            focus = fields.first
        }
    }

    /// Return: the next field, or, after the last, the detail added.
    private func advance(from field: Field) {
        if let i = fields.firstIndex(of: field), i + 1 < fields.count {
            focus = fields[i + 1]
        } else if canKeep {
            submit()
        }
    }

    private func submit() {
        guard canKeep else { return }
        save(draft)
        dismiss()
    }
}

/// One of the four kinds of detail as a tile: its symbol on its colour and
/// its name; chosen, a green edge and a check.
private struct KindTile: View {
    let kind: OwnRule.Kind
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                OwnDetailTile(kind: kind)
                Text(kind.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
            .background(SnapflyTokens.hideCard, in: shape)
            .overlay {
                shape.strokeBorder(chosen ? SnapflyTokens.hideAccent : SnapflyTokens.hideSeparator,
                                   lineWidth: chosen ? SnapflyTokens.hideChosenEdge : SnapflyTokens.hideHairline)
            }
            .overlay(alignment: .topTrailing) {
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SnapflyTokens.hideAccent)
                        .font(.title3)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("always-hide-kind-" + kind.rawValue)
    }
}

// MARK: A rule

/// A rule's sheet, as it is asked for: a new one of a kind, or one kept.
struct RuleRequest: Identifiable {
    let id = UUID()
    var draft: OwnRule
    var isNew: Bool

    static func new(_ kind: OwnRule.Kind) -> RuleRequest {
        RuleRequest(draft: OwnRule(kind: kind), isNew: true)
    }

    static func edit(_ rule: OwnRule) -> RuleRequest {
        RuleRequest(draft: rule, isNew: false)
    }
}

/// One of the owner's rules, added or changed: a word or a label, chosen
/// above; its one field, focused; for a label, what is covered after it,
/// Automatic first, as every label rule did before there was a choice; and
/// a made-up page that shows, live, what the rule covers, covered by the
/// engine itself (`RuleSample`). A pattern kept before can be changed here,
/// though new ones are made on the Mac.
struct RuleSheet: View {
    let request: RuleRequest
    let save: (OwnRule) -> Void
    let remove: () -> Void

    @State private var kind: OwnRule.Kind
    /// What was typed for each kind, so going to the other keeps it.
    @State private var texts: [OwnRule.Kind: String]
    @State private var reach: OwnRule.Reach
    @State private var deleting = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    init(request: RuleRequest, save: @escaping (OwnRule) -> Void, remove: @escaping () -> Void) {
        self.request = request
        self.save = save
        self.remove = remove
        let kind = OwnRule.Kind.rules.contains(request.draft.kind) ? request.draft.kind : .word
        _kind = State(initialValue: kind)
        _texts = State(initialValue: [kind: request.draft.text])
        _reach = State(initialValue: request.draft.reach)
    }

    /// The kinds to choose from: a pattern only where one is kept.
    private var kinds: [OwnRule.Kind] {
        request.draft.kind == .pattern ? [.word, .label, .pattern] : [.word, .label]
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

    private var canSave: Bool { !draft.isBlank && draft.isReadable }

    private var changed: Bool {
        request.isNew ? !draft.isBlank : draft != request.draft
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker(L("Kind of Rule"), selection: $kind) {
                        ForEach(kinds, id: \.self) { kind in
                            Text(Self.segment(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("always-hide-rule-kind")
                    VStack(alignment: .leading, spacing: 8) {
                        fieldCard
                        hint
                    }
                    if kind == .label { reaches }
                    preview
                    if !request.isNew { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(SnapflyMotion.change(reduceMotion), value: kind)
                .animation(SnapflyMotion.change(reduceMotion), value: reach)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SnapflyTokens.hideGround)
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            .navigationTitle(request.isNew ? L("New Rule") : L("Edit Rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    focused = true
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(changed)
    }

    // MARK: Parts

    static func segment(_ kind: OwnRule.Kind) -> String {
        switch kind {
        case .label: L("After Label")
        case .pattern: L("Pattern")
        default: L("Word")
        }
    }

    private var fieldTitle: String {
        switch kind {
        case .label: L("Label")
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

    private var fieldCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fieldTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .accessibilityHidden(true)
            TextField(fieldTitle, text: text, prompt: Text(placeholder))
                .font(.body)
                .foregroundStyle(SnapflyTokens.hideText)
                .textInputAutocapitalization(kind == .pattern ? .never : .sentences)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if canSave { submit() } }
                .accessibilityIdentifier("always-hide-rule-text")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
        .hideCard()
    }

    @ViewBuilder
    private var hint: some View {
        if !draft.isReadable {
            Label(L("This pattern cannot be read."), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideWarning)
        } else {
            Text(kind == .label ? L("Found where a line begins with it, in capitals or small letters.")
                 : L("Covered everywhere, whether written in capitals or small letters."))
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .padding(.horizontal, 16)
        }
    }

    /// What a label covers: automatically, the rest of its line, or the line below.
    private var reaches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What is covered?"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(OwnRule.Reach.allCases, id: \.self) { option in
                    ReachRow(reach: option, chosen: option == reach) { reach = option }
                    if option != OwnRule.Reach.allCases.last {
                        Rectangle()
                            .fill(SnapflyTokens.hideSeparator)
                            .frame(height: 1 / displayScale)
                            .padding(.leading, 16)
                    }
                }
            }
            .hideCard()
        }
    }

    /// The made-up page, as the rule covers it.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L("Preview"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(L("Example"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SnapflyTokens.hideAccentSoft, in: Capsule())
            }
            if let sample = RuleSample.of(draft) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sample.lines.enumerated()), id: \.offset) { _, line in
                        CoveredLineText(line: line)
                            .font(.callout)
                            .foregroundStyle(SnapflyTokens.hideText)
                            .accessibilityLabel(Text(verbatim: line.spoken))
                    }
                }
                if kind == .label, reach == .automatic {
                    Text(L("With nothing after it, the line below is covered."))
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
            } else {
                Text(kind == .pattern ? L("There is no preview for a pattern.") : L("Type something to see what is covered."))
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .hideCard()
        .accessibilityIdentifier("always-hide-preview")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleting = true
        } label: {
            Text(L("Delete Rule"))
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .hideCard()
        .confirmationDialog(L("Delete Rule"), isPresented: $deleting, titleVisibility: .hidden) {
            Button(L("Delete Rule"), role: .destructive) {
                remove()
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    private var saveBar: some View {
        Button(action: submit) {
            Text(L("Save Rule"))
        }
        .buttonStyle(HidePrimaryButtonStyle())
        .disabled(!canSave)
        .accessibilityIdentifier("always-hide-save-rule")
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(SnapflyTokens.hideGround)
    }

    private func submit() {
        guard canSave else { return }
        save(draft)
        dismiss()
    }
}

/// One of a label's reaches, to choose: its name, what it covers, and a
/// check when chosen.
private struct ReachRow: View {
    let reach: OwnRule.Reach
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("always-hide-reach-" + reach.rawValue)
    }

    private var title: String {
        switch reach {
        case .automatic: L("Automatic")
        case .restOfLine: L("Rest of the Line")
        case .nextLine: L("Next Line")
        }
    }

    private var detail: String {
        switch reach {
        case .automatic: L("What follows it, else the line below")
        case .restOfLine: L("What follows it on its line")
        case .nextLine: L("The line under it")
        }
    }
}

// MARK: Pieces

/// A rule's symbol, green on soft green: "Aa" for a word, a tag for a label.
struct HideRuleTile: View {
    let kind: OwnRule.Kind
    @ScaledMetric(relativeTo: .body) private var size = OwnDetailTile.base

    var body: some View {
        Image(systemName: Self.symbol(kind))
            .font(.callout.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideAccent)
            .frame(width: size, height: size)
            .background(SnapflyTokens.hideAccentSoft, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }

    static func symbol(_ kind: OwnRule.Kind) -> String {
        switch kind {
        case .label: "tag.fill"
        case .pattern: "chevron.left.forwardslash.chevron.right"
        default: "textformat"
        }
    }
}

/// One way a name is found, or how many more there are, in green on soft green.
struct HideChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SnapflyTokens.hideAccentSoft, in: Capsule())
    }
}

/// Words with some of them covered, as a covered copy shows them: a bar
/// of the words' own colour over what is covered.
struct CoveredLineText: View {
    private let segments: [(text: String, covered: Bool)]

    init(segments: [(String, Bool)]) {
        self.segments = segments.map { (text: $0.0, covered: $0.1) }
    }

    /// A line of a rule's made-up page.
    init(line: RuleSample.Line) {
        guard !line.whole else {
            segments = [(text: line.text, covered: true)]
            return
        }
        var parts: [(text: String, covered: Bool)] = []
        var at = line.text.startIndex
        for range in line.covered.sorted(by: { $0.lowerBound < $1.lowerBound }) where range.lowerBound >= at {
            if at < range.lowerBound { parts.append((text: String(line.text[at..<range.lowerBound]), covered: false)) }
            parts.append((text: String(line.text[range]), covered: true))
            at = range.upperBound
        }
        if at < line.text.endIndex { parts.append((text: String(line.text[at...]), covered: false)) }
        segments = parts
    }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var whole = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            if segment.covered {
                part.foregroundColor = Self.cover
                part.backgroundColor = Self.cover
            }
            whole += part
        }
        return whole
    }

    /// The bar over covered words: the words' colour, nearly solid.
    static let cover = Color.primary.opacity(0.85)
}

/// Chips one after another, on as many lines as they need.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            if x > 0, x + size.width > limit {
                y += row + spacing
                x = 0
                row = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: min(widest, limit), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// A row that dims a little under the finger, at once.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(SnapflyMotion.feedback, value: configuration.isPressed)
    }
}

/// Always Hide's one main action: white on its green, as wide as there is
/// room, a little smaller under the finger, not with Reduce Motion.
struct HidePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
            .background(SnapflyTokens.hideButton, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SnapflyMotion.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension View {
    /// On a white card with the small cards' corners, as Always Hide's
    /// sheets hold their parts.
    func hideCard() -> some View {
        background(SnapflyTokens.hideCard,
                   in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
    }
}

#if DEBUG
#Preview("New detail") {
    DetailSheet(request: .new(.name), save: { _ in }, remove: {})
}

#Preview("New detail, typed, dark") {
    DetailSheet(request: DetailRequest(draft: AlwaysHideSample.name, isNew: true, choosing: true), save: { _ in }, remove: {})
        .preferredColorScheme(.dark)
}

#Preview("New detail, XXXL") {
    DetailSheet(request: DetailRequest(draft: AlwaysHideSample.name, isNew: true, choosing: true), save: { _ in }, remove: {})
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Card, kept") {
    DetailSheet(request: .edit(AlwaysHideSample.card), save: { _ in }, remove: {})
}

#Preview("IBAN, typed, dark, XXXL") {
    DetailSheet(request: DetailRequest(draft: AlwaysHideSample.account, isNew: true, choosing: true), save: { _ in }, remove: {})
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("New rule") {
    RuleSheet(request: RuleRequest(draft: OwnRule(text: "Musterfirma", kind: .word), isNew: true), save: { _ in }, remove: {})
}

#Preview("Label rule, dark") {
    RuleSheet(request: RuleRequest(draft: OwnRule(text: "Kundennummer", kind: .label), isNew: true), save: { _ in }, remove: {})
        .preferredColorScheme(.dark)
}

#Preview("Label rule, next line, XXXL") {
    RuleSheet(request: .edit(OwnRule(text: "Aktenzeichen", kind: .label, reach: .nextLine)), save: { _ in }, remove: {})
        .dynamicTypeSize(.xxxLarge)
}
#endif
