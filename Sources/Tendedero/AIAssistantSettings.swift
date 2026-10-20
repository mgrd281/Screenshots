import AppKit
import SwiftUI

/// Settings › AI Assistant: Claude or ChatGPT, with the owner's own key, for
/// Write a Reply, Explain and Order Details. The assistant is chosen with a
/// tile each; under them, whether its key works, checked with the provider
/// as it is saved; the key, kept in the keychain with only its last four
/// characters shown; the model, from the provider's own list once the key
/// works; and what the assistant does, with the switch that lets it find
/// private details too.
struct AIAssistantPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var connection = AIConnection.shared
    @State private var key = ""
    @State private var kept: String?
    @State private var keychainFailed = false
    @State private var changing = false
    @State private var model = ""
    @State private var other = false

    private static let otherTag = "\u{0}other"

    private var provider: AIProvider { prefs.aiProvider }
    private var state: AIConnection.State? { connection.states[provider] }

    var body: some View {
        Form {
            Section(L("Assistant")) {
                HStack(spacing: 12) {
                    ForEach(AIProvider.allCases) { choice in
                        AIProviderTile(provider: choice, chosen: choice == provider,
                                       hasKey: choice == provider ? kept != nil : AIAccount.hasKey(choice)) {
                            prefs.aiProvider = choice
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("Assistant"))
            }
            Section(L("Connection")) {
                if kept != nil || keychainFailed { statusRow }
                if kept == nil || state == .refused { getKeyRow }
                keyRow
            }
            Section {
                Picker(L("Model"), selection: modelChoice) {
                    ForEach(models) { choice in
                        Text(verbatim: choice.name).tag(choice.id)
                    }
                    Divider()
                    Text(L("Other…")).tag(Self.otherTag)
                }
                if showsModelField {
                    TextField(L("Model ID"), text: $model, prompt: Text(verbatim: provider.defaultModel))
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text(L("Model"))
            } footer: {
                Text(L("The largest models answer best; smaller ones answer faster and cost less."))
                    .foregroundStyle(.secondary)
            }
            Section {
                use(L("Write a Reply"), symbol: "arrowshape.turn.up.left",
                    L("Writes the reply to send, from a conversation, an order or a review."))
                use(String(format: L("Explain with %@"), provider.name), symbol: "bubble.left.and.text.bubble.right",
                    L("Says what a screenshot shows and what matters in it, or answers your question about it."))
                use(L("Order Details"), symbol: "list.bullet.rectangle",
                    L("Reads an order’s number, date, total, product and tracking."))
                Toggle(isOn: $prefs.assistantFindsPrivate) {
                    Text(String(format: L("Find more with %@"), provider.name))
                    Text(prefs.aiSetUp
                         ? L("Sends the words of each screenshot to the AI assistant, to cover what the patterns miss. Covering takes a few seconds longer.")
                         : L("Needs an AI assistant key; add one under AI Assistant."))
                }
                .disabled(!prefs.aiSetUp)
            } header: {
                Text(L("What it does"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("In a photo’s menu, under Text and AI."))
                    Text(L("Write a Reply, Explain and Order Details send the screenshot, its private details covered, straight to Anthropic or OpenAI with your own key, only when you choose them. They bill each request to your account there; a Claude or ChatGPT subscription does not cover it."))
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: prefs.aiProvider) { _, _ in load() }
        .onChange(of: model) { _, value in AIAccount.setModel(value, for: provider) }
    }

    // MARK: Connection

    /// Whether the key works, and Check Again once it has been checked.
    private var statusRow: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 8)
            if kept != nil {
                Button(L("Check Again")) { connection.check(provider) }
                    .disabled(state == .checking)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if keychainFailed {
            Label {
                Text(L("The keychain did not keep the key."))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } else {
            switch state {
            case .works:
                Label {
                    Text(L("Ready. The key works."))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .refused:
                Label {
                    Text(String(format: L("%@ did not accept this key. Check it, or make a new one."), provider.name))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            case .failed(let reason):
                Label {
                    Text(reason).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                }
            case .checking, nil:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Checking the key…")).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Where a key is made, while there is none or the one kept is refused.
    private var getKeyRow: some View {
        LabeledContent {
            SettingsButton(L("Get a Key…")) { NSWorkspace.shared.open(provider.keyPage) }
        } label: {
            Text(L("No key yet?"))
            Text(String(format: L("Make one on the %@ website, copy it, then paste it here."), provider.maker))
        }
    }

    /// The key kept, by its end, or the field a new one goes into.
    @ViewBuilder private var keyRow: some View {
        if let kept, !changing {
            LabeledContent {
                HStack(spacing: 8) {
                    Button(L("Change")) { changing = true }
                    Button(L("Remove Key"), role: .destructive, action: remove)
                }
            } label: {
                Text(L("API key"))
                Text(String(format: L("Saved in your keychain, ending in %@"), kept))
            }
        } else {
            LabeledContent(L("API key")) {
                HStack(spacing: 8) {
                    SecureField(L("API key"), text: $key, prompt: Text(L("Paste your key here")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                        .onSubmit(save)
                    Button(action: pasteAndSave) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Paste the key from the clipboard and save it"))
                    .accessibilityLabel(L("Paste the key from the clipboard and save it"))
                    if changing {
                        Button(L("Cancel")) {
                            changing = false
                            key = ""
                        }
                    }
                    Button(L("Save"), action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(typed.isEmpty)
                }
            }
        }
    }

    private var typed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Model

    /// The provider's own list once the key works, else the usual ones; the
    /// usual model is always in it.
    private var models: [AIModel] {
        var list = connection.models[provider] ?? provider.suggestedModels
        if !list.contains(where: { $0.id == provider.defaultModel }) {
            list.insert(AIModel(id: provider.defaultModel, name: provider.defaultModel), at: 0)
        }
        return list
    }

    /// A model typed by hand, or one the list does not have.
    private var showsModelField: Bool {
        other || (!model.isEmpty && !models.contains { $0.id == model })
    }

    /// The usual model is kept as none named, so it follows Snapfly's own choice.
    private var modelChoice: Binding<String> {
        Binding {
            showsModelField ? Self.otherTag : (model.isEmpty ? provider.defaultModel : model)
        } set: { id in
            guard id != Self.otherTag else {
                other = true
                return
            }
            other = false
            model = id == provider.defaultModel ? "" : id
        }
    }

    // MARK: What it does

    private func use(_ title: String, symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Keeping the key

    /// What is kept for the assistant chosen, checked if it was not yet.
    private func load() {
        key = ""
        keychainFailed = false
        changing = false
        other = false
        kept = AIAccount.key(for: provider).map(AIAccount.hint(for:))
        model = UserDefaults.standard.string(forKey: "aiModel.\(provider.rawValue)") ?? ""
        connection.checkIfNeeded(provider)
    }

    private func save() {
        let typed = self.typed
        guard !typed.isEmpty else { return }
        keychainFailed = !AIAccount.setKey(typed, for: provider)
        key = ""
        kept = keychainFailed ? nil : AIAccount.hint(for: typed)
        changing = false
        prefs.aiKeyChanged()
        if keychainFailed { connection.forget(provider) } else { connection.check(provider) }
    }

    /// One click for the usual way a key arrives: copied on the provider's page.
    private func pasteAndSave() {
        key = NSPasteboard.general.string(forType: .string) ?? ""
        save()
    }

    private func remove() {
        AIAccount.setKey("", for: provider)
        kept = nil
        changing = false
        connection.forget(provider)
        prefs.aiKeyChanged()
    }
}

/// One assistant to choose, as the line styles and cover looks are chosen:
/// its app's icon as the Dock shows it, where the app is on this Mac, else
/// its short mark; its name and maker; and whether a key is kept for it.
private struct AIProviderTile: View {
    let provider: AIProvider
    let chosen: Bool
    let hasKey: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let status = hasKey ? L("Key saved") : L("No key yet")
        Button(action: choose) {
            HStack(spacing: 10) {
                ChatIcon(chat: provider == .claude ? .claude : .chatGPT, size: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: provider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: provider.maker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: hasKey ? "checkmark.circle.fill" : "key")
                            .foregroundStyle(hasKey ? Color.green : Color.secondary)
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(chosen ? Color.accentColor : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(chosen ? Color.accentColor.opacity(0.08)
                                          : Color.primary.opacity(hovering ? 0.06 : 0.03)))
            .overlay(shape.strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: chosen ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: "\(provider.name), \(provider.maker), \(status)"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
