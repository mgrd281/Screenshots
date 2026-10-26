import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Convert to SVG: a photo drawn again as shapes, in a window laid out like
/// Hide Part's: the photo and its SVG one over the other under a divider on
/// the canvas, and the choices on the trailing edge. The SVG is made from the
/// photo as it leaves the line, with its private details covered, so nothing
/// private is in it. The file itself is never changed.
@MainActor
final class VectorEditor: NSObject, NSWindowDelegate {
    static let shared = VectorEditor()

    private var window: NSWindow?
    private var model: VectorEditorModel?

    func convert(_ url: URL) {
        window?.close()
        let name = url.deletingPathExtension().lastPathComponent
        // What leaves the line, with the private details covered.
        let model = VectorEditorModel(source: PrivateDetails.shareable(url), name: name, covered: PrivateDetails.alters(url),
                                folder: url.deletingLastPathComponent())
        let view = VectorEditorView(model: model) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(format: L("%@ as SVG"), name)
        let hosting = NSHostingView(rootView: view)
        // The window sets the size; the view fills it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = HidePartLayout.minimum
        // As large as the picture needs and at most 80% of the screen, as Hide Part opens.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
        let size = VectorRaster.pixelSize(of: model.source).map { CGSize(width: $0.width, height: $0.height) }
            ?? HidePartLayout.minimum
        window.setContentSize(HidePartLayout.windowSize(for: size, pages: 2, in: room))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        model.load()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        model?.stop()
        model = nil
        window = nil
    }

    /// The save panel over the window, in the photo's folder, for the SVG.
    fileprivate func save(_ svg: String, named name: String, in folder: URL) {
        let panel = NSSavePanel()
        panel.directoryURL = folder
        panel.nameFieldStringValue = name + ".svg"
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            MainActor.assumeIsolated {
                guard response == .OK, let target = panel.url else { return }
                do {
                    // The panel has already asked whether to replace it.
                    try svg.write(to: target, atomically: true, encoding: .utf8)
                    Notice.savedCopy(target)
                } catch {
                    log.error("Could not save the SVG: \(error.localizedDescription, privacy: .private)")
                    Notice.show(L("Could not save the SVG."))
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

// MARK: The model

extension VectorPreset {
    var title: String {
        switch self {
        case .screenshot: L("Screenshot")
        case .logo: L("Logo or icon")
        case .illustration: L("Illustration")
        case .photo: L("Photo")
        case .blackAndWhite: L("Black and white")
        }
    }

    /// What it is for, in a line.
    var summary: String {
        switch self {
        case .screenshot: L("Interfaces and text: flat colors with crisp edges.")
        case .logo: L("A few colors and smooth shapes.")
        case .illustration: L("Artwork with many flat colors.")
        case .photo: L("Many soft colors as shapes. The file gets large.")
        case .blackAndWhite: L("Only the dark lines, with nothing behind them.")
        }
    }
}

/// Lets a trace be stopped from the main thread while it runs on another.
private final class TraceToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

@MainActor
final class VectorEditorModel: ObservableObject {
    let source: URL
    let name: String
    /// Whether the photo is covered, drawn on or stamped, so the SVG is of the copy.
    let covered: Bool
    let folder: URL

    @Published private(set) var settings = VectorPreset.screenshot.settings
    /// The ready-made choice the settings are, or nil when they are the owner's own.
    @Published private(set) var preset: VectorPreset? = .screenshot
    @Published private(set) var original: CGImage?
    @Published private(set) var result: VectorImage?
    /// Which result is showing, so the canvas makes paths only for a new one.
    @Published private(set) var resultID = 0
    @Published private(set) var svg = ""
    @Published private(set) var loading = true
    @Published private(set) var working = false
    @Published private(set) var failed = false
    /// The photo was too big to trace whole.
    @Published private(set) var shrunk = false

    @Published var show = VectorShow.compare
    @Published var divider: CGFloat = 0.5
    @Published var scalePercent = 100
    weak var canvas: VectorCanvasView?

    private var pixels: VectorPixels?
    private var shownSize: (width: Int, height: Int)?
    private var token: TraceToken?
    private var pending: DispatchWorkItem?

    init(source: URL, name: String, covered: Bool, folder: URL) {
        self.source = source
        self.name = name
        self.covered = covered
        self.folder = folder
    }

    /// Reads the photo, then traces it.
    func load() {
        let url = source
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = VectorRaster.image(of: url)
            let pixels = image.flatMap { VectorRaster.pixels(of: $0) }
            let size = VectorRaster.pixelSize(of: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = false
                    guard let image, let pixels else {
                        self.failed = true
                        return
                    }
                    self.original = image
                    self.pixels = pixels
                    self.shownSize = size
                    self.shrunk = size.map { $0.width != pixels.width || $0.height != pixels.height } ?? false
                    self.retrace()
                }
            }
        }
    }

    /// Stops what is being traced, as the window closes.
    func stop() {
        pending?.cancel()
        token?.stop()
    }

    func choose(_ preset: VectorPreset) {
        self.preset = preset
        settings = preset.settings
        retraceSoon()
    }

    /// One setting changed; it is a ready-made choice again if it makes the same settings as one.
    func change(_ edit: (inout VectorSettings) -> Void) {
        var changed = settings
        edit(&changed)
        guard changed != settings else { return }
        settings = changed
        preset = VectorPreset.allCases.first { $0.settings == changed }
        retraceSoon()
    }

    /// After a pause, so a slider being dragged does not trace at every step.
    private func retraceSoon() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.retrace() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func retrace() {
        guard let pixels else { return }
        token?.stop()
        let token = TraceToken()
        self.token = token
        working = true
        failed = false
        let settings = self.settings
        let size = shownSize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = VectorTracer.trace(pixels, settings: settings, isCancelled: { token.isStopped })
            let text = image?.svg(size: size)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A newer trace has taken over.
                    guard let self, !token.isStopped else { return }
                    self.working = false
                    guard let image, let text else {
                        // Nothing of the old settings is kept to be copied or saved.
                        self.failed = true
                        self.result = nil
                        self.svg = ""
                        self.resultID += 1
                        return
                    }
                    self.result = image
                    self.svg = text
                    self.resultID += 1
                }
            }
        }
    }

    // MARK: What it came to

    var colorCount: Int { result?.layers.count ?? 0 }
    var shapeCount: Int { result?.contourCount ?? 0 }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(svg.utf8.count), countStyle: .file)
    }

    var canUse: Bool { result != nil && !svg.isEmpty }

    func copy() {
        guard canUse else { return }
        let board = NSPasteboard.general
        board.clearContents()
        // Design apps take the SVG as a picture, text editors as text.
        board.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType("public.svg-image"))
        board.setString(svg, forType: .string)
        Notice.show(L("Copied the SVG."), done: true)
    }

    func save() {
        guard canUse else { return }
        VectorEditor.shared.save(svg, named: name, in: folder)
    }
}

// MARK: The window

private struct VectorEditorView: View {
    @ObservedObject var model: VectorEditorModel
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            inspector
        }
        .frame(minWidth: HidePartLayout.minimum.width, minHeight: HidePartLayout.minimum.height)
    }

    // MARK: The canvas

    private var canvas: some View {
        VStack(spacing: 0) {
            ZStack {
                VectorCanvas(model: model)
                if model.loading {
                    ProgressView()
                        .controlSize(.small)
                }
                if model.failed && model.original == nil {
                    Text(L("Could not trace this picture."))
                        .foregroundStyle(.secondary)
                }
            }
            controls
                .frame(height: HidePartLayout.pagesHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// What to look at, and how closely, under the picture.
    private var controls: some View {
        HStack(spacing: 10) {
            Picker(L("Show"), selection: $model.show) {
                Text(L("Compare")).tag(VectorShow.compare)
                Text(L("SVG")).tag(VectorShow.vector)
                Text(L("Original")).tag(VectorShow.original)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .controlSize(.small)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button {
                    model.canvas?.zoomBy(0.8)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help(L("Zoom Out"))
                .accessibilityLabel(L("Zoom Out"))
                Text(verbatim: "\(model.scalePercent)%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)
                Button {
                    model.canvas?.zoomBy(1.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help(L("Zoom In"))
                .accessibilityLabel(L("Zoom In"))
                Button {
                    model.canvas?.fit()
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .help(L("Fit to Window"))
                .accessibilityLabel(L("Fit to Window"))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
    }

    // MARK: The inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                kind
                detail
                outcome
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: HidePartLayout.panelWidth)
    }

    /// The kind of picture, which sets everything else to what suits it.
    private var kind: some View {
        Section {
            Picker(L("Kind of picture"), selection: Binding<VectorPreset?>(
                get: { model.preset },
                set: { if let chosen = $0 { model.choose(chosen) } }
            )) {
                ForEach(VectorPreset.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
                if model.preset == nil {
                    Text(L("Custom")).tag(VectorPreset?.none)
                }
            }
        } footer: {
            Text(model.preset?.summary ?? L("Your own settings."))
                .foregroundStyle(.secondary)
        }
    }

    private var detail: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.settings.colors) },
                                          set: { value in model.change { $0.colors = Int(value.rounded()) } }),
                           in: 2...64, step: 1)
                    Text(verbatim: "\(model.settings.colors)")
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                }
                .frame(width: 190)
            } label: {
                Text(L("Colors"))
            }
            LabeledContent {
                Slider(value: Binding(get: { model.settings.smoothness },
                                      set: { value in model.change { $0.smoothness = value } }),
                       in: 0...1) {
                    Text(L("Smoothness"))
                } minimumValueLabel: {
                    Text(L("Exact"))
                } maximumValueLabel: {
                    Text(L("Smooth"))
                }
                .labelsHidden()
                .frame(width: 190)
            } label: {
                Text(L("Smoothness"))
            }
            LabeledContent {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.settings.speckle) },
                                          set: { value in model.change { $0.speckle = Int(value.rounded()) } }),
                           in: 0...20, step: 1)
                    Text(String(format: L("%d px"), model.settings.speckle))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .frame(width: 190)
            } label: {
                Text(L("Leave out specks"))
            }
            Toggle(L("Smooth gradients"), isOn: Binding(get: { model.settings.smoothsGradients },
                                                         set: { on in model.change { $0.smoothsGradients = on } }))
                .help(L("Evens out soft color changes before they are cut into bands."))
            Toggle(L("Transparent background"), isOn: Binding(get: { model.settings.transparentBackground },
                                                              set: { on in model.change { $0.transparentBackground = on } }))
                .help(L("Leaves out the color behind everything else."))
        } header: {
            Text(L("Detail"))
        } footer: {
            Text(L("A gradient becomes bands of flat color. More colors make the bands finer."))
                .foregroundStyle(.secondary)
        }
    }

    /// What the SVG came to, and a word on how it was made.
    private var outcome: some View {
        Section {
            figure(L("Colors"), "\(model.colorCount)")
            figure(L("Shapes"), "\(model.shapeCount)")
            figure(L("Size"), model.sizeText)
        } header: {
            HStack(spacing: 6) {
                Text(L("Result"))
                if model.working {
                    ProgressView().controlSize(.mini)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if model.failed && model.original != nil {
                    Text(L("Could not trace this picture."))
                }
                if model.shrunk {
                    Text(L("This picture is large, so it was traced smaller. The SVG still opens at the picture's own size."))
                }
                if model.covered {
                    Text(L("Made from the covered copy, like anything that leaves the line."))
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
        } label: {
            Text(title)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(L("Close")) { close() }
                .keyboardShortcut(.cancelAction)
            Button(L("Copy SVG")) { model.copy() }
                .disabled(!model.canUse)
            Button(L("Save SVG…")) { model.save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canUse)
        }
        .padding(16)
    }
}
