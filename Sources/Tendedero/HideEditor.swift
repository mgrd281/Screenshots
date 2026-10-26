import AppKit
import SwiftUI

/// Hide Part: the screenshot large, to drag a box over anything that should
/// not leave the line, like a name the reading missed, or to say what to
/// hide in words. What Hide private details covers shows too, so what you
/// see is what goes. The boxes are kept with the photo, and the file itself
/// is never changed. A PDF brought in is shown a page at a time, with a way
/// to turn the pages; each keeps its own boxes.
@MainActor
final class HideEditor: NSObject, NSWindowDelegate {
    static let shared = HideEditor()

    private var window: NSWindow?
    /// The picture open, and whether for a copy.
    private var opened: (url: URL, copying: Bool)?
    /// Whether closing would lose boxes or choices not kept yet.
    private var hasChanges: () -> Bool = { false }

    /// Calls back once new boxes are saved; not when cancelled.
    func edit(_ url: URL, saved: @escaping () -> Void) {
        show(url, copying: false, saved: saved)
    }

    /// Hide private details for a copy beside a photo or PDF from Finder.
    /// What is hidden is chosen in the window, for that copy alone: the
    /// original stays as it is.
    func hideInCopy(_ url: URL) {
        show(url, copying: true) {}
    }

    private func show(_ url: URL, copying: Bool, saved: @escaping () -> Void) {
        // The same picture again: its window comes forward, as it was left.
        if let window, let opened, opened.url == url, opened.copying == copying {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard mayLetGo() else { return }
        window?.close()
        let document = isDocument(url)
        let pages = document ? DocumentCover.pageCount(url) : 1
        guard let image = document ? Self.page(1, of: url) : NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0 else {
            Notice.show(L("Could not open the screenshot."))
            return
        }
        // A copy starts with nothing hidden by hand: its boxes are its own.
        let stored: (Int) -> [CGRect] = { page in
            guard !copying else { return [] }
            return document ? PrivateDetails.hand(url, page: page) : PrivateDetails.hand(url)
        }
        let model = HideModel(image: image, hand: stored(1), chosen: PrivateDetails.details, copying: copying)
        model.pageCount = pages
        if document {
            model.turn = { [weak self, weak model] page in
                guard let model, let image = Self.page(page, of: url) else { return }
                model.show(page: page, image: image, hand: stored(page))
                self?.read(image, into: model)
            }
            read(image, into: model)
        } else {
            readCovered(url, into: model)
            readLines(url, into: model)
        }
        // A word covered always from now on is covered all over the picture.
        model.rulesChanged = { [weak self, weak model] in
            guard let self, let model else { return }
            if document { self.read(model.image, into: model) } else { self.readCovered(url, into: model) }
        }
        if copying {
            // Changing what is chosen covers the picture again at once.
            model.refresh = { [weak self, weak model] in
                guard let self, let model else { return }
                if document { self.read(model.image, into: model) } else { self.readCovered(url, into: model) }
            }
        }

        let view = HideEditorView(model: model, send: { [weak self, weak model] way in
            guard let model else { return }
            self?.send(way, of: url, model: model)
        }) { [weak self] save in
            guard save else {
                self?.window?.close()
                return
            }
            if copying {
                self?.saveCopy(of: url, model: model)
                return
            }
            if document {
                model.keepPage()
                for page in 1...max(1, pages) where model.handByPage[page] != nil {
                    PrivateDetails.setHand(model.handByPage[page] ?? [], for: url, page: page)
                }
            } else {
                PrivateDetails.setHand(model.hand, for: url)
            }
            saved()
            self?.window?.close()
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = url.deletingPathExtension().lastPathComponent
        let hosting = NSHostingView(rootView: view)
        // The window sets the size; the view fills it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = HidePartLayout.minimum
        // As large as fits the screen, with the picture never larger than
        // itself; it can be made larger or smaller after.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
        window.setContentSize(HidePartLayout.windowSize(for: image.size, pages: pages, in: room))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        opened = (url, copying)
        hasChanges = { [weak model] in model?.hasChanges(since: stored) ?? false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether the window open may give way, to its close button or another
    /// picture: at once with nothing changed, else once the owner chooses
    /// to discard the changes.
    private func mayLetGo() -> Bool {
        guard let window, hasChanges() else { return true }
        return EditorChanges.mayDiscard(in: window, keptBy: opened?.copying == true ? L("Save Copy…") : L("Done"))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        return mayLetGo()
    }

    /// Asks where the copy goes: in the folder of the original, under a name
    /// of its own. Nothing is written until the owner confirms the place.
    private func saveCopy(of url: URL, model: HideModel) {
        guard let window, !model.saving else { return }
        model.keepPage()
        let panel = NSSavePanel()
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = SaveCopy.suggestedName(for: url)
        panel.allowedContentTypes = [SaveCopy.fileType(for: url)]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self, weak model] response in
            guard response == .OK, let target = panel.url, let model else { return }
            MainActor.assumeIsolated { self?.export(url, model: model, to: target) }
        }
    }

    /// Writes the copy in the background, with a spinner meanwhile, and then
    /// says where it went.
    private func export(_ url: URL, model: HideModel, to target: URL) {
        let chosen = model.chosen
        let hand = model.hand
        let pages = model.handByPage
        model.saving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let written = SaveCopy.write(url, chosen, hand: hand, pages: pages, to: target)
            DispatchQueue.main.async { [weak self, weak model] in
                MainActor.assumeIsolated {
                    model?.saving = false
                    if written != nil {
                        Notice.show(String(format: L("Saved beside the original as %@."), target.lastPathComponent),
                                    done: true)
                        self?.window?.close()
                    } else {
                        Notice.show(L("Could not save the copy."))
                    }
                }
            }
        }
    }

    /// The copy straight to a chat, the clipboard or the Share menu,
    /// written first, in the background, as Save Copy… writes it. An AI
    /// chat covers everything when Settings says so for AI chats.
    private func send(_ way: CopySend, of url: URL, model: HideModel) {
        guard let window, !model.saving else { return }
        model.keepPage()
        var chosen = model.chosen
        if case .chat(let chat) = way, chat.isAI {
            chosen = CoveringProfile.details(chosen, inAIChat: true, coversAll: CoveringProfile.coversAllInAIChats)
        }
        let hand = model.hand
        let pages = model.handByPage
        guard let target = Self.sendFile(for: url, covering: chosen) else {
            Notice.show(L("Could not save the copy."))
            return
        }
        model.saving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let written = SaveCopy.write(url, chosen, hand: hand, pages: pages, to: target)
            DispatchQueue.main.async { [weak self, weak model] in
                MainActor.assumeIsolated {
                    model?.saving = false
                    guard let written else {
                        Notice.show(L("Could not save the copy."))
                        return
                    }
                    self?.deliver(target, way, covering: chosen, covered: !written.isEmpty, from: window)
                }
            }
        }
    }

    /// - Parameter covered: whether anything was covered in the copy, so
    ///   the note says "covered" only then.
    private func deliver(_ file: URL, _ way: CopySend, covering chosen: Set<PrivateDetail>, covered: Bool,
                         from window: NSWindow) {
        switch way {
        case .copy:
            Self.clip(file)
            Notice.show(covered ? L("Copied, covered. Paste it wherever you like.")
                                : L("Nothing to cover was found. Copied as it is, ready to paste."), done: true)
        case .share:
            guard let view = window.contentView else { return }
            let picker = NSSharingServicePicker(items: [file])
            let y = view.isFlipped ? view.bounds.maxY - 32 : 32
            picker.show(relativeTo: CGRect(x: view.bounds.maxX - 36, y: y, width: 1, height: 1), of: view,
                        preferredEdge: .minY)
        case .chat(let chat):
            // Out of the way, so the chat comes to the front.
            window.close()
            chat.open {
                Self.clip(file)
                // A mailbox takes it once a message is open: copied for that.
                if chat.copiesOnly {
                    Notice.show(L("Copied. Start a new message and paste."), done: true, lasting: 6)
                    return
                }
                // A new message starts in the address field; the copy is for its body.
                if chat.startsFresh { Paste.pressTab(times: 2) }
                guard Paste.askToBeAllowed() else {
                    Notice.show(L("Copied. Paste it with ⌘V."), done: true, lasting: 6)
                    return
                }
                Paste.intoFrontApp(after: chat.startsFresh ? 0.15 : 0)
                SendLog.note([file], to: chat.name, message: nil, covering: chosen)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        opened = nil
        hasChanges = { false }
    }

    /// A page of a PDF, at the size it shows on screen.
    private static func page(_ number: Int, of url: URL) -> NSImage? {
        guard let page = DocumentCover.page(number, of: url) else { return nil }
        let scale = 72 / DocumentCover.dpi
        return NSImage(cgImage: page, size: NSSize(width: CGFloat(page.width) * scale, height: CGFloat(page.height) * scale))
    }

    /// A page's text and what Hide private details covers on it, read in
    /// the background.
    private func read(_ image: NSImage, into model: HideModel) {
        guard let page = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let chosen = model.chosen
        let shown = model.page
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            let lines = Finder.textLines(in: page)
            let areas = Cover.areas(in: page, chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Read for a page that is still the one showing, and the choice still in place.
                    guard let model, model.page == shown, model.chosen == chosen else { return }
                    model.found = areas
                    model.lines = lines
                }
            }
        }
    }

    /// Every line of text, with where it sits, for hiding by saying.
    private func readLines(_ url: URL, into model: HideModel) {
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            // Upright, as it shows: a photo from a phone may be stored turned.
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Cover.upright(source) else { return }
            let lines = Finder.textLines(in: image)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { model?.lines = lines }
            }
        }
    }

    /// What Hide private details covers, read in the background.
    private func readCovered(_ url: URL, into model: HideModel) {
        let chosen = model.chosen
        guard isImage(url) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Cover.upright(source) else { return }
            let areas = Cover.areas(in: image, chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Only for the choice still in place.
                    if let model, model.chosen == chosen { model.found = areas }
                }
            }
        }
    }
}

@MainActor
final class HideModel: ObservableObject {
    @Published private(set) var image: NSImage
    /// Hidden by hand, from 0 to 1 from the bottom left.
    @Published var hand: [CGRect]
    /// A PDF's pages: the one showing, from 1, and how many there are.
    @Published private(set) var page = 1
    var pageCount = 1
    /// The boxes of the pages already seen, kept while turning.
    private(set) var handByPage: [Int: [CGRect]] = [:]
    /// Shows another page.
    var turn: ((Int) -> Void)?
    /// Covered by Hide private details, the same way.
    @Published var found: [CGRect] = []

    /// What to hide, in words.
    @Published var request = ""
    @Published private(set) var working = false
    /// Said under the field once it has run.
    @Published private(set) var note: String?
    /// The text in the screenshot, once read.
    var lines: [Finder.TextLine]? {
        didSet { if lines != nil, waiting { hideAsSaid() } }
    }
    let understandsSentences = HideBySaying.understandsSentences

    /// Asked before the text was read.
    private var waiting = false
    /// The boxes the last request added, replaced by the next one.
    private var said: [CGRect] = []

    /// What is covered. A copy sets its own choice, starting from Settings.
    @Published var chosen: Set<PrivateDetail> {
        didSet {
            if chosen != oldValue { refresh?() }
        }
    }
    /// Whether this is a copy beside a photo or PDF from Finder: it has a
    /// choice of its own and a save button.
    let copying: Bool
    /// Covers the picture again after a change of choice.
    var refresh: (() -> Void)?
    /// The copy is being written.
    @Published var saving = false
    /// What a copy hid when the window opened.
    private let firstChosen: Set<PrivateDetail>

    /// A word hidden with a click, offered to be covered always.
    struct WordOffer: Equatable {
        let word: String
        /// Its box, from 0 to 1 from the bottom left.
        let box: CGRect
    }

    /// The word last hidden with a click, until something else happens.
    @Published var offer: WordOffer?
    /// Covers the picture again once a word is covered always.
    var rulesChanged: (() -> Void)?

    init(image: NSImage, hand: [CGRect], chosen: Set<PrivateDetail>, copying: Bool) {
        self.image = image
        self.hand = hand
        self.chosen = chosen
        self.copying = copying
        firstChosen = chosen
    }

    /// Keeps the boxes of the page showing, before turning or saving.
    func keepPage() {
        handByPage[page] = hand
    }

    /// Whether boxes were drawn or taken away on any page, or a copy's
    /// choice of what to hide changed, since the window opened: what
    /// closing it would lose.
    /// - Parameter stored: the boxes kept for a page.
    func hasChanges(since stored: (Int) -> [CGRect]) -> Bool {
        if copying, chosen != firstChosen { return true }
        var pages = handByPage
        pages[page] = hand
        return pages.contains { stored($0.key) != $0.value }
    }

    func go(to page: Int) {
        guard page >= 1, page <= pageCount, page != self.page else { return }
        keepPage()
        turn?(page)
    }

    /// The page turned to, with its boxes as they were left, or as saved.
    func show(page: Int, image: NSImage, hand saved: [CGRect]) {
        self.page = page
        self.image = image
        hand = handByPage[page] ?? saved
        offer = nil
        found = []
        waiting = false
        lines = nil
        said = []
        request = ""
        note = nil
        working = false
    }

    func hideAsSaid() {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        working = true
        note = nil
        offer = nil
        guard let lines else {
            waiting = true
            return
        }
        waiting = false
        let texts = lines.map(\.string)
        let asked = page
        Task { @MainActor in
            let outcome = await HideBySaying.pieces(toHide: request, in: texts)
            // The answer belongs to the page it was asked on.
            guard page == asked else { return }
            let pieces: [HideBySaying.Piece]
            switch outcome {
            case let .understood(found): pieces = found
            case let .matched(found): pieces = found
            }
            var boxes: [CGRect] = []
            for piece in pieces {
                for box in Self.boxes(for: piece, in: lines[piece.line]).map(Self.padded) where !boxes.contains(box) {
                    boxes.append(box)
                }
            }
            hand.removeAll { said.contains($0) }
            hand += boxes
            said = boxes
            working = false
            if boxes.isEmpty {
                note = L("Nothing found to hide.")
            } else if case .matched = outcome, understandsSentences {
                note = L("Apple Intelligence could not answer, so the words typed are hidden where they appear.")
            } else {
                note = String(format: L("Parts hidden: %d. Click a box to show it again."), boxes.count)
            }
        }
    }

    /// A click on a word hides it, with a little room round it, and offers
    /// to cover that word always. A click beside any word, or on one
    /// already covered, hides nothing.
    func coverWord(at point: CGPoint) {
        offer = nil
        guard let lines, !found.contains(where: { $0.contains(point) }),
              !hand.contains(where: { $0.contains(point) }) else { return }
        for line in lines {
            let slack = line.box.height * 0.2
            guard line.box.insetBy(dx: -line.box.height, dy: -slack).contains(point) else { continue }
            let words = Self.words(in: line)
            guard let i = Self.word(at: point, among: words.map(\.box)) else { continue }
            let box = Self.padded(words[i].box)
            hand.append(box)
            offer = Self.ruleText(words[i].text).map { WordOffer(word: $0, box: box) }
            note = nil
            return
        }
    }

    /// The word offered is covered in every photo from now on, as a rule of
    /// the owner's own, which Settings › Always Hide lists.
    func alwaysCover() {
        guard let offer else { return }
        self.offer = nil
        OwnRules.add(word: offer.word)
        note = String(format: L("“%1$@” is covered from now on, in every photo. Change it in %2$@."), offer.word,
                      [L("Settings"), L("Always Hide")].joined(separator: " › "))
        rulesChanged?()
    }

    /// A hand box taken away, the word offered with it too.
    func remove(at index: Int) {
        guard hand.indices.contains(index) else { return }
        if hand[index] == offer?.box { offer = nil }
        hand.remove(at: index)
    }

    /// Each word of a line, as the spaces part them, with where it is.
    private static func words(in line: Finder.TextLine) -> [(text: String, box: CGRect)] {
        let string = line.string
        return wordRanges(in: string).compactMap { range in
            line.box(for: range).map { (String(string[range]), $0) }
        }
    }

    /// Where each word is in a line of text, as the spaces part them.
    nonisolated static func wordRanges(in string: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in string.indices {
            if string[index].isWhitespace {
                if let begun = start { ranges.append(begun..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begun = start { ranges.append(begun..<string.endIndex) }
        return ranges
    }

    /// The word under the point, or else the nearest on its row, no further
    /// than its own height, from boxes 0 to 1 from the bottom left.
    nonisolated static func word(at point: CGPoint, among boxes: [CGRect]) -> Int? {
        let rows = boxes.indices.filter {
            let slack = boxes[$0].height * 0.2
            return point.y >= boxes[$0].minY - slack && point.y <= boxes[$0].maxY + slack
        }
        if let inside = rows.first(where: { boxes[$0].minX <= point.x && point.x <= boxes[$0].maxX }) { return inside }
        func distance(_ i: Int) -> CGFloat { max(boxes[i].minX - point.x, point.x - boxes[i].maxX) }
        guard let nearest = rows.min(by: { distance($0) < distance($1) }),
              distance(nearest) <= boxes[nearest].height else { return nil }
        return nearest
    }

    /// The word as a rule takes it: without the punctuation round it, like
    /// "Kelly" from "Kelly,"; nil for a sign or a single letter.
    nonisolated static func ruleText(_ word: String) -> String? {
        let text = word.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        return text.count >= 2 ? text : nil
    }

    /// Where the words are in the line, each time they appear. Words the
    /// line does not have hide all of it, to be safe.
    private static func boxes(for piece: HideBySaying.Piece, in line: Finder.TextLine) -> [CGRect] {
        guard let words = piece.words, !words.isEmpty else { return [line.box] }
        let string = line.string
        var boxes: [CGRect] = []
        var from = string.startIndex
        while from < string.endIndex,
              let range = string.range(of: words, options: HideBySaying.insensitive, range: from..<string.endIndex) {
            if let box = line.box(for: range) { boxes.append(box) }
            from = range.upperBound
        }
        return boxes.isEmpty ? [line.box] : boxes
    }

    /// A box with a little room around it, so no letter peeks out.
    private static func padded(_ box: CGRect) -> CGRect {
        let room = box.height * 0.15
        return box.insetBy(dx: -room, dy: -room).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// How the Hide Part window is laid out: the picture on a canvas, as large
/// as fits, beside an inspector with everything to choose, and how large the
/// window opens for a picture.
enum HidePartLayout {
    /// The inspector on the trailing edge.
    static let panelWidth: CGFloat = 340
    /// Around the picture on its canvas.
    static let margin: CGFloat = 24
    /// The page control under a PDF's page.
    static let pagesHeight: CGFloat = 36
    /// The least the window may be.
    static let minimum = CGSize(width: 760, height: 480)

    /// The picture as large as fits the area, never larger than itself.
    static func fitted(_ image: CGSize, in area: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(0, min(1, area.width / image.width, area.height / image.height))
        return CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }

    /// The window to open: the picture as large as fits the room beside the
    /// inspector, and the window never smaller than the minimum.
    static func windowSize(for image: CGSize, pages: Int, in room: CGSize) -> CGSize {
        let bar = pages > 1 ? pagesHeight : 0
        let area = CGSize(width: room.width - panelWidth - 2 * margin, height: room.height - 2 * margin - bar)
        let picture = fitted(image, in: area)
        let wanted = CGSize(width: picture.width + 2 * margin + panelWidth, height: picture.height + 2 * margin + bar)
        return CGSize(width: max(minimum.width, min(room.width, wanted.width)).rounded(),
                      height: max(minimum.height, min(room.height, wanted.height)).rounded())
    }
}

/// Asks before what was changed in an editor's window is let go: Hide
/// Part's, Draw on Photo's and Background's, when the close button is
/// clicked or another picture is opened in it. Keep Editing is the
/// default; Discard lets the changes go. Cancel and Done in the window ask
/// nothing. Studio keeps its work instead, since it changes nothing sent.
@MainActor
enum EditorChanges {
    /// - Parameter action: the button in the window that keeps them, like Done.
    static func mayDiscard(in window: NSWindow, keptBy action: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = L("Discard your changes?")
        alert.informativeText = String(format: L("They are kept only once you click %@."), action)
        alert.addButton(withTitle: L("Keep Editing"))
        alert.addButton(withTitle: L("Discard"))
        alert.buttons.last?.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// The window: the picture on its canvas, and on the trailing edge the
/// inspector, a grouped form of what to hide over the Cancel and Done
/// buttons.
private struct HideEditorView: View {
    @ObservedObject var model: HideModel
    /// A copy straight to where it goes, for a copy from Finder.
    let send: (CopySend) -> Void
    let finish: (Bool) -> Void

    /// The box being drawn, in the view.
    @State private var drawing: CGRect?
    @State private var hovered: Int?
    @State private var crosshair = false
    @FocusState private var fieldFocused: Bool
    /// The window's reading direction, for the words on the picture.
    @Environment(\.layoutDirection) private var layoutDirection

    private static let cover = Color(white: 0.12)

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            inspector
        }
        .frame(minWidth: HidePartLayout.minimum.width, minHeight: HidePartLayout.minimum.height)
    }

    // MARK: The canvas

    /// The picture as large as fits, centred on the canvas, with a PDF's
    /// pages under it.
    private var canvas: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let margin = HidePartLayout.margin
                let size = HidePartLayout.fitted(model.image.size,
                                                 in: CGSize(width: geometry.size.width - 2 * margin,
                                                            height: geometry.size.height - 2 * margin))
                picture(size)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            if model.pageCount > 1 {
                pages
                    .frame(height: HidePartLayout.pagesHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// The picture at that size, with what is covered and the boxes drawn
    /// by hand over it, ready for another box to be dragged.
    private func picture(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: model.image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
            ForEach(Array(model.found.enumerated()), id: \.offset) { _, box in
                place(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.cover), box, in: size)
                    .allowsHitTesting(false)
            }
            ForEach(Array(model.hand.enumerated()), id: \.offset) { i, box in
                place(handBox(hovering: hovered == i), box, in: size)
                    .onHover { inside in
                        if inside { hovered = i } else if hovered == i { hovered = nil }
                    }
                    .onTapGesture {
                        hovered = nil
                        model.remove(at: i)
                    }
            }
            if let offer = model.offer {
                alwaysCover(offer, in: size)
            }
            if let drawing {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .frame(width: drawing.width, height: drawing.height)
                    .offset(x: drawing.minX, y: drawing.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        // A click on a word hides it; the boxes take their own clicks first.
        .onTapGesture(coordinateSpace: .local) { point in
            guard size.width > 0, size.height > 0 else { return }
            model.coverWord(at: CGPoint(x: point.x / size.width, y: 1 - point.y / size.height))
        }
        .animation(.easeOut(duration: 0.15), value: model.offer)
        // Alongside the boxes' clicks, so a drag can start on one too.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { drawing = box(from: $0.startLocation, to: $0.location, in: size) }
                .onEnded { value in
                    let drawn = box(from: value.startLocation, to: value.location, in: size)
                    drawing = nil
                    guard drawn.width >= 4, drawn.height >= 4 else { return }
                    model.offer = nil
                    model.hand.append(normalized(drawn, in: size))
                }
        )
        .onHover { inside in
            guard inside != crosshair else { return }
            if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            crosshair = inside
        }
        .onDisappear {
            if crosshair { NSCursor.pop() }
        }
        // Laid out from the left, as the picture is, in every language, so
        // the covers and the boxes sit on what they hide.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// A PDF's pages, one at a time, under the page showing.
    private var pages: some View {
        HStack(spacing: 4) {
            Button {
                model.go(to: model.page - 1)
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(model.page <= 1)
            .help(L("Previous Page"))
            .accessibilityLabel(L("Previous Page"))
            Text(String(format: L("Page %d of %d"), model.page, model.pageCount))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            Button {
                model.go(to: model.page + 1)
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(model.page >= model.pageCount)
            .help(L("Next Page"))
            .accessibilityLabel(L("Next Page"))
        }
        .controlSize(.small)
    }

    // MARK: The inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                saying
                if model.copying {
                    copyChoice
                }
                byHand
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: HidePartLayout.panelWidth)
    }

    /// A field to say what to hide, examples ready to click, and a note on
    /// what it did.
    private var saying: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: model.understandsSentences ? "sparkles" : "text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L("Say what to hide"), text: $model.request, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit {
                        // Empty, Return is Done, as everywhere else.
                        if model.request.trimmingCharacters(in: .whitespaces).isEmpty {
                            finish(true)
                        } else {
                            model.hideAsSaid()
                        }
                    }
                if model.working {
                    ProgressView().controlSize(.small)
                }
                Button(L("Hide")) { model.hideAsSaid() }
                    .disabled(model.working || model.request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.understandsSentences {
                // In a row where they fit, else one under another.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { examples }
                    VStack(alignment: .leading, spacing: 6) { examples }
                }
            }
        } header: {
            Text(L("Say what to hide"))
        } footer: {
            if let note = model.note {
                Text(note)
                    .foregroundStyle(.secondary)
            } else if !model.understandsSentences {
                Text(L("With Apple Intelligence on, you can say it in a sentence."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var prompt: String {
        model.understandsSentences
            ? L("Say what to hide, like “everything but the amount and the date”")
            : L("Words to hide, separated by commas")
    }

    /// Ready to click, for what is hidden most often.
    private static let exampleRequests = [
        L("Names and addresses"),
        L("Everything but the amount and the date"),
        L("Phone numbers and emails"),
    ]

    private var examples: some View {
        ForEach(Self.exampleRequests, id: \.self) { example in
            Button(example) {
                model.request = example
                model.hideAsSaid()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.working)
        }
    }

    /// What the copy hides, chosen for that copy alone: every kind, the
    /// recommended ones or none at once, then the kinds in the three groups
    /// Settings has, in the same words.
    @ViewBuilder private var copyChoice: some View {
        Section {
            // One row, small, so the kinds below come into view sooner.
            HStack(spacing: 6) { choices }
                .controlSize(.small)
        } header: {
            Text(L("Hide in this copy"))
        } footer: {
            Text(L("The copy has no place or camera details. The original stays as it is."))
                .foregroundStyle(.secondary)
        }
        ForEach(PrivateDetail.Group.allCases, id: \.self) { group in
            Section(group.title) {
                ForEach(group.kinds, id: \.self) { detail in
                    Toggle(isOn: Binding(
                        get: { model.chosen.contains(detail) },
                        set: { on in
                            if on { model.chosen.insert(detail) } else { model.chosen.remove(detail) }
                        }
                    )) {
                        Text(detail.title)
                        if let subtitle = detail.subtitle { Text(subtitle) }
                    }
                }
            }
        }
    }

    private var choices: some View {
        Group {
            choice(L("Check All"), Set(PrivateDetail.allCases))
            choice(L("Recommended"), PrivateDetail.recommended)
            choice(L("Uncheck All"), [])
        }
    }

    private func choice(_ title: String, _ kinds: Set<PrivateDetail>) -> some View {
        Button { model.chosen = kinds } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
    }

    /// The boxes dragged over the picture, and a way to take them all away.
    private var byHand: some View {
        Section {
            LabeledContent {
                Button(L("Remove All")) { model.hand = [] }
                    .disabled(model.hand.isEmpty)
            } label: {
                Text(L("By hand"))
                Text(L("Click a word to hide it, or drag over anything. Click a box to show it again."))
            }
        }
    }

    /// For a copy, the chats to send it to; then Cancel and Done, or Save
    /// Copy…, with a spinner while the copy is written.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.copying {
                SendBar(busy: model.saving, send: send)
                Divider()
            }
            buttons
        }
        .padding(16)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if model.saving {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button(L("Cancel")) { finish(false) }
                .keyboardShortcut(.cancelAction)
                .disabled(model.saving)
            Button(model.copying ? L("Save Copy…") : L("Done")) { finish(true) }
                // Return in the field hides what it says instead.
                .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut.defaultAction)
                .disabled(model.saving)
        }
    }

    // MARK: Boxes

    /// Under the word just hidden, or over it at the bottom of the picture:
    /// a small button to cover that word always.
    private func alwaysCover(_ offer: HideModel.WordOffer, in size: CGSize) -> some View {
        let below = (1 - offer.box.minY) * size.height + 16
        let y = below + 12 < size.height ? below : (1 - offer.box.maxY) * size.height - 16
        let x = min(max(offer.box.midX * size.width, 90), max(90, size.width - 90))
        return Button {
            model.alwaysCover()
        } label: {
            Label(String(format: L("Always cover “%@”"), offer.word), systemImage: "plus.circle.fill")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
                // Its words in the window's reading direction, on the picture laid out from the left.
                .environment(\.layoutDirection, layoutDirection)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help(String(format: L("Covered in every photo from now on, as a rule of your own under %@."), L("Always Hide")))
        .position(x: x, y: y)
        .transition(.opacity)
    }

    private func handBox(hovering: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Self.cover)
            .overlay {
                if hovering {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: hovering ? 2 : 0))
            .contentShape(Rectangle())
    }

    /// A box from 0 to 1 from the bottom left, placed over the picture.
    private func place(_ view: some View, _ box: CGRect, in size: CGSize) -> some View {
        let rect = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        return view
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Between two points of a drag, kept on the picture.
    private func box(from a: CGPoint, to b: CGPoint, in size: CGSize) -> CGRect {
        let minX = max(0, min(a.x, b.x)), maxX = min(size.width, max(a.x, b.x))
        let minY = max(0, min(a.y, b.y)), maxY = min(size.height, max(a.y, b.y))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func normalized(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX / size.width, y: 1 - rect.maxY / size.height,
               width: rect.width / size.width, height: rect.height / size.height)
    }
}
