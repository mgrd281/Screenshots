import SwiftUI

/// What to cover and how covers look, rules of the owner's own, and how to
/// cover a screenshot with a double tap on the back of the iPhone.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Choice.details
    @State private var look = CoverStyle.current
    @State private var keepsLastDigits = Finder.keepsLastDigits
    @State private var strongest = Finder.strongest
    @State private var usesIntelligence = Finder.usesIntelligence && Finder.intelligenceAvailable
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
                    CoverLookPicker(selection: $look)
                    Toggle(isOn: $keepsLastDigits) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Keep the last four digits"))
                            Text(L("Card, account and phone numbers stay recognisable by their last four digits, as on a bank statement."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Cover look"))
                } footer: {
                    Text(L("Every look hides for good: blur, pixels, dots and erased are drawn from the colors around what is covered, never from it, so it cannot be brought back."))
                }
                .onChange(of: look) { _, new in CoverStyle.current = new }
                .onChange(of: keepsLastDigits) { _, new in Finder.keepsLastDigits = new }

                Section {
                    Toggle(isOn: $strongest) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Strongest protection"))
                            Text(L("Every line with something private is covered whole, with more room around it, so nothing of it shows, not even how long it was."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $usesIntelligence) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Find more with Apple Intelligence"))
                            Text(Finder.intelligenceAvailable
                                 ? L("Reads the words right here and covers what the patterns miss, like a name in a sentence. Nothing leaves this device.")
                                 : L("Needs Apple Intelligence on this device."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!Finder.intelligenceAvailable)
                } header: {
                    Text(L("Protection"))
                } footer: {
                    Text(L("Every copy is read again before it leaves, as anyone could read it, and whatever private still shows is covered too."))
                }
                .onChange(of: strongest) { _, new in Finder.strongest = new }
                .onChange(of: usesIntelligence) { _, new in Finder.usesIntelligence = new }

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

                Section {
                    Button {
                        dismiss()
                        // Once the sheet has gone, on the screenshots themselves.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.4))
                            PhoneGuide.shared.start()
                        }
                    } label: {
                        Label(L("Start Introduction"), systemImage: "hand.wave")
                    }
                } header: {
                    Text(L("Help & Introduction"))
                } footer: {
                    Text(L("Snapfly on your own screenshots, step by step."))
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
