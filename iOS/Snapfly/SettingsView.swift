import SwiftUI

/// What to cover, kind by kind in groups, whose names among them, the owner's own first; how covers look;
/// how a screenshot is read; the AI assistant; the apps to send to; the devices it syncs with; and, further in,
/// what to hide always, the owner's details and rules (`AlwaysHideView`), and how to cover a screenshot with a
/// double tap on the back of the iPhone.
struct SettingsView: View {
    /// As the More tab, with a large title and no Done; else a sheet.
    var inTab = false
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Choice.details
    /// The owner's own name, first under People, and its sheet, to add it
    /// or change it.
    @State private var ownName = OwnRules.all.first { $0.kind == .name }
    @State private var nameRequest: DetailRequest?
    /// Always Hide open, as screenshots made in CI and the UI tests ask.
    @State private var showsAlwaysHide = AlwaysHideSample.requested
    @State private var look = CoverStyle.current
    @State private var keepsLastDigits = Finder.keepsLastDigits
    @State private var strongest = Finder.strongest
    @State private var usesIntelligence = Finder.usesIntelligence && Finder.intelligenceAvailable
    /// The assistant set up, by its name, read again as Settings shows.
    @State private var assistant: String?
    @ObservedObject private var indexer = PhotoIndexer.shared
    @ObservedObject private var sendApps = SendApps.shared

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
                        if group == .people {
                            Button {
                                nameRequest = ownName.map { DetailRequest.edit($0) } ?? .new(.name, choosing: false)
                            } label: {
                                OwnNameRow(name: ownName)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(group.kinds, id: \.self) { detail in
                            Toggle(isOn: binding(for: detail)) {
                                if let subtitle = detail.subtitle {
                                    described(detail.title, subtitle)
                                } else {
                                    Text(detail.title)
                                }
                            }
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .people {
                            Text(L("Each covers its own people, told by the words round each name, like \"Patient:\" or \"Dr. med.\". All three together cover everyone's names. Your own name, under Your Details, is always covered."))
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
                    // Over the pictures protected lately: the middle one, and the slowest but a few.
                    ForEach(Timing.Measure.allCases, id: \.self) { measure in
                        let times = Timing.recent(measure)
                        if let middle = Timing.percentile(times, 0.5), let slow = Timing.percentile(times, 0.95) {
                            LabeledContent(measure == .shown ? L("Picture shown") : L("Ready to share"),
                                           value: String(format: L("Median %@ · 95%% under %@"),
                                                         duration(middle), duration(slow)))
                        }
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

                Section {
                    NavigationLink {
                        AssistantSettings()
                    } label: {
                        LabeledContent {
                            Text(assistant ?? L("Off"))
                        } label: {
                            Label(L("AI Assistant"), systemImage: "sparkles")
                        }
                    }
                } footer: {
                    Text(L("Your own Claude or ChatGPT explains documents in Protect Picture."))
                }
                .onAppear { assistant = AIAccount.isSetUp ? AIAccount.provider.name : nil }

                Section {
                    NavigationLink {
                        ChooseApps()
                    } label: {
                        LabeledContent {
                            Text(sendApps.chosen.count, format: .number)
                        } label: {
                            Label(L("Send to Apps"), systemImage: "paperplane")
                        }
                    }
                } footer: {
                    Text(L("The apps after a scan and beside the picture in Protect Picture, to hand them the covered copy. The same apps as on the Mac."))
                }

                SyncSection(sync: .shared)

                Section {
                    NavigationLink {
                        AlwaysHideView()
                    } label: {
                        Label(L("Always Hide"), systemImage: "text.badge.plus")
                    }
                    .accessibilityIdentifier("settings-always-hide")
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
                        if inTab { AppTabs.shared.selection = .photos } else { dismiss() }
                        // Once the sheet or the tab has gone, on the screenshots themselves.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.4))
                            PhoneGuide.shared.start()
                        }
                    } label: {
                        Label(L("Start Introduction"), systemImage: "hand.wave")
                    }
                    Button {
                        if !inTab { dismiss() }
                        // Over everything, once a sheet has gone.
                        Task { @MainActor in
                            if !inTab { try? await Task.sleep(for: .seconds(0.4)) }
                            FirstRunCoordinator.shared.replay()
                        }
                    } label: {
                        Label(L("Watch the Demo"), systemImage: "play.circle")
                    }
                } header: {
                    Text(L("Help & Introduction"))
                } footer: {
                    Text(L("Snapfly on your own screenshots, step by step."))
                }
            }
            .navigationTitle(inTab ? L("More") : L("Settings"))
            .navigationBarTitleDisplayMode(inTab ? .large : .inline)
            // Back from Always Hide, where the name may have changed.
            .onAppear { ownName = OwnRules.all.first { $0.kind == .name } }
            .sheet(item: $nameRequest) { request in
                DetailSheet(request: request) { kept in
                    keepName(kept)
                }
            }
            .navigationDestination(isPresented: $showsAlwaysHide) {
                AlwaysHideView()
            }
            .toolbar {
                if !inTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
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

    /// The owner's name kept with their details, in the place of the one
    /// before. It is removed in Always Hide, with a swipe.
    private func keepName(_ name: OwnRule) {
        var all = OwnRules.all
        if let i = all.firstIndex(where: { $0.kind == .name }) {
            all[i] = name
        } else {
            all.append(name)
        }
        OwnRules.all = all
        ownName = name
    }

    private func binding(for detail: PrivateDetail) -> Binding<Bool> {
        // Each kind is its own switch, Names and its two parts too.
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
