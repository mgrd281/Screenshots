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

    /// Calls back once new boxes are saved; not when cancelled.
    func edit(_ url: URL, saved: @escaping () -> Void) {
        window?.close()
        let document = isDocument(url)
        let pages = document ? DocumentCover.pageCount(url) : 1
        guard let image = document ? Self.page(1, of: url) : NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0 else {
            Notice.show(L("Could not open the screenshot."))
            return
        }
        let model = HideModel(image: image, hand: document ? PrivateDetails.hand(url, page: 1) : PrivateDetails.hand(url))
        model.pageCount = pages
        if document {
            model.turn = { [weak self, weak model] page in
                guard let model, let image = Self.page(page, of: url) else { return }
                model.show(page: page, image: image, hand: PrivateDetails.hand(url, page: page))
                self?.read(image, into: model)
            }
            read(image, into: model)
        } else {
            readCovered(url, into: model)
            readLines(url, into: model)
        }

        // As large as fits, never larger than the screenshot itself.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8 - 60)

        let view = HideEditorView(model: model, room: room) { [weak self] save in
            if save {
                if document {
                    model.keepPage()
                    for page in 1...max(1, pages) where model.handByPage[page] != nil {
                        PrivateDetails.setHand(model.handByPage[page] ?? [], for: url, page: page)
                    }
                } else {
                    PrivateDetails.setHand(model.hand, for: url)
                }
                saved()
            }
            self?.window?.close()
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = url.deletingPathExtension().lastPathComponent
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
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
        let chosen = PrivateDetails.details
        let shown = model.page
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            let lines = Finder.textLines(in: page)
            let areas = chosen.isEmpty ? [] : Cover.areas(in: page, chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Read for a page that is still the one showing.
                    guard let model, model.page == shown else { return }
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
        let chosen = PrivateDetails.details
        guard !chosen.isEmpty, isImage(url) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Cover.upright(source) else { return }
            let areas = Cover.areas(in: image, chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let model { model.found = areas }
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

    init(image: NSImage, hand: [CGRect]) {
        self.image = image
        self.hand = hand
    }

    /// Keeps the boxes of the page showing, before turning or saving.
    func keepPage() {
        handByPage[page] = hand
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

    /// Where the words are in the line, each time they appear. Words the
    /// line does not have hide all of it, to be safe.
    private static func boxes(for piece: HideBySaying.Piece, in line: Finder.TextLine) -> [CGRect] {
        guard let words = piece.words, !words.isEmpty else { return [line.box] }
        let string = line.string
        var boxes: [CGRect] = []
        var from = string.startIndex
        while from < string.endIndex,
              let range = string.range(of: words, options: HideBySaying.insensitive, range: from..<string.endIndex) {
            if let box = try? line.text.boundingBox(for: range)?.boundingBox { boxes.append(box) }
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

private struct HideEditorView: View {
    @ObservedObject var model: HideModel
    /// The most room the picture may take.
    let room: CGSize
    let finish: (Bool) -> Void

    /// As large as fits, never larger than the picture itself.
    private var size: CGSize {
        let image = model.image.size
        guard image.width > 0, image.height > 0 else { return room }
        let scale = min(1, room.width / image.width, room.height / image.height)
        return CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }

    /// The box being drawn, in the view.
    @State private var drawing: CGRect?
    @State private var hovered: Int?
    @State private var crosshair = false
    @FocusState private var fieldFocused: Bool

    private static let cover = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: model.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                ForEach(Array(model.found.enumerated()), id: \.offset) { _, box in
                    place(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.cover), box)
                        .allowsHitTesting(false)
                }
                ForEach(Array(model.hand.enumerated()), id: \.offset) { i, box in
                    place(handBox(hovering: hovered == i), box)
                        .onHover { inside in
                            if inside { hovered = i } else if hovered == i { hovered = nil }
                        }
                        .onTapGesture {
                            hovered = nil
                            model.hand.remove(at: i)
                        }
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
            // Alongside the boxes' clicks, so a drag can start on one too.
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drawing = rect(from: $0.startLocation, to: $0.location) }
                    .onEnded { value in
                        let rect = rect(from: value.startLocation, to: value.location)
                        drawing = nil
                        guard rect.width >= 4, rect.height >= 4 else { return }
                        model.hand.append(normalized(rect))
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

            saying
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .frame(width: max(size.width, 520))

            HStack(spacing: 10) {
                if model.pageCount > 1 {
                    pages
                }
                Text(L("Drag over anything to hide it. Click a box to show it again."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(L("Remove All")) { model.hand = [] }
                    .disabled(model.hand.isEmpty)
                Button(L("Cancel")) { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button(L("Done")) { finish(true) }
                    // Return in the field hides what it says instead.
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut.defaultAction)
            }
            .padding(14)
            .frame(width: max(size.width, 520))
        }
    }

    /// A PDF's pages, one at a time.
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

    /// A field to say what to hide, with a note on what it did.
    private var saying: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: model.understandsSentences ? "sparkles" : "text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(model.understandsSentences
                          ? L("Say what to hide, like “everything but the amount and the date”")
                          : L("Words to hide, separated by commas"),
                          text: $model.request)
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
            if let note = model.note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.understandsSentences {
                Text(L("With Apple Intelligence on, you can say it in a sentence."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

    /// A box from 0 to 1 from the bottom left, placed over the image.
    private func place(_ view: some View, _ box: CGRect) -> some View {
        let rect = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        return view
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Between two points of a drag, kept on the image.
    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        let minX = max(0, min(a.x, b.x)), maxX = min(size.width, max(a.x, b.x))
        let minY = max(0, min(a.y, b.y)), maxY = min(size.height, max(a.y, b.y))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func normalized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / size.width, y: 1 - rect.maxY / size.height,
               width: rect.width / size.width, height: rect.height / size.height)
    }
}
