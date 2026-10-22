import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// What the full-screen cover over the app shows: the project's pages, or
/// nothing in the moment it closes.
struct ProjectCover: View {
    @ObservedObject private var store = ProjectStore.shared

    var body: some View {
        if store.project != nil {
            ProjectOverview()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }
}

/// The pages chosen for "As PDF", or all of them.
struct ExportScope: Identifiable {
    let id = UUID()
    let only: Set<UUID>?
}

/// A PDF project's pages, three to a row, each small in its own shape with
/// its number and where it comes from. A tap chooses a page; held, a page
/// lifts and is dragged to its new place, the others making room. Chosen
/// pages are turned, duplicated, saved as a PDF of their own or deleted
/// from the bar at the bottom, which otherwise adds pages or goes on to the
/// editor. Every change can be undone.
struct ProjectOverview: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var path: [UUID] = []
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var adding: ProjectAdding?
    @State private var exporting: ExportScope?
    @State private var renaming = false
    @State private var name = ""
    @State private var password = ""
    /// The made-up project's Save and Share was opened once.
    @State private var shownExport = false
    /// A PDF's password is asked for.
    @State private var askingPassword = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var project: PDFProject? { store.project }
    private var pages: [ProjectPage] { project?.pages ?? [] }

    var body: some View {
        alerts(stack)
            .onAppear {
                reopen()
                askingPassword = store.locked != nil
            }
            .onChange(of: store.locked?.id) { _, id in
                if id != nil { askingPassword = true }
            }
            .onChange(of: project?.openPage) { _, _ in reopen() }
            .onChange(of: pages.map(\.id)) { _, ids in
                // Pages gone are no longer chosen.
                selection.formIntersection(ids)
                showDemo()
            }
    }

    /// The pages, their header and bar, the editor pushed over them, and the sheets.
    private var stack: some View {
        NavigationStack(path: $path) {
            content
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom, spacing: 0) { bar }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 8) {
                        ProjectWorking()
                        ProjectToastView()
                    }
                    .padding(.bottom, 12)
                }
                .navigationDestination(for: UUID.self) { page in ProjectEditor(page: page) }
        }
        .tint(SnapflyTokens.protectTint)
        .modifier(ProjectAdder(adding: $adding, index: insertion))
        .sheet(item: $exporting) { scope in ProjectExportSheet(only: scope.only) }
    }

    /// A PDF's password, something said once, and the project's new name.
    private func alerts(_ content: some View) -> some View {
        content
            .alert(L("This PDF is protected with a password."), isPresented: $askingPassword) {
                SecureField(L("Password"), text: $password)
                    .accessibilityIdentifier("project-password")
                Button(L("Open"), action: tryPassword)
                Button(L("Cancel"), role: .cancel) {
                    password = ""
                    store.cancelUnlock()
                }
            } message: {
                Text(passwordMessage)
            }
            .alert(noticeTitle, isPresented: noticing) {
                Button(L("OK"), role: .cancel) { store.notice = nil }
            } message: {
                Text(noticeMessage)
            }
            .alert(L("Rename"), isPresented: $renaming) {
                TextField(L("Name"), text: $name)
                Button(L("Done")) { store.rename(name) }
                Button(L("Cancel"), role: .cancel) {}
            }
    }

    private var passwordMessage: String {
        if store.wrongPassword { return L("That is not its password. Try again.") }
        return String(format: L("Enter the password for %@. It is not kept."), store.locked?.name ?? "PDF")
    }

    /// The password tried: not its password, it is asked again once this alert has gone.
    private func tryPassword() {
        let opened = store.unlock(password)
        password = ""
        guard !opened else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            askingPassword = store.locked != nil
        }
    }

    // MARK: The header

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if selecting {
                let all = !pages.isEmpty && selection.count == pages.count
                Button(all ? L("Deselect All") : L("Select All")) {
                    selection = all ? [] : Set(pages.map(\.id))
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            } else {
                Button(L("Cancel")) { store.close() }
                    .accessibilityIdentifier("project-close")
            }
        }
        ToolbarItem(placement: .principal) {
            Button {
                name = project?.name ?? ""
                renaming = true
            } label: {
                VStack(spacing: 0) {
                    Text(project?.name ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)
            .disabled(selecting)
            .accessibilityHint(selecting ? "" : L("Rename"))
            .accessibilityIdentifier("project-title")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(selecting ? L("Done") : L("Select")) {
                withAnimation(motion) {
                    selecting.toggle()
                    if !selecting { selection = [] }
                }
            }
            .fontWeight(selecting ? .semibold : .regular)
            .disabled(pages.isEmpty)
            .accessibilityIdentifier("project-select")
        }
    }

    /// "6 pages", or while choosing, "2 pages selected".
    private var subtitle: String {
        guard selecting else { return ProjectNaming.pages(pages.count) }
        return selection.count == 1 ? L("1 page selected") : String(format: L("%d pages selected"), selection.count)
    }

    // MARK: The pages

    @ViewBuilder private var content: some View {
        if pages.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Tap a page to select it. Hold it and drag it to change the order."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                PageGrid(pages: pages, labels: labels, selecting: selecting, selection: selection,
                         reduceMotion: reduceMotion || ScanDemo.still, tap: tap, move: { store.move(from: $0, to: $1) },
                         turn: { store.turn([$0]) }, delete: { store.delete([$0]) })
                    .ignoresSafeArea(.container, edges: .bottom)
                    .accessibilityIdentifier("project-grid")
                    #if DEBUG
                    .overlay(alignment: .topLeading) { FrameMeterMark() }
                    #endif
            }
        }
    }

    private var labels: [UUID: String] {
        guard let project else { return [:] }
        return Dictionary(project.pages.map { ($0.id, project.label(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Nothing added yet: where pages can come from, one tap each.
    private var empty: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .accessibilityHidden(true)
                    .padding(.top, 28)
                Text(L("Add photos, scans and PDFs"))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(L("They become one PDF, in the order you choose. The files themselves stay as they are."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    source(L("From Photos"), symbol: "photo.on.rectangle.angled") { adding = .photos }
                    source(L("From Files"), symbol: "folder") { adding = .files }
                    if VNDocumentCameraViewController.isSupported {
                        source(L("Scan"), symbol: "doc.viewfinder") { adding = .camera }
                    }
                    if ScannedPages.shared.pages.contains(where: { $0.state == .ready }) {
                        source(L("Scanned Pages"), symbol: "doc.on.doc") { store.addScanned(at: nil) }
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func source(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The bar

    @ViewBuilder private var bar: some View {
        Group {
            if selecting {
                chosenBar
            } else if !pages.isEmpty {
                mainBar
            }
        }
        .animation(motion, value: selecting)
    }

    /// Add, a menu of where pages come from, and Next, to the editor.
    private var mainBar: some View {
        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return row {
            Menu {
                ProjectAddItems(choose: { adding = $0 }, blank: { _ = store.addBlank(at: insertion) },
                                scanned: { store.addScanned(at: insertion) })
            } label: {
                Label(L("Add"), systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemBackground), in: Capsule())
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .accessibilityIdentifier("project-add")
            Button {
                guard let first = pages.first else { return }
                path.append(first.id)
            } label: {
                HStack(spacing: 8) {
                    Text(L("Next"))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(SnapflyTokens.protect, in: Capsule())
            }
            .accessibilityIdentifier("project-next")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .transition(.opacity)
    }

    /// While choosing: Turn, Duplicate, As PDF and Delete, dimmed until a page is chosen.
    private var chosenBar: some View {
        let none = selection.isEmpty
        return HStack(spacing: 0) {
            action(L("Turn"), symbol: "rotate.right", id: "turn") { store.turn(selection) }
            action(L("Duplicate"), symbol: "plus.square.on.square", id: "duplicate") {
                selection = Set(store.duplicate(selection))
            }
            action(L("As PDF"), symbol: "doc.richtext", id: "pdf") { exporting = ExportScope(only: selection) }
            action(L("Delete"), symbol: "trash", id: "delete", destructive: true) {
                store.delete(selection)
                selection = []
            }
        }
        .disabled(none)
        .opacity(none ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .transition(.opacity)
    }

    private func action(_ title: String, symbol: String, id: String, destructive: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(destructive ? Color.red : SnapflyTokens.protectTint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project-\(id)")
    }

    // MARK: Doing it

    /// A tap chooses a page, and starts choosing.
    private func tap(_ id: UUID) {
        withAnimation(motion) {
            if !selecting { selecting = true }
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Where pages are added: after the last page chosen, else at the end.
    private var insertion: Int? {
        let chosen = pages.indices.filter { selection.contains(pages[$0].id) }
        return chosen.last.map { $0 + 1 }
    }

    /// For pictures made in CI: two pages chosen, or Save and Share open,
    /// once the made-up pages are in (`ProjectDemo`).
    private func showDemo() {
        guard pages.count >= 5 else { return }
        if ProjectDemo.selects, !selecting {
            selecting = true
            selection = [pages[0].id, pages[3].id]
        }
        if ProjectDemo.opensExport, exporting == nil, !shownExport {
            shownExport = true
            exporting = ExportScope(only: nil)
        }
    }

    /// Opened again where it was left: in the editor on its page.
    private func reopen() {
        guard path.isEmpty, let open = project?.openPage, project?.index(of: open) != nil else { return }
        path = [open]
    }

    private var noticing: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    }

    private var noticeTitle: String {
        switch store.notice {
        case .signed: L("This PDF is digitally signed.")
        case .unreadable(let count): count == 1 ? L("1 file could not be read.") : String(format: L("%d files could not be read."), count)
        case nil: ""
        }
    }

    private var noticeMessage: String {
        switch store.notice {
        case .signed: L("After editing, the signature is no longer valid.")
        case .unreadable: L("Snapfly reads PDFs and pictures (JPEG, PNG, HEIC).")
        case nil: ""
        }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)
    }
}

// MARK: The grid

/// The pages in a grid of their own, so 300 of them scroll smoothly and
/// one can be lifted and dragged with the others making room.
struct PageGrid: UIViewControllerRepresentable {
    let pages: [ProjectPage]
    let labels: [UUID: String]
    let selecting: Bool
    let selection: Set<UUID>
    let reduceMotion: Bool
    let tap: (UUID) -> Void
    let move: (Int, Int) -> Void
    let turn: (UUID) -> Void
    let delete: (UUID) -> Void

    func makeUIViewController(context: Context) -> PageGridController {
        PageGridController()
    }

    func updateUIViewController(_ controller: PageGridController, context: Context) {
        controller.update(self)
    }
}

/// The grid itself: a collection view of the pages, each drawn in SwiftUI,
/// and the lift, drag and drop of a page done here by hand, so it moves as
/// the design says: lifted a little larger with a deeper shadow while its
/// place fades to 45 %, a green bar where it will land, the others making
/// room on a spring, the grid scrolling near its edges, and a haptic as it
/// lifts, as its place changes and as it is dropped.
final class PageGridController: UIViewController, UICollectionViewDelegate {
    private var grid: PageGrid?
    private var collection: UICollectionView!
    private var source: UICollectionViewDiffableDataSource<Int, UUID>!
    /// The pages in the order shown, which runs ahead of the project's while one is dragged.
    private var order: [UUID] = []
    private var pages: [UUID: ProjectPage] = [:]
    /// Each page's turns as shown, counted on, so every turn goes the way it was turned.
    private var turns: [UUID: Int] = [:]
    private var drag: Drag?
    private let bar = UIView()
    private var link: CADisplayLink?
    private let spacing: CGFloat = 14

    /// A page being dragged: where it started, where it is now, its lifted
    /// picture, and where the finger holds it.
    private struct Drag {
        let id: UUID
        let from: Int
        var at: Int
        let lifted: UIView
        let hold: CGPoint
        var finger: CGPoint
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout())
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.delegate = self
        view.addSubview(collection)
        let cell = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [weak self] cell, _, id in
            self?.configure(cell, id)
        }
        source = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, id in
            collection.dequeueConfiguredReusableCell(using: cell, for: path, item: id)
        }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.3
        collection.addGestureRecognizer(press)
        bar.backgroundColor = UIColor(SnapflyTokens.protect)
        bar.layer.cornerRadius = 1.5
        bar.alpha = 0
        bar.isUserInteractionEnabled = false
        collection.addSubview(bar)
    }

    /// The project's undo, for the system's gestures: shaking, three fingers, ⌘Z.
    override var undoManager: UndoManager? { ProjectStore.shared.undoManager }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    /// Three to a row, two at the largest text sizes, each a page's room in
    /// A4's shape with its number and source under it.
    private func layout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            let spacing = self?.spacing ?? 14
            let large = environment.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            let columns = large ? 2 : 3
            let inset: CGFloat = 16
            let room = environment.container.effectiveContentSize.width - inset * 2
            let width = max(1, floor((room - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
            let words = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 30, compatibleWith: environment.traitCollection)
            let height = ceil(width * 1.414 + 8 + words)
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(width),
                                                                                heightDimension: .absolute(height)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 18
            section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: inset, bottom: 24, trailing: inset)
            return section
        }
    }

    // MARK: The pages

    func update(_ grid: PageGrid) {
        loadViewIfNeeded()
        let before = self.grid
        self.grid = grid
        // While a page is dragged, the order shown runs ahead; the project catches up once it is dropped.
        guard drag == nil else { return }
        for page in grid.pages {
            if let was = pages[page.id] {
                let change = ((page.turns - was.turns) % 4 + 4) % 4
                turns[page.id, default: page.turns] += change == 3 ? -1 : change
            } else {
                turns[page.id] = page.turns
            }
        }
        let changed = Set(grid.pages.filter { pages[$0.id] != $0 }.map(\.id))
        pages = Dictionary(grid.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = grid.pages.map(\.id)
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        let shown = source.snapshot().itemIdentifiers
        let moved = shown != ids
        // Numbers, sources, turns and choices drawn again where they changed:
        // all of them once the order changed, here or by a drop.
        let reordered = before.map { $0.pages.map(\.id) != ids } ?? false
        let looks = before.map { $0.selecting != grid.selecting || $0.selection != grid.selection || $0.labels != grid.labels }
            ?? false
        let kept = Set(shown)
        let again = moved || reordered || looks ? ids.filter { kept.contains($0) }
            : ids.filter { changed.contains($0) && kept.contains($0) }
        snapshot.reconfigureItems(again)
        order = ids
        guard before != nil, moved || !again.isEmpty else {
            source.apply(snapshot, animatingDifferences: false)
            return
        }
        if grid.reduceMotion {
            UIView.transition(with: collection, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.source.apply(snapshot, animatingDifferences: false)
            }
        } else {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.allowUserInteraction]) {
                self.source.apply(snapshot, animatingDifferences: true)
            }
        }
    }

    private func configure(_ cell: UICollectionViewCell, _ id: UUID) {
        guard let grid, let page = pages[id] else { return }
        let index = order.firstIndex(of: id) ?? 0
        let store = ProjectStore.shared
        let chosen = grid.selection.contains(id)
        let label = grid.labels[id] ?? ""
        cell.contentConfiguration = UIHostingConfiguration {
            PageCell(page: page, number: index + 1, label: label, aspect: store.aspect(page.source),
                     turns: turns[id] ?? page.turns, locked: store.isLocked(page), selecting: grid.selecting, chosen: chosen)
        }
        .margins(.all, 0)
        cell.contentView.alpha = drag?.id == id ? 0.45 : 1
        cell.isAccessibilityElement = true
        var words = [String(format: L("Page %d of %d"), index + 1, order.count), label]
        if chosen { words.append(L("selected")) }
        cell.accessibilityLabel = words.joined(separator: ", ")
        cell.accessibilityTraits = chosen ? [.button, .selected] : .button
        cell.accessibilityIdentifier = "project-page-\(index + 1)"
        cell.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: L("Move Earlier")) { [weak self] _ in self?.step(id, by: -1) ?? false },
            UIAccessibilityCustomAction(name: L("Move Later")) { [weak self] _ in self?.step(id, by: 1) ?? false },
            UIAccessibilityCustomAction(name: L("Turn")) { [weak self] _ in
                self?.grid?.turn(id)
                return true
            },
            UIAccessibilityCustomAction(name: L("Delete")) { [weak self] _ in
                self?.grid?.delete(id)
                return true
            },
        ]
    }

    /// VoiceOver moves a page earlier or later.
    private func step(_ id: UUID, by step: Int) -> Bool {
        guard let from = order.firstIndex(of: id), order.indices.contains(from + step) else { return false }
        grid?.move(from, from + step)
        return true
    }

    #if DEBUG
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if drag == nil { FrameMeter.shared.start("scroll") }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate, drag == nil { FrameMeter.shared.stop() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if drag == nil { FrameMeter.shared.stop() }
    }
    #endif

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: false)
        guard order.indices.contains(path.item) else { return }
        grid?.tap(order[path.item])
    }

    // MARK: Lifting and dropping

    @objc private func pressed(_ press: UILongPressGestureRecognizer) {
        let point = press.location(in: collection)
        switch press.state {
        case .began: lift(at: point)
        case .changed: follow(point)
        case .ended: drop(cancelled: false)
        default: drop(cancelled: true)
        }
    }

    private var still: Bool { grid?.reduceMotion ?? false }

    private func lift(at point: CGPoint) {
        guard drag == nil, let path = collection.indexPathForItem(at: point), order.indices.contains(path.item),
              let cell = collection.cellForItem(at: path), let lifted = cell.snapshotView(afterScreenUpdates: false)
        else { return }
        lifted.frame = cell.frame
        lifted.layer.shadowColor = UIColor.black.cgColor
        lifted.layer.shadowOffset = CGSize(width: 0, height: 10)
        lifted.layer.shadowRadius = 18
        lifted.layer.shadowOpacity = 0
        collection.addSubview(lifted)
        drag = Drag(id: order[path.item], from: path.item, at: path.item, lifted: lifted,
                    hold: CGPoint(x: point.x - cell.center.x, y: point.y - cell.center.y), finger: point)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #if DEBUG
        FrameMeter.shared.start("reorder")
        #endif
        let still = self.still
        UIView.animate(withDuration: still ? 0.15 : 0.35, delay: 0, usingSpringWithDamping: still ? 1 : 0.85,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            if !still { lifted.transform = CGAffineTransform(scaleX: 1.04, y: 1.04) }
            lifted.layer.shadowOpacity = 0.24
            cell.contentView.alpha = 0.45
        }
        place(bar: path.item, animated: false)
        UIView.animate(withDuration: 0.15) { self.bar.alpha = 1 }
        let link = CADisplayLink(target: self, selector: #selector(scrollNearEdges))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func follow(_ point: CGPoint) {
        guard var drag else { return }
        drag.finger = point
        drag.lifted.center = CGPoint(x: point.x - drag.hold.x, y: point.y - drag.hold.y)
        self.drag = drag
        guard let target = place(for: point), target != drag.at else { return }
        reorder(to: target)
    }

    /// The place a finger is over: the page under it, else the nearest.
    private func place(for point: CGPoint) -> Int? {
        if let path = collection.indexPathForItem(at: point) { return path.item }
        let visible = collection.indexPathsForVisibleItems.compactMap { path -> (Int, CGFloat)? in
            guard let frame = collection.layoutAttributesForItem(at: path)?.frame else { return nil }
            return (path.item, hypot(frame.midX - point.x, frame.midY - point.y))
        }
        return visible.min { $0.1 < $1.1 }?.0
    }

    /// The page dragged takes another place in the order shown, the others making room.
    private func reorder(to target: Int) {
        guard var drag, order.indices.contains(target) else { return }
        order = ScanOrder.moving(order, from: drag.at, to: target)
        drag.at = target
        self.drag = drag
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(order)
        UISelectionFeedbackGenerator().selectionChanged()
        if still {
            source.apply(snapshot, animatingDifferences: false)
        } else {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.source.apply(snapshot, animatingDifferences: true)
            }
        }
        place(bar: target, animated: !still)
        collection.bringSubviewToFront(drag.lifted)
    }

    /// The green bar at the leading edge of the place the page will land.
    private func place(bar index: Int, animated: Bool) {
        guard let frame = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let leading = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? frame.maxX + spacing / 2 : frame.minX - spacing / 2
        let target = CGRect(x: leading - 1.5, y: frame.minY + 4, width: 3, height: frame.width * 1.414 - 8)
        guard animated else {
            bar.frame = target
            return
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.bar.frame = target
        }
    }

    /// Near the top or the bottom, the grid scrolls, faster the nearer the finger is.
    @objc private func scrollNearEdges() {
        guard let drag else { return }
        let inset = collection.adjustedContentInset
        let top = collection.contentOffset.y + inset.top, bottom = collection.contentOffset.y + collection.bounds.height - inset.bottom
        let reach: CGFloat = 80
        var speed: CGFloat = 0
        if drag.finger.y < top + reach { speed = -(top + reach - drag.finger.y) / reach * 14 }
        if drag.finger.y > bottom - reach { speed = (drag.finger.y - (bottom - reach)) / reach * 14 }
        guard speed != 0 else { return }
        let lowest = -inset.top, highest = max(lowest, collection.contentSize.height - collection.bounds.height + inset.bottom)
        let offset = min(max(collection.contentOffset.y + speed, lowest), highest)
        let moved = offset - collection.contentOffset.y
        guard moved != 0 else { return }
        collection.contentOffset.y = offset
        follow(CGPoint(x: drag.finger.x, y: drag.finger.y + moved))
    }

    private func drop(cancelled: Bool) {
        link?.invalidate()
        link = nil
        guard let drag else { return }
        #if DEBUG
        FrameMeter.shared.stop()
        #endif
        if cancelled, drag.at != drag.from { reorder(to: drag.from) }
        let landing = cancelled ? drag.from : drag.at
        let frame = collection.layoutAttributesForItem(at: IndexPath(item: landing, section: 0))?.frame ?? drag.lifted.frame
        let still = self.still
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.animate(withDuration: still ? 0.15 : 0.35, delay: 0, usingSpringWithDamping: still ? 1 : 0.85,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            drag.lifted.transform = .identity
            drag.lifted.center = CGPoint(x: frame.midX, y: frame.midY)
            drag.lifted.layer.shadowOpacity = 0
            self.bar.alpha = 0
        } completion: { _ in
            drag.lifted.removeFromSuperview()
            for cell in self.collection.visibleCells { cell.contentView.alpha = 1 }
        }
        self.drag = nil
        if !cancelled, drag.at != drag.from {
            grid?.move(drag.from, drag.at)
        } else if let grid {
            update(grid)
        }
    }
}

/// A page in the grid: small in its own shape on the page's room, a check
/// circle while choosing, its number and where it comes from under it.
struct PageCell: View {
    let page: ProjectPage
    let number: Int
    let label: String
    let aspect: CGFloat
    let turns: Int
    let locked: Bool
    let selecting: Bool
    let chosen: Bool

    var body: some View {
        VStack(spacing: 8) {
            PagePaper(source: page.source, aspect: aspect, turns: turns, locked: locked)
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SnapflyTokens.protectTint, lineWidth: 2.5)
                            .padding(-4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if selecting { check.padding(6) }
                }
                .aspectRatio(1 / 1.414, contentMode: .fit)
            HStack(spacing: 6) {
                Text(number, format: .number)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color(.tertiarySystemFill), in: Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Photos' mark of a chosen picture: a white tick on the green, ringed in white; an empty ring otherwise.
    private var check: some View {
        ZStack {
            Circle()
                .fill(chosen ? AnyShapeStyle(SnapflyTokens.protect) : AnyShapeStyle(Color.white.opacity(0.85)))
            Circle()
                .strokeBorder(chosen ? Color.white : Color.black.opacity(0.25), lineWidth: 1.5)
            if chosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

#if DEBUG
/// For the numbers made in CI: the frames drawn while the grid scrolls or a
/// page is dragged, and how many came late, as Instruments counts a hitch:
/// a frame later than half a frame more than it should take.
@MainActor
final class FrameMeter: NSObject, ObservableObject {
    static let shared = FrameMeter()
    @Published private(set) var summary = "none"
    private var link: CADisplayLink?
    private var what = ""
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var lateTime: CFTimeInterval = 0
    private var total: CFTimeInterval = 0

    func start(_ what: String) {
        stop()
        self.what = what
        last = 0
        frames = 0
        late = 0
        lateTime = 0
        total = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let expected = link.targetTimestamp - link.timestamp
        if last > 0 {
            let took = link.timestamp - last
            total += took
            frames += 1
            if took > expected * 1.5 {
                late += 1
                lateTime += took - expected
            }
        }
        last = link.timestamp
    }

    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        guard total > 0 else { return }
        summary = String(format: "%@: %d frames in %.1f s, %d late, hitch time %.1f ms per s", what, frames, total, late,
                         lateTime * 1000 / total)
    }
}

/// The numbers as invisible words the UI tests read, in debug builds only.
struct FrameMeterMark: View {
    @ObservedObject private var meter = FrameMeter.shared

    var body: some View {
        Text(verbatim: meter.summary)
            .font(.system(size: 2))
            .foregroundStyle(.clear)
            .frame(width: 2, height: 2)
            .allowsHitTesting(false)
            .accessibilityIdentifier("project-frame-meter")
    }
}
#endif
