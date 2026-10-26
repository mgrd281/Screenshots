import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// The Scan tab: letters, forms and receipts from the system's document
/// camera, or photos of them chosen from Photos. Its start has one job, a
/// scan started in one tap (`ScanStart`): the emerald card, Aus Fotos,
/// Verbinden and PDF öffnen, and the three documents edited last; scrolled
/// past the card, a green Scannen pill in the bar takes its place. Each page is made flat,
/// upright and level, cleaned as a good scanner leaves a page and checked
/// (`ScannedPages`), then opened to cover its private details like any
/// screenshot, in the editor with its pages (`ScanEditor`). The pages wait
/// under "Scanned pages" in the document's order, for Save and Share (one
/// A4 PDF or a PNG each, covered or only cleaned) or an app. Pages stay in
/// memory while the app runs, and are never saved unless the owner saves them.
/// Under the scan card, "PDF erstellen und bearbeiten" starts a PDF project
/// (`ProjectStore`), and the projects changed last wait under it.
struct ScanTab: View {
    @ObservedObject private var store = ScannedPages.shared
    @ObservedObject private var tabs = AppTabs.shared
    @State private var scanning = false
    @State private var path = NavigationPath()
    @State private var picked: [PhotosPickerItem] = []
    @State private var saving = false
    /// An AI chat tapped, while what to ask with the pages is chosen.
    @State private var asking: AssistantChoice?
    /// What was asked there, handed over once its sheet has gone.
    @State private var asked: (chat: ChatTarget, ask: ScanAsk?)?
    /// Each press of the scan button, for its haptic.
    @State private var presses = 0
    /// The card scrolled out of view: the bar offers Scannen instead.
    @State private var heroHidden = false
    /// "So funktioniert's", from the "?".
    @State private var helping = false
    /// Clear tapped beside the scanned pages, while it is asked.
    @State private var discarding = false
    /// The start came in, once per launch.
    @State private var shown = ScanStart.entered
    @ObservedObject private var projects = ProjectStore.shared
    @ScanCalm private var calm

    /// The system's document camera, or Snapfly's own where it is on.
    private var supported: Bool { VNDocumentCameraViewController.isSupported || PageCamera.isOn }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: SnapflyTokens.scanGroupGap) {
                        ScanHero(supported: supported, scan: startScan)
                            .onGeometryChange(for: Bool.self) { proxy in
                                proxy.frame(in: .scrollView).maxY < 100
                            } action: { hidden in
                                withAnimation(SnapflyMotion.change(calm)) { heroHidden = hidden }
                            }
                            .scanEntrance(shown, step: 0, calm: calm)
                        if !supported {
                            Text(L("This iPhone cannot scan documents."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, -12)
                        }
                        ScanQuickActions(picked: $picked)
                            .scanEntrance(shown, step: 1, calm: calm)
                        if !store.pages.isEmpty { scanned }
                        RecentDocuments(projects: recent) { path.append(ScanRoute.allDocuments) }
                            .scanEntrance(shown, step: 2, calm: calm)
                        Color.clear.frame(height: 1).id(Self.end)
                    }
                    .padding(.horizontal, SnapflyTokens.scanMargin)
                    .padding(.top, 4)
                    // Above the tab bar (in the safe area) by 16 pt once scrolled to the end.
                    .padding(.bottom, 16)
                }
                .softBottomEdge()
                .onChange(of: store.pages.count) { _, count in
                    // For pictures made in CI: scrolled past the card once the pages are in.
                    guard ScanDemo.scrolls, count > 0 else { return }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { reader.scrollTo(Self.end, anchor: .bottom) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .sensoryFeedback(.impact(weight: .light), trigger: presses)
            .navigationTitle(L("Scan"))
            .toolbar { bar }
            .sheet(isPresented: $helping) { ScanHowSheet() }
            .onAppear(perform: enter)
            .quickNotes()
            .overlay(alignment: .bottom) { improving }
            .navigationDestination(for: ScanRoute.self) { _ in AllDocumentsView() }
            .navigationDestination(for: ProtectSession.Source.self) { source in
                if case .scanned(let id) = source {
                    ScanEditor(page: id)
                } else {
                    ProtectView(source: source)
                }
            }
        }
        // The first run's Try It Now opens the camera here.
        .onAppear(perform: scanIfAsked)
        .onAppear(perform: showDemo)
        .onChange(of: tabs.scanRequested) { _, asked in
            if asked { scanIfAsked() }
        }
        .onChange(of: picked) { _, items in
            Task { await add(items) }
        }
        .fullScreenCover(isPresented: $scanning) {
            if PageCamera.isOn {
                PageCamera { images in
                    scanning = false
                    if let first = store.add(camera: images, whole: true).first { open(first.id) }
                }
            } else {
                DocumentScanner { images in
                    scanning = false
                    // The editor opens on the first page at once, while it is made ready.
                    if let first = store.add(camera: images).first { open(first.id) }
                } failed: {
                    // Never a camera that just closes: the note says why, as when it may not be used.
                    QuickCoverer.shared.show(DocumentScanner.failure, for: 5)
                }
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: wantedCorners) { wanted in
            if let page = store.page(wanted.id), let picture = page.source ?? store.picture(wanted.id) {
                ScanCornerEditor(image: picture, quad: page.quad ?? .inset(0.06)) { quad in
                    if let quad { store.setCorners(wanted.id, quad) } else { store.remove(wanted.id) }
                }
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .sheet(isPresented: $saving) { ScanSaveSheet() }
        .sheet(item: $asking, onDismiss: handOverAsked) { choice in
            ScanAssistantSheet(chat: choice.chat) { asked = (choice.chat, $0) }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) { HandoffAuditMarks() }
        #endif
    }

    /// An AI chat first asks what to ask with the pages; any other app takes them at once.
    private func send(_ chat: ChatTarget) {
        if chat.isAI { asking = AssistantChoice(chat: chat) } else { store.send(to: chat) }
    }

    /// What was chosen for the AI chat, once its sheet has gone.
    private func handOverAsked() {
        guard let asked else { return }
        self.asked = nil
        store.send(to: asked.chat, asking: asked.ask)
    }

    /// A photo whose page Vision was not sure of, while its corners are set.
    private var wantedCorners: Binding<ScanPageRef?> {
        Binding(get: { store.cornersWanted.map(ScanPageRef.init) }, set: { if $0 == nil { store.cornersWanted = nil } })
    }

    /// While pages are made ready and the tab shows: which, over its bottom.
    @ViewBuilder private var improving: some View {
        if let index = store.improving, path.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(format: L("Page %d of %d is being improved"), index, store.pages.count))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .floatingPill()
            .padding(.bottom, 24)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan-improving")
        }
    }

    /// The pages scanned while the app runs, in the document's order, the
    /// apps to hand them to, and Save and Share.
    private var scanned: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Scanned pages"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let kind = store.title?.kind { PaperKindLabel(kind: kind) }
                Spacer()
                // The pages live in memory alone, so clearing them asks first, as the editor's Discard Scan does.
                Button(L("Clear")) { discarding = true }
                    .font(.subheadline.weight(.medium))
                    .disabled(store.making != nil)
                    .confirmationDialog(L("Discard the whole scan?"), isPresented: $discarding, titleVisibility: .visible) {
                        Button(L("Discard Scan"), role: .destructive) {
                            withAnimation(.easeOut(duration: 0.2)) { store.clear() }
                        }
                        Button(L("Cancel"), role: .cancel) {}
                    } message: {
                        Text(L("Every page goes, with what was covered on it."))
                    }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                    Button { open(page.id) } label: {
                        PageCard(page: page, number: index + 1, session: store.opened(page.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("Cover Private Details"))
                    .accessibilityIdentifier("scan-page-\(index + 1)")
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(.easeOut(duration: 0.2)) { store.remove(page.id) }
                        } label: {
                            Label(L("Remove"), systemImage: "trash")
                        }
                        .disabled(store.making != nil)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Send to"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                AppTiles(busy: store.sendingTo) { send($0) }
                    .padding(.horizontal, -16)
            }
            .padding(.top, 4)
            Button { saving = true } label: {
                Label(L("Save and Share"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ProtectButtonStyle())
            .accessibilityIdentifier("scan-save-share")
            .disabled(store.making != nil)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            Button { store.saveAsDocument() } label: {
                Label(L("Keep Under Recent"), systemImage: "tray.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .frame(minHeight: SnapflyTokens.touch)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressStyle())
            .disabled(store.making != nil || store.improving != nil)
            .accessibilityHint(L("Keeps the pages on this iPhone as a document. Covered as your settings say."))
            .accessibilityIdentifier("scan-keep")
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Each page is covered as Settings says, or as you left it after opening it."))
                Text(L("A tap on an app covers every page and hands them to it, through the share sheet where needed."))
                Text(L("An AI chat first offers questions for the covered pages. You ask them in its own app; Snapfly sends nothing itself."))
                Text(L("Pages stay on this iPhone only while Snapfly is open."))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The "?" on the trailing side; scrolled past the card, on the leading
    /// side, and the green Scannen pill on the trailing one.
    @ToolbarContentBuilder private var bar: some ToolbarContent {
        if heroHidden {
            ToolbarItem(placement: .topBarLeading) { help }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: startScan) {
                    Label(L("Scan"), systemImage: "dot.viewfinder")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(ProtectButtonStyle(compact: true))
                .disabled(!supported)
                .transition(.opacity.combined(with: .offset(y: calm ? 0 : -10)))
                .accessibilityLabel(L("Scan a document"))
                .accessibilityHint(L("Opens the camera"))
                .accessibilityIdentifier("scan-bar-camera")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { help }
        }
    }

    private var help: some View {
        Button { helping = true } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background {
                    // From iOS 26 the bar's own glass holds it, as it does the eye's.
                    if #available(iOS 26, *) { Color.clear } else { Circle().fill(.regularMaterial) }
                }
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Help"))
        .accessibilityHint(L("How It Works"))
        .accessibilityIdentifier("scan-help")
    }

    /// The start's end, for pictures made in CI scrolled to it.
    private static let end = "scan-end"

    /// The documents edited last, newest first.
    private var recent: [PDFProject] {
        Array(projects.projects.filter { !$0.pages.isEmpty }.prefix(ScanStart.shown))
    }

    private func startScan() {
        guard supported else { return }
        presses += 1
        scanning = true
    }

    /// The card, the quick actions and the documents rise in, once per launch.
    private func enter() {
        guard !ScanStart.entered else { return }
        ScanStart.entered = true
        shown = true
    }

    private func open(_ id: UUID) {
        _ = store.session(id)
        path.append(ProtectSession.Source.scanned(id))
    }

    /// Photos chosen, read, and added as pages; the editor opens on the first.
    private func add(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        picked = []
        let photos = await ScanPhoto.read(items)
        guard !photos.isEmpty else { return QuickCoverer.shared.show(L("The picture could not be read.")) }
        if let first = store.add(photos: photos).first { open(first.id) }
    }

    /// Opens the camera once, as the first run asked.
    private func scanIfAsked() {
        guard tabs.scanRequested else { return }
        tabs.scanRequested = false
        guard supported else { return }
        presses += 1
        scanning = true
    }

    /// For pictures made in CI: made-up photos of a made-up invoice, as
    /// `-SnapflyScan` asks (`ScanDemo`).
    private func showDemo() {
        guard ScanDemo.requested, store.pages.isEmpty else { return }
        if ScanDemo.opensHelp { helping = true }
        if ScanDemo.makesRecent { Task { await ScanDemo.makeRecent(ProjectStore.shared) } }
        Task {
            if let mode = ScanDemo.mode { store.setMode(mode) }
            ScanDemo.keepOwnDetails()
            let photos = await Task.detached(priority: .userInitiated) { ScanDemo.photos() }.value
            let added = store.add(photos: photos, unsure: ScanDemo.unsure)
            if ScanDemo.asksAssistant { asking = AssistantChoice(chat: .claude) }
            guard ScanDemo.opensEditor, let page = added.dropFirst(ScanDemo.page).first ?? added.first else { return }
            open(page.id)
        }
    }
}

/// A scanned page as a small square card, its top showing, with its
/// number in the document; while it is made ready, a spinner; while its
/// corners wait to be set, the crop glyph in dark amber; once opened and its
/// copy checked, the shield the protected screenshots carry, or where
/// something on it is wrong, an orange mark.
private struct PageCard: View {
    let page: ScannedPages.Page
    let number: Int
    let session: ProtectSession?

    private var working: Bool { page.state == .waiting || page.state == .improving }

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                // Its covered copy only, veiled unless shown; none before it is covered.
                if let session { CoveredPicture(session: session) }
            }
            .overlay {
                if working {
                    ProgressView()
                } else if page.state == .needsCorners {
                    Image(systemName: "crop")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.scanWarnText)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(number, format: .number)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                if let session {
                    Checked(session: session)
                } else if !page.issues.isEmpty {
                    Image(systemName: "exclamationmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Color.orange, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: L("Page %d"), number))
            .accessibilityValue(value)
    }

    private var value: String {
        if working { return L("being brightened") }
        if page.state == .needsCorners { return L("corners to set") }
        if session?.isReady == true { return L("Protected") }
        return page.issues.isEmpty ? "" : L("hard to read")
    }

    /// The page's covered copy, small: veiled unless the owner shows the
    /// pictures, and always while Snapfly is away or something on the page
    /// is still to check; nothing until its copy is made.
    private struct CoveredPicture: View {
        @ObservedObject var session: ProtectSession
        @AppStorage(ScanStart.previewKey) private var shows = false
        @Environment(\.scenePhase) private var phase
        @State private var veiled: UIImage?

        private var hidden: Bool { !shows || phase != .active || session.plan.tally.toCheck > 0 }

        var body: some View {
            Group {
                if let copy = session.copy, session.isReady {
                    if !hidden {
                        Image(uiImage: copy).resizable().scaledToFill()
                    } else if let veiled {
                        Image(uiImage: veiled).resizable().scaledToFill()
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: hidden)
            .task(id: session.copy.map(ObjectIdentifier.init)) {
                guard let copy = session.copy?.cgImage else { return veiled = nil }
                veiled = await Task.detached(priority: .utility) {
                    ScanCleaner.smaller(copy, longest: 360).flatMap(ScanVeil.image).map { UIImage(cgImage: $0) }
                }.value
            }
        }
    }

    /// The shield, while the page's copy is made and checked as it was left.
    private struct Checked: View {
        @ObservedObject var session: ProtectSession

        var body: some View {
            if session.isReady {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(SnapflyTokens.protect, in: Circle())
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// The system's document camera; `done` gets the pages, upright and
/// cropped, or none when it was cancelled or failed; `failed` is told
/// after `done` when it could not scan, so a note can say why.
struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([CGImage]) -> Void
    var failed: () -> Void = {}

    /// What the note says when the camera could not scan: that Snapfly may
    /// not use it, where that is why.
    static var failure: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: L("Snapfly may not use the camera. Allow it in Settings.")
        default: L("The camera could not scan. Try again.")
        }
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done, failed: failed) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([CGImage]) -> Void
        let failed: () -> Void

        init(done: @escaping ([CGImage]) -> Void, failed: @escaping () -> Void) {
            self.done = done
            self.failed = failed
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            done([])
            failed()
        }
    }
}
