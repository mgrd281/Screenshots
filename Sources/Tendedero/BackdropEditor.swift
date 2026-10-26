import AppKit
import SwiftUI

/// Background…: the photo on a colour, with room round it, rounded corners
/// and a shadow, shown large as it will go out, in a window laid out like
/// Draw on Photo's. It is kept with the photo, and the file itself is never
/// changed.
@MainActor
final class BackdropEditor: NSObject, NSWindowDelegate {
    static let shared = BackdropEditor()

    private var window: NSWindow?
    /// The photo open, and its background as chosen so far.
    private var url: URL?
    private var model: BackdropModel?

    /// The last background chosen, the one a photo without one starts from.
    private static let lastKey = "backdropLast"

    static var last: Backdrop {
        get {
            UserDefaults.standard.data(forKey: lastKey).flatMap { try? JSONDecoder().decode(Backdrop.self, from: $0) }
                ?? Backdrop()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: lastKey) }
    }

    /// Calls back with the background chosen, or nil when it was removed;
    /// not when cancelled.
    func edit(_ url: URL, chosen: @escaping (Backdrop?) -> Void) {
        // The same photo again: its window comes forward, as it was left.
        if let window, self.url == url {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard mayLetGo() else { return }
        window?.close()
        guard let pixels = NSImage(contentsOf: url)?.size, pixels.width > 0, pixels.height > 0 else {
            Notice.show(L("Could not open the screenshot."))
            return
        }
        let before = Drawings.saved(url).backdrop
        let model = BackdropModel(backdrop: before ?? Self.last, had: before != nil)
        model.load(url)
        let title = url.deletingPathExtension().lastPathComponent
        let view = BackdropEditorView(model: model) { [weak self] ending in
            self?.window?.close()
            switch ending {
            case .cancel:
                break
            case .done:
                Self.last = model.backdrop
                chosen(model.backdrop)
            case .remove:
                chosen(nil)
            }
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = HidePartLayout.minimum
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
        window.setContentSize(HidePartLayout.windowSize(for: pixels, pages: 1, in: room))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        self.url = url
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether the window open may give way, to its close button or another
    /// photo: at once with nothing changed, else once the owner chooses to
    /// discard the changes.
    private func mayLetGo() -> Bool {
        guard let window, model?.hasChanges == true else { return true }
        return EditorChanges.mayDiscard(in: window, keptBy: L("Done"))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        return mayLetGo()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        url = nil
        model = nil
    }
}

/// The background being chosen, and the picture it is shown round: the
/// photo as it goes out, covered, drawn on, cut and stamped, made small
/// enough to draw again at every change.
@MainActor
final class BackdropModel: ObservableObject {
    @Published var backdrop: Backdrop {
        didSet { if backdrop != oldValue { redraw() } }
    }
    @Published private(set) var preview: NSImage?
    /// Whether the photo had a background before, so it can be removed.
    let had: Bool
    /// The background the window opened with.
    private let opened: Backdrop

    private var base: CGImage?
    private var generation = 0

    /// The longest side the preview is drawn at.
    private nonisolated static let previewSide = 1400

    init(backdrop: Backdrop, had: Bool) {
        self.backdrop = backdrop
        self.had = had
        opened = backdrop
    }

    /// Whether the background was changed since the window opened: what
    /// closing it without Done would lose.
    var hasChanges: Bool { backdrop != opened }

    /// Makes the picture shown inside, off the main thread.
    func load(_ url: URL) {
        let chosen = PrivateDetails.details
        let hand = PrivateDetails.hand(url)
        // The owner's own details and rules are covered whatever is chosen.
        let covers = !chosen.isEmpty || PrivateDetails.alwaysHides || !hand.isEmpty
        var drawing = Drawings.saved(url)
        drawing.backdrop = nil
        let stamp = TimeStamp.mark(for: url)
        let side = Self.previewSide
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Cover.upright(source) else { return }
            var picture = image
            if covers, let made = Finder.covered(image, chosen, hand: hand) {
                picture = made.image
            }
            if !drawing.isEmpty, let drawn = Drawing.render(picture, drawing) { picture = drawn }
            if let stamp, let stamped = TimeStamp.render(picture, stamp) { picture = stamped }
            let small = BackdropModel.shrunk(picture, side: side) ?? picture
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.base = small
                    self?.redraw()
                }
            }
        }
    }

    /// Draws the preview again, the newest change winning.
    private func redraw() {
        guard let base else { return }
        generation += 1
        let mine = generation
        let backdrop = backdrop
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let made = Backdrop.render(base, backdrop) else { return }
            let image = NSImage(cgImage: made.image, size: CGSize(width: made.image.width, height: made.image.height))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, mine == self.generation else { return }
                    self.preview = image
                }
            }
        }
    }

    private nonisolated static func shrunk(_ image: CGImage, side: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > side else { return image }
        let scale = CGFloat(side) / CGFloat(longest)
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

extension Backdrop.Fill {
    var title: String {
        switch self {
        case .sunset: return L("Sunset")
        case .emerald: return L("Emerald")
        case .orange: return L("Orange")
        case .ocean: return L("Ocean")
        case .lilac: return L("Lilac")
        case .graphite: return L("Graphite")
        case .mist: return L("Mist")
        case .white: return L("White")
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Backdrop.Ratio {
    var title: String {
        switch self {
        case .fit: return L("Fit to Photo")
        case .square: return L("Square")
        case .wide: return L("Wide (16:9)")
        case .portrait: return L("Portrait (4:5)")
        case .story: return L("Story (9:16)")
        }
    }
}

private struct BackdropEditorView: View {
    enum Ending {
        case cancel, done, remove
    }

    @ObservedObject var model: BackdropModel
    let finish: (Ending) -> Void

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            inspector
        }
        .frame(minWidth: HidePartLayout.minimum.width, minHeight: HidePartLayout.minimum.height)
    }

    private var canvas: some View {
        ZStack {
            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(HidePartLayout.margin)
                    .accessibilityLabel(L("Preview"))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                colours
                shape
                Section {
                    Text(L("Set on what is sent, round what is covered and drawn. The photo itself stays as it is."))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: HidePartLayout.panelWidth)
    }

    private var colours: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 12), count: 4), spacing: 12) {
                ForEach(Backdrop.Fill.allCases, id: \.self) { fill in
                    Swatch(fill: fill, chosen: model.backdrop.fill == fill) { model.backdrop.fill = fill }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(L("Background"))
        }
    }

    private var shape: some View {
        Section {
            LabeledContent(L("Padding")) {
                Slider(value: $model.backdrop.padding, in: Backdrop.paddings)
                    .accessibilityLabel(L("Padding"))
            }
            LabeledContent(L("Corners")) {
                Slider(value: $model.backdrop.corners, in: 0...1)
                    .accessibilityLabel(L("Corners"))
            }
            Toggle(L("Shadow"), isOn: $model.backdrop.shadow)
            Picker(L("Size"), selection: $model.backdrop.ratio) {
                ForEach(Backdrop.Ratio.allCases, id: \.self) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
        }
    }

    /// Remove on the leading edge, only for a photo that has one; Cancel and
    /// Done on the trailing.
    private var footer: some View {
        HStack(spacing: 10) {
            if model.had {
                Button(L("Remove Background")) { finish(.remove) }
            }
            Spacer()
            Button(L("Cancel")) { finish(.cancel) }
                .keyboardShortcut(.cancelAction)
            Button(L("Done")) { finish(.done) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// One colour to choose: a circle of it, ringed in the accent when chosen.
private struct Swatch: View {
    let fill: Backdrop.Fill
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(fill.gradient)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .frame(width: 26, height: 26)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: chosen ? 2 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(fill.title)
        .accessibilityLabel(fill.title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
