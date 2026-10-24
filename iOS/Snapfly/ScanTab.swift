import PhotosUI
import SwiftUI
import VisionKit

/// The Scan tab: letters, forms and receipts from the system's document
/// camera, or photos of them chosen from Photos. Each page is made flat,
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

    private let supported = VNDocumentCameraViewController.isSupported

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScanCard(supported: supported, picked: $picked) {
                        presses += 1
                        scanning = true
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: presses)
                    if !store.pages.isEmpty { scanned }
                    PDFStartCard()
                    RecentProjects()
                    steps
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(L("Scan"))
            .quickNotes()
            .overlay(alignment: .bottom) { improving }
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
            DocumentScanner { images in
                scanning = false
                // The editor opens on the first page at once, while it is made ready.
                if let first = store.add(camera: images).first { open(first.id) }
            }
            .ignoresSafeArea()
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
                Button(L("Clear")) {
                    withAnimation(.easeOut(duration: 0.2)) { store.clear() }
                }
                .font(.subheadline.weight(.medium))
                .disabled(store.making != nil)
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

    /// How a scan goes, in four short steps, what is new among them.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("doc.viewfinder", Text(L("Hold your iPhone over the page. It is found and taken by itself.")))
            step("sun.max", Text(L("New:")).fontWeight(.semibold).foregroundStyle(.primary) + Text(verbatim: " ")
                + Text(L("The page is straightened and brightened, like a clean PDF. No text is changed.")))
            step("eye.slash", Text(L("Names, numbers and other private details are covered as Settings says.")))
            step("square.and.arrow.up", Text(L("Check the places, then copy, share or save the page as a PDF or a picture.")))
        }
        .padding(.horizontal, 4)
    }

    private func step(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SnapflyTokens.protect)
                .frame(width: 24)
                .accessibilityHidden(true)
            text
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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

/// The scan tab's first card: a page in a viewfinder on the soft green,
/// what scanning does, the green button that opens the camera, and the way
/// to scan photos chosen from Photos instead.
private struct ScanCard: View {
    let supported: Bool
    @Binding var picked: [PhotosPickerItem]
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // A little smaller than it was, so the PDF card under it shows too.
            Viewfinder()
                .frame(width: 132, height: 132)
                .scaleEffect(0.8)
                .frame(width: 106, height: 106)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(L("Scan a document"))
                    .font(.title2.weight(.bold))
                Text(L("Letters, forms and receipts, straight from the camera. Straightened, brightened and with private details covered, all on this iPhone."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                Button(action: scan) {
                    Label(L("Scan Document"), systemImage: "camera.viewfinder")
                }
                .buttonStyle(ProtectButtonStyle())
                .disabled(!supported)
                .accessibilityIdentifier("scan-camera")
                PhotosPicker(selection: $picked, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                    Text(L("Choose from Photos"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.protectTint)
                        .frame(minHeight: SnapflyTokens.touch)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("scan-photos")
            }
            if !supported {
                Text(L("This iPhone cannot scan documents."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(SnapflyTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .padding(.top, 4)
    }
}

/// A page with a covered line in the corners of a viewfinder, drawn with
/// shapes, so it fits light and dark and shows no one's details. Each time
/// the tab shows, a green line reads the page once, top to bottom.
private struct Viewfinder: View {
    @State private var visits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the reading line is, and how much it shows.
    private struct Sweep {
        var y: CGFloat = -44
        var opacity = 0.0
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SnapflyTokens.card)
                .frame(width: 74, height: 96)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color.primary.opacity(0.22)).frame(width: 30, height: 5)
                        Capsule().fill(Color.primary.opacity(0.85)).frame(width: 46, height: 5)
                        ForEach([CGFloat(50), 40, 48, 28], id: \.self) { width in
                            Capsule().fill(Color.primary.opacity(0.10)).frame(width: width, height: 5)
                        }
                    }
                    .padding(11)
                }
            if !reduceMotion { line }
            Corners()
                .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .onAppear { visits += 1 }
    }

    /// The reading line: brightest in its middle, glowing softly, wider
    /// than the page so it seems to come from the viewfinder.
    private var line: some View {
        Capsule()
            .fill(LinearGradient(colors: [SnapflyTokens.protect.opacity(0), SnapflyTokens.protect, SnapflyTokens.protect.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 96, height: 2.5)
            .shadow(color: SnapflyTokens.protect.opacity(0.7), radius: 5)
            .keyframeAnimator(initialValue: Sweep(), trigger: visits) { line, sweep in
                line.offset(y: sweep.y).opacity(sweep.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    LinearKeyframe(-44, duration: 0.15)
                    CubicKeyframe(44, duration: 0.9)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.15)
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 0.55)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
    }

    /// The four corners of a viewfinder.
    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let arm = rect.width * 0.2, inset: CGFloat = 2
            let r = rect.insetBy(dx: inset, dy: inset)
            var path = Path()
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1),
            ]
            for (corner, dx, dy) in corners {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }
            return path
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
                if let thumbnail = page.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
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
/// cropped, or none when it was cancelled or failed.
struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([CGImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([CGImage]) -> Void

        init(done: @escaping ([CGImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            done([])
        }
    }
}
