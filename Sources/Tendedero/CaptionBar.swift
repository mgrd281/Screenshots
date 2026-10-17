import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// A line to write a message in, just above the chat button: a press and
/// hold on the button opens it, Return sends the photos with the message
/// after them, as one message in the chat, and Escape closes it. Like the
/// search bar, it takes the keyboard without bringing Snapfly to the front,
/// so the chat stays the app in front and gets the paste.
@MainActor
final class CaptionBar: NSObject, NSWindowDelegate {
    static let shared = CaptionBar()

    static let width: CGFloat = 340
    /// Room around the bar for its shadow.
    static let margin: CGFloat = 20

    private var panel: CaptionPanel?

    var isOpen: Bool { panel != nil }

    /// - Parameters:
    ///   - anchor: the chat button's capsule, in screen coordinates; the
    ///     bar's trailing edge lines up with it, just above.
    ///   - photo: the newest photo to send, which fills a saved message's
    ///     blanks.
    func show(above anchor: CGRect, count: Int, photo: URL? = nil, send: @escaping (String) -> Void) {
        close()
        // The chat it goes to, which keeps the language chosen for it.
        let view = CaptionBarView(count: count, photo: photo, destination: SendLog.destination, send: { [weak self] text in
            RecentCaptions.note(text)
            // The keyboard goes back to the chat before anything is pasted.
            self?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { send(text) }
        }, close: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = CaptionPanel()
        panel.contentView = host
        panel.delegate = self
        var origin = CGPoint(x: anchor.maxX + Self.margin - size.width, y: anchor.maxY + 6 - Self.margin)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX - Self.margin), visible.maxX - size.width + Self.margin)
            origin.y = min(origin.y, visible.maxY - size.height + Self.margin)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// A click in another app puts it away, as it does the search bar.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

private final class CaptionPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    // Typing needs a key window; a non-activating panel can be one without
    // bringing the app forward.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The last messages sent with photos, newest first, to pick again in the
/// message bar. They stay on this Mac.
enum RecentCaptions {
    static let key = "recentCaptions"
    static let limit = 5

    static var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The list with a message just sent at the top, once, and the oldest
    /// left out past the limit.
    static func adding(_ text: String, to list: [String]) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return list }
        return Array(([text] + list.filter { $0 != text }).prefix(limit))
    }

    static func note(_ text: String) {
        all = adding(text, to: all)
    }

    static func remove(_ text: String) {
        all.removeAll { $0 == text }
    }
}

/// The field and the send button, in the chat button's own glyph and color,
/// and over them, while the field is empty, the saved messages and those
/// sent lately.
private struct CaptionBarView: View {
    let count: Int
    let photo: URL?
    let destination: String?
    let send: (String) -> Void
    let close: () -> Void

    @State private var text = ""
    @State private var saved = SavedMessages.all.filter { !$0.isBlank }
    @State private var recent = RecentCaptions.all
    /// Which recent message ↑ and ↓ have put in the field; nil for none.
    @State private var browsing: Int?
    @FocusState private var focused: Bool
    /// The language the message goes in, as an identifier like "de"; nil
    /// to send it as typed.
    @State private var language: String?
    /// What the last translation put in the field, which goes as it is.
    @State private var translated: String?
    @State private var translating = false
    @StateObject private var translation = MessageTranslation()

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if text.isEmpty && !(saved.isEmpty && recent.isEmpty) { recentList }
            field
        }
        .padding(CaptionBar.margin)
        // The bar keeps its place by the button when the list goes.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// The saved messages, then each message sent lately, a click putting
    /// it in the field. A recent one's cross on hover takes it off the list.
    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(saved) { message in
                RecentRow(message: message.text, symbol: "bookmark") { use(message) }
            }
            ForEach(recent, id: \.self) { message in
                RecentRow(message: message, symbol: "clock.arrow.circlepath") {
                    text = message
                    focused = true
                } remove: {
                    RecentCaptions.remove(message)
                    recent = RecentCaptions.all
                }
            }
        }
        .padding(4)
        .frame(width: CaptionBar.width)
        .background(listBackground)
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField(L("Add a message…"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: close)
                // ↑ brings back the messages sent lately, newest first; ↓
                // goes the other way, down to an empty field.
                .onKeyPress(.upArrow) { browse(by: 1) }
                .onKeyPress(.downArrow) { browse(by: -1) }
            #if canImport(Translation)
            if #available(macOS 15, *) {
                languageMenu
            }
            #endif
            Text(count, format: .number)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .help(String(format: L("%d photos"), count))
                .accessibilityLabel(String(format: L("%d photos"), count))
            Button(action: submit) {
                Group {
                    if translating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ChatButton.tint.glyph)
                    } else {
                        Image(systemName: ChatButton.symbol.rawValue)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(ChatButton.tint.glyph)
                .frame(width: 30, height: 30)
                .background(ChatButton.tint.color, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("Send"))
            .accessibilityLabel(L("Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .frame(width: CaptionBar.width, height: 44)
        .background(bar)
        #if canImport(Translation)
        .background {
            if #available(macOS 15, *) {
                MessageTranslator(translation: translation) { result in
                    translating = false
                    guard let result else {
                        Notice.show(L("Could not translate this text."))
                        return
                    }
                    text = result
                    translated = result
                }
            }
        }
        #endif
        .onAppear {
            language = MessageLanguage.language(for: destination)
            DispatchQueue.main.async { focused = true }
        }
    }

    private func submit() {
        guard !translating else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // In the language chosen for this chat, translated first, on this
        // Mac, and shown: the next Return sends it.
        if message != translated?.trimmingCharacters(in: .whitespacesAndNewlines),
           let target = language.map(Locale.Language.init(identifier:)),
           let source = MessageLanguage.source(of: message, into: target) {
            translate(message, from: source, to: target)
            return
        }
        send(message)
    }

    private func translate(_ message: String, from source: Locale.Language, to target: Locale.Language) {
        #if canImport(Translation)
        if #available(macOS 15, *) {
            translating = true
            Task {
                switch await LanguageAvailability().status(from: source, to: target) {
                case .installed:
                    translation.job = MessageTranslation.Job(text: message, source: source, target: target)
                case .supported:
                    translating = false
                    Notice.show(String(format: L("To translate on this Mac, add %@ and %@ under Translation Languages in System Settings."),
                                       Languages.name(source), Languages.name(target)))
                default:
                    translating = false
                    Notice.show(String(format: L("Translating from %@ into %@ is not available."),
                                       Languages.name(source), Languages.name(target)))
                }
            }
            return
        }
        #endif
        send(message)
    }

    #if canImport(Translation)
    /// The language the message goes in: as typed, or one of the Mac's
    /// languages, the user's own first. Kept for the chat.
    @available(macOS 15, *)
    private var languageMenu: some View {
        Menu {
            Picker(L("Language of the message"), selection: $language) {
                Text(L("As typed")).tag(String?.none)
                Divider()
                ForEach(Languages.mine + Languages.others, id: \.minimalIdentifier) { item in
                    Text(Languages.name(item)).tag(Optional(item.minimalIdentifier))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            if let language {
                Text(verbatim: MessageLanguage.code(Locale.Language(identifier: language)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(language.map { String(format: L("Sent in %@"), Languages.name(Locale.Language(identifier: $0))) }
              ?? L("Send in another language"))
        .accessibilityLabel(L("Language of the message"))
        .onChange(of: language) { _, chosen in
            MessageLanguage.remember(chosen, for: destination)
            translated = nil
        }
    }
    #endif

    /// A saved message, its blanks filled from the photo: the order's
    /// number, total, date, name and tracking number, read on this Mac.
    private func use(_ message: SavedMessage) {
        focused = true
        guard let photo, SavedMessages.hasBlanks(message.text) else {
            text = message.text
            return
        }
        // Over an AI chat with Cover Everything there on, every kind's blank stays empty.
        let covering = CoveringProfile.detailsNow
        Task {
            let fields = await Task.detached(priority: .userInitiated) { OrderCard.read(photo) }.value
            text = SavedMessages.fill(message.text, with: fields, covering: covering)
        }
    }

    private func browse(by step: Int) -> KeyPress.Result {
        guard !recent.isEmpty else { return .ignored }
        let next = (browsing ?? -1) + step
        guard next >= -1, next < recent.count else { return .handled }
        browsing = next < 0 ? nil : next
        text = next < 0 ? "" : recent[next]
        return .handled
    }

    /// The bar's glass, with the corners of a list.
    @ViewBuilder
    private var listBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }

    /// The search bar's glass, in a capsule.
    @ViewBuilder
    private var bar: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }
}

/// The language a message goes in, chosen in the message bar for each chat
/// and kept for it: German for a shop's customers, as typed for a friend.
/// The translating is Apple's, on this Mac.
enum MessageLanguage {
    static let key = "messageLanguages"

    /// The language chosen for a chat, as an identifier like "de".
    static func language(for destination: String?, in defaults: UserDefaults = .standard) -> String? {
        guard let destination else { return nil }
        return (defaults.dictionary(forKey: key) as? [String: String])?[destination]
    }

    static func remember(_ identifier: String?, for destination: String?, in defaults: UserDefaults = .standard) {
        guard let destination else { return }
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[destination] = identifier
        defaults.set(all, forKey: key)
    }

    /// The language a message is written in when it is not the one chosen,
    /// so it is translated first; nil to send it as it is, like a message
    /// without words or one already in that language.
    static func source(of message: String, into target: Locale.Language) -> Locale.Language? {
        guard Languages.hasWords(message), let source = Languages.detect(message),
              !Languages.same(source, target) else { return nil }
        return source
    }

    /// Two letters on the bar, like "DE".
    static func code(_ language: Locale.Language) -> String {
        (language.languageCode?.identifier ?? language.minimalIdentifier).uppercased()
    }
}

/// The message waiting to be translated, for the view that holds Apple's
/// translation.
@MainActor
final class MessageTranslation: ObservableObject {
    struct Job: Equatable {
        let id = UUID()
        let text: String
        let source: Locale.Language
        let target: Locale.Language
    }

    @Published var job: Job?
}

#if canImport(Translation)
/// Apple's translation runs from a view: this one waits, unseen, for the
/// message and hands back its translation, nil when it failed.
@available(macOS 15, *)
private struct MessageTranslator: View {
    @ObservedObject var translation: MessageTranslation
    let done: (String?) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .onChange(of: translation.job?.id) { _, _ in
                guard let job = translation.job else { return }
                if configuration?.source == job.source && configuration?.target == job.target {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: job.source, target: job.target)
                }
            }
            .translationTask(configuration) { session in
                guard let job = translation.job else { return }
                let text = try? await session.translate(job.text).targetText
                guard translation.job?.id == job.id else { return }
                translation.job = nil
                done(text)
            }
    }
}
#endif

/// A message to pick: a saved one with its bookmark, or one sent lately
/// with the clock and, on hover, a cross to take it off the list.
private struct RecentRow: View {
    let message: String
    let symbol: String
    let pick: () -> Void
    var remove: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help(L("Remove"))
                .accessibilityLabel(L("Remove"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pick() }
    }
}
