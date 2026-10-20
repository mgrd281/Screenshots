import SwiftUI

/// One of the owner's details as a row of Also hide: its symbol on a green
/// tile, its name, like "Visa", and the detail with most of a number
/// hidden, like "•••• 4242". A tap opens it to change it.
struct OwnDetailRow: View {
    let detail: OwnRule

    var body: some View {
        HStack(spacing: 12) {
            OwnDetailTile(kind: detail.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(OwnDetails.title(of: detail))
                    .foregroundStyle(.primary)
                Text(OwnDetails.summary(of: detail))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: OwnDetails.spoken(detail)))
    }
}

/// A detail's symbol, white on the protect green in a rounded square, as
/// Settings shows its rows.
struct OwnDetailTile: View {
    let kind: OwnRule.Kind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(SnapflyTokens.protect, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One of the owner's details, added or changed in a sheet: its fields,
/// checked and grouped as they are typed, Done once there is something to
/// keep, and Delete for one kept already. A kept card's or account's number
/// shows hidden until Show is tapped.
struct OwnDetailEditor: View {
    @State var detail: OwnRule
    let isNew: Bool
    let save: (OwnRule) -> Void
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var deleting = false
    @FocusState private var focused: Field?
    private let start: OwnRule

    private enum Field { case text, postcode, city, caption }

    init(detail: OwnRule, isNew: Bool, save: @escaping (OwnRule) -> Void, remove: @escaping () -> Void) {
        _detail = State(initialValue: detail)
        start = detail
        self.isNew = isNew
        self.save = save
        self.remove = remove
    }

    var body: some View {
        NavigationStack {
            Form {
                switch detail.kind {
                case .name: name
                case .address: address
                case .card: card
                case .account: account
                case .word, .label, .pattern: EmptyView()
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            deleting = true
                        } label: {
                            Text(L("Delete Detail"))
                                .frame(maxWidth: .infinity)
                        }
                        .confirmationDialog(L("Delete Detail"), isPresented: $deleting, titleVisibility: .hidden) {
                            Button(L("Delete Detail"), role: .destructive) {
                                remove()
                                dismiss()
                            }
                            Button(L("Cancel"), role: .cancel) {}
                        }
                    }
                }
            }
            .navigationTitle(detail.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        save(OwnDetails.cleaned(detail))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!OwnDetails.canKeep(detail))
                }
            }
            .onAppear { if isNew { focused = .text } }
        }
        // What was typed is not lost to a swipe down.
        .interactiveDismissDisabled(detail != start)
    }

    // MARK: Each kind's fields

    private var name: some View {
        Section {
            TextField(L("First and last name"), text: $detail.text)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused, equals: .text)
        } footer: {
            note
        }
    }

    private var address: some View {
        Section {
            TextField(L("Street and house number"), text: $detail.text)
                .textContentType(.fullStreetAddress)
                .focused($focused, equals: .text)
            TextField(L("Postcode"), text: $detail.postcode)
                .textContentType(.postalCode)
                .keyboardType(.numbersAndPunctuation)
                .focused($focused, equals: .postcode)
            TextField(L("Town"), text: $detail.city)
                .textContentType(.addressCity)
                .focused($focused, equals: .city)
        } footer: {
            note
        }
    }

    private var card: some View {
        Section {
            number(placeholder: L("Card number"), grouped: OwnDetails.grouped(card: detail.text),
                   hidden: hiddenCard) { typed in
                detail.text = String(OwnDetails.digits(typed).prefix(19))
            }
            .textContentType(.creditCardNumber)
            .keyboardType(.numberPad)
            TextField(L("Name for it (optional)"), text: $detail.caption)
                .focused($focused, equals: .caption)
        } footer: {
            note
        }
    }

    private var account: some View {
        Section {
            number(placeholder: L("IBAN"), grouped: OwnDetails.grouped(iban: detail.text),
                   hidden: hiddenIBAN) { typed in
                detail.text = String(OwnDetails.compact(iban: typed).prefix(34))
            }
            .textInputAutocapitalization(.characters)
            .keyboardType(.asciiCapable)
            TextField(L("Name for it (optional)"), text: $detail.caption)
                .focused($focused, equals: .caption)
        } footer: {
            note
        }
    }

    /// A card's or account's number: grouped as typed, in a field with the
    /// network's name beside it; kept already, hidden until Show is tapped.
    @ViewBuilder
    private func number(placeholder: String, grouped: String, hidden: String,
                        typed: @escaping (String) -> Void) -> some View {
        if isNew || revealed {
            HStack(spacing: 8) {
                TextField(placeholder, text: Binding(get: { grouped }, set: typed))
                    .font(.body.monospacedDigit())
                    .autocorrectionDisabled()
                    .focused($focused, equals: .text)
                if detail.kind == .card, let brand = OwnDetails.brand(of: OwnDetails.digits(detail.text)) {
                    Text(verbatim: brand.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: OwnDetails.brand(of: OwnDetails.digits(detail.text)))
        } else {
            HStack {
                Text(verbatim: hidden)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    revealed = true
                    focused = .text
                } label: {
                    Image(systemName: "eye")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Show Number"))
            }
        }
    }

    private var hiddenCard: String {
        let number = OwnDetails.digits(detail.text)
        return "•••• •••• •••• " + String(number.suffix(4))
    }

    private var hiddenIBAN: String {
        let iban = OwnDetails.compact(iban: detail.text)
        return String(iban.prefix(4)) + " •••• •••• " + String(iban.suffix(4))
    }

    /// What is wrong with what was typed, in orange; else how it is covered.
    @ViewBuilder
    private var note: some View {
        let said = OwnDetails.note(for: detail)
        if said.isProblem {
            Label(said.text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Text(said.text)
        }
    }
}
