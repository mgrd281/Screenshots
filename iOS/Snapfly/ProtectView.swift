import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// A picture being protected, the page in the middle of a bright screen:
/// shown at once, its private places marked as they are found, then
/// covered and checked. Two fingers or a double tap zoom. Under the title a
/// small capsule says how it stands; beside the picture, one above another,
/// the apps to send to, then Photos, Files and the share sheet; along the
/// bottom, one bar of tools (Select to tap a place or a word and move,
/// resize or turn it; the marker, a box and the lasso to hide more by hand;
/// the eraser to take covers away; Undo and Redo). The menu holds Explain,
/// which sends the checked copy to the owner's own AI assistant, Details,
/// Copy, Send to Mac and Full Screen, which leaves the picture alone.
/// Holding the eye shows the picture as it was. Every way out waits until
/// the copy is made and checked, and asks first while places are still to
/// check; only that copy ever leaves. The picture itself stays as it was.
///
/// A scanned page is reviewed here too, as Review (`ReviewParts`): its own
/// bar along the top with Next, the status chip that opens the list of
/// places to check, the page large with the eye in its corner, the
/// document's pages small under it and one bar of tools, Covers or Page.
/// Once cleaned, the page wipes in over the page as it came, then its
/// covers sweep in; what is wrong is outlined in orange with its name.
/// Next opens Save and Share for the whole document.
///
/// A PDF project's page is covered here too, under its title "Page 1 of 6":
/// the grid button goes back to the overview of the pages, a swipe up or
/// down turns to the next page or the one before, it zooms up to eight
/// times, "3 / 12" shows over it as it opens, the project's strip is under
/// it, and Next saves and shares the PDF.
struct ProtectView: View {
    @StateObject private var session: ProtectSession
    @ObservedObject private var sync = SyncCenter.shared
    @ObservedObject private var scans = ScannedPages.shared
    /// A scanned page's place in its document; nil for any other picture.
    private let scan: ScanContext?
    /// A PDF project's page: its place and the ways to the others; nil for any other picture.
    private let project: ProjectContext?
    @State private var tool = EditTool.select
    @State private var selected: Int?
    @State private var markerWidth = HandShape.widths[1]
    @State private var eraserReach: CGFloat = 0.03
    @State private var showsOriginal = false
    @State private var reviewing = false
    @State private var explaining = false
    @State private var explainHeight = PresentationDetent.large
    @State private var showsOptions = false
    /// The choice of apps beside the picture, from the menu.
    @State private var choosingApps = false
    /// An AI chat tapped for a scanned page, while what to ask is chosen.
    @State private var asking: AssistantChoice?
    /// What was asked there, handed over once its sheet has gone.
    @State private var asked: (chat: ChatTarget, ask: ScanAsk?)?
    /// Only the picture, until a tap brings the controls back.
    @State private var focus = false
    /// The mark held down, whose menu shows.
    @State private var menuFor: ProtectionPlan.Mark?
    /// A way out waiting while places are still to check.
    @State private var waiting: Leaving?
    /// A way out tapped before the copy was ready, which goes once it is.
    @State private var pending: Leaving?
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
    /// A scanned page: where the divider stands while Before and After are
    /// compared, from 0 to 1 from the leading edge; nil while they are not.
    @State private var split: CGFloat?
    /// Each wipe of the cleaned page over the page as it came.
    @State private var wipes = 0
    /// While the wipe passes, the covers wait, to sweep in after it.
    @State private var sweeping = false
    /// Save and Share, for the whole document.
    @State private var saving = false
    /// The page whose corners are set again, with its picture.
    @State private var cropping: ScanCrop?
    /// The page to delete, while it is asked.
    @State private var deleting: ScanPageRef?
    /// A page to turn or cut again with covers drawn by hand, while it is asked.
    @State private var reshaping: ScanReshape?
    /// Pages from the camera or photos: the page they are taken again for,
    /// nil for pages added.
    @State private var replacing: UUID?
    @State private var shooting = false
    /// The page whose small print is taken again close up (`PageCamera`).
    @State private var closingUp: ScanPageRef?
    @State private var choosingPhotos = false
    @State private var picked: [PhotosPickerItem] = []
    /// The made-up scans' state shown once, for pictures made in CI.
    @State private var demoShown = false
    /// Review's bar of tools: the tools that cover, or the page's own.
    @State private var reviewMode = ReviewMode.cover
    /// The place tapped on the page, shown first in Review's list.
    @State private var listFocus: Int?
    /// The whole scan to discard, while it is asked.
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Right to left, the apps stand on the left, and the room for them too.
    @Environment(\.layoutDirection) private var direction

    init(source: ProtectSession.Source, scan: ScanContext? = nil, project: ProjectContext? = nil) {
        _session = StateObject(wrappedValue: ProtectSession.made(for: source))
        self.scan = scan
        self.project = project
        _reviewMode = State(initialValue: scan?.opensOnPage == true ? .page : .cover)
    }

    /// A scanned document's page, on Review: its own bar along the top,
    /// the status chip, the page large, its pages and one bar of tools.
    private var isReview: Bool { scan != nil }

    /// Reduce Motion, or the made-up scans played as it would (`ScanDemo`).
    private var still: Bool { reduceMotion || ScanDemo.still }

    /// The scanned page open, while it is in the document.
    private var scanPage: ScannedPages.Page? {
        scan.flatMap { scans.page($0.page) }
    }

    var body: some View {
        // The picture is the screen: the tab bar steps aside while it is open.
        lifecycle(scanDialogs(dialogs(scanning(sheets(screen)))))
            .toolbar(.hidden, for: .tabBar)
    }

    /// The picture, how it stands over it, the apps beside it and the tools
    /// under it.
    private var screen: some View {
        GeometryReader { geometry in
            ZStack {
                picture(chrome: chrome(geometry.safeAreaInsets, size: geometry.size))
                    .ignoresSafeArea()
                if isReview, !focus {
                    reviewEye(in: geometry)
                    openPlaces(in: geometry)
                }
                // Between the status and the tools, where hints and notes never move it.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !focus, !isReview {
                        AppRail(pending: pending, leave: leave)
                            .phoneGuideTarget(.actions)
                            .padding(.trailing, Self.railEdge)
                            .transition(still ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.top, statusHeight + 8)
                .padding(.bottom, docksHeight + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    if !focus { (isReview ? AnyView(reviewTop) : AnyView(top)).transition(.opacity) }
                    Spacer(minLength: 0)
                    bottom
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background((focus ? Color.black : SnapflyTokens.editorGround).ignoresSafeArea())
        .animation(motion, value: focus)
        .animation(motion, value: session.stage)
        .animation(motion, value: selected)
        .animation(motion, value: note)
        .animation(motion, value: hint)
        .animation(motion, value: split != nil)
        .animation(motion, value: session.documentPage != nil)
        .animation(motion, value: session.cleaning)
        .animation(motion, value: session.cleaned)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let project {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: project.overview) {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(L("All Pages"))
                    .accessibilityIdentifier("project-overview")
                }
            }
            if !isReview {
                ToolbarItem(placement: .topBarTrailing) { more }
            }
            if let project {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Next"), action: project.export)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("project-next")
                }
            }
        }
        // Review draws its own bar.
        .toolbar(focus || isReview ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(focus)
        .persistentSystemOverlays(focus ? .hidden : .automatic)
    }

    /// "Page 1 of 6" on a PDF's page, "Review" on a scanned page, else "Protect Picture".
    private var title: String {
        if let project { return String(format: L("Page %d of %d"), project.number, project.count) }
        return scan == nil ? L("Protect Picture") : L("Review")
    }

    private func sheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $reviewing, onDismiss: { listFocus = nil }) {
                if let scan {
                    ReviewListSheet(store: scans, current: scan.page, focus: listFocus, look: { look($0) }, retake: { id in
                        guard let page = scans.pages.first(where: { $0.id == id }) else { return }
                        // With Snapfly's own camera, the small print alone is taken again, close up.
                        if PageCamera.isOn, page.origin == .camera { closingUp = ScanPageRef(id: id) } else { retake(page) }
                    })
                } else {
                    ReviewSheet(session: session, show: show)
                }
            }
            .sheet(isPresented: $explaining) {
                ExplainSheet(session: session)
                    .presentationDetents([.medium, .large], selection: $explainHeight)
            }
            .sheet(isPresented: $choosingApps) { ChooseAppsSheet() }
            .sheet(item: $asking, onDismiss: handOverAsked) { choice in
                ScanAssistantSheet(chat: choice.chat) { asked = (choice.chat, $0) }
            }
            .sheet(isPresented: $showsOptions) {
                ToolOptions(tool: tool, markerWidth: $markerWidth, eraserReach: $eraserReach, session: session)
                    .presentationDetents([.height(300), .medium])
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

    /// A scanned page's sheets: Save and Share, its corners set again, and
    /// the camera or photos to add pages or take one again.
    private func scanning(_ content: some View) -> some View {
        content
            .sheet(isPresented: $saving) { ScanSaveSheet() }
            .fullScreenCover(item: $cropping) { crop in
                if let page = scans.page(crop.id) {
                    ScanCornerEditor(image: crop.picture, quad: page.quad ?? .whole) { quad in
                        cropping = nil
                        // Corners waited for are set even where they stay as Vision put them.
                        guard let quad, quad != page.quad ?? .whole || page.state == .needsCorners else { return }
                        scans.setCorners(crop.id, quad)
                    }
                } else {
                    Color.black.onAppear { cropping = nil }
                }
            }
            .fullScreenCover(isPresented: $shooting) {
                if PageCamera.isOn {
                    PageCamera { images in
                        shooting = false
                        took(camera: images, whole: true)
                    }
                } else {
                    DocumentScanner { images in
                        shooting = false
                        took(camera: images)
                    }
                    .ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $closingUp) { wanted in
                PageCamera(closeUp: true) { images in
                    closingUp = nil
                    guard let detail = images.first else { return }
                    Task { await tookCloser(detail, for: wanted.id) }
                }
            }
            .photosPicker(isPresented: $choosingPhotos, selection: $picked, maxSelectionCount: replacing == nil ? 20 : 1,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                let target = replacing
                picked = []
                Task { await took(photos: items, replacing: target) }
            }
    }

    private func dialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(checkTitle,
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

    /// A scanned page's questions, in a chain of their own so neither chain
    /// grows too long to type-check: deleting the page, and turning or
    /// cutting it again where covers were drawn on it by hand.
    private func scanDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(deleteTitle,
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { ref in
                Button(L("Delete Page"), role: .destructive) {
                    withAnimation(motion) { scans.remove(ref.id) }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("The other pages stay as they are."))
            }
            .confirmationDialog(L("Discard the whole scan?"), isPresented: $discarding, titleVisibility: .visible) {
                Button(L("Discard Scan"), role: .destructive) {
                    scans.clear()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Every page goes, with what was covered on it."))
            }
            .confirmationDialog(L("Covers drawn by hand go"),
                                isPresented: Binding(get: { reshaping != nil }, set: { if !$0 { reshaping = nil } }),
                                titleVisibility: .visible, presenting: reshaping) { change in
                Button(change.title) { reshaped(change) }
                Button(L("Cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("The page's private details are found again, and what you covered by hand on it is taken away."))
            }
    }

    private func lifecycle(_ content: some View) -> some View {
        content
            .phoneGuide(on: .shot)
            .onAppear {
                // Preparing other photos waits, so this one opens fast.
                PhotoIndexer.shared.hold()
                session.start()
                showCleaning()
                readEveryPage()
                PhoneGuide.shared.screen = .shot
                PhoneGuide.shared.happened(.openedShot)
            }
            .onDisappear {
                PhotoIndexer.shared.release()
                PhoneGuide.shared.screen = .library
            }
            .onChange(of: tool) { _, tool in
                selected = nil
                split = nil
                UISelectionFeedbackGenerator().selectionChanged()
                hint = hintText(for: tool)
            }
            .onChange(of: session.isReady) { _, ready in
                if ready { showDemo() }
                // A way tapped while the copy was made goes now.
                guard ready, let way = pending else { return }
                pending = nil
                leave(way)
            }
            .onChange(of: session.original != nil) { _, shown in
                if shown { showCleaning() }
            }
            .onChange(of: scans.pages.map(\.state)) { _, _ in readEveryPage() }
            .task(id: wipes) {
                guard wipes > 0 else { return }
                sweeping = true
                try? await Task.sleep(for: .milliseconds(still ? 300 : 500))
                sweeping = false
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

    /// How many places are still to check, one or more, before a picture leaves.
    private var checkTitle: String {
        let left: Int = session.plan.tally.toCheck
        return left == 1 ? L("1 place still to check") : String(format: L("%d places still to check"), left)
    }

    /// The question before a page is deleted, with its number.
    private var deleteTitle: String {
        guard let deleting else { return "" }
        let number: Int = (scans.index(of: deleting.id) ?? 0) + 1
        return String(format: L("Delete page %d?"), number)
    }

    private var motion: Animation {
        still ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    /// How far the apps stand in from the screen's trailing edge, and the
    /// room between them and the picture.
    private static let railEdge: CGFloat = 12
    private static let railGap: CGFloat = 12

    /// What the floating controls cover on each side, so the picture is
    /// fitted between them, left of the apps; only the safe areas in Full
    /// Screen. On Review there are no apps: the page takes about 86 % of
    /// the width.
    private func chrome(_ safe: EdgeInsets, size: CGSize) -> UIEdgeInsets {
        let side: CGFloat = 8
        if focus {
            return UIEdgeInsets(top: safe.top + side, left: safe.leading + side, bottom: safe.bottom + side,
                                right: safe.trailing + side)
        }
        if isReview {
            let width = size.width + safe.leading + safe.trailing
            let margin = max(16, (width * 0.07).rounded())
            return UIEdgeInsets(top: safe.top + statusHeight + 10, left: safe.leading + margin,
                                bottom: safe.bottom + docksHeight + 10, right: safe.trailing + margin)
        }
        let leading = safe.leading + 16
        let trailing = safe.trailing + Self.railEdge + AppRail.width + Self.railGap
        let rightToLeft = direction == .rightToLeft
        return UIEdgeInsets(top: safe.top + statusHeight + 12, left: rightToLeft ? trailing : leading,
                            bottom: safe.bottom + docksHeight + 12, right: rightToLeft ? leading : trailing)
    }

    // MARK: The picture

    @ViewBuilder private func picture(chrome: UIEdgeInsets) -> some View {
        // While a scanned page's cleaning wipes in, the page alone: its
        // covers sweep in after it.
        if let shown = showsOriginal || sweeping ? session.original : session.copy ?? session.original ?? session.preview {
            MarkCanvas(image: shown, marks: showsOriginal || sweeping ? [] : session.plan.marks,
                       checking: Set(session.plan.marks.filter(session.plan.needsCheck).map(\.id)),
                       isCopy: !showsOriginal && !sweeping && session.copy != nil, tool: tool, selected: selected,
                       markerWidth: markerWidth, eraserReach: eraserReach, chrome: chrome,
                       animated: !still, reveal: reveal, before: scanPage?.before,
                       split: showsOriginal ? nil : split, wipes: wipes, holdsBefore: scanPage?.shown == false,
                       issues: showsOriginal ? [] : scanPage?.places ?? [],
                       issueNames: showsOriginal ? [] : issueNames, checksInOrange: isReview,
                       pagesSideways: isReview, maxZoom: zoomLimit,
                       arrival: arrival, actions: actions)
                .accessibilityAction(named: L("Details")) { reviewing = true }
        } else if case .failed = session.stage {
            ContentUnavailableView(L("The picture could not be read."), systemImage: "exclamationmark.triangle")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Eight times on a PDF's page, six on any other picture.
    private var zoomLimit: CGFloat {
        project == nil ? 6 : 8
    }

    /// Where a PDF's page or a scanned page came in from.
    private var arrival: CGFloat {
        project?.arrival ?? scan?.arrival ?? 0
    }

    /// Each fault's short name, in the order of its outline on the page.
    private var issueNames: [String] {
        (scanPage?.issues ?? []).filter { $0.area != nil }.map(\.kind.tag)
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
            },
            split: { split = $0 },
            canPage: { step in
                if let project { return project.canStep(step) }
                guard let scan, let index = scans.index(of: scan.page) else { return false }
                return scans.pages.indices.contains(index + step)
            },
            page: { step in
                if let project { return project.step(step) }
                guard let scan, let index = scans.index(of: scan.page), scans.pages.indices.contains(index + step) else { return }
                scan.open(scans.pages[index + step].id)
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
            // On Review, a place still to check opens the list, there.
            if isReview, tool == .select, session.plan.needsCheck(mark) {
                listFocus = mark.id
                reviewing = true
                return
            }
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

    /// Under the title: how the picture stands, the eye in line with the
    /// apps, Before and After over the page while they are compared, and
    /// how to use the tool just chosen.
    private var top: some View {
        VStack(spacing: 6) {
            VStack(spacing: 8) {
                ZStack {
                    capsule
                        .padding(.horizontal, Self.railEdge + AppRail.width + 8)
                    eye
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Self.railEdge)
                }
                .padding(.top, 6)
                // A photographed document's offer to clean it, above the page, which makes room for it.
                if scan == nil {
                    DocumentOfferBanner(session: session)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .measuredHeight($statusHeight)
            if let project {
                PageIndicator(number: project.number, count: project.count)
            }
            if split != nil {
                CompareLabels()
                    .transition(.opacity)
            }
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

    /// How the picture stands, in its capsule; while a scanned page is made
    /// ready, what is being done to it.
    @ViewBuilder private var capsule: some View {
        if let page = scanPage, page.state != .ready {
            ScanWorking(state: page.state, retake: { retake(page) }, corners: { reshape(.crop(page.id)) })
        } else {
            PrivacyStatus(stage: session.stage, tally: session.plan.tally, hints: scanPage?.issues.count ?? 0, chip: isReview,
                          open: { reviewing = true }, dontWait: session.dontWait, retry: session.retry)
        }
    }

    /// Over the bottom: what was done or went wrong, the place selected,
    /// then the tools; in Full Screen, only the way back.
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
                VStack(spacing: 8) {
                    if let scan, let page = scanPage {
                        pages(scan, page)
                    } else if let project {
                        ProjectPageStrip(store: .shared, current: project.page, open: project.open, add: project.add,
                                         blank: project.blank, scanned: project.scanned)
                            .padding(.horizontal, 16)
                    }
                    if !isReview { docks }
                }
                .measuredHeight($docksHeight)
                .transition(still ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 4)
    }

    /// Under a scanned page: the document's pages, small, then Review's
    /// one bar of tools, Covers or Page.
    @ViewBuilder private func pages(_ scan: ScanContext, _ page: ScannedPages.Page) -> some View {
        ReviewPages(store: scans, current: scan.page, open: { hasOpen($0) },
                    show: { if $0 != scan.page { scan.open($0) } }, add: { add($0) },
                    turn: { reshape(.turn($0)) }, crop: { reshape(.crop($0)) },
                    delete: { deleting = ScanPageRef(id: $0) })
        ReviewToolbar(mode: $reviewMode, tool: $tool,
                      canUndo: session.plan.canUndo, canRedo: session.plan.canRedo,
                      undo: {
                          session.undo()
                          selected = nil
                      },
                      redo: {
                          session.redo()
                          selected = nil
                      },
                      options: { showsOptions = true },
                      comparing: split != nil, colour: scans.mode,
                      ready: page.state == .ready && session.original != nil, canTurn: page.way != nil,
                      compare: { compare() }, crop: { reshape(.crop(page.id)) }, turn: { reshape(.turn(page.id)) },
                      choose: { scans.setMode($0) }, delete: { deleting = ScanPageRef(id: page.id) })
            .disabled(session.original == nil && page.state == .ready)
            .onChange(of: reviewMode) { _, mode in
                // The page's tools are for the page as it is: nothing is drawn meanwhile.
                if mode == .page { tool = .select }
            }
    }

    /// Whether a page has something still open: a place to check, or a fault.
    private func hasOpen(_ page: ScannedPages.Page) -> Bool {
        !page.issues.isEmpty || (scans.opened(page.id)?.plan.tally.toCheck ?? 0) > 0
    }

    // MARK: Review

    /// Review's bar along the top and the status chip under it, then Before
    /// and After while they are compared, and how to use the tool just
    /// chosen.
    private var reviewTop: some View {
        VStack(spacing: 6) {
            VStack(spacing: 8) {
                ReviewHeader(page: (scan.flatMap { scans.index(of: $0.page) } ?? 0) + 1, pages: scans.pages.count,
                             canGoOn: !scans.pages.isEmpty, back: { dismiss() }, next: { saving = true }) {
                    Menu { reviewMenu } label: { ReviewMenuLabel() }
                        .accessibilityLabel(L("More"))
                        .accessibilityIdentifier("review-more")
                }
                capsule
            }
            .padding(.top, 4)
            .measuredHeight($statusHeight)
            if split != nil {
                CompareLabels()
                    .transition(.opacity)
            }
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

    /// Ask AI, every page, the page taken again, and what was in the menu
    /// before; last, apart and in red, the whole scan discarded.
    @ViewBuilder private var reviewMenu: some View {
        Button {
            explaining = true
        } label: {
            Label(L("Ask AI"), systemImage: "sparkles")
        }
        .disabled(session.original == nil)
        Button {
            dismiss()
        } label: {
            Label(L("All Pages"), systemImage: "square.grid.2x2")
        }
        if let page = scanPage {
            Button {
                retake(page)
            } label: {
                Label(L("Retake"), systemImage: "camera")
            }
        }
        Divider()
        if sync.canSend {
            Button { leave(.mac) } label: { Label(Leaving.mac.title, systemImage: Leaving.mac.symbol) }
                .disabled(sent)
        }
        Button {
            tool = .select
            focus = true
        } label: {
            Label(L("Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
        }
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
        Divider()
        Button(role: .destructive) {
            discarding = true
        } label: {
            Label(L("Discard Scan"), systemImage: "trash")
        }
    }

    /// Where the page stands on the screen, fitted into the room the bars
    /// leave, as the canvas fits it while it is not zoomed; in the view's
    /// own space, from its leading edge.
    private func pageRect(in geometry: GeometryProxy) -> CGRect? {
        guard let image = session.original ?? session.preview, image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let safe = geometry.safeAreaInsets
        let room = chrome(safe, size: geometry.size)
        let width = geometry.size.width + safe.leading + safe.trailing
        let height = geometry.size.height + safe.top + safe.bottom
        let space = CGSize(width: width - room.left - room.right, height: height - room.top - room.bottom)
        guard space.width > 0, space.height > 0 else { return nil }
        let scale = min(space.width / image.size.width, space.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: room.left + (space.width - size.width) / 2 - safe.leading,
                      y: room.top + (space.height - size.height) / 2 - safe.top,
                      width: size.width, height: size.height)
    }

    /// The eye in the page's bottom trailing corner: a tap shows the page
    /// without its covers, and again with them.
    @ViewBuilder private func reviewEye(in geometry: GeometryProxy) -> some View {
        if let page = pageRect(in: geometry), session.original != nil, split == nil {
            Button {
                showsOriginal.toggle()
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: showsOriginal ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .editorGlass(in: Circle())
                    .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: page.maxX - 24, y: page.maxY - 24)
            .accessibilityLabel(showsOriginal ? L("Show With Covers") : L("Show Without Covers"))
            .accessibilityIdentifier("review-eye")
        }
    }

    /// For VoiceOver, each place still to check on the page is an element
    /// of its own, "Rechnungsnummer, zu prüfen", to cover or leave.
    @ViewBuilder private func openPlaces(in geometry: GeometryProxy) -> some View {
        if let page = pageRect(in: geometry), !showsOriginal {
            ForEach(session.plan.marks.filter(session.plan.needsCheck)) { mark in
                Color.clear
                    .frame(width: max(mark.rect.width * page.width, 24), height: max(mark.rect.height * page.height, 24))
                    .position(x: page.minX + mark.rect.midX * page.width, y: page.minY + (1 - mark.rect.midY) * page.height)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("\(ReviewListSheet.name(of: mark)), \(L("To check"))")
                    .accessibilityAction(named: L("Cover")) { session.set([mark.id], covered: true) }
                    .accessibilityAction(named: L("Leave")) { session.set([mark.id], covered: false) }
            }
        }
    }

    /// Every page ready is read as soon as Review opens, so what the owner
    /// keeps in Always Hide is found on all of them, and the list and the
    /// pages' dots say what is open everywhere.
    private func readEveryPage() {
        guard isReview else { return }
        for page in scans.pages where page.state == .ready {
            scans.session(page.id).start()
        }
    }

    /// A fault's page with its own tools: Page in the bar.
    private func look(_ page: UUID) {
        guard let scan else { return }
        if page == scan.page {
            withAnimation(motion) { reviewMode = .page }
        } else {
            scan.look(page)
        }
    }

    /// The one bar of tools, kept in place while drawing.
    private var docks: some View {
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

    /// Explain, Details, Copy, Send to Mac while a Mac is there, Full
    /// Screen, the choice of apps, and taking back what was changed, each as
    /// one change to undo.
    private var more: some View {
        Menu {
            Button {
                explaining = true
            } label: {
                Label(L("Explain"), systemImage: "sparkles")
            }
            .disabled(session.original == nil)
            Button {
                reviewing = true
            } label: {
                Label(L("Details"), systemImage: "list.bullet")
            }
            .disabled(session.plan.marks.isEmpty)
            Divider()
            Button { leave(.copy) } label: { Label(Leaving.copy.title, systemImage: Leaving.copy.symbol) }
            if sync.canSend {
                Button { leave(.mac) } label: { Label(Leaving.mac.title, systemImage: Leaving.mac.symbol) }
                    .disabled(sent)
            }
            Button {
                tool = .select
                focus = true
            } label: {
                Label(L("Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Divider()
            if let project {
                Button(action: project.pictures) {
                    Label(L("Save as Pictures"), systemImage: "photo.on.rectangle")
                }
                Divider()
            }
            Button {
                choosingApps = true
            } label: {
                Label(L("Send to Apps"), systemImage: "slider.horizontal.3")
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

    // MARK: Scanned pages

    /// A scanned page's cleaning, shown once: the cleaned page wipes in
    /// over the page as it came, then its covers sweep in.
    private func showCleaning() {
        guard session.original != nil, let page = scanPage, !page.shown else { return }
        wipes += 1
        scans.markShown(page.id)
    }

    /// Before and After, the divider in the middle; again, the page alone.
    private func compare() {
        selected = nil
        split = split == nil ? 0.5 : nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Pages from the camera or from photos, added or taking a page's place.
    private func add(_ adding: ScanAdding) {
        switch adding {
        case .camera(let page):
            replacing = page
            shooting = true
        case .photos(let page):
            replacing = page
            choosingPhotos = true
        }
    }

    /// A page taken again as it was taken: with the camera, or from photos.
    private func retake(_ page: ScannedPages.Page) {
        let camera = page.origin == .camera && VNDocumentCameraViewController.isSupported
        add(camera ? .camera(replacing: page.id) : .photos(replacing: page.id))
    }

    /// The camera's pages: in the place of the page taken again, which the
    /// editor follows, or after the others, the first of them opened.
    private func took(camera images: [CGImage], whole: Bool = false) {
        let target = replacing
        replacing = nil
        guard !images.isEmpty else { return }
        if let target {
            scans.replace(target, camera: images, whole: whole)
        } else if let first = scans.add(camera: images, whole: whole).first {
            scan?.open(first.id)
        }
    }

    /// A close-up of a page's small print, laid in where it reads more surely.
    private func tookCloser(_ detail: CGImage, for page: UUID) async {
        if await scans.takeCloser(page, detail: detail) {
            note = EditorNote(text: L("Close-up used"))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            failed(L("Close-up not used"))
        }
    }

    /// The photos chosen, as the camera's pages are.
    private func took(photos items: [PhotosPickerItem], replacing target: UUID?) async {
        replacing = nil
        let photos = await ScanPhoto.read(items)
        guard !photos.isEmpty else { return failed(L("The picture could not be read.")) }
        if let target {
            scans.replace(target, photos: photos)
        } else if let first = scans.add(photos: photos).first {
            scan?.open(first.id)
        }
    }

    /// A page turned or cut again has its private details found again:
    /// where something was covered on it by hand, it asks first.
    private func reshape(_ change: ScanReshape) {
        if scans.opened(change.page)?.plan.hasHand == true { reshaping = change } else { reshaped(change) }
    }

    private func reshaped(_ change: ScanReshape) {
        switch change {
        case .turn(let page):
            scans.turn(page)
        case .crop(let page):
            // The picture as it came, decoded once, as large as the corner editor shows it.
            guard let picture = scans.picture(page) else { return failed(L("The picture could not be read.")) }
            cropping = ScanCrop(id: page, picture: picture)
        }
    }

    /// For pictures made in CI: Before and After compared, or Save and
    /// Share open, once the page's copy is checked (`ScanDemo`).
    private func showDemo() {
        guard scan != nil, !demoShown else { return }
        demoShown = true
        if ScanDemo.compares { split = 0.5 }
        if ScanDemo.opensSheet { saving = true }
        if ScanDemo.opensList { reviewing = true }
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
        // For a scanned page, an AI chat first asks what to ask with it.
        case .app(let chat) where scan != nil && chat.isAI: asking = AssistantChoice(chat: chat)
        case .app(let chat): send(to: chat)
        }
    }

    /// What was chosen for the AI chat, once its sheet has gone.
    private func handOverAsked() {
        guard let asked else { return }
        self.asked = nil
        send(to: asked.chat, asking: asked.ask)
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

    /// The share sheet, with the copy alone as a PNG file of its own, with
    /// nothing of the original's notes in it.
    private func share() {
        guard session.isReady, let png = session.png else { return }
        let shown = Handoff.shared.send([png], to: nil, named: baseName) { went in
            if went { session.left() }
        }
        if !shown { failed(L("The copy could not be made."), retry: .share) }
    }

    /// Into Photos, as a new picture, then Photos opens to show it.
    private func save() {
        guard session.isReady, let png = session.png else { return }
        Task {
            do {
                try await Covering.save(png)
                done(L("Saved to Photos"))
                if let photos = URL(string: "photos-redirect://") { _ = await UIApplication.shared.open(photos) }
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

    /// The copy handed to the app: straight to WhatsApp, an AI chat opened
    /// with it copied, to paste, else through the share sheet, where the app
    /// is tapped (`Handoff`); with a question, the share sheet with it.
    private func send(to chat: ChatTarget, asking ask: ScanAsk? = nil) {
        guard session.isReady, let png = session.png else { return }
        let shown = Handoff.shared.send([png], to: chat, named: baseName, asking: ask?.prompt, opened: {
            note = EditorNote(text: String(format: L("Copied for %@: tap the picture above the keyboard there, or hold the message field and tap Paste."), chat.name))
        }) { went in
            if went { session.left() }
        }
        if !shown { failed(L("The copy could not be made."), retry: .app(chat)) }
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
        return mark.origin == .hand ? L("Hidden by hand") : L("Your details and rules")
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
