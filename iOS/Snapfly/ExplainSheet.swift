import SwiftUI
import UIKit

/// A conversation about one document with the owner's own Claude or
/// ChatGPT: first what it is, what matters in it and what to do, then the
/// owner's questions, each answer shown word by word as it is written. Only
/// the protected copy is sent, smaller, and only once the owner opens
/// Explain; nothing of it is kept once the sheet closes.
@MainActor
final class DocumentTalk: ObservableObject {
    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        /// What the owner asked; nil for the first explanation.
        let question: String?
        var answer = ""
        var failure: AIError?
        var done = false
    }

    /// Sent with the picture, for the first explanation.
    private static let opening = "Explain this document."

    @Published private(set) var exchanges: [Exchange] = []
    private var image: AIImage?
    private var running: Task<Void, Never>?

    var isWriting: Bool { exchanges.last.map { !$0.done } ?? false }

    /// Questions wait for the first explanation.
    var canAsk: Bool {
        guard let first = exchanges.first else { return false }
        return first.done && first.failure == nil && !isWriting
    }

    /// Starts once, with the protected copy as it is now.
    func start(with copy: CGImage) {
        guard exchanges.isEmpty else { return }
        exchanges = [Exchange(question: nil)]
        running = Task {
            image = await Task.detached(priority: .userInitiated) { AIImage.from(copy, longest: 1600) }.value
            guard !Task.isCancelled else { return }
            await answer()
        }
    }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAsk, !question.isEmpty else { return }
        exchanges.append(Exchange(question: question))
        running = Task { await answer() }
    }

    /// Asks again what went wrong last.
    func retry() {
        guard let last = exchanges.last, last.failure != nil, !isWriting else { return }
        exchanges[exchanges.count - 1] = Exchange(question: last.question)
        running = Task { await answer() }
    }

    func stop() {
        running?.cancel()
        running = nil
    }

    /// The last exchange answered, piece by piece, with the conversation
    /// before it; what went wrong in its place, the words so far dropped.
    private func answer() async {
        let index = exchanges.count - 1
        guard index >= 0 else { return }
        guard let image else {
            fail(index, .other(L("The copy could not be made.")))
            return
        }
        var later: [AITurn] = []
        for exchange in exchanges.dropLast() where exchange.failure == nil {
            if let question = exchange.question { later.append(AITurn(role: .user, text: question)) }
            later.append(AITurn(role: .assistant, text: exchange.answer))
        }
        if let question = exchanges[index].question { later.append(AITurn(role: .user, text: question)) }
        do {
            let words = AIRequest.stream(instructions: AITask.document(in: AITask.ownLanguage), text: Self.opening,
                                         image: image, later: later)
            for try await piece in words {
                guard !Task.isCancelled, exchanges.indices.contains(index) else { return }
                exchanges[index].answer += piece
            }
            guard !Task.isCancelled, exchanges.indices.contains(index) else { return }
            let answer = exchanges[index].answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                fail(index, .other(L("The answer was empty.")))
                return
            }
            exchanges[index].answer = answer
            exchanges[index].done = true
        } catch {
            guard !Task.isCancelled else { return }
            fail(index, error as? AIError ?? .other(error.localizedDescription))
        }
    }

    private func fail(_ index: Int, _ failure: AIError) {
        guard exchanges.indices.contains(index) else { return }
        exchanges[index].answer = ""
        exchanges[index].failure = failure
        exchanges[index].done = true
    }
}

/// Explain, from Protect Picture: the protected copy as it was sent, then
/// the conversation, then ready questions and a field to ask more. Without
/// a key it offers to set one up first; until the copy is made and checked,
/// it waits for it.
struct ExplainSheet: View {
    @ObservedObject var session: ProtectSession
    @StateObject private var talk = DocumentTalk()
    @State private var question = ""
    @State private var setUp = AIAccount.isSetUp
    @State private var settingUp = false
    @State private var copied: UUID?
    @FocusState private var asking: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ready questions, sent as the owner would type them.
    private let quick = [L("What do I have to do?"), L("Is there a deadline?"), L("Explain it more simply."),
                         L("Write a short reply.")]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("Explain"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                }
                .navigationDestination(isPresented: $settingUp) { AssistantSettings() }
        }
        .onAppear(perform: begin)
        .onChange(of: session.isReady) { begin() }
        .onChange(of: settingUp) { _, open in
            // Back from AI Assistant, with a key perhaps.
            guard !open else { return }
            setUp = AIAccount.isSetUp
            begin()
        }
        .onDisappear { talk.stop() }
    }

    /// Starts once there is a key and a checked copy.
    private func begin() {
        guard setUp, session.isReady, let copy = session.copy?.cgImage else { return }
        talk.start(with: copy)
    }

    @ViewBuilder private var content: some View {
        if !setUp {
            invitation
        } else if case .failed(let reason) = session.stage {
            ContentUnavailableView(reason, systemImage: "exclamationmark.triangle")
        } else if talk.exchanges.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(L("Waiting for the protected copy…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            conversation
        }
    }

    // MARK: Without a key

    private var invitation: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(L("Understand documents faster"))
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(L("Connect your own Claude or ChatGPT. It says what a document is, what matters in it and what to do, and answers your questions. Snapfly sends it only the protected copy, and only when you ask."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    settingUp = true
                } label: {
                    Text(L("Set Up AI Assistant"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProtectButtonStyle())
                .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: The conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sent
                    ForEach(talk.exchanges) { exchange in
                        exchangeView(exchange)
                            .id(exchange.id)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: copied)
            .onChange(of: talk.exchanges.count) {
                // A question asked shows at the top, its answer under it.
                guard let last = talk.exchanges.last, last.question != nil else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { askBar }
    }

    /// The protected copy, small, as it was sent.
    private var sent: some View {
        HStack(spacing: 12) {
            if let copy = session.copy {
                Image(uiImage: copy)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(String(format: L("Sent to %@"), AIAccount.provider.name), systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(SentLabel())
                Text(L("Only the protected copy, with your own key."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func exchangeView(_ exchange: DocumentTalk.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = exchange.question {
                Text(question)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 40)
            }
            if let failure = exchange.failure {
                failed(failure, last: exchange.id == talk.exchanges.last?.id)
            } else if exchange.answer.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(String(format: L("Asking %@…"), AIAccount.provider.name))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                AnswerText(text: exchange.answer)
                if exchange.done {
                    Button {
                        UIPasteboard.general.string = exchange.answer
                        copied = exchange.id
                    } label: {
                        Label(copied == exchange.id ? L("Copied") : L("Copy"),
                              systemImage: copied == exchange.id ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    /// What went wrong, with the way to put it right: Try Again, or the
    /// assistant's settings for a key or a model.
    private func failed(_ failure: AIError, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(failure.message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.subheadline)
            if last {
                HStack(spacing: 12) {
                    if failure.isSettings {
                        Button(L("AI Assistant")) { settingUp = true }
                            .buttonStyle(.bordered)
                    }
                    Button(L("Try Again")) { talk.retry() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: Asking

    /// The ready questions, then a field for the owner's own, over a line
    /// saying answers can be wrong.
    private var askBar: some View {
        VStack(spacing: 8) {
            if talk.canAsk {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.self) { ready in
                            Button {
                                talk.ask(ready)
                            } label: {
                                Text(ready)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
            HStack(spacing: 8) {
                TextField(L("Ask about this document…"), text: $question)
                    .focused($asking)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.leading, 16)
                    .frame(minHeight: 44)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(!talk.canAsk || question.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L("Ask"))
            }
            .background(Color(.secondarySystemBackground), in: Capsule())
            .padding(.horizontal, 16)
            .disabled(!talk.canAsk)
            Text(L("Answers can be wrong. Check what matters."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: talk.canAsk)
    }

    private func send() {
        guard talk.canAsk, !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        talk.ask(question)
        question = ""
        asking = false
    }
}

/// The shield before the words, in the protect green.
private struct SentLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(SnapflyTokens.protect)
            configuration.title
        }
    }
}

/// An answer as it is written: lines that name a part, like "Important:",
/// in the headline; points starting with a bullet, hanging; the rest as
/// it is. Selectable, to copy a part of it.
private struct AnswerText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let words):
                    Text(words)
                        .font(.headline)
                        .padding(.top, 4)
                case .point(let words):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .foregroundStyle(.secondary)
                        Text(words)
                    }
                case .words(let words):
                    Text(words)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Line {
        case heading(String), point(String), words(String)
    }

    private var lines: [Line] {
        text.replacingOccurrences(of: "**", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> Line in
                for bullet in ["• ", "- ", "* ", "· "] where line.hasPrefix(bullet) {
                    return .point(String(line.dropFirst(bullet.count)))
                }
                if line.hasSuffix(":") || line.hasSuffix("："), line.count <= 40 {
                    return .heading(line)
                }
                return .words(line)
            }
    }
}
