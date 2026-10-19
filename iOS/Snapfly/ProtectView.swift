import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A picture being protected, filling the screen: shown at once, its private
/// places marked as they are found, then covered and checked. Two fingers
/// or a double tap zoom. Over the picture float a small capsule with how it
/// stands, the tools (Select to tap a place or a word and move, resize or
/// turn it; the marker, a box and the lasso to hide more by hand; the
/// eraser to take covers away; Undo and Redo), and Copy, Share and Save.
/// Full Screen leaves the picture alone. Holding the eye shows the picture
/// as it was. Copy, Share and Save wait until the copy is made and checked,
/// and ask first while places are still to check. The picture itself stays
/// as it was.
struct ProtectView: View {
    @StateObject private var session: ProtectSession
    @ObservedObject private var sync = SyncCenter.shared
    @State private var tool = EditTool.select
    @State private var selected: Int?
    @State private var markerWidth = HandShape.widths[1]
    @State private var eraserReach: CGFloat = 0.03
    @State private var showsOriginal = false
    @State private var reviewing = false
    @State private var showsOptions = false
    /// Only the picture, until a tap brings the controls back.
    @State private var focus = false
    /// The mark held down, whose menu shows.
    @State private var menuFor: ProtectionPlan.Mark?
    /// A way out waiting while places are still to check.
    @State private var waiting: Leaving?
    /// A way out tapped before the copy was ready, which goes once it is.
    @State private var pending: Leaving?
    @State private var sharing: SharedFile?
    @State private var exporting: PNGFile?
    /// The name the file is offered under, set as it is saved.
    @State private var exportName = ""
    @State private var note: EditorNote?
    /// How to use the tool just chosen, for a moment.
    @State private var hint: String?
    /// A place to show close up, from the list of places.
    @State private var reveal: Reveal?
    /// Sent to the Mac already, so it goes once.
    @State private var sent = false
    /// The floating controls' heights, so the picture is fitted between them.
    @State private var statusHeight: CGFloat = 0
    @State private var docksHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: ProtectSession.Source) {
        _session = StateObject(wrappedValue: ProtectSession(source: source))
    }

    var body: some View {
        lifecycle(dialogs(sheets(screen)))
    }

    /// The picture, the floating controls over it, and the bars.
    private var screen: some View {
        GeometryReader { geometry in
            ZStack {
                picture(chrome: chrome(geometry.safeAreaInsets))
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    if !focus { top.transition(.opacity) }
                    Spacer(minLength: 0)
                    bottom
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background((focus ? Color.black : Color(.secondarySystemBackground)).ignoresSafeArea())
        .animation(motion, value: focus)
        .animation(motion, value: session.stage)
        .animation(motion, value: selected)
        .animation(motion, value: note)
        .animation(motion, value: hint)
        .navigationTitle(L("Protect Picture"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { more }
        }
        .toolbar(focus ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(focus)
        .persistentSystemOverlays(focus ? .hidden : .automatic)
    }

    private func sheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $reviewing) { ReviewSheet(session: session, show: show) }
            .sheet(isPresented: $showsOptions) {
                ToolOptions(tool: tool, markerWidth: $markerWidth, eraserReach: $eraserReach, session: session)
                    .presentationDetents([.height(300), .medium])
            }
            .sheet(item: $sharing) { file in
                ShareSheet(url: file.url) { done in
                    try? FileManager.default.removeItem(at: file.url)
                    if done { session.left() }
                }
                .ignoresSafeArea()
            }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting, contentType: .png, defaultFilename: exportName) { result in
                switch result {
                case .success:
                    done(L("Saved to Files"))
                case .failure(let error):
                    // Cancelled, nothing went wrong.
                    if (error as? CocoaError)?.code == .userCancelled { return }
                    failed(L("The picture could not be saved."), retry: .files)
                }
            }
    }

    private func dialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(String(format: L("%d places still to check"), session.plan.tally.toCheck),
                                isPresented: Binding(get: { waiting != nil }, set: { if !$0 { waiting = nil } }),
                                titleVisibility: .visible, presenting: waiting) { way in
                Button(L("Check Now")) { reviewing = true }
                Button(L("Continue Anyway")) { go(way) }
                Button(L("Cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("Snapfly is not sure about these. Check them before the picture leaves, or let it go as it is."))
            }
            .confirmationDialog(menuFor.map(title(of:)) ?? "", isPresented: Binding(get: { menuFor != nil },
                                                                               set: { if !$0 { menuFor = nil } }),
                                titleVisibility: .visible, presenting: menuFor) { mark in
                Button(mark.covered ? L("Uncover") : L("Cover")) { session.toggle(mark.id) }
                if mark.origin == .hand {
                    Button(L("Delete"), role: .destructive) {
                        session.remove([mark.id])
                        selected = nil
                    }
                }
                Button(L("Cancel"), role: .cancel) {}
            }
    }

    private func lifecycle(_ content: some View) -> some View {
        content
            .phoneGuide(on: .shot)
            .onAppear {
                // Preparing other photos waits, so this one opens fast.
                PhotoIndexer.shared.hold()
                session.start()
                PhoneGuide.shared.screen = .shot
                PhoneGuide.shared.happened(.openedShot)
            }
            .onDisappear {
                PhotoIndexer.shared.release()
                PhoneGuide.shared.screen = .library
            }
            .onChange(of: tool) { _, tool in
                selected = nil
                UISelectionFeedbackGenerator().selectionChanged()
                hint = hintText(for: tool)
            }
            .onChange(of: session.isReady) { _, ready in
                // A way tapped while the copy was made goes now.
                guard ready, let way = pending else { return }
                pending = nil
                leave(way)
            }
            .onChange(of: session.stage) { _, stage in
                if case .failed = stage { pending = nil }
            }
            .task(id: hint) {
                guard hint != nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                hint = nil
            }
            .task(id: note) {
                guard let note else { return }
                try? await Task.sleep(for: .seconds(note.failed ? 5 : 2))
                if self.note == note { self.note = nil }
            }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    /// What the floating controls cover on each side, so the picture is
    /// fitted between them; only the safe areas in Full Screen.
    private func chrome(_ safe: EdgeInsets) -> UIEdgeInsets {
        let side: CGFloat = 8
        if focus {
            return UIEdgeInsets(top: safe.top + side, left: safe.leading + side, bottom: safe.bottom + side,
                                right: safe.trailing + side)
        }
        return UIEdgeInsets(top: safe.top + statusHeight + side, left: safe.leading + side,
                            bottom: safe.bottom + docksHeight + side, right: safe.trailing + side)
    }

    // MARK: The picture

    @ViewBuilder private func picture(chrome: UIEdgeInsets) -> some View {
        if let shown = showsOriginal ? session.original : session.copy ?? session.original ?? session.preview {
            MarkCanvas(image: shown, marks: showsOriginal ? [] : session.plan.marks,
                       checking: Set(session.plan.marks.filter(session.plan.needsCheck).map(\.id)),
                       isCopy: !showsOriginal && session.copy != nil, tool: tool, selected: selected,
                       markerWidth: markerWidth, eraserReach: eraserReach, chrome: chrome,
                       animated: !reduceMotion, reveal: reveal, actions: actions)
                .accessibilityAction(named: L("Details")) { reviewing = true }
        } else if case .failed = session.stage {
            ContentUnavailableView(L("The picture could not be read."), systemImage: "exclamationmark.triangle")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actions: CanvasActions {
        CanvasActions(
            tap: tap,
            longPress: { point in
                guard session.original != nil, let mark = session.plan.mark(at: point) else { return }
                selected = mark.id
                menuFor = mark
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            draw: { shape in
                guard session.original != nil, session.draw(shape) != nil else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            erase: { points in
                let count = session.plan.tally
                session.erase(along: points, reach: eraserReach)
                if session.plan.tally != count { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            },
            move: { id, offset in session.move([id], by: offset) },
            resize: { id, rect in session.resize(id, to: rect) },
            turn: { id, angle in session.turn(id, by: angle) },
            outside: {
                // Beside the picture: back from Full Screen, or let go, or
                // with Select in hand, the picture alone.
                if focus {
                    focus = false
                } else if selected != nil {
                    selected = nil
                } else if tool == .select, session.original != nil {
                    focus = true
                }
            })
    }

    /// Selecting: a tap on a place selects it, on a word hides it, and
    /// anywhere else lets go of the place selected, or with none, leaves
    /// the picture alone in Full Screen.
    private func tap(_ point: CGPoint) {
        guard session.original != nil, !showsOriginal else { return }
        // In Full Screen, a tap only brings the controls back.
        if focus {
            focus = false
        } else if let mark = session.plan.mark(at: point) {
            selected = selected == mark.id ? nil : mark.id
            UISelectionFeedbackGenerator().selectionChanged()
        } else if let id = session.hideWord(at: point) {
            selected = id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if selected != nil {
            selected = nil
        } else {
            focus = true
        }
    }

    private var selectedMark: ProtectionPlan.Mark? {
        guard let selected else { return nil }
        return session.plan.marks.first { $0.id == selected }
    }

    /// From the list of places: the place selected, close up.
    private func show(_ mark: ProtectionPlan.Mark) {
        reviewing = false
        focus = false
        tool = .select
        selected = mark.id
        reveal = Reveal(rect: mark.rect, count: (reveal?.count ?? 0) + 1)
    }

    // MARK: Over the picture

    /// Under the title: how the picture stands, and how to use the tool
    /// just chosen.
    private var top: some View {
        VStack(spacing: 6) {
            PrivacyStatus(stage: session.stage, tally: session.plan.tally,
                          nothingFound: session.found && session.plan.marks.isEmpty,
                          open: { reviewing = true }, dontWait: session.dontWait, retry: session.retry)
                .padding(.top, 6)
                .measuredHeight($statusHeight)
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .editorGlass(in: Capsule())
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
    }

    /// Over the bottom: what was done or went wrong, the place selected,
    /// then the tools and the ways out; in Full Screen, only the way back.
    private var bottom: some View {
        VStack(spacing: 10) {
            if let note {
                EditorNoteView(note: note) { way in
                    self.note = nil
                    leave(way)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if focus {
                HStack {
                    Spacer()
                    Button {
                        focus = false
                    } label: {
                        ToolButton(symbol: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Exit Full Screen"))
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            } else {
                if let mark = selectedMark { selection(mark) }
                docks
                    .measuredHeight($docksHeight)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 4)
    }

    private var docks: some View {
        VStack(spacing: 8) {
            EditingDock(tool: $tool, markerWidth: $markerWidth, eraserReach: $eraserReach,
                        canUndo: session.plan.canUndo, canRedo: session.plan.canRedo,
                        undo: {
                            session.undo()
                            selected = nil
                        },
                        redo: {
                            session.redo()
                            selected = nil
                        },
                        options: { showsOptions = true })
                .disabled(session.original == nil)
            HStack(spacing: 8) {
                eye
                ExportDock(pending: pending, canSend: sync.canSend, sent: sent, leave: leave)
                    .phoneGuideTarget(.actions)
                Button {
                    tool = .select
                    focus = true
                } label: {
                    ToolButton(symbol: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Full Screen"))
            }
        }
    }

    /// The eye, held down to see the picture as it was.
    private var eye: some View {
        ToolButton(symbol: showsOriginal ? "eye.fill" : "eye", active: showsOriginal)
            .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                showsOriginal = pressing
            })
            .opacity(session.original == nil ? 0.4 : 1)
            .allowsHitTesting(session.original != nil)
            .accessibilityLabel(L("Show the screenshot as it was"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showsOriginal.toggle() }
    }

    /// Details, Full Screen, and taking back what was changed, each as one
    /// change to undo.
    private var more: some View {
        Menu {
            Button {
                reviewing = true
            } label: {
                Label(L("Details"), systemImage: "list.bullet")
            }
            .disabled(session.plan.marks.isEmpty)
            Button {
                tool = .select
                focus = true
            } label: {
                Label(L("Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Divider()
            Button {
                session.clearHand()
                selected = nil
            } label: {
                Label(L("Clear Hidden by Hand"), systemImage: "eraser.line.dashed")
            }
            .disabled(!session.plan.hasHand)
            Button {
                session.resetToFound()
                selected = nil
            } label: {
                Label(L("Reset to Suggestions"), systemImage: "arrow.counterclockwise")
            }
            .disabled(!session.plan.isChanged)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L("More"))
    }

    /// How to use a tool, while the picture is ready.
    private func hintText(for tool: EditTool) -> String? {
        switch tool {
        case .select: nil
        case .marker: L("Draw over what to hide. Two fingers move the picture.")
        case .box: L("Drag a box over what to hide. Two fingers move the picture.")
        case .lasso: L("Draw round what to hide. Two fingers move the picture.")
        case .eraser: L("Rub over a cover to take it away. The picture shows there again.")
        }
    }

    /// What can be done with the mark selected, floating over the tools.
    private func selection(_ mark: ProtectionPlan.Mark) -> some View {
        HStack(spacing: 14) {
            Button(mark.covered ? L("Uncover") : L("Cover")) { session.toggle(mark.id) }
            if case .stroke(_, let width) = mark.shape {
                Menu {
                    ForEach(HandShape.widths.indices, id: \.self) { i in
                        Button {
                            session.widen([mark.id], to: HandShape.widths[i])
                        } label: {
                            if HandShape.widths[i] == width {
                                Label(widthNames[i], systemImage: "checkmark")
                            } else {
                                Text(widthNames[i])
                            }
                        }
                    }
                } label: {
                    Image(systemName: "lineweight")
                }
                .accessibilityLabel(L("Width"))
            }
            if mark.origin == .hand {
                Button(role: .destructive) {
                    session.remove([mark.id])
                    selected = nil
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L("Delete"))
            }
            Button(L("Done")) { selected = nil }
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .editorGlass(in: Capsule())
        .transition(.opacity)
    }

    // MARK: Ways out

    /// A way out: tapped before the copy is ready, it waits for it (tapped
    /// again, it no longer does); while places are still to check, it asks
    /// first.
    private func leave(_ way: Leaving) {
        guard session.isReady else {
            if case .failed = session.stage { return }
            pending = pending == way ? nil : way
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        if session.plan.tally.toCheck > 0 { waiting = way } else { go(way) }
    }

    private func go(_ way: Leaving) {
        switch way {
        case .copy: copy()
        case .share: share()
        case .photos: save()
        case .files: saveFile()
        case .mac: send()
        }
    }

    private func done(_ text: String) {
        note = EditorNote(text: text)
        session.left()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func failed(_ text: String, retry: Leaving? = nil) {
        note = EditorNote(text: text, failed: true, retry: retry)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func copy() {
        guard session.isReady, let png = session.png else { return }
        Covering.copy(png)
        done(L("Copied"))
    }

    /// The copy alone, as a PNG file of its own, with nothing of the
    /// original's notes in it.
    private func share() {
        guard session.isReady, let png = session.png else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(baseName + ".png")
        do {
            try png.write(to: url, options: [.atomic, .completeFileProtection])
            sharing = SharedFile(url: url)
        } catch {
            failed(L("The copy could not be made."), retry: .share)
        }
    }

    private func save() {
        guard session.isReady, let png = session.png else { return }
        Task {
            do {
                try await Covering.save(png)
                done(L("Saved to Photos"))
            } catch {
                failed(L("The picture could not be saved."), retry: .photos)
            }
        }
    }

    private func saveFile() {
        guard session.isReady, let png = session.png else { return }
        exportName = baseName
        exporting = PNGFile(data: png)
    }

    private func send() {
        guard session.isReady, let png = session.png else { return }
        sent = true
        let report = session.plan.report
        let redaction = SyncRedaction(kinds: report.keys, areas: report.total, look: CoverStyle.current.rawValue)
        let name = baseName + ".png"
        Task {
            if await sync.send(covered: png, name: name, redaction: redaction) {
                done(L("On its way to your Mac"))
            } else {
                sent = false
                failed(L("Could not send it. Try again."), retry: .mac)
            }
        }
    }

    /// Named by when it was taken, as the Mac names screenshots.
    private var baseName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var taken = Date()
        if case .asset(let id) = session.source, let date = Library.asset(id)?.creationDate { taken = date }
        return "Snapfly \(formatter.string(from: taken))"
    }

    private func title(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.title }
        return mark.origin == .hand ? L("Hidden by hand") : L("Your own rules")
    }
}

/// A file to share, while the share sheet shows.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system's share sheet for one file; `done` says whether it went.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let done: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in done(completed) }
        return sheet
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The tool in hand's options, in a small sheet: the marker's width, the
/// eraser's size, and taking back what was changed.
private struct ToolOptions: View {
    let tool: EditTool
    @Binding var markerWidth: CGFloat
    @Binding var eraserReach: CGFloat
    @ObservedObject var session: ProtectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if tool == .marker {
                    Picker(L("Width"), selection: $markerWidth) {
                        ForEach(HandShape.widths.indices, id: \.self) { i in
                            Text(widthNames[i]).tag(HandShape.widths[i])
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if tool == .eraser {
                    Picker(L("Size"), selection: $eraserReach) {
                        ForEach(eraserSizes.indices, id: \.self) { i in
                            Text(eraserNames[i]).tag(eraserSizes[i])
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button(L("Clear Hidden by Hand")) {
                        session.clearHand()
                        dismiss()
                    }
                    .disabled(!session.plan.hasHand)
                    Button(L("Reset to Suggestions")) {
                        session.resetToFound()
                        dismiss()
                    }
                    .disabled(!session.plan.isChanged)
                } footer: {
                    Text(L("Each can be undone."))
                }
            }
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
