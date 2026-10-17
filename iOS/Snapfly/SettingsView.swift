import SwiftUI

/// What to cover, rules of the owner's own, and how to cover a screenshot
/// with a double tap on the back of the iPhone.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Choice.details
    @State private var rules = OwnRules.all

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Every kind at once, the recommended ones, or none, as on the Mac.
                    HStack(spacing: 8) {
                        choiceButton(L("Check All"), Set(PrivateDetail.allCases))
                        choiceButton(L("Recommended"), PrivateDetail.recommended)
                        choiceButton(L("Uncheck All"), [])
                    }
                    .controlSize(.small)
                } header: {
                    Text(L("Hide private details"))
                }
                ForEach(PrivateDetail.Group.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(group.kinds, id: \.self) { detail in
                            Toggle(detail.title, isOn: binding(for: detail))
                        }
                    }
                }

                Section {
                    ForEach($rules) { $rule in
                        RuleRow(rule: $rule)
                    }
                    .onDelete { rules.remove(atOffsets: $0) }
                    Button(L("Add Rule")) { rules.append(OwnRule()) }
                } header: {
                    Text(L("Also hide"))
                } footer: {
                    Text(L("Words are covered wherever they appear. After a label, what follows it is covered: the rest of the line, or the line below."))
                }
                .onChange(of: rules) { _, new in OwnRules.all = new }

                Section {
                    step(1, L("Take a screenshot as usual."))
                    step(2, L("Double tap the back of your iPhone: the latest screenshot is covered and copied, ready to paste into a chat."))
                    step(3, String(format: L("To set it up once, open Settings › Accessibility › Touch › Back Tap › Double Tap, and choose %@."),
                                   L("Cover the Latest Screenshot")))
                } header: {
                    Text(L("Double tap the back of your iPhone"))
                } footer: {
                    Text(L("Everything happens on this iPhone. Nothing is sent anywhere."))
                }
            }
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func binding(for detail: PrivateDetail) -> Binding<Bool> {
        Binding {
            chosen.contains(detail)
        } set: { on in
            if on { chosen.insert(detail) } else { chosen.remove(detail) }
            Choice.details = chosen
        }
    }

    private func choiceButton(_ title: String, _ kinds: Set<PrivateDetail>) -> some View {
        Button {
            chosen = kinds
            Choice.details = kinds
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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

/// One rule of the owner's own: its kind, and the text. Swipe to remove it.
private struct RuleRow: View {
    @Binding var rule: OwnRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(rule.kind.title, selection: $rule.kind) {
                ForEach(OwnRule.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            TextField(rule.kind.title, text: $rule.text, prompt: Text(rule.kind.prompt))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !rule.isReadable {
                Label(L("This pattern cannot be read."), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
