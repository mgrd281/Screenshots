import AppKit
import SwiftUI

/// Capture and Ask AI, ⌃⌥A or from the menu: once the screenshot has landed
/// on the line, a card asks what to ask about it, and in which AI chat. A
/// question kept in Settings (⌘1 to ⌘9) or one typed, then Return, and the
/// covered copy goes into the chat with the question under it, as a photo's
/// own Ask menu sends it; nothing is sent until Return is pressed there.
/// Escape keeps the screenshot on the line. Like Check Before Sending, the
/// card takes the keyboard without bringing Snapfly to the front.
@MainActor
final class AskPanel: NSObject, NSWindowDelegate {
    static let shared = AskPanel()

    static let width: CGFloat = 400
    /// Room around the card for its shadow.
    static let margin: CGFloat = 28
    private static let chatKey = "askChat"

    private var panel: AskPanelWindow?
    private var model: AskModel?

    var isOpen: Bool { panel != nil }

    /// The AI chat asked last, else the one each screenshot goes to, else
    /// the first shown under photos.
    static func preferredChat(among chats: [ChatTarget], last: String?, captureChat: ChatTarget?) -> ChatTarget? {
        chats.first { $0.rawValue == last } ?? captureChat.flatMap { chats.contains($0) ? $0 : nil } ?? chats.first
    }

    /// The AI chats to ask, in the order Settings has them: those shown under
    /// photos, or every one when none is.
    static func chats(shown: (ChatTarget) -> Bool = { ChatTarget.shows($0) },
                      order: [ChatTarget] = ChatTarget.ordered()) -> [ChatTarget] {
        let ai = order.filter(\.isAI)
        let chosen = ai.filter(shown)
        return chosen.isEmpty ? ai : chosen
    }

    func show(_ id: UUID, url: URL, line: Line) {
        close()
        let chats = Self.chats()
        guard let chat = Self.preferredChat(among: chats, last: UserDefaults.standard.string(forKey: Self.chatKey),
                                            captureChat: CaptureToChat.chat) else { return }
        let questions = AIQuestions.all.filter { !$0.isBlank }.prefix(9).map(\.text)
        let model = AskModel(chats: chats, chat: chat, questions: Array(questions),
                             thumb: NSImage(contentsOf: PrivateDetails.shown(url) ?? url))
        model.ask = { [weak self, weak line] question in
            guard let self, let line else { return }
            self.ask(question, about: id, on: line)
        }
        model.cancel = { [weak self] in self?.close() }
        self.model = model
        let host = NSHostingView(rootView: AskView(model: model))
        let size = host.fittingSize
        let panel = AskPanelWindow()
        panel.contentView = host
        panel.delegate = self
        panel.onReturn = { [weak model] in model?.askTyped() }
        panel.onEscape = { [weak self] in self?.close() }
        panel.onNumber = { [weak model] n in model?.askKept(n) }
        panel.setFrame(CGRect(origin: origin(for: size), size: size), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduced ? 0 : 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// Below the strip the line hangs in, in the middle of the screen with
    /// the pointer, as Check Before Sending sits without a send button.
    private func origin(for size: CGSize) -> CGPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let line = Layout.photoMaxHeight + 106
        var origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - line - size.height + Self.margin)
        origin.y = max(origin.y, visible.minY - Self.margin + 8)
        return origin
    }

    /// The keyboard goes back to the app in front before the chat opens.
    private func ask(_ question: String?, about id: UUID, on line: Line) {
        guard let chat = model?.chat else { return }
        UserDefaults.standard.set(chat.rawValue, forKey: Self.chatKey)
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            line.send(id, to: chat, asking: question)
        }
    }

    /// Put away without asking: the screenshot stays on the line.
    func close() {
        model = nil
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// A click in another app puts it away, as it does Check Before Sending.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// What the card holds: the chats, the one chosen, the questions kept and
/// the one being typed.
@MainActor
final class AskModel: ObservableObject {
    let chats: [ChatTarget]
    @Published var chat: ChatTarget
    let questions: [String]
    let thumb: NSImage?
    @Published var typed = ""
    var ask: (String?) -> Void = { _ in }
    var cancel: () -> Void = {}

    init(chats: [ChatTarget], chat: ChatTarget, questions: [String], thumb: NSImage?) {
        self.chats = chats
        self.chat = chat
        self.questions = questions
        self.thumb = thumb
    }

    /// Return: the question typed, or the screenshot alone without one.
    func askTyped() {
        let question = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        ask(question.isEmpty ? nil : question)
    }

    /// ⌘1 to ⌘9: a question kept in Settings, by its number.
    func askKept(_ number: Int) {
        guard questions.indices.contains(number - 1) else { return }
        ask(questions[number - 1])
    }
}

/// Takes the keyboard without bringing Snapfly forward, and hears Return,
/// Escape and ⌘1 to ⌘9 wherever the focus is.
private final class AskPanelWindow: NSPanel {
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    var onNumber: (Int) -> Void = { _ in }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command, let key = event.charactersIgnoringModifiers, let n = Int(key), (1...9).contains(n) {
            onNumber(n)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn()
        case 53: onEscape()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}

/// The card, in the text card's look: the screenshot, the chats to ask,
/// the questions kept with their keys, a field for one's own, and how it goes.
private struct AskView: View {
    @ObservedObject var model: AskModel
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chats
            if !model.questions.isEmpty { questions }
            field
            Text(L("Private details are covered before it goes. Nothing is sent until you press Return in the chat."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: AskPanel.width, alignment: .leading)
        .background(card)
        .padding(AskPanel.margin)
        .onAppear { DispatchQueue.main.async { typing = true } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let thumb = model.thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 52, maxHeight: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: MenuSymbol.ask)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }
            Text(L("Ask about this screenshot"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: model.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L("Close"))
            .accessibilityLabel(L("Close"))
        }
    }

    /// The AI chats, each by its icon and name, the chosen one in the accent.
    private var chats: some View {
        HStack(spacing: 6) {
            ForEach(model.chats) { chat in
                chatButton(chat)
            }
        }
    }

    private func chatButton(_ chat: ChatTarget) -> some View {
        let chosen = model.chat == chat
        return Button {
            model.chat = chat
        } label: {
            HStack(spacing: 5) {
                if let icon = chat.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(chat.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(chosen ? Color.accentColor : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(chosen ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(chosen ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(chat.name)
        .accessibilityLabel(chat.name)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// The questions kept in Settings, each with its key.
    private var questions: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.questions.enumerated()), id: \.offset) { index, question in
                AskQuestionRow(number: index + 1, question: question) { model.ask(question) }
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One's own question; Return asks it.
    private var field: some View {
        HStack(spacing: 8) {
            TextField(L("Or type your own question…"), text: $model.typed)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($typing)
                .onSubmit { model.askTyped() }
            Button {
                model.askTyped()
            } label: {
                Label(L("Ask"), systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// A question kept in Settings: its key, ⌘1 to ⌘9, then its words, lit
/// under the pointer.
private struct AskQuestionRow: View {
    let number: Int
    let question: String
    let ask: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: ask) {
            HStack(spacing: 8) {
                Text(verbatim: "⌘\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 26)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .environment(\.layoutDirection, .leftToRight)
                Text(question)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(question)
    }
}
