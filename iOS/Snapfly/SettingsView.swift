import SwiftUI

/// What to cover, kind by kind in groups, whose names among them; how covers look;
/// how a screenshot is read; the devices it syncs with; and, further in,
/// rules of the owner's own and how to cover a screenshot with a double tap
/// on the back of the iPhone.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Choice.details
    @State private var look = CoverStyle.current
    @State private var keepsLastDigits = Finder.keepsLastDigits
    @State private var strongest = Finder.strongest
    @State private var usesIntelligence = Finder.usesIntelligence && Finder.intelligenceAvailable
    @ObservedObject private var indexer = PhotoIndexer.shared

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
                    Section {
                        ForEach(group.kinds, id: \.self) { detail in
                            // Names covers everyone's, patients' and other people's too.
                            let included = PrivateDetail.people.contains(detail) && chosen.contains(.names)
                            Toggle(isOn: included ? .constant(true) : binding(for: detail)) {
                                if let subtitle = detail.subtitle {
                                    described(detail.title, subtitle)
                                } else {
                                    Text(detail.title)
                                }
                            }
                            .disabled(included)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .people {
                            Text(L("Without Names, only the people chosen are covered, told by the words round each name, like \"Patient:\" or \"Dr. med.\". A name whose role is not clear is covered anyway, and marked for you to check."))
                        }
                    }
                }

                Section {
                    CoverLookPicker(selection: $look)
                    Toggle(isOn: $keepsLastDigits) {
                        described(L("Keep the last four digits"),
                                  L("Card, account and phone numbers stay recognisable by their last four digits, as on a bank statement."))
                    }
                    Toggle(isOn: $strongest) {
                        described(L("Strongest protection"),
                                  L("Every line with something private is covered whole, with more room around it, so nothing of it shows, not even how long it was."))
                    }
                } header: {
                    Text(L("Cover look"))
                } footer: {
                    Text(L("Every look hides for good: blur, pixels, dots and erased are drawn from the colors around what is covered, never from it, so it cannot be brought back."))
                }
                .onChange(of: look) { _, new in CoverStyle.current = new }
                .onChange(of: keepsLastDigits) { _, new in Finder.keepsLastDigits = new }
                .onChange(of: strongest) { _, new in Finder.strongest = new }

                Section {
                    Toggle(isOn: $usesIntelligence) {
                        described(L("Find more with Apple Intelligence"),
                                  Finder.intelligenceAvailable
                                      ? L("Reads the words right here and covers what the patterns miss, like a name in a sentence. Nothing leaves this device.")
                                      : L("Needs Apple Intelligence on this device."))
                    }
                    .disabled(!Finder.intelligenceAvailable)
                    if let last = Timing.last {
                        LabeledContent(L("Last screenshot"), value: duration(last.milliseconds))
                    }
                    NavigationLink {
                        PreparingView()
                    } label: {
                        LabeledContent(L("Faster picture processing"),
                                       value: indexer.settings.isOn ? L("On") : L("Off"))
                    }
                } header: {
                    Text(L("Reading and checking"))
                } footer: {
                    Text(L("What the patterns find shows at once; Apple Intelligence adds to it. Every copy is read again before it leaves, as anyone could read it, and whatever private still shows is covered too."))
                }
                .onChange(of: usesIntelligence) { _, new in Finder.usesIntelligence = new }

                SyncSection(sync: .shared)

                Section {
                    NavigationLink {
                        AdvancedSettings()
                    } label: {
                        Label(L("Also hide"), systemImage: "text.badge.plus")
                    }
                    NavigationLink {
                        BackTapSettings()
                    } label: {
                        Label(L("Double tap the back of your iPhone"), systemImage: "hand.tap")
                    }
                } header: {
                    Text(L("Advanced"))
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

    private func described(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Milliseconds as the language says a duration, like "0.8 s".
    private func duration(_ milliseconds: Int) -> String {
        Measurement(value: Double(milliseconds) / 1000, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
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
}

/// Rules of the owner's own: words, patterns and labels.
private struct AdvancedSettings: View {
    @State private var rules = OwnRules.all

    var body: some View {
        Form {
            Section {
                ForEach($rules) { $rule in
                    RuleRow(rule: $rule)
                }
                .onDelete { rules.remove(atOffsets: $0) }
                Button(L("Add Rule")) { rules.append(OwnRule()) }
            } footer: {
                Text(L("Words are covered wherever they appear. After a label, what follows it is covered: the rest of the line, or the line below."))
            }
        }
        .onChange(of: rules) { _, new in OwnRules.all = new }
        .navigationTitle(L("Also hide"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How to cover the newest screenshot with a double tap on the back.
private struct BackTapSettings: View {
    var body: some View {
        Form {
            Section {
                step(1, L("Take a screenshot as usual."))
                step(2, L("Double tap the back of your iPhone: the latest screenshot is covered and copied, ready to paste into a chat."))
                step(3, String(format: L("To set it up once, open Settings › Accessibility › Touch › Back Tap › Double Tap, and choose %@."),
                               L("Cover the Latest Screenshot")))
            } footer: {
                Text(L("Everything happens on this iPhone. Nothing is sent anywhere."))
            }
        }
        .navigationTitle(L("Double tap the back of your iPhone"))
        .navigationBarTitleDisplayMode(.inline)
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
