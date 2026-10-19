import SwiftUI

/// A screenshot being protected: shown at once, its private places marked
/// as they are found, then covered and checked. Two fingers zoom; a tap on
/// a place turns it on or off; Add Area covers more by hand; holding the eye
/// shows the screenshot as it was. Copy, Share and Save wait until the copy
/// is made and checked. The screenshot itself stays as it was.
struct ProtectView: View {
    @StateObject private var session: ProtectSession
    @ObservedObject private var sync = SyncCenter.shared
    @State private var adding = false
    @State private var showsOriginal = false
    @State private var showsDetails = false
    @State private var note: String?
    /// Sent to the Mac already, so it goes once.
    @State private var sent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: ProtectSession.Source) {
        _session = StateObject(wrappedValue: ProtectSession(source: source))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            picture
            if session.original != nil {
                tools
                    .padding(16)
            }
        }
        .overlay(alignment: .top) {
            Group {
                if adding, session.stage == .ready {
                    Text(L("Drag over a part to cover it. Two fingers move the picture."))
                        .floatingPill()
                } else {
                    StatusPill(stage: session.stage, onDontWait: session.dontWait, onRetry: session.retry)
                }
            }
            .padding(.top, 8)
        }
        .animation(motion, value: session.stage)
        .animation(motion, value: adding)
        .navigationTitle(L("Cover Private Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    session.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!session.plan.canUndo)
                .accessibilityLabel(L("Undo"))
                Button {
                    session.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!session.plan.canRedo)
                .accessibilityLabel(L("Redo"))
            }
        }
        .safeAreaInset(edge: .bottom) { bar }
        .sheet(isPresented: $showsDetails) { DetailsSheet(session: session) }
        .phoneGuide(on: .shot)
        .onAppear {
            session.start()
            PhoneGuide.shared.screen = .shot
            PhoneGuide.shared.happened(.openedShot)
        }
        .onDisappear { PhoneGuide.shared.screen = .library }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    // MARK: The picture

    @ViewBuilder private var picture: some View {
        if let shown = showsOriginal ? session.original : session.copy ?? session.original {
            MarkCanvas(image: shown, marks: showsOriginal ? [] : session.plan.marks,
                       isCopy: !showsOriginal && session.copy != nil, adding: adding,
                       onTap: tap, onDraw: { session.cover($0) })
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

    /// A tap turns the place under the finger on or off.
    private func tap(_ point: CGPoint) {
        guard !adding, !showsOriginal, let mark = session.plan.mark(at: point) else { return }
        session.toggle(mark.id)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Add Area, and the eye held down to see the screenshot as it was.
    private var tools: some View {
        HStack(spacing: 12) {
            Button {
                adding.toggle()
            } label: {
                ToolButton(symbol: "plus.viewfinder", active: adding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Add Area"))
            .accessibilityValue(adding ? L("On") : L("Off"))
            ToolButton(symbol: showsOriginal ? "eye.fill" : "eye", active: showsOriginal)
                .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                    showsOriginal = pressing
                })
                .accessibilityLabel(L("Show the screenshot as it was"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showsOriginal.toggle() }
        }
    }

    // MARK: The bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            actions
            if let note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .phoneGuideTarget(.actions)
        .animation(.easeOut(duration: 0.2), value: note)
    }

    /// What is covered, in a sentence and kind by kind, with Details.
    @ViewBuilder private var summary: some View {
        let report = session.plan.report
        let toCheck = session.plan.toCheck
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(headline(report))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.found ? .primary : .secondary)
                Spacer()
                Button(L("Details")) { showsDetails = true }
                    .font(.subheadline)
                    .disabled(session.plan.marks.isEmpty)
            }
            if !report.isEmpty || toCheck > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if toCheck > 0 {
                            Button {
                                showsDetails = true
                            } label: {
                                KindChip(title: L("To check"), count: toCheck, accent: true)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(PrivateDetail.allCases.filter { report.kinds[$0, default: 0] > 0 }, id: \.self) { kind in
                            KindChip(title: kind.title, count: report.kinds[kind, default: 0])
                        }
                        if report.rules > 0 { KindChip(title: L("Your own rules"), count: report.rules) }
                        if report.hand > 0 { KindChip(title: L("Hidden by hand"), count: report.hand) }
                    }
                }
            }
        }
    }

    private func headline(_ report: CoverReport) -> String {
        guard session.found else { return L("Finding private details…") }
        return report.isEmpty ? L("Nothing private found") : String(format: L("%d places covered"), report.total)
    }

    /// Copy, Share and Save, and Send to Mac with syncing on: waiting, dimmed,
    /// until the copy is made and checked.
    private var actions: some View {
        let ready = session.isReady
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: copy) {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                if let picture = session.shared, let image = session.copy {
                    ShareLink(item: picture, preview: SharePreview("Snapfly", image: Image(uiImage: image))) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .simultaneousGesture(TapGesture().onEnded { session.left() })
                } else {
                    Button {} label: {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(true)
                }
                Button(action: save) {
                    Label(L("Save"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(!ready)
            // With syncing on, the covered copy hangs on the Mac's line.
            if sync.canSend {
                Button(action: send) {
                    Label(L("Send to Mac"), systemImage: "laptopcomputer.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!ready || sent)
            }
        }
    }

    private func copy() {
        guard session.isReady, let png = session.png else { return }
        Covering.copy(png)
        note = L("Copied")
        session.left()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        // Named by when it was taken, as the Mac names screenshots.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var taken = Date()
        if case .asset(let id) = session.source, let date = Library.asset(id)?.creationDate { taken = date }
        let name = "Snapfly \(formatter.string(from: taken)).png"
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
}
