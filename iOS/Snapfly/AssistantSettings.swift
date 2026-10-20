import SwiftUI

/// More › AI Assistant: Claude or ChatGPT with the owner's own key, for
/// Explain in Protect Picture and, if they choose, for finding more private
/// details. The assistant is chosen from a list; under it, whether its key
/// works, checked with the provider as it is saved; the key, kept in this
/// iPhone's keychain with only its last four characters shown; the model,
/// from the provider's own list once the key works; and what it does.
struct AssistantSettings: View {
    @ObservedObject private var connection = AIConnection.shared
    @State private var provider = AIAccount.provider
    @State private var key = ""
    @State private var kept: String?
    @State private var keychainFailed = false
    @State private var changing = false
    @State private var model = ""
    @State private var findsMore = AIAccount.findsPrivate

    private var state: AIConnection.State? { connection.states[provider] }

    var body: some View {
        Form {
            Section(L("Assistant")) {
                ForEach(AIProvider.allCases) { choice in
                    providerRow(choice)
                }
            }
            Section {
                if kept != nil || keychainFailed { statusRow }
                if kept == nil || state == .refused { getKeyRow }
                keyRows
            } header: {
                Text(L("Connection"))
            } footer: {
                if kept == nil || state == .refused {
                    Text(String(format: L("Make one on the %@ website, copy it, then paste it here."), provider.maker))
                }
            }
            Section {
                Picker(L("Model"), selection: $model) {
                    ForEach(models) { choice in
                        Text(verbatim: choice.name).tag(choice.id)
                    }
                }
            } footer: {
                Text(L("The largest models answer best; smaller ones answer faster and cost less."))
            }
            Section {
                Label {
                    described(L("Explain"),
                              L("In Protect Picture: what a document says, what matters in it and what to do, then answers to your questions about it."))
                } icon: {
                    Image(systemName: "sparkles")
                }
                Toggle(isOn: $findsMore) {
                    described(String(format: L("Find more with %@"), provider.name),
                              kept != nil
                                  ? L("Sends the words of each screenshot to the AI assistant, to cover what the patterns miss. Covering takes a few seconds longer.")
                                  : L("Needs an AI assistant key; add one under AI Assistant."))
                }
                .disabled(kept == nil)
            } header: {
                Text(L("What it does"))
            } footer: {
                Text(L("Explain sends the protected copy, never the original, straight to Anthropic or OpenAI with your own key, and only when you tap it. They bill each request to your account there; a Claude or ChatGPT subscription does not cover it."))
            }
        }
        .navigationTitle(L("AI Assistant"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: provider) { _, new in
            AIAccount.provider = new
            load()
        }
        .onChange(of: model) { _, new in
            // The usual model is kept as none named, so it follows Snapfly's own choice.
            AIAccount.setModel(new == provider.defaultModel ? "" : new, for: provider)
        }
        .onChange(of: findsMore) { _, new in AIAccount.findsPrivate = new }
    }

    // MARK: Assistant

    /// One assistant to choose: its name, its maker and whether a key is kept for it.
    private func providerRow(_ choice: AIProvider) -> some View {
        let hasKey = choice == provider ? kept != nil : AIAccount.hasKey(choice)
        let status = hasKey ? L("Key saved") : L("No key yet")
        return Button {
            provider = choice
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: choice.name)
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(choice.maker) · \(status)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if choice == provider {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(choice.name), \(choice.maker), \(status)"))
        .accessibilityAddTraits(choice == provider ? .isSelected : [])
    }

    // MARK: Connection

    /// Whether the key works, and Check Again once it has been checked.
    private var statusRow: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 8)
            if kept != nil {
                Button(L("Check Again")) { connection.check(provider) }
                    .buttonStyle(.borderless)
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
                    ProgressView()
                    Text(L("Checking the key…")).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Where a key is made, while there is none or the one kept is refused.
    private var getKeyRow: some View {
        Link(destination: provider.keyPage) {
            Label(L("Get a Key…"), systemImage: "arrow.up.forward.square")
        }
    }

    /// The key kept, by its end, or the field a new one goes into, with the
    /// system's Paste, which asks nothing.
    @ViewBuilder private var keyRows: some View {
        if let kept, !changing {
            LabeledContent(L("API key")) {
                Text(String(format: L("Saved in your keychain, ending in %@"), kept))
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
            }
            Button(L("Change")) { changing = true }
            Button(L("Remove Key"), role: .destructive, action: remove)
        } else {
            SecureField(L("API key"), text: $key, prompt: Text(L("Paste your key here")))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
            HStack(spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        key = strings.first ?? ""
                        save()
                    }
                }
                .buttonBorderShape(.capsule)
                .accessibilityLabel(L("Paste the key from the clipboard and save it"))
                Spacer(minLength: 8)
                if changing {
                    Button(L("Cancel")) {
                        changing = false
                        key = ""
                    }
                    .buttonStyle(.borderless)
                }
                Button(L("Save"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(typed.isEmpty)
            }
        }
    }

    private var typed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Model

    /// The provider's own list once the key works, else the usual ones; the
    /// usual model, and the one chosen, are always in it.
    private var models: [AIModel] {
        var list = connection.models[provider] ?? provider.suggestedModels
        if !list.contains(where: { $0.id == provider.defaultModel }) {
            list.insert(AIModel(id: provider.defaultModel, name: provider.defaultModel), at: 0)
        }
        if !model.isEmpty, !list.contains(where: { $0.id == model }) {
            list.append(AIModel(id: model, name: model))
        }
        return list
    }

    // MARK: Keeping the key

    /// What is kept for the assistant chosen, checked if it was not yet.
    private func load() {
        key = ""
        keychainFailed = false
        changing = false
        kept = AIAccount.key(for: provider).map(AIAccount.hint(for:))
        model = AIAccount.model(for: provider)
        connection.checkIfNeeded(provider)
    }

    private func save() {
        let typed = self.typed
        guard !typed.isEmpty else { return }
        keychainFailed = !AIAccount.setKey(typed, for: provider)
        key = ""
        kept = keychainFailed ? nil : AIAccount.hint(for: typed)
        changing = false
        if keychainFailed { connection.forget(provider) } else { connection.check(provider) }
    }

    private func remove() {
        AIAccount.setKey("", for: provider)
        kept = nil
        changing = false
        findsMore = false
        connection.forget(provider)
    }

    private func described(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
