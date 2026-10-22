import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

// MARK: The editor's pages

/// A page of a PDF project in the editor: which page it is of how many, and
/// the ways to the others: a swipe up or down, the strip, the overview, and
/// Next, to save and share the PDF.
struct ProjectContext {
    let page: UUID
    let number: Int
    let count: Int
    /// Where the page came in from: from below (1), from above (-1), or neither.
    let arrival: CGFloat
    let open: (UUID) -> Void
    let canStep: (Int) -> Bool
    let step: (Int) -> Void
    let overview: () -> Void
    let export: () -> Void
    let pictures: () -> Void
    let add: (ProjectAdding) -> Void
    let blank: () -> Void
    let scanned: () -> Void
}

/// The editor for a PDF project's pages, one page at a time: the same
/// editor as a photo's or a scanned page's, with the project's strip under
/// it. A swipe up opens the next page, a swipe down the one before, while
/// the page is shown whole; pinched or double-tapped, it zooms up to eight
/// times. When the page open is taken away, the page in its place opens, or
/// the one before it; with none left, the overview shows again.
struct ProjectEditor: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var current: UUID
    @State private var arrival: CGFloat = 0
    @State private var exporting = false
    @State private var adding: ProjectAdding?
    @State private var sharing: SharedFiles?
    /// Why the pages could not be saved as pictures.
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(page: UUID) {
        _current = State(initialValue: page)
    }

    private var pages: [ProjectPage] { store.project?.pages ?? [] }
    private var index: Int { pages.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        ProtectView(source: .page(current), project: context)
            .id("\(current.uuidString)-\(store.revisions[current] ?? 0)")
            .navigationBarBackButtonHidden(true)
            .onAppear { store.setOpenPage(current) }
            .onChange(of: pages.map(\.id)) { before, ids in
                guard !ids.contains(current) else { return }
                guard let place = before.firstIndex(of: current), !ids.isEmpty else { return leave() }
                show(ids[min(place, ids.count - 1)], from: 0)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    ProjectWorking()
                    ProjectToastView()
                }
                .padding(.bottom, 150)
            }
            .sheet(isPresented: $exporting) { ProjectExportSheet() }
            .sheet(item: $sharing) { files in
                ShareFilesSheet(files: files)
                    .ignoresSafeArea()
            }
            .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L("OK"), role: .cancel) {}
            }
            .modifier(ProjectAdder(adding: $adding, index: index + 1))
    }

    private var context: ProjectContext {
        let index = self.index, count = pages.count
        return ProjectContext(
            page: current, number: index + 1, count: count, arrival: arrival,
            open: { id in
                guard let to = pages.firstIndex(where: { $0.id == id }), id != current else { return }
                show(id, from: to > index ? 1 : -1)
            },
            canStep: { step in pages.indices.contains(index + step) },
            step: { step in
                guard pages.indices.contains(index + step) else { return }
                show(pages[index + step].id, from: CGFloat(step))
            },
            overview: leave,
            export: { exporting = true },
            pictures: savePictures,
            add: { adding = $0 },
            blank: {
                if let page = store.addBlank(at: index + 1) { show(page, from: 1) }
            },
            scanned: { store.addScanned(at: index + 1) })
    }

    /// Another page, its protection made first, before its editor is drawn.
    private func show(_ page: UUID, from side: CGFloat) {
        _ = store.session(page)
        arrival = side
        current = page
        store.setOpenPage(page)
        UISelectionFeedbackGenerator().selectionChanged()
        if let number = pages.firstIndex(where: { $0.id == page }) {
            UIAccessibility.post(notification: .pageScrolled, argument: String(format: L("Page %d of %d"), number + 1, pages.count))
        }
    }

    /// Back to the overview of the pages.
    private func leave() {
        store.setOpenPage(nil)
        dismiss()
    }

    /// Every page covered, as pictures, to save or share.
    private func savePictures() {
        guard store.making == nil else { return }
        Task {
            do {
                let pngs = try await store.pngs()
                let base = ScanNaming.safe(store.project?.name ?? "Snapfly")
                let folder = FileManager.default.temporaryDirectory
                var urls: [URL] = []
                for (number, png) in pngs.enumerated() {
                    let url = folder.appendingPathComponent(pngs.count == 1 ? "\(base).png" : "\(base) \(number + 1).png")
                    try png.write(to: url, options: [.atomic, .completeFileProtection])
                    urls.append(url)
                }
                sharing = SharedFiles(urls: urls)
            } catch {
                failure = (error as? ScanProblem)?.message ?? L("The copy could not be made.")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: Adding pages

/// Where pages come from when they are added.
enum ProjectAdding: Hashable, Identifiable {
    case photos, files, camera

    var id: Self { self }
}

/// The Add menu's items: from Photos, from Files, scanned with the camera,
/// an empty page, and the Scan tab's pages while there are some.
struct ProjectAddItems: View {
    let choose: (ProjectAdding) -> Void
    let blank: () -> Void
    let scanned: () -> Void
    @ObservedObject private var scans = ScannedPages.shared

    var body: some View {
        Button { choose(.photos) } label: { Label(L("From Photos"), systemImage: "photo.on.rectangle.angled") }
        Button { choose(.files) } label: { Label(L("From Files"), systemImage: "folder") }
        if VNDocumentCameraViewController.isSupported {
            Button { choose(.camera) } label: { Label(L("Scan"), systemImage: "doc.viewfinder") }
        }
        Button(action: blank) { Label(L("Blank Page"), systemImage: "doc") }
        if scans.pages.contains(where: { $0.state == .ready }) {
            Button(action: scanned) { Label(L("Scanned Pages"), systemImage: "doc.on.doc") }
        }
    }
}

/// Photos, files or the camera, for pages added after the page at `index`.
struct ProjectAdder: ViewModifier {
    @Binding var adding: ProjectAdding?
    let index: Int?
    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: shows(.photos), selection: $picked, maxSelectionCount: 100,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                let at = index
                Task { await ProjectStore.shared.add(.photos(items), at: at) }
            }
            .fileImporter(isPresented: shows(.files), allowedContentTypes: [.pdf, .jpeg, .png, .heic, .image],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                let at = index
                Task { await ProjectStore.shared.add(.files(urls), at: at) }
            }
            .fullScreenCover(isPresented: shows(.camera)) {
                DocumentScanner { images in
                    adding = nil
                    guard !images.isEmpty else { return }
                    let at = index
                    Task { await ProjectStore.shared.add(.pictures(images, origin: .scan), at: at) }
                }
                .ignoresSafeArea()
            }
    }

    private func shows(_ way: ProjectAdding) -> Binding<Bool> {
        Binding(get: { adding == way }, set: { if !$0, adding == way { adding = nil } })
    }
}

extension ProjectStore {
    /// The Scan tab's pages, cleaned, added as scans of the kind its first page shows.
    func addScanned(at index: Int?) {
        let scans = ScannedPages.shared
        let images = scans.pages.compactMap { $0.state == .ready ? $0.cleaned : nil }
        guard !images.isEmpty else { return }
        let kind = scans.title?.kind
        Task { await add(.pictures(images, origin: .scan, kind: kind), at: index) }
    }
}

// MARK: The strip

/// The project's pages under the page open, in a strip of glass, each small
/// in its own shape, the one open ringed in green: a tap opens a page;
/// dragged onto another it takes that one's place; held, it offers Turn,
/// Duplicate and Delete, and VoiceOver moves it earlier or later. The plus
/// adds pages.
struct ProjectPageStrip: View {
    @ObservedObject var store: ProjectStore
    let current: UUID
    let open: (UUID) -> Void
    let add: (ProjectAdding) -> Void
    let blank: () -> Void
    let scanned: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pages: [ProjectPage] { store.project?.pages ?? [] }

    var body: some View {
        HStack(spacing: 2) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            thumb(page, index: index)
                                .id(page.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
                .onAppear { reader.scrollTo(current, anchor: .center) }
                .onChange(of: current) { _, page in
                    withAnimation(reduceMotion ? nil : .snappy) { reader.scrollTo(page, anchor: .center) }
                }
            }
            .frame(height: 52)
            Menu {
                ProjectAddItems(choose: add, blank: blank, scanned: scanned)
            } label: {
                DockIcon(symbol: "plus")
            }
            .accessibilityLabel(L("Add Pages"))
            .accessibilityIdentifier("project-strip-add")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .editorGlass(in: RoundedRectangle(cornerRadius: SnapflyTokens.scanStripRadius, style: .continuous))
    }

    /// The page small, ringed while it is open; apart from the button, so
    /// the compiler checks each in good time.
    private func paper(_ page: ProjectPage, chosen: Bool) -> some View {
        PagePaper(source: page.source, aspect: store.aspect(page.source), turns: page.turns,
                  locked: store.isLocked(page), corner: 3)
            .frame(width: 34, height: 46)
            .overlay {
                RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous)
                    .strokeBorder(chosen ? SnapflyTokens.protectTint : Color.clear, lineWidth: 2)
                    .padding(-3)
            }
            .frame(width: SnapflyTokens.touch, height: 52)
            .contentShape(Rectangle())
    }

    private func thumb(_ page: ProjectPage, index: Int) -> some View {
        let chosen = page.id == current
        let base = Button { open(page.id) } label: { paper(page, chosen: chosen) }
        .buttonStyle(.plain)
        .draggable(page.id.uuidString) {
            PagePaper(source: page.source, aspect: store.aspect(page.source), turns: page.turns, locked: false, corner: 3)
                .frame(width: 34, height: 46)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first.flatMap(UUID.init(uuidString:)), moved != page.id,
                  let place = store.project?.index(of: page.id) else { return false }
            withAnimation(reduceMotion ? nil : .snappy) { store.move(moved, to: place) }
            UISelectionFeedbackGenerator().selectionChanged()
            return true
        }
        .contextMenu {
            Button { store.turn([page.id]) } label: { Label(L("Turn"), systemImage: "rotate.right") }
            Button { store.duplicate([page.id]) } label: { Label(L("Duplicate"), systemImage: "plus.square.on.square") }
            Button(role: .destructive) { store.delete([page.id]) } label: { Label(L("Delete Page"), systemImage: "trash") }
        }
        let named = base
            .accessibilityLabel(String(format: L("Page %d of %d"), index + 1, pages.count))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("project-thumb-\(index + 1)")
        return named
            .accessibilityAction(named: L("Move Earlier")) {
                if index > 0 { store.move(page.id, to: index - 1) }
            }
            .accessibilityAction(named: L("Move Later")) {
                if index < pages.count - 1 { store.move(page.id, to: index + 1) }
            }
            .accessibilityAction(named: L("Delete Page")) { store.delete([page.id]) }
    }
}

// MARK: A page small

/// A page small in its own shape, as it came, white under it, turned as the
/// owner turned it on a spring, fitted to the room it is given; a locked
/// PDF's page shows a lock until its password is given.
struct PagePaper: View {
    let source: PageSource
    /// Its width over its height, upright as it came.
    let aspect: CGFloat
    /// Quarter turns clockwise, counted on without wrapping, so a turn always goes clockwise.
    let turns: Int
    let locked: Bool
    var corner: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let lying = abs(turns) % 2 == 1
            let shown = lying ? 1 / max(aspect, 0.01) : aspect
            let room = geometry.size
            let fit = shown > room.width / max(room.height, 1)
                ? CGSize(width: room.width, height: room.width / shown)
                : CGSize(width: room.height * shown, height: room.height)
            let upright = lying ? CGSize(width: fit.height, height: fit.width) : fit
            PageThumb(source: source, locked: locked)
                .id(source)
                .frame(width: upright.width, height: upright.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .rotationEffect(.degrees(Double(turns) * 90))
                .frame(width: fit.width, height: fit.height)
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                .frame(width: room.width, height: room.height)
        }
        .animation(reduceMotion || ScanDemo.still ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85),
                   value: turns)
        .accessibilityHidden(true)
    }
}

/// A page's small picture, drawn when it is first shown and kept a while.
struct PageThumb: View {
    let source: PageSource
    let locked: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            SnapflyTokens.morePaper
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if locked {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.morePaperLabel)
            }
        }
        .task(id: locked) {
            if let drawn = await ProjectStore.shared.thumbnail(source) { image = drawn }
        }
    }
}

// MARK: Notes over the pages

/// What was just done to the pages, in a dark capsule over the bottom, with
/// Undo, then Redo, for 4 seconds.
struct ProjectToastView: View {
    @ObservedObject private var store = ProjectStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { reduceMotion || ScanDemo.still }

    var body: some View {
        Group {
            if let toast = store.toast {
                HStack(spacing: 14) {
                    Text(toast.undone ? L("Undone") : toast.text)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Button(toast.undone ? L("Redo") : L("Revert")) { store.toastUndo() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.projectToastAction)
                        .frame(minHeight: SnapflyTokens.touch)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("project-toast-undo")
                }
                .foregroundStyle(.white)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .background(SnapflyTokens.projectToast, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.horizontal, 16)
                .transition(still ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project-toast")
                .onAppear { UIAccessibility.post(notification: .announcement, argument: toast.text) }
            }
        }
        .animation(still ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
        .task(id: store.toast) {
            guard store.toast != nil, !ProjectDemo.keepsToast else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { store.toast = nil }
        }
    }
}

/// While pages are added or covered: how far it is, in the floating pill.
struct ProjectWorking: View {
    @ObservedObject private var store = ProjectStore.shared

    var body: some View {
        if let progress = store.making ?? store.adding {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(format: store.making != nil ? L("Covering page %d of %d …") : L("Adding %d of %d …"),
                            min(progress.done + 1, progress.total), progress.total))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .floatingPill()
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("project-working")
        }
    }
}

/// "3 / 12" over the page as it opens, fading once it has been seen.
struct PageIndicator: View {
    let number: Int
    let count: Int
    @State private var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "\(number) / \(count)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .editorGlass(in: Capsule())
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.4), value: shown)
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                shown = false
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("project-page-indicator")
    }
}
