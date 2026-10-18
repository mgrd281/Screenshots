import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A guide, once recorded: its title and its steps one under another, each
/// with its number, its sentence to read through or write again, and the
/// part of the screen it shows, covered and marked as it will leave. A step
/// can move up or down, show the whole screen, or go. From here the guide
/// hangs on the line as a PDF, ready to send, or is saved as a PDF or one
/// tall picture. It is kept as it changes, and Recent Guides in the menu bar
/// opens it again.
@MainActor
final class HowToEditor: NSObject, NSWindowDelegate {
    static let shared = HowToEditor()

    /// Hangs a file on the line, picked and ready to send.
    var onHang: (URL) -> Void = { _ in }

    private var window: NSWindow?
    private var model: HowToEditorModel?

    func open(_ guide: HowToGuide) {
        if let window, model?.guide.id == guide.id {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()
        let model = HowToEditorModel(guide: guide)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Guide")
        let hosting = NSHostingView(rootView: HowToEditorView(model: model))
        // The window sets the size; the view fills it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = CGSize(width: 560, height: 480)
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window.setContentSize(CGSize(width: 720, height: min(880, screen.height * 0.85)))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        model.prepare()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        model?.saveNow()
        model = nil
        window = nil
    }

    /// The save panel over the window, in Downloads, for a PDF or a picture.
    fileprivate func save(_ model: HowToEditorModel, as type: UTType) {
        let panel = NSSavePanel()
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = HowToRender.name(of: model.guide) + "." + (type.preferredFilenameExtension ?? "pdf")
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            MainActor.assumeIsolated {
                guard response == .OK, let target = panel.url else { return }
                model.export(type == .pdf ? .pdf : .image, to: target)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// Asks first, over the window: the steps' screenshots go with it.
    fileprivate func delete(_ model: HowToEditorModel) {
        let alert = NSAlert()
        alert.messageText = L("Delete this guide?")
        alert.informativeText = L("Its steps and their screenshots are deleted. What was already sent or saved stays.")
        alert.addButton(withTitle: L("Delete"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                model.discard()
                self?.window?.close()
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

// MARK: The model

@MainActor
final class HowToEditorModel: ObservableObject {
    enum Export {
        case pdf, image
    }

    @Published var guide: HowToGuide {
        didSet { if guide != oldValue { scheduleSave() } }
    }
    /// Each step as it will leave, small enough to show.
    @Published private(set) var previews: [UUID: NSImage] = [:]
    /// The steps whose screenshots are covered.
    @Published private(set) var covered: Set<UUID> = []
    /// The steps whose screenshots could not be read, to be let go.
    @Published private(set) var failed: Set<UUID> = []
    /// Something is being made from it.
    @Published private(set) var busy = false

    let folder: URL
    private var saving: DispatchWorkItem?
    private var discarded = false

    init(guide: HowToGuide) {
        self.guide = guide
        folder = HowToStore.folder(of: guide.id)
    }

    var ready: Bool { !guide.steps.isEmpty && guide.steps.allSatisfy { covered.contains($0.id) } }

    /// Covers each step's screenshot, once, and draws its preview, off the
    /// main thread.
    func prepare() {
        let steps = guide.steps, folder = folder
        let chosen = PrivateDetails.details
        DispatchQueue.global(qos: .userInitiated).async {
            for step in steps {
                let done = HowToRender.prepare(step, in: folder, chosen: chosen)
                let preview = done ? HowToRender.picture(step, in: folder, maxPixels: 1400) : nil
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in self?.prepared(step.id, done: done, preview) }
                }
            }
        }
    }

    private func prepared(_ id: UUID, done: Bool, _ preview: CGImage?) {
        if done {
            covered.insert(id)
        } else {
            failed.insert(id)
            log.error("Could not cover a guide's step")
        }
        if let preview { previews[id] = NSImage(cgImage: preview, size: .zero) }
    }

    /// Draws a step's preview again, as it now shows.
    private func redraw(_ id: UUID) {
        guard let step = guide.steps.first(where: { $0.id == id }), covered.contains(id) else { return }
        let folder = folder
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = HowToRender.picture(step, in: folder, maxPixels: 1400)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    if let preview { self?.previews[id] = NSImage(cgImage: preview, size: .zero) }
                }
            }
        }
    }

    // MARK: Changes

    func text(of id: UUID) -> Binding<String> {
        Binding(get: { [weak self] in self?.guide.steps.first { $0.id == id }?.text ?? "" },
                set: { [weak self] text in
                    guard let self, let index = self.guide.steps.firstIndex(where: { $0.id == id }) else { return }
                    self.guide.steps[index].text = text
                })
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = guide.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard guide.steps.indices.contains(target) else { return }
        guide.steps.swapAt(index, target)
    }

    func toggleFocus(_ id: UUID) {
        guard let index = guide.steps.firstIndex(where: { $0.id == id }) else { return }
        guide.steps[index].focused.toggle()
        redraw(id)
    }

    func delete(_ id: UUID) {
        guard let index = guide.steps.firstIndex(where: { $0.id == id }) else { return }
        let step = guide.steps.remove(at: index)
        previews[id] = nil
        failed.remove(id)
        for name in [step.file, HowToStore.coveredName(of: step)] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Keeping

    private func scheduleSave() {
        saving?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { [weak self] in self?.saveNow() } }
        saving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saving?.cancel()
        saving = nil
        guard !discarded else { return }
        do {
            try HowToStore.save(guide)
        } catch {
            log.error("Could not keep a guide: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discard() {
        discarded = true
        saving?.cancel()
        HowToStore.delete(guide.id)
    }

    // MARK: Leaving

    /// Hangs it on the line as a PDF, picked and ready to send.
    func hang() {
        make(.pdf, to: Collage.newFile(HowToRender.name(of: guide), "pdf")) { url in
            HowToEditor.shared.onHang(url)
        }
    }

    func export(_ kind: Export, to url: URL) {
        make(kind, to: url) { url in Notice.savedCopy(url) }
    }

    /// The tall picture on the pasteboard, to paste into a chat.
    func copyImage() {
        guard ready, !busy else { return }
        busy = true
        let guide = guide, folder = folder
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        DispatchQueue.global(qos: .userInitiated).async {
            let data = HowToRender.image(guide, in: folder, rightToLeft: rightToLeft).flatMap(HowToRender.png)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.busy = false
                    guard let data else {
                        Notice.show(L("Could not make the guide."))
                        return
                    }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: .png)
                    Notice.show(L("Copied. Paste it into a chat or an email."), done: true)
                }
            }
        }
    }

    private func make(_ kind: Export, to url: URL, then done: @escaping (URL) -> Void) {
        guard ready, !busy else { return }
        busy = true
        saveNow()
        let guide = guide, folder = folder
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        DispatchQueue.global(qos: .userInitiated).async {
            let made: Bool
            switch kind {
            case .pdf:
                made = HowToRender.pdf(guide, in: folder, to: url, rightToLeft: rightToLeft)
            case .image:
                made = HowToRender.image(guide, in: folder, rightToLeft: rightToLeft)
                    .map { Capture.write($0, to: url) } ?? false
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.busy = false
                    guard made else {
                        log.error("Could not make a guide")
                        try? FileManager.default.removeItem(at: url)
                        Notice.show(L("Could not make the guide."))
                        return
                    }
                    done(url)
                }
            }
        }
    }
}

// MARK: The window

struct HowToEditorView: View {
    @ObservedObject var model: HowToEditorModel

    private var count: String {
        model.guide.steps.count == 1 ? L("1 step") : String(format: L("%d steps"), model.guide.steps.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(L("Name this guide"), text: $model.guide.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                        Text(count)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.guide.steps.enumerated()), id: \.element.id) { index, step in
                        HowToStepCard(model: model, step: step, number: index + 1, last: index == model.guide.steps.count - 1)
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                HowToEditor.shared.delete(model)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(L("Delete Guide…"))
            .accessibilityLabel(L("Delete Guide…"))
            if !model.ready && !model.guide.steps.isEmpty && model.failed.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text(L("Covering private details…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if model.busy {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Menu {
                Button(L("Save as PDF…")) { HowToEditor.shared.save(model, as: .pdf) }
                Button(L("Save as Image…")) { HowToEditor.shared.save(model, as: .png) }
                Divider()
                Button(L("Copy as Image")) { model.copyImage() }
            } label: {
                Text(L("Save"))
            }
            .fixedSize()
            .disabled(!model.ready || model.busy)
            Button {
                model.hang()
            } label: {
                Label(L("Hang on the Line"), systemImage: "arrow.up.to.line")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.ready || model.busy)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// One step: its number, its sentence and what it shows, with its tools
/// under it.
private struct HowToStepCard: View {
    @ObservedObject var model: HowToEditorModel
    let step: HowToStep
    let number: Int
    let last: Bool

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .frame(width: 24, height: 24)
                .background(Color.primary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                TextField(L("What to do"), text: model.text(of: step.id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel(String(format: L("Step %d"), number))
                picture
                tools
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var picture: some View {
        if let image = model.previews[step.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(maxWidth: .infinity, maxHeight: 340, alignment: .leading)
                .accessibilityLabel(String(format: L("Step %d"), number))
        } else if model.failed.contains(step.id) {
            shape
                .fill(Color.primary.opacity(0.06))
                .frame(height: 120)
                .overlay(
                    Label(L("This step's screenshot could not be read. Delete the step to go on."),
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                )
        } else {
            shape
                .fill(Color.primary.opacity(0.06))
                .frame(height: 180)
                .overlay(ProgressView().controlSize(.small))
                .accessibilityHidden(true)
        }
    }

    private var tools: some View {
        HStack(spacing: 4) {
            if let app = step.app {
                Text(app)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            tool(step.focused ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                 step.focused ? L("Show Whole Screen") : L("Show Around the Click")) {
                model.toggleFocus(step.id)
            }
            .disabled(!model.covered.contains(step.id))
            tool("arrow.up", L("Move Up")) { model.move(step.id, by: -1) }
                .disabled(number == 1)
            tool("arrow.down", L("Move Down")) { model.move(step.id, by: 1) }
                .disabled(last)
            tool("trash", L("Delete Step")) { model.delete(step.id) }
        }
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}
