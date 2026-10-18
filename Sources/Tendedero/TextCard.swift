import AppKit
import Combine
import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Translate Text and Describe, from a photo's menu: what the screenshot
/// says, translated, or summed up in a line to send along with it. Both
/// run on this Mac, with Apple's translation and Apple Intelligence, and
/// start from the text as it leaves the line, private details left out.
/// The result shows in a card under the photo, to copy or send. Order
/// Details lists the order's parts as the screenshot shows them, to copy.
/// Write a Reply and Explain with Claude, or ChatGPT, send the screenshot
/// covered to the AI assistant set up in Settings, with the owner's own
/// key; it also reads what Order Details on this Mac could not.
@MainActor
final class TextCard {
    static let shared = TextCard()

    /// Opens Settings, where the assistant's key goes.
    var openSettings: () -> Void = {}

    /// The card, and the clear margin around it its shadow falls in.
    static let width: CGFloat = 380
    static let margin: CGFloat = 28
    private static var windowWidth: CGFloat { width + margin * 2 }

    private var panel: CardPanel?
    private var host: NSHostingController<TextCardView>?
    private var watch: AnyCancellable?

    func show(_ model: TextCardModel, under photo: CGRect?) {
        close(animated: false)
        let host = NSHostingController(rootView: TextCardView(model: model) { [weak self] in self?.close() })
        host.sizingOptions = []
        let panel = CardPanel()
        // A question for the assistant is typed into the card.
        panel.takesKeys = model.kind == .reply || model.kind == .ask
        panel.contentViewController = host
        self.host = host
        self.panel = panel

        // Under the photo, or at the top of the screen in use.
        let anchor = photo.map { CGPoint(x: $0.midX, y: $0.minY - 14) }
        let screen = anchor.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let top = anchor ?? CGPoint(x: visible.midX, y: visible.maxY - 150)
        let x = min(max(top.x - Self.width / 2, visible.minX + 8), visible.maxX - Self.width - 8)
        panel.setFrameTopLeftPoint(CGPoint(x: x - Self.margin, y: min(top.y, visible.maxY - 8) + Self.margin))
        fit()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        // It grows and shrinks with what it shows, from its top edge.
        watch = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.fit() }
            }
        }
    }

    func close(animated: Bool = true) {
        watch = nil
        guard let panel else { return }
        self.panel = nil
        host = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func fit() {
        guard let panel, let host else { return }
        let height = ceil(host.sizeThatFits(in: CGSize(width: Self.windowWidth, height: 2000)).height)
        let top = panel.frame.maxY
        let frame = NSRect(x: panel.frame.minX, y: top - height, width: Self.windowWidth, height: height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }
}

/// Floats over everything like the line, without taking focus from the
/// app in front, so Send pastes into the chat you were in.
private final class CardPanel: NSPanel {
    /// Only for a field to type in, and only while one is clicked: the app
    /// in front stays in front.
    var takesKeys = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: TextCard.width + TextCard.margin * 2, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { takesKeys }
    override var canBecomeMain: Bool { false }
}

// MARK: - Languages

enum Languages {
    /// What Apple's translation on this Mac knows.
    private static let translatable = [
        "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nl",
        "pl", "pt-BR", "ru", "th", "tr", "uk", "vi", "zh-Hans",
    ]

    /// The language Snapfly speaks, like Arabic or German.
    static var own: Locale.Language {
        Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The user's own languages, Snapfly's first, then the rest by name.
    static var mine: [Locale.Language] {
        var ids: [String] = []
        for id in [Bundle.main.preferredLocalizations.first ?? "en"] + Locale.preferredLanguages {
            if let entry = entry(for: id), !ids.contains(entry) { ids.append(entry) }
        }
        return ids.map(Locale.Language.init(identifier:))
    }

    static var others: [Locale.Language] {
        let skip = Set(mine.map(\.minimalIdentifier))
        return translatable.map(Locale.Language.init(identifier:))
            .filter { !skip.contains($0.minimalIdentifier) }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }

    /// The entry in the list for a language like "de-DE" or "pt-PT".
    private static func entry(for id: String) -> String? {
        guard let code = Locale.Language(identifier: id).languageCode?.identifier else { return nil }
        switch code {
        case "zh": return "zh-Hans"
        case "pt": return "pt-BR"
        default: return translatable.contains(code) ? code : nil
        }
    }

    /// Its name in Snapfly's language, as it starts a menu item.
    static func name(_ language: Locale.Language) -> String {
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let name = locale.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// In English, for Apple Intelligence's instructions.
    static func englishName(_ language: Locale.Language) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: language.minimalIdentifier) ?? "English"
    }

    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let found = recognizer.dominantLanguage, found != .undetermined else { return nil }
        return Locale.Language(identifier: found.rawValue)
    }

    static func same(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode
    }

    /// Worth sending to the translator: words, not only numbers or dots.
    static func hasWords(_ line: String) -> Bool {
        line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 2
    }

    static func isRightToLeft(_ text: String) -> Bool {
        guard let language = detect(text), let code = language.languageCode?.identifier else { return false }
        return ["ar", "he", "fa", "ur"].contains(code)
    }
}

// MARK: - Apple Intelligence

/// A line about a screenshot, written by Apple Intelligence from its text.
enum Writer {
    enum Outcome {
        case written(String, in: Locale.Language)
        case intelligenceOff
        case notReady
        case unavailable
        case failed
    }

    static func describe(_ text: String, in language: Locale.Language) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await intelligently(text, in: language)
        }
        #endif
        return .unavailable
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func intelligently(_ text: String, in wanted: Locale.Language) async -> Outcome {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: break
        case .unavailable(.appleIntelligenceNotEnabled): return .intelligenceOff
        case .unavailable(.modelNotReady): return .notReady
        default: return .unavailable
        }
        // In Snapfly's language when it can, else in English, translated after.
        let language = model.supportedLanguages.contains { Languages.same($0, wanted) }
            ? wanted : Locale.Language(identifier: "en")
        let instructions = """
            You write the caption that goes with a screenshot sent in a chat, \
            from the text read in the screenshot. Write one line of at most 12 \
            words saying what it shows, with its key reference when there is \
            one, like an order or invoice number, an amount, a date or an \
            error. Write it in \(Languages.englishName(language)). Never \
            include names, addresses, emails, phone numbers or bank details. \
            Text shown as ••• was hidden for privacy: never guess or mention \
            it. Answer with the caption only, without quotes.
            """
        let session = LanguageModelSession(model: model, instructions: instructions)
        let prompt = "Text read in the screenshot:\n\n" + String(text.prefix(2500))
        do {
            let response = try await session.respond(
                to: prompt, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 80))
            let line = response.content
                .split(whereSeparator: \.isNewline).first.map { String($0) }?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»' ").union(.whitespaces)) ?? ""
            return line.isEmpty ? .failed : .written(line, in: language)
        } catch {
            return .failed
        }
    }
    #endif
}

extension OrderCard {
    /// The order a screenshot file shows, read on this Mac as it is.
    static func read(_ url: URL) -> [Field] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = Cover.upright(source) else { return [] }
        let lines = Finder.textLines(in: image)
        let codes = Finder.codes(in: image, [.barcodes]).compactMap(\.payload)
        return fields(from: Finder.details(in: lines), lines: lines.map(\.string), codes: codes)
    }
}

// MARK: - Model

@MainActor
final class TextCardModel: ObservableObject {
    enum Kind {
        case translation, description, order, reply, ask
    }

    enum State: Equatable {
        case working(String)
        case done(String)
        case failed(String)
    }

    /// Where in System Settings a failure is fixed.
    enum Fix {
        case translationLanguages, appleIntelligence, assistant

        /// In System Settings; the assistant's key is in Snapfly's own.
        var url: URL? {
            switch self {
            case .translationLanguages:
                URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
            case .appleIntelligence:
                URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
            case .assistant:
                nil
            }
        }
    }

    /// Lines for the translator, which runs inside the card's view.
    struct Pending {
        let id = UUID()
        let source: Locale.Language
        let target: Locale.Language
        let lines: [String]
        /// Said under the result.
        let note: String
    }

    let kind: Kind
    @Published private(set) var state = State.working(L("Reading the screenshot…"))
    @Published private(set) var note: String?
    @Published private(set) var fix: Fix?
    @Published private(set) var copied = false
    /// Order Details: the order's parts, and the one copied last.
    @Published private(set) var fields: [OrderCard.Field] = []
    @Published private(set) var copiedField: OrderCard.Part?
    @Published private(set) var target: Locale.Language
    @Published private(set) var pending: Pending?
    /// The result reads right to left, like Arabic.
    @Published private(set) var rightToLeft = false
    /// What the owner asks the assistant, or adds to the reply it writes.
    @Published var question = ""

    private let photo: UUID
    private let url: URL
    private weak var line: Line?
    private var reading: Finder.Reading?
    /// The screenshot as the assistant is sent it: covered.
    private var image: AIImage?

    var text: String? {
        if case .done(let text) = state { return text }
        return nil
    }

    init(_ kind: Kind, photo: UUID, url: URL, line: Line, target: Locale.Language) {
        self.kind = kind
        self.photo = photo
        self.url = url
        self.line = line
        self.target = target
    }

    func start() {
        let url = url
        if kind == .reply || kind == .ask {
            Task { await assist() }
            return
        }
        if kind == .order {
            Task { [weak self] in
                let fields = await Task.detached(priority: .userInitiated) { OrderCard.read(url) }.value
                self?.list(fields)
            }
            return
        }
        // Its text can be sent into the chat in front: into an AI chat with
        // Cover Everything there on, every kind is left out.
        let chosen = CoveringProfile.detailsNow
        let hand = PrivateDetails.hand(url)
        Task { [weak self] in
            let reading = await Task.detached(priority: .userInitiated) {
                Finder.reading(of: url, hiding: chosen, hand: hand)
            }.value
            self?.read(reading)
        }
    }

    private func read(_ reading: Finder.Reading) {
        self.reading = reading
        guard reading.lines.contains(where: Languages.hasWords) else {
            fail(L("There is no text to read in this screenshot."))
            return
        }
        switch kind {
        case .translation: translate()
        case .description: Task { await describe() }
        // Order Details reads the screenshot as it is, in start(); the
        // assistant is sent a picture, not its text.
        case .order, .reply, .ask: break
        }
    }

    // MARK: Order Details

    private func list(_ fields: [OrderCard.Field]) {
        // With the assistant set up, it reads the rest, like what was bought.
        if AIAccount.isSetUp {
            Task { await complete(fields) }
            return
        }
        guard !fields.isEmpty else {
            fail(L("No order details were found in this screenshot."))
            return
        }
        self.fields = fields
        finish(OrderCard.text(fields), note: L("Read on this Mac as the screenshot shows them, not covered."))
    }

    /// The order as read on this Mac, shown at once, with what the
    /// assistant reads in the covered copy added where this Mac found
    /// nothing. Without an answer, what this Mac read stays.
    private func complete(_ local: [OrderCard.Field]) async {
        let name = AIAccount.provider.name
        let here = L("Read on this Mac as the screenshot shows them, not covered.")
        if local.isEmpty {
            state = .working(String(format: L("Asking %@…"), name))
        } else {
            fields = local
            finish(OrderCard.text(local), note: String(format: L("Asking %@ for the rest…"), name))
        }
        do {
            guard let image = await coveredImage() else { throw AIError.other(L("Could not open the screenshot.")) }
            let answer = try await AIRequest.ask(instructions: AITask.order, text: "Read this order.", image: image,
                                                 schema: AITask.orderSchema)
            var values = Dictionary(local.map { ($0.part, $0.value) }, uniquingKeysWith: { first, _ in first })
            for (part, value) in AITask.orderParts(from: answer) where values[part] == nil { values[part] = value }
            let all = OrderCard.Part.allCases.compactMap { part in values[part].map { OrderCard.Field(part: part, value: $0) } }
            guard !all.isEmpty else {
                fail(L("No order details were found in this screenshot."))
                return
            }
            fields = all
            finish(OrderCard.text(all), note: all == local ? here
                   : String(format: L("Read on this Mac, not covered; %@ added what it read in the covered copy."), name))
        } catch {
            let failure = error as? AIError ?? .other(error.localizedDescription)
            if local.isEmpty {
                fail(failure.message, fix: failure.isSettings ? .assistant : nil)
            } else {
                finish(OrderCard.text(local), note: here + " " + failure.message, fix: failure.isSettings ? .assistant : nil)
            }
        }
    }

    // MARK: The assistant

    /// The screenshot with its private details covered, as for an AI chat:
    /// with Cover Everything in AI Chats on, every kind.
    private func coveredImage() async -> AIImage? {
        if let image { return image }
        let chosen = CoveringProfile.details(PrivateDetails.details, inAIChat: true,
                                             coversAll: CoveringProfile.coversAllInAIChats)
        let covered = PrivateDetails.shareable(url, covering: chosen)
        let made = await Task.detached(priority: .userInitiated) { AIImage.from(covered) }.value
        image = made
        return made
    }

    /// Write a Reply, or Ask: the covered screenshot and what the owner
    /// typed, to the assistant, and its answer in the card.
    private func assist() async {
        let name = AIAccount.provider.name
        guard AIAccount.isSetUp else {
            fail(AIError.noKey.message, fix: .assistant)
            return
        }
        state = .working(kind == .reply ? String(format: L("%@ is writing a reply…"), name)
                                        : String(format: L("Asking %@…"), name))
        note = nil
        fix = nil
        copied = false
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = kind == .reply ? AITask.reply : AITask.explain(in: Languages.englishName(Languages.own))
        let text = kind == .reply
            ? (asked.isEmpty ? "Write the reply." : "Write the reply. The seller adds: \(asked)")
            : (asked.isEmpty ? "What does this screenshot show?" : asked)
        do {
            guard let image = await coveredImage() else { throw AIError.other(L("Could not open the screenshot.")) }
            let answer = try await AIRequest.ask(instructions: instructions, text: text, image: image, effort: "medium")
            finish(answer.trimmingCharacters(in: .whitespacesAndNewlines),
                   note: String(format: L("Written by %@ from the screenshot with its private details covered."), name))
        } catch {
            let failure = error as? AIError ?? .other(error.localizedDescription)
            fail(failure.message, fix: failure.isSettings ? .assistant : nil)
        }
    }

    /// Asks again, with what the owner typed.
    func askAgain() {
        guard kind == .reply || kind == .ask, !isWorking else { return }
        Task { await assist() }
    }

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    func copy(_ field: OrderCard.Field) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(field.value, forType: .string)
        copiedField = field.part
    }

    /// Every part in one row with tabs between, for a spreadsheet.
    func copyRow() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(OrderCard.row(fields), forType: .string)
        copied = true
    }

    // MARK: Translating

    func retarget(_ language: Locale.Language) {
        guard kind == .translation, !Languages.same(language, target) else { return }
        target = language
        pending = nil
        copied = false
        translate()
    }

    private func translate() {
        guard let reading else { return }
        guard let source = Languages.detect(reading.text) else {
            fail(L("The language of this text could not be recognised."))
            return
        }
        if Languages.same(source, target) {
            finish(reading.text, note: String(format: L("The text is already in %@."), Languages.name(target)))
            return
        }
        #if canImport(Translation)
        if #available(macOS 15, *) {
            state = .working(L("Translating…"))
            note = nil
            fix = nil
            let target = target
            Task {
                let status = await LanguageAvailability().status(from: source, to: target)
                guard target == self.target else { return }
                switch status {
                case .installed:
                    pending = Pending(source: source, target: target, lines: reading.lines,
                                      note: String(format: L("Translated from %@ on this Mac."), Languages.name(source)))
                case .supported:
                    fail(String(format: L("To translate on this Mac, add %@ and %@ under Translation Languages in System Settings."),
                                Languages.name(source), Languages.name(target)), fix: .translationLanguages)
                default:
                    fail(String(format: L("Translating from %@ into %@ is not available."),
                                Languages.name(source), Languages.name(target)))
                }
            }
            return
        }
        #endif
        fail(L("Could not translate this text."))
    }

    #if canImport(Translation)
    /// Line by line, so the translation keeps the screenshot's layout.
    @available(macOS 15, *)
    func translate(with session: TranslationSession) async {
        guard let job = pending else { return }
        let requests = job.lines.indices
            .filter { Languages.hasWords(job.lines[$0]) }
            .map { TranslationSession.Request(sourceText: job.lines[$0], clientIdentifier: String($0)) }
        do {
            let responses = try await session.translations(from: requests)
            guard pending?.id == job.id else { return }
            var lines = job.lines
            for response in responses {
                if let id = response.clientIdentifier, let i = Int(id), lines.indices.contains(i) {
                    lines[i] = response.targetText
                }
            }
            pending = nil
            finish(lines.joined(separator: "\n"), note: job.note)
        } catch {
            guard pending?.id == job.id else { return }
            pending = nil
            fail(L("Could not translate this text."))
        }
    }
    #endif

    // MARK: Describing

    private func describe() async {
        guard let reading else { return }
        state = .working(L("Writing a description…"))
        let own = Languages.own
        switch await Writer.describe(reading.text, in: own) {
        case .written(let line, let language):
            if Languages.same(language, own) {
                finish(line, note: L("Written by Apple Intelligence on this Mac."))
            } else {
                await translateDescription(line, from: language)
            }
        case .intelligenceOff:
            headline(L("Apple Intelligence is off, so this is the screenshot's title. Turn it on in System Settings for a written description."),
                     fix: .appleIntelligence)
        case .notReady:
            headline(L("Apple Intelligence is still getting ready, so this is the screenshot's title for now."))
        case .unavailable:
            headline(L("Apple Intelligence is not available on this Mac, so this is the screenshot's title."))
        case .failed:
            headline(L("This is the screenshot's title."))
        }
    }

    /// Apple Intelligence writes in fewer languages than Snapfly speaks.
    private func translateDescription(_ line: String, from language: Locale.Language) async {
        let own = Languages.own
        #if canImport(Translation)
        if #available(macOS 15, *), await LanguageAvailability().status(from: language, to: own) == .installed {
            state = .working(L("Translating…"))
            pending = Pending(source: language, target: own, lines: [line],
                              note: L("Written by Apple Intelligence and translated on this Mac."))
            return
        }
        #endif
        finish(line, note: String(format: L("Apple Intelligence cannot write in %@ yet, so this is in English."),
                                  Languages.name(own)))
    }

    private func headline(_ note: String, fix: Fix? = nil) {
        guard let headline = reading?.headline else {
            fail(L("Could not describe this screenshot."), fix: fix)
            return
        }
        finish(headline, note: note, fix: fix)
    }

    // MARK: Results

    private func finish(_ text: String, note: String?, fix: Fix? = nil) {
        rightToLeft = Languages.isRightToLeft(text)
        state = .done(text)
        self.note = note
        self.fix = fix
    }

    private func fail(_ message: String, fix: Fix? = nil) {
        state = .failed(message)
        note = nil
        self.fix = fix
    }

    func openFix() {
        guard let fix else { return }
        if let url = fix.url {
            NSWorkspace.shared.open(url)
        } else {
            TextCard.shared.openSettings()
        }
    }

    func copy() {
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true
    }

    /// A translation goes as text; a description goes with its photo.
    func send() {
        guard let text, let line else { return }
        switch kind {
        case .translation, .reply: line.sendText(text)
        case .description: line.send(photo, caption: text)
        case .order, .ask: break
        }
    }
}

// MARK: - View

private struct TextCardView: View {
    @ObservedObject var model: TextCardModel
    let close: () -> Void

    private var title: String {
        switch model.kind {
        case .translation: L("Translation")
        case .description: L("Description")
        case .order: L("Order Details")
        case .reply: L("Reply")
        case .ask: L("Explanation")
        }
    }

    private var symbol: String {
        switch model.kind {
        case .translation: "translate"
        case .description: "sparkles"
        case .order: "list.bullet.rectangle"
        case .reply: "arrowshape.turn.up.left"
        case .ask: "bubble.left.and.text.bubble.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if let note = model.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fix = model.fix {
                Button(fix == .assistant ? L("Open Settings…") : L("Open System Settings…")) { model.openFix() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if model.kind == .reply || model.kind == .ask { questionField }
            if model.text != nil { footer }
        }
        .padding(16)
        .frame(width: TextCard.width, alignment: .leading)
        .background(card)
        .padding(TextCard.margin)
        .background {
            #if canImport(Translation)
            if #available(macOS 15, *) {
                TranslatorHost(model: model)
            }
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            if model.kind == .translation { languages }
            Button(action: close) {
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

    /// Into which language; changing it translates again.
    private var languages: some View {
        Menu {
            ForEach(Languages.mine, id: \.self) { language in
                Button(Languages.name(language)) { model.retarget(language) }
            }
            Divider()
            ForEach(Languages.others, id: \.self) { language in
                Button(Languages.name(language)) { model.retarget(language) }
            }
        } label: {
            Text(Languages.name(model.target))
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .working(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Placeholder()
            }
        case .done(let text):
            if model.kind == .order { orderRows } else { result(text) }
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func result(_ text: String) -> some View {
        let rtl = model.rightToLeft
        let words = Text(text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .multilineTextAlignment(rtl ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        return Group {
            // Long text scrolls, so the card stays a card.
            if text.count > 420 || text.filter(\.isNewline).count > 12 {
                ScrollView { words.padding(.trailing, 6) }
                    .frame(height: 240)
            } else {
                words
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Each part of the order on a row: its name, its value to select, and
    /// a button that copies it.
    private var orderRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(field.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)
                    Text(field.value)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.copy(field) } label: {
                        Image(systemName: model.copiedField == field.part ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Copy"))
                    .accessibilityLabel(L("Copy"))
                }
                .padding(.vertical, 6)
                if field.id != model.fields.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// What to ask, or to add to the reply; Return asks again.
    private var questionField: some View {
        HStack(spacing: 8) {
            TextField(model.kind == .reply ? L("Add something, like “offer a replacement”") : L("Ask about this screenshot"),
                      text: $model.question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.askAgain() }
            Button { model.askAgain() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            .disabled(model.isWorking)
            .help(model.kind == .reply ? L("Write Again") : L("Ask"))
            .accessibilityLabel(model.kind == .reply ? L("Write Again") : L("Ask"))
        }
    }

    @ViewBuilder private var footer: some View {
        if model.kind == .order { orderFooter } else { sendFooter }
    }

    /// The whole order as a row for a spreadsheet, or as lines to read.
    private var orderFooter: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                model.copyRow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { close() }
            } label: {
                Label(L("Copy Row"), systemImage: "tablecells")
            }
            .controlSize(.large)
            .help(L("Every part in one row, for a spreadsheet"))
            Button {
                model.copy()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { close() }
            } label: {
                Label(model.copied ? L("Copied") : L("Copy All"), systemImage: model.copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var sendFooter: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                model.copy()
                // Copied: it has done its job.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { close() }
            } label: {
                Label(model.copied ? L("Copied") : L("Copy"), systemImage: model.copied ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.large)
            if model.kind != .ask {
                Button {
                    if model.kind == .reply {
                        // Closed first, so the chat in front has the
                        // keyboard back from the question field when the
                        // reply is pasted.
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.send() }
                    } else {
                        model.send()
                        close()
                    }
                } label: {
                    Label(model.kind == .description ? L("Send with Photo") : L("Send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// Lines of text to come, breathing while the work goes on.
private struct Placeholder: View {
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach([1.0, 0.86, 0.62], id: \.self) { fraction in
                Capsule()
                    .fill(Color.primary.opacity(dim ? 0.05 : 0.11))
                    .frame(width: (TextCard.width - 32) * fraction, height: 9)
            }
        }
        .onAppear {
            // Still, with Reduce Motion on; the spinner above still says it works.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }
}

#if canImport(Translation)
/// Apple's translation runs from a view: this one waits, unseen, for the
/// card's lines and hands them a session.
@available(macOS 15, *)
private struct TranslatorHost: View {
    @ObservedObject var model: TextCardModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .onChange(of: model.pending?.id, initial: true) { _, _ in
                guard let job = model.pending else { return }
                if configuration?.source == job.source && configuration?.target == job.target {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: job.source, target: job.target)
                }
            }
            .translationTask(configuration) { session in
                await model.translate(with: session)
            }
    }
}
#endif
