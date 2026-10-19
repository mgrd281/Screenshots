import SwiftUI
import UIKit

/// A picture being protected: shown at once, its private places marked as
/// they are found, then covered and checked. Two fingers or a double tap
/// zoom. Under the picture, the tools: Select to tap a place or a word and
/// move, resize or turn it; the marker, a box and the lasso to hide more by
/// hand; the eraser to take covers away; Undo and Redo. Holding the eye
/// shows the picture as it was. Copy, Share and Save wait until the copy is
/// made and checked, and ask first while places are still to check. The
/// picture itself stays as it was.
struct ProtectView: View {
    @StateObject private var session: ProtectSession
    @ObservedObject private var sync = SyncCenter.shared
    @State private var tool = EditTool.select
    @State private var selected: Int?
    @State private var markerWidth = HandShape.widths[1]
    @State private var eraserReach: CGFloat = 0.03
    @State private var showsOriginal = false
    @State private var showsDetails = false
    @State private var showsOptions = false
    /// The mark held down, whose menu shows.
    @State private var menuFor: ProtectionPlan.Mark?
    /// A way out waiting while places are still to check.
    @State private var waiting: Leaving?
    @State private var sharing: SharedFile?
    @State private var note: String?
    /// Sent to the Mac already, so it goes once.
    @State private var sent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ways a copy leaves.
    enum Leaving: Identifiable {
        case copy, share, save, send
        var id: Self { self }
    }

    init(source: ProtectSession.Source) {
        _session = StateObject(wrappedValue: ProtectSession(source: source))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            picture
            if session.original != nil {
                eye.padding(16)
            }
        }
        .overlay(alignment: .top) {
            Group {
                if session.stage == .ready, let hint {
                    Text(hint).floatingPill()
                } else {
                    StatusPill(stage: session.stage, onDontWait: session.dontWait, onRetry: session.retry)
                }
            }
            .padding(.top, 8)
        }
        .animation(motion, value: session.stage)
        .animation(motion, value: tool)
        .navigationTitle(L("Protect Picture"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { more }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let mark = selectedMark { selection(mark).padding(.bottom, 8) }
                VStack(spacing: 0) {
                    tools
                    Divider()
                    bar
                }
                .background(.bar)
            }
        }
        .sheet(isPresented: $showsDetails) { DetailsSheet(session: session) }
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
        .confirmationDialog(String(format: L("%d places still to check"), session.plan.tally.toCheck),
                            isPresented: Binding(get: { waiting != nil }, set: { if !$0 { waiting = nil } }),
                            titleVisibility: .visible, presenting: waiting) { way in
            Button(L("Check Now")) { showsDetails = true }
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
        .onChange(of: tool) { _, _ in
            selected = nil
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    /// How to use the tool in hand, while the picture is ready.
    private var hint: String? {
        switch tool {
        case .select: nil
        case .marker: L("Draw over what to hide. Two fingers move the picture.")
        case .box: L("Drag a box over what to hide. Two fingers move the picture.")
        case .lasso: L("Draw round what to hide. Two fingers move the picture.")
        case .eraser: L("Rub over a cover to take it away. The picture shows there again.")
        }
    }

    // MARK: The picture

    @ViewBuilder private var picture: some View {
        if let shown = showsOriginal ? session.original : session.copy ?? session.original ?? session.preview {
            MarkCanvas(image: shown, marks: showsOriginal ? [] : session.plan.marks,
                       checking: Set(session.plan.marks.filter(session.plan.needsCheck).map(\.id)),
                       isCopy: !showsOriginal && session.copy != nil, tool: tool, selected: selected,
                       markerWidth: markerWidth, eraserReach: eraserReach, actions: actions)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityAction(named: L("Details")) { showsDetails = true }
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
            turn: { id, angle in session.turn(id, by: angle) })
    }

    /// Selecting: a tap on a place selects it, on a word hides it, and
    /// anywhere else lets go.
    private func tap(_ point: CGPoint) {
        guard session.original != nil, !showsOriginal else { return }
        if let mark = session.plan.mark(at: point) {
            selected = selected == mark.id ? nil : mark.id
            UISelectionFeedbackGenerator().selectionChanged()
        } else if let id = session.hideWord(at: point) {
            selected = id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            selected = nil
        }
    }

    private var selectedMark: ProtectionPlan.Mark? {
        guard let selected else { return nil }
        return session.plan.marks.first { $0.id == selected }
    }

    /// The eye, held down to see the picture as it was.
    private var eye: some View {
        ToolButton(symbol: showsOriginal ? "eye.fill" : "eye", active: showsOriginal)
            .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                showsOriginal = pressing
            })
            .accessibilityLabel(L("Show the screenshot as it was"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showsOriginal.toggle() }
    }

    /// Details, and taking back what was changed, each as one change to undo.
    private var more: some View {
        Menu {
            Button {
                showsDetails = true
            } label: {
                Label(L("Details"), systemImage: "list.bullet")
            }
            .disabled(session.plan.marks.isEmpty)
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

    // MARK: The tools

    private var tools: some View {
        HStack(spacing: 0) {
            ForEach(EditTool.allCases) { item in
                Button {
                    // The tool in hand, chosen again, opens its options.
                    if tool == item, item != .select { showsOptions = true } else { tool = item }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tool == item ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(tool == item ? Color.accentColor : Color.clear, in: Circle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
                .accessibilityHint(tool == item && item != .select ? L("Tap again for its options.") : "")
            }
            Divider().frame(height: 28)
            toolButton("arrow.uturn.backward", L("Undo"), enabled: session.plan.canUndo) {
                session.undo()
                selected = nil
            }
            toolButton("arrow.uturn.forward", L("Redo"), enabled: session.plan.canRedo) {
                session.redo()
                selected = nil
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .disabled(session.original == nil)
    }

    private func toolButton(_ symbol: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .accessibilityLabel(title)
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
        .floatingPill()
    }

    // MARK: The bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            leaving
            if let note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .phoneGuideTarget(.actions)
        .animation(.easeOut(duration: 0.2), value: note)
    }

    /// How the places stand, each counted once: protected, to check, and
    /// not protected; a place only offered is never counted as protected.
    private var summary: some View {
        let tally = session.plan.tally
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                status(tally)
                Spacer(minLength: 8)
                Button(L("Details")) { showsDetails = true }
                    .font(.subheadline)
                    .disabled(session.plan.marks.isEmpty)
            }
            if session.found, !session.plan.marks.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { counters(tally) }
                    VStack(alignment: .leading, spacing: 6) { counters(tally) }
                }
            }
        }
    }

    @ViewBuilder private func status(_ tally: ProtectionPlan.Tally) -> some View {
        if !session.found {
            Text(L("Finding private details…"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if session.plan.marks.isEmpty {
            Text(L("Nothing private found"))
                .font(.subheadline.weight(.semibold))
        } else if tally.exposed > 0 {
            Label {
                Text(String(format: L("Not fully protected: %d places to check are not covered"), tally.exposed))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline.weight(.semibold))
        } else if tally.toCheck > 0 {
            Text(L("Covered. Check the marked places before sharing."))
                .font(.subheadline.weight(.semibold))
        } else {
            Label(L("Everything found is covered"), systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder private func counters(_ tally: ProtectionPlan.Tally) -> some View {
        KindChip(title: L("Protected"), count: tally.covered)
        Button {
            showsDetails = true
        } label: {
            KindChip(title: L("To check"), count: tally.toCheck, accent: tally.toCheck > 0)
        }
        .buttonStyle(.plain)
        KindChip(title: L("Not protected"), count: tally.left)
    }

    /// Copy, Share and Save, and Send to Mac with syncing on: waiting,
    /// dimmed, until the copy is made and checked. Side by side while their
    /// words fit, else one under another, never cut short.
    private var leaving: some View {
        let ready = session.isReady
        return VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { ways.lineLimit(1) }
                VStack(spacing: 8) { ways }
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(!ready)
            // With syncing on, the covered copy hangs on the Mac's line.
            if sync.canSend {
                Button { leave(.send) } label: {
                    Label(L("Send to Mac"), systemImage: "laptopcomputer.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!ready || sent)
            }
        }
    }

    @ViewBuilder private var ways: some View {
        Button { leave(.copy) } label: {
            Label(L("Copy"), systemImage: "doc.on.doc").frame(maxWidth: .infinity)
        }
        Button { leave(.share) } label: {
            Label(L("Share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }
        Button { leave(.save) } label: {
            Label(L("Save"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
        }
    }

    /// A way out, asked first while places are still to check.
    private func leave(_ way: Leaving) {
        guard session.isReady else { return }
        if session.plan.tally.toCheck > 0 { waiting = way } else { go(way) }
    }

    private func go(_ way: Leaving) {
        switch way {
        case .copy: copy()
        case .share: share()
        case .save: save()
        case .send: send()
        }
    }

    private func copy() {
        guard session.isReady, let png = session.png else { return }
        Covering.copy(png)
        note = L("Copied")
        session.left()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The copy alone, as a PNG file of its own, with nothing of the
    /// original's notes in it.
    private func share() {
        guard session.isReady, let png = session.png else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try png.write(to: url, options: [.atomic, .completeFileProtection])
            sharing = SharedFile(url: url)
        } catch {
            note = L("The copy could not be made.")
        }
    }

    private func save() {
        guard session.isReady, let png = session.png else { return }
        Task {
            do {
                try await Covering.save(png)
                note = L("Saved to Photos")
                session.left()
            } catch {
                note = L("The picture could not be saved.")
            }
        }
    }

    private func send() {
        guard session.isReady, let png = session.png else { return }
        sent = true
        let report = session.plan.report
        let redaction = SyncRedaction(kinds: report.keys, areas: report.total, look: CoverStyle.current.rawValue)
        let name = fileName
        Task {
            if await sync.send(covered: png, name: name, redaction: redaction) {
                note = L("On its way to your Mac")
                session.left()
            } else {
                sent = false
                note = L("Could not send it. Try again.")
            }
        }
    }

    /// Named by when it was taken, as the Mac names screenshots.
    private var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var taken = Date()
        if case .asset(let id) = session.source, let date = Library.asset(id)?.creationDate { taken = date }
        return "Snapfly \(formatter.string(from: taken)).png"
    }

    private func title(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.title }
        return mark.origin == .hand ? L("Hidden by hand") : L("Your own rules")
    }
}

/// The marker's widths, by name, as `HandShape.widths` orders them.
private let widthNames = [L("Thin"), L("Medium"), L("Thick")]

/// The eraser's sizes, a share of the picture's width, and their names.
private let eraserSizes: [CGFloat] = [0.015, 0.03, 0.06]
private let eraserNames = [L("Small"), L("Medium"), L("Large")]

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
