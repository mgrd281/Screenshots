import SwiftUI
import VisionKit

/// The Scan tab: a letter, a form or a receipt scanned with the system's
/// document camera, straightened and cropped by it, then opened to cover its
/// private details like any screenshot, or covered all together and sent to
/// an app with one tap, or made into one PDF. Scanned pages stay in memory while the app runs, and are never
/// saved unless the owner saves a covered copy.
struct ScanTab: View {
    @ObservedObject private var store = ScannedPages.shared
    @ObservedObject private var tabs = AppTabs.shared
    @State private var scanning = false
    @State private var path = NavigationPath()
    /// Each press of the scan button, for its haptic.
    @State private var presses = 0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScanCard(supported: VNDocumentCameraViewController.isSupported) {
                        presses += 1
                        scanning = true
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: presses)
                    if !store.pages.isEmpty { scanned }
                    steps
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(L("Scan"))
            .quickNotes()
            .navigationDestination(for: ProtectSession.Source.self) { source in ProtectView(source: source) }
        }
        // The first run's Try It Now opens the camera here.
        .onAppear(perform: scanIfAsked)
        .onChange(of: tabs.scanRequested) { _, asked in
            if asked { scanIfAsked() }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                guard !images.isEmpty else { return }
                let new = store.add(images)
                // One page goes straight to covering; several wait here to be chosen.
                if new.count == 1 { open(new[0]) }
            }
            .ignoresSafeArea()
        }
    }

    /// The pages scanned while the app runs, in the order they were
    /// scanned, and the PDF they make together.
    private var scanned: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Scanned pages"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L("Clear")) {
                    withAnimation(.easeOut(duration: 0.2)) { store.clear() }
                }
                .font(.subheadline.weight(.medium))
                .disabled(store.making != nil)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                    Button { open(page) } label: {
                        PageCard(image: page.image, number: index + 1, session: store.opened(page.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("Cover Private Details"))
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
                AppTiles(busy: store.sendingTo) { store.send(to: $0) }
                    .padding(.horizontal, -16)
            }
            .padding(.top, 4)
            Button { store.sharePDF() } label: {
                // Pages covered for an app show on its icon instead.
                if let making = store.making, store.sendingTo == nil {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(String(format: L("Page %d of %d"), making, store.pages.count))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                } else {
                    Label(L("Share Covered PDF"), systemImage: "doc.richtext")
                }
            }
            .buttonStyle(ProtectButtonStyle())
            .disabled(store.making != nil)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .animation(.easeOut(duration: 0.15), value: store.making)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Each page is covered as Settings says, or as you left it after opening it. The PDF holds only pictures of the covered pages, no text to copy."))
                Text(L("A tap on an app covers every page and hands them to it, through the share sheet where needed."))
                Text(L("Pages stay on this iPhone only while Snapfly is open."))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How a scan goes, in three short steps.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("doc.viewfinder", L("Hold your iPhone over the page; it is found and taken by itself."))
            step("eye.slash", L("Names, numbers and other private details are covered as Settings says."))
            step("square.and.arrow.up", L("Check the places, then copy, share or save the covered page."))
        }
        .padding(.horizontal, 4)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SnapflyTokens.protect)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ page: ScannedPages.Page) {
        _ = store.session(page.id)
        path.append(ProtectSession.Source.scanned(page.id))
    }

    /// Opens the camera once, as the first run asked.
    private func scanIfAsked() {
        guard tabs.scanRequested else { return }
        tabs.scanRequested = false
        guard VNDocumentCameraViewController.isSupported else { return }
        presses += 1
        scanning = true
    }
}

/// The pages scanned while the app runs, in the order they were scanned,
/// and the protection of each page opened, so it opens again as it was
/// left and the PDF takes it as it is. Never written anywhere.
@MainActor
final class ScannedPages: ObservableObject {
    static let shared = ScannedPages()

    struct Page: Identifiable {
        let id = UUID()
        let image: CGImage
    }

    @Published private(set) var pages: [Page] = []
    /// The page being covered for the PDF or an app, counted from 1; nil
    /// while none is.
    @Published private(set) var making: Int?
    /// The app the pages are going to, while they are covered.
    @Published private(set) var sendingTo: ChatTarget?
    @Published private var sessions: [UUID: ProtectSession] = [:]

    /// Adds pages after those scanned before, and gives them back.
    func add(_ images: [CGImage]) -> [Page] {
        let new = images.map { Page(image: $0) }
        pages += new
        return new
    }

    func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
        sessions[id] = nil
    }

    func clear() {
        pages = []
        sessions = [:]
    }

    func image(_ id: UUID) -> CGImage? {
        pages.first { $0.id == id }?.image
    }

    /// A page's protection, made the first time it is opened, before the
    /// screen that shows it.
    func session(_ id: UUID) -> ProtectSession {
        if let session = sessions[id] { return session }
        let session = ProtectSession(source: .scanned(id))
        sessions[id] = session
        return session
    }

    /// The protection of a page opened before; nil for one never opened.
    func opened(_ id: UUID) -> ProtectSession? { sessions[id] }

    /// Covers every page, makes them one PDF and opens the share sheet,
    /// where it can be sent or saved to Files. A page opened before goes as
    /// it was left there, once its copy is checked; any other is covered as
    /// Settings says. If a page cannot be covered, no PDF is made at all.
    func sharePDF() {
        guard making == nil, !pages.isEmpty else { return }
        let pages = pages
        Task {
            defer { making = nil }
            guard let finished = await covered(pages, failing: L("Page %d could not be covered, so no PDF was made.")) else {
                return
            }
            let pdf = await Task.detached(priority: .userInitiated) { ScanPDF.make(finished) }.value
            let name = "Snapfly " + Date.now.formatted(.iso8601.year().month().day()) + ".pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                guard let pdf else { throw CocoaError(.fileWriteUnknown) }
                try pdf.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                return QuickCoverer.shared.show(L("The copy could not be made."))
            }
            QuickCoverer.shared.sharing = SharedFile(url: url)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Covers every page as for the PDF and hands them to the app: one page
    /// straight to WhatsApp, or to an AI chat opened with it copied, else
    /// through the share sheet, where the app is tapped (`Handoff`). If a
    /// page cannot be covered, nothing goes at all.
    func send(to chat: ChatTarget) {
        guard making == nil, !pages.isEmpty else { return }
        let pages = pages
        sendingTo = chat
        Task {
            defer {
                making = nil
                sendingTo = nil
            }
            guard let finished = await covered(pages, failing: L("Page %d could not be covered, so nothing was sent.")) else {
                return
            }
            let pngs = await Task.detached(priority: .userInitiated) { finished.compactMap(Covering.png) }.value
            guard pngs.count == finished.count else {
                return QuickCoverer.shared.show(L("The copy could not be made."))
            }
            let name = "Snapfly " + Date.now.formatted(.iso8601.year().month().day())
            let shown = Handoff.shared.send(pngs, to: chat, named: name, opened: {
                QuickCoverer.shared.show(String(format: L("Copied for %@: tap the picture above the keyboard there, or hold the message field and tap Paste."), chat.name),
                                         for: 6)
            }) { went in
                if went { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
            if !shown { QuickCoverer.shared.show(L("The copy could not be made.")) }
        }
    }

    /// Every page covered, in their order: one opened before as it was left
    /// there, once its copy is checked, any other as Settings says. Nil, with
    /// a note saying which page, when one is not ready or cannot be covered.
    private func covered(_ pages: [Page], failing: String) async -> [CGImage]? {
        var done: [CGImage] = []
        for (index, page) in pages.enumerated() {
            making = index + 1
            if let session = sessions[page.id] {
                guard session.isReady, let copy = session.copy?.cgImage else {
                    QuickCoverer.shared.show(String(format: L("Page %d is not ready yet. Open it to check it."), index + 1), for: 4)
                    return nil
                }
                done.append(copy)
            } else {
                guard let made = await Covering.cover(page.image, Choice.details) else {
                    QuickCoverer.shared.show(String(format: failing, index + 1), for: 4)
                    return nil
                }
                done.append(made.image)
            }
        }
        return done
    }
}

/// The scan tab's first card: a page in a viewfinder on the soft green,
/// what scanning does, and the green button that opens the camera.
private struct ScanCard: View {
    let supported: Bool
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Viewfinder()
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(L("Scan a document"))
                    .font(.title2.weight(.bold))
                Text(L("Letters, forms and receipts, straight from the camera. Private details are covered on this iPhone before anything leaves it."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            Button(action: scan) {
                Label(L("Scan Document"), systemImage: "camera.viewfinder")
            }
            .buttonStyle(ProtectButtonStyle())
            .disabled(!supported)
            if !supported {
                Text(L("This iPhone cannot scan documents."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
/// number in the document and, once opened and its copy checked, the
/// shield the protected screenshots carry.
private struct PageCard: View {
    let image: CGImage
    let number: Int
    let session: ProtectSession?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
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
                if let session { Checked(session: session) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: L("Page %d"), number))
            .accessibilityValue(session?.isReady == true ? L("Protected") : "")
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
private struct DocumentScanner: UIViewControllerRepresentable {
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
