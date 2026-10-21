import SwiftUI

// Always Hide's sheets: as tall as what they hold, nothing in them
// scrolling, sitting whole above the keyboard; a title on the leading side
// and a close button on the trailing. Only at the accessibility text sizes,
// when they would not fit, do they fill the screen and scroll.

// MARK: A detail

/// A detail's sheet, as it is asked for: a new one, from the list of kinds
/// or straight to a kind's fields, or one kept.
struct DetailRequest: Identifiable {
    let id = UUID()
    var draft: OwnRule
    var isNew: Bool
    /// Opened from the list of kinds, so its fields can go back to it.
    var choosing: Bool
    /// Showing the list of kinds first.
    var picking: Bool

    /// A new detail: the list of kinds, or the kind's fields at once.
    static func new(_ kind: OwnRule.Kind, choosing: Bool) -> DetailRequest {
        DetailRequest(draft: OwnRule(kind: kind), isNew: true, choosing: choosing, picking: choosing)
    }

    static func edit(_ detail: OwnRule) -> DetailRequest {
        DetailRequest(draft: detail, isNew: false, choosing: false, picking: false)
    }

    /// A kind's fields as if chosen from the list, typed already, for the
    /// screenshots made in CI.
    static func chosen(_ draft: OwnRule) -> DetailRequest {
        DetailRequest(draft: draft, isNew: true, choosing: true, picking: false)
    }
}

/// One of the owner's details, added or changed. First, for a new one, the
/// four kinds as a plain list; a kind chosen moves on in the same sheet to
/// its fields in one grouped card, the first focused, Return going on to
/// the next and adding after the last; a line on what keeps it private and
/// that other spellings are found too; and Add, which waits for what can
/// be kept.
struct DetailSheet: View {
    let request: DetailRequest
    let save: (OwnRule) -> Void

    @State private var picking: Bool
    /// Which way the sheet moved last, for the push's direction.
    @State private var forward = true
    @State private var kind: OwnRule.Kind
    @State private var given: String
    @State private var surname: String
    @State private var street: String
    @State private var postcode: String
    @State private var city: String
    @State private var card: String
    @State private var iban: String
    @State private var revealed = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Field: String, Hashable {
        case given, surname, street, postcode, city, card, iban
    }

    init(request: DetailRequest, save: @escaping (OwnRule) -> Void) {
        self.request = request
        self.save = save
        let draft = request.draft
        let name: (given: [String], surname: [String]) = draft.kind == .name
            ? OwnDetails.nameParts(draft.text) : (given: [], surname: [])
        _picking = State(initialValue: request.picking)
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

    private var canKeep: Bool { draft.canSave }

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

    private var push: AnyTransition {
        reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading)
    }

    var body: some View {
        FittedSheet {
            Group {
                if picking {
                    kinds
                        .transition(push)
                } else {
                    entry
                        .transition(push)
                }
            }
        }
        .interactiveDismissDisabled(changed)
        .onAppear { if !picking { focusFirst() } }
    }

    // MARK: Step one, the kinds

    private var kinds: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetHeader(title: L("Add Detail")) { dismiss() }
            VStack(spacing: 0) {
                ForEach(OwnRule.Kind.details, id: \.self) { kind in
                    KindRow(kind: kind) { choose(kind) }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: Step two, a kind's fields

    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: kind.title, back: request.choosing ? goBack : nil) { dismiss() }
            VStack(spacing: 0) {
                switch kind {
                case .name:
                    field(L("First Name"), text: $given, as: .given, content: .givenName)
                    FieldLine()
                    field(L("Last Name"), text: $surname, as: .surname, content: .familyName)
                case .address:
                    field(L("Street and No."), text: $street, as: .street, content: .fullStreetAddress)
                    FieldLine()
                    field(L("Postcode"), text: $postcode, as: .postcode, content: .postalCode,
                          keyboard: .numbersAndPunctuation, capitals: .characters)
                    FieldLine()
                    field(L("Town"), text: $city, as: .city, content: .addressCity)
                case .card:
                    number(L("Card number"), grouped: OwnDetails.grouped(card: card), as: .card) {
                        card = String(OwnDetails.digits($0).prefix(19))
                    }
                case .account:
                    number(L("IBAN"), grouped: OwnDetails.grouped(iban: iban), as: .iban) {
                        iban = String(OwnDetails.compact(iban: $0).prefix(34))
                    }
                case .word, .label, .pattern:
                    EmptyView()
                }
            }
            .background(SnapflyTokens.hideField,
                        in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
            note
            Button(action: submit) {
                Text(request.isNew ? L("Add") : L("Save"))
            }
            .buttonStyle(HidePrimaryButtonStyle())
            .disabled(!canKeep)
            .accessibilityIdentifier("always-hide-save-detail")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func field(_ title: String, text: Binding<String>, as field: Field, content: UITextContentType,
                       keyboard: UIKeyboardType = .default, capitals: TextInputAutocapitalization = .words) -> some View {
        TextField(title, text: text, prompt: Text(title))
            .font(.body)
            .foregroundStyle(SnapflyTokens.hideText)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitals)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(field == fields.last ? .done : .next)
            .onSubmit { advance(from: field) }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .accessibilityIdentifier("always-hide-field-" + field.rawValue)
    }

    /// A card's or an account's number: grouped as typed, the card's network
    /// beside it; kept already, hidden until the eye is tapped.
    @ViewBuilder
    private func number(_ title: String, grouped: String, as field: Field, typed: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            if request.isNew || revealed {
                TextField(title, text: Binding(get: { grouped }, set: typed), prompt: Text(title))
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
                }
            } else {
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
        .padding(.leading, 16)
        .padding(.trailing, request.isNew || revealed ? 16 : 0)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    /// What is wrong with what was typed; else what keeps it private and
    /// that other spellings are found too.
    @ViewBuilder
    private var note: some View {
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideWarning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
                Text(AlwaysHidePromise.hint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(SnapflyTokens.hideSecondary)
        }
    }

    private var problem: String? {
        switch kind {
        case .card: OwnDetails.cardProblem(card)
        case .account: OwnDetails.ibanProblem(iban)
        default: nil
        }
    }

    // MARK: Doing

    private func choose(_ chosen: OwnRule.Kind) {
        forward = true
        withAnimation(SnapflyMotion.change(reduceMotion)) {
            kind = chosen
            picking = false
        }
        focusFirst()
    }

    private func goBack() {
        focus = nil
        forward = false
        withAnimation(SnapflyMotion.change(reduceMotion)) { picking = true }
    }

    /// Once the sheet has moved, the first field, and the keyboard with it.
    private func focusFirst() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
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

/// One of the four kinds in the list: its outline symbol in green, its
/// name, what it asks for, and a chevron.
private struct KindRow: View {
    let kind: OwnRule.Kind
    let action: () -> Void

    private var symbol: String {
        switch kind {
        case .address: "house"
        case .card: "creditcard"
        case .account: "building.columns"
        default: "person"
        }
    }

    private var detail: String {
        switch kind {
        case .address: L("Street, postcode and town")
        case .card: L("Card number")
        case .account: L("IBAN")
        default: L("First and last name")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .frame(width: OwnDetailTile.base)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.body)
                        .foregroundStyle(SnapflyTokens.hideText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SnapflyTokens.hideRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
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
/// Automatic first, as every label rule did before there was a choice; a
/// line of a made-up page, covered by the engine itself (`RuleSample`) as
/// it is typed; and Save Rule, which an empty rule never reaches. A pattern
/// kept before can be changed here, though new ones are made on the Mac.
struct RuleSheet: View {
    let request: RuleRequest
    let save: (OwnRule) -> Void

    @State private var kind: OwnRule.Kind
    /// What was typed for each kind, so going to the other keeps it.
    @State private var texts: [OwnRule.Kind: String]
    @State private var reach: OwnRule.Reach
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(request: RuleRequest, save: @escaping (OwnRule) -> Void) {
        self.request = request
        self.save = save
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

    private var canSave: Bool { draft.canSave }

    private var changed: Bool {
        request.isNew ? !draft.isBlank : draft != request.draft
    }

    var body: some View {
        FittedSheet {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: request.isNew ? L("New Rule") : L("Edit Rule")) { dismiss() }
                Picker(L("Kind of Rule"), selection: $kind) {
                    ForEach(kinds, id: \.self) { kind in
                        Text(Self.segment(kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("always-hide-rule-kind")
                TextField(Self.segment(kind), text: text, prompt: Text(placeholder))
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                    .textInputAutocapitalization(kind == .pattern ? .never : .sentences)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if canSave { submit() } }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(SnapflyTokens.hideField,
                                in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
                    .accessibilityIdentifier("always-hide-rule-text")
                if kind == .label {
                    Picker(L("What is covered?"), selection: $reach) {
                        ForEach(OwnRule.Reach.allCases, id: \.self) { option in
                            Text(RuleWords.title(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("always-hide-reach")
                }
                if !draft.isReadable {
                    Label(L("This pattern cannot be read."), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideWarning)
                }
                preview
                Button(action: submit) {
                    Text(L("Save Rule"))
                }
                .buttonStyle(HidePrimaryButtonStyle())
                .disabled(!canSave)
                .accessibilityIdentifier("always-hide-save-rule")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(changed)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                focused = true
            }
        }
    }

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

    /// One line of a made-up page, as the rule covers it: a word in a
    /// sentence, a label with what follows it covered, or, for the line
    /// below, the label and the covered line after it.
    private var preview: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("Example"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SnapflyTokens.hideAccentSoft, in: Capsule())
            previewLine
                .font(.subheadline)
                .foregroundStyle(SnapflyTokens.hideText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(SnapflyTokens.hideField,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("always-hide-preview")
    }

    @ViewBuilder
    private var previewLine: some View {
        if let sample = RuleSample.of(draft),
           let index = sample.lines.firstIndex(where: { $0.whole || !$0.covered.isEmpty }) {
            let line = sample.lines[index]
            if line.whole, index > 0 {
                CoveredLineText(segments: [(sample.lines[index - 1].text + "  ↵  ", false), (line.text, true)])
                    .accessibilityLabel(Text(verbatim: sample.lines[index - 1].text + ", " + line.spoken))
            } else {
                CoveredLineText(line: line)
                    .accessibilityLabel(Text(verbatim: line.spoken))
            }
        } else {
            Text(kind == .pattern ? L("There is no preview for a pattern.") : L("Type something to see what is covered."))
                .foregroundStyle(SnapflyTokens.hideSecondary)
        }
    }

    private func submit() {
        guard canSave else { return }
        save(draft)
        dismiss()
    }
}

// MARK: Pieces

/// A sheet as tall as what it holds, nothing in it scrolling, so it never
/// resizes as the owner types and sits whole above the keyboard. At the
/// accessibility text sizes it may be taller than the screen: then it fills
/// it and scrolls.
struct FittedSheet<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 320
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView {
                    content
                }
                .scrollDismissesKeyboard(.interactively)
                .presentationDetents([.large])
            } else {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { measured in
                        if measured > 0 { height = measured }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .presentationDetents([.height(height)])
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SnapflyTokens.hideSheetRadius)
        .presentationBackground(SnapflyTokens.hideCard)
    }
}

/// A sheet's title on the leading side, maybe with a way back before it,
/// and its close button on the trailing side: an xmark in a grey circle,
/// with a finger's room round it.
private struct SheetHeader: View {
    let title: String
    var back: (() -> Void)? = nil
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.hideText)
                        .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Back"))
                .accessibilityIdentifier("always-hide-back")
            }
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(SnapflyTokens.hideText)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .frame(width: 30, height: 30)
                    .background(SnapflyTokens.hideButtonOff, in: Circle())
                    .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Close"))
            .accessibilityIdentifier("always-hide-close")
        }
        .frame(minHeight: SnapflyTokens.touch)
    }
}

/// The line between two fields of a card, inset to the words.
private struct FieldLine: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(SnapflyTokens.hideFieldLine)
            .frame(height: 1 / displayScale)
            .padding(.leading, 16)
    }
}

/// A rule's symbol, dark on a quiet grey: "Aa" for a word, a tag for a label.
struct HideRuleTile: View {
    let kind: OwnRule.Kind
    @ScaledMetric(relativeTo: .body) private var size = OwnDetailTile.base

    var body: some View {
        Image(systemName: Self.symbol(kind))
            .font(.callout.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideText)
            .frame(width: size, height: size)
            .background(SnapflyTokens.hideRuleTile, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }

    static func symbol(_ kind: OwnRule.Kind) -> String { RuleWords.symbol(kind) }
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
/// room, a little smaller under the finger, not with Reduce Motion. While
/// it waits, dark grey words on grey, still easy to read.
struct HidePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : SnapflyTokens.hideButtonOffText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
            .background(isEnabled ? SnapflyTokens.hideButton : SnapflyTokens.hideButtonOff, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SnapflyMotion.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

#if DEBUG
#Preview("Add detail") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailSheet(request: .new(.name, choosing: true)) { _ in }
    }
}

#Preview("Name, typed, dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailSheet(request: .chosen(AlwaysHideSample.name)) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("Address, XXXL") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailSheet(request: .chosen(AlwaysHideSample.address)) { _ in }
    }
    .dynamicTypeSize(.xxxLarge)
}

#Preview("Card, kept") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailSheet(request: .edit(AlwaysHideSample.card)) { _ in }
    }
}

#Preview("IBAN, dark, accessibility size") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailSheet(request: .chosen(AlwaysHideSample.account)) { _ in }
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}

#Preview("New rule") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RuleSheet(request: RuleRequest(draft: OwnRule(text: "Musterfirma", kind: .word), isNew: true)) { _ in }
    }
}

#Preview("Label rule, dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RuleSheet(request: RuleRequest(draft: OwnRule(text: "Kundennummer", kind: .label), isNew: true)) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("Label rule, next line, XXXL") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RuleSheet(request: .edit(OwnRule(text: "Aktenzeichen", kind: .label, reach: .nextLine))) { _ in }
    }
    .dynamicTypeSize(.xxxLarge)
}
#endif
