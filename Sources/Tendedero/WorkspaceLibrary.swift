import AppKit
import SwiftUI

/// One screenshot in the Workspace, with the category folder it is in.
struct LibraryItem: Identifiable, Equatable, Sendable {
    var item: WorkspaceItem
    var category: String

    var id: String { item.id }
    var url: URL { item.url }
    var name: String { item.url.lastPathComponent }
    var date: Date { item.date }
}

/// What the Workspace page of the History window shows: the screenshots on
/// disk, by category, to look through, search, open, move, rename and send
/// to the Trash. The folders are the truth: the list is read from them when
/// the window shows, when Snapfly comes to the front after the Finder, and
/// after each change made here, with no polling in between.
@MainActor
final class WorkspaceLibraryModel: ObservableObject {
    enum Arrangement: Hashable {
        case grid, list
    }

    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var loaded = false
    /// A category's id, or nil for all of them.
    @Published var filter: String?
    @Published var arrangement = Arrangement.grid
    @Published var selection: Set<String> = []

    /// Thumbnails, made off the main thread as cards come into view, and
    /// kept only for the most recent, so a large library stays light.
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()
    @Published private var thumbTick = 0
    private var loading = Set<String>()
    private var activation: NSObjectProtocol?

    init() {
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }

    /// Reads the category folders, off the main thread.
    func reload() {
        let workspace = Workspace.shared
        guard workspace.isOn, workspace.isReady else {
            items = []
            loaded = true
            return
        }
        let config = workspace.config, root = workspace.root
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { () -> [LibraryItem] in
                var all: [LibraryItem] = []
                for category in config.visible {
                    for item in WorkspaceFiles.items(in: config.folder(of: category, root: root)) {
                        all.append(LibraryItem(item: item, category: category.id))
                    }
                }
                return all.sorted { $0.date > $1.date }
            }.value
            self.items = found
            self.selection = self.selection.filter { path in found.contains { $0.id == path } }
            self.loaded = true
            workspace.refreshStats()
        }
    }

    func thumb(for url: URL) -> NSImage? {
        _ = thumbTick
        return cache.object(forKey: url.path as NSString)
    }

    func loadThumb(_ url: URL) {
        let path = url.path
        guard cache.object(forKey: path as NSString) == nil, loading.insert(path).inserted else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = makeThumbnail(url, maxPixels: 320)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.loading.remove(path)
                    self.cache.setObject(image ?? NSImage(), forKey: path as NSString)
                    self.thumbTick += 1
                }
            }
        }
    }

    // MARK: What is shown

    /// The category's items, with every word typed in the file's name or, for
    /// a photo Snapfly has read, in its text.
    func shown(search: String) -> [LibraryItem] {
        let base = filter.map { id in items.filter { $0.category == id } } ?? items
        let terms = TextIndex.fold(search).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return base }
        return base.filter { entry in
            let words = (TextIndex.rows(for: entry.url) ?? []).map(\.folded).joined(separator: " ")
                + " " + TextIndex.fold(entry.name)
            return terms.allSatisfy { words.contains($0) }
        }
    }

    func days(search: String) -> [(day: Date, items: [LibraryItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: shown(search: search)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    func count(in category: String?) -> Int {
        category.map { id in items.filter { $0.category == id }.count } ?? items.count
    }

    func categoryName(_ id: String) -> String {
        Workspace.shared.config.category(id)?.name ?? ""
    }

    /// What an action on a screenshot applies to: the whole selection when it
    /// is one of them, else just it.
    func targets(for entry: LibraryItem) -> [LibraryItem] {
        guard selection.contains(entry.id) else { return [entry] }
        return items.filter { selection.contains($0.id) }
    }

    func select(_ entry: LibraryItem, extending: Bool) {
        if extending {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
        } else {
            selection = [entry.id]
        }
    }

    // MARK: Actions

    func open(_ entries: [LibraryItem]) {
        for entry in entries.prefix(10) { NSWorkspace.shared.open(entry.url) }
    }

    func quickLook(_ entries: [LibraryItem]) {
        QuickLook.shared.show(entries.map(\.url), at: 0)
    }

    func reveal(_ entries: [LibraryItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(entries.map(\.url))
    }

    func copy(_ entries: [LibraryItem]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(entries.map { $0.url as NSURL })
    }

    func copyPath(_ entries: [LibraryItem]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries.map(\.url.path).joined(separator: "\n"), forType: .string)
    }

    func move(_ entries: [LibraryItem], to id: String) {
        Workspace.shared.move(entries.map(\.url), to: id) { [weak self] in self?.reload() }
    }

    /// To the Trash, where it can be put back; the line forgets it.
    func trash(_ entries: [LibraryItem]) {
        let urls = entries.map(\.url)
        Task { @MainActor in
            let failed = await Task.detached { () -> Int in
                var failed = 0
                for url in urls where (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil { failed += 1 }
                return failed
            }.value
            Workspace.shared.removed()
            self.reload()
            if failed > 0 { Notice.show(L("Could not move the screenshot to the Trash.")) }
        }
    }

    /// Asks for a new name, keeping the file's extension. Nothing is ever
    /// replaced.
    func rename(_ entry: LibraryItem) {
        let alert = NSAlert()
        alert.messageText = L("Rename")
        alert.informativeText = entry.name
        let field = NSTextField(string: entry.url.deletingPathExtension().lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let name = WorkspaceNames.clean(field.stringValue) else { return }
        let ext = entry.url.pathExtension
        let target = entry.url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
        guard target.path != entry.url.path else { return }
        if FileManager.default.fileExists(atPath: target.path) {
            Notice.show(String(format: L("A file named “%@” is already there."), target.lastPathComponent))
            return
        }
        do {
            try FileManager.default.moveItem(at: entry.url, to: target)
            Workspace.shared.relocated(entry.url, target)
            reload()
        } catch {
            log.error("Could not rename a screenshot: \(error.localizedDescription, privacy: .public)")
            Notice.show(L("Could not rename the screenshot."))
        }
    }
}

// MARK: The page

struct WorkspaceLibraryView: View {
    @ObservedObject var model: WorkspaceLibraryModel
    @ObservedObject private var workspace = Workspace.shared
    let search: String
    let hang: (URL) -> Void

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        // "Today" and "Yesterday", in the user's language.
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { model.reload() }
        .onChange(of: workspace.isReady) { _, _ in model.reload() }
        .onChange(of: workspace.config.categories) { _, _ in model.reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker(L("Category"), selection: $model.filter) {
                Text("\(L("All")) (\(model.count(in: nil)))").tag(String?.none)
                Divider()
                ForEach(workspace.config.visible) { category in
                    Text("\(category.name) (\(model.count(in: category.id)))").tag(String?.some(category.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button { workspace.reveal() } label: {
                Label(L("Open Workspace"), systemImage: "folder")
            }
            .help(L("Open Workspace"))
            Picker(L("View"), selection: $model.arrangement) {
                Image(systemName: "square.grid.2x2").tag(WorkspaceLibraryModel.Arrangement.grid)
                    .accessibilityLabel(L("Grid"))
                Image(systemName: "list.bullet").tag(WorkspaceLibraryModel.Arrangement.list)
                    .accessibilityLabel(L("List"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help(L("Grid or List"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let shown = model.shown(search: search)
        if !model.loaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            ContentUnavailableView {
                Label(L("No screenshots yet"), systemImage: "camera.viewfinder")
            } description: {
                Text(L("Your captures will appear here automatically."))
            } actions: {
                Button(L("Take Screenshot")) { Capture.shared.start(after: 0.3) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else if shown.isEmpty {
            if search.isEmpty {
                ContentUnavailableView {
                    Label(L("Nothing in this category"), systemImage: "folder")
                } description: {
                    Text(L("Move a screenshot here from its menu, or drag it into the folder in the Finder."))
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        } else if model.arrangement == .grid {
            grid
        } else {
            list(shown)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(model.days(search: search), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.dayFormat.string(from: group.day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(group.items) { entry in
                                LibraryCard(model: model, entry: entry, hang: hang)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func list(_ shown: [LibraryItem]) -> some View {
        Table(shown, selection: $model.selection) {
            TableColumn(L("Name")) { entry in
                Text(entry.name).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 160, ideal: 260)
            TableColumn(L("Category")) { entry in
                Text(model.categoryName(entry.category)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn(L("Date")) { entry in
                Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn(L("Size")) { entry in
                Text(ByteCountFormatter.string(fromByteCount: entry.item.size, countStyle: .file))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let entries = model.items.filter { ids.contains($0.id) }
            if !entries.isEmpty {
                LibraryMenu(model: model, entries: entries, hang: hang)
            }
        } primaryAction: { ids in
            model.open(model.items.filter { ids.contains($0.id) })
        }
    }
}

/// What a screenshot's menu offers, for one or for several.
private struct LibraryMenu: View {
    @ObservedObject var model: WorkspaceLibraryModel
    let entries: [LibraryItem]
    let hang: (URL) -> Void

    var body: some View {
        if entries.count == 1, let entry = entries.first {
            Button(L("Hang on the line")) { hang(entry.url) }
            Divider()
        }
        Button(L("Open")) { model.open(entries) }
        Button(L("Quick Look")) { model.quickLook(entries) }
        Button(L("Show in Finder")) { model.reveal(entries) }
        Divider()
        Button(L("Copy")) { model.copy(entries) }
        Button(L("Copy File Path")) { model.copyPath(entries) }
        Divider()
        Menu(L("Move to Folder")) {
            ForEach(Workspace.shared.config.visible) { category in
                Button(category.name) { model.move(entries, to: category.id) }
                    .disabled(entries.allSatisfy { $0.category == category.id })
            }
        }
        if entries.count == 1, let entry = entries.first {
            Button(L("Rename…")) { model.rename(entry) }
        }
        Divider()
        Button(L("Move to Trash"), role: .destructive) { model.trash(entries) }
    }
}

/// One screenshot as a card: a click selects it, a double-click opens it, and
/// its menu does the rest. The thumbnail is made when the card shows.
private struct LibraryCard: View {
    @ObservedObject var model: WorkspaceLibraryModel
    let entry: LibraryItem
    let hang: (URL) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var selected: Bool { model.selection.contains(entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let thumb = model.thumb(for: entry.url), thumb.size.width > 0 {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 112)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 10, y: 5)
            .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
            Text(entry.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(model.categoryName(entry.category)) · \(Self.timeFormat.string(from: entry.date))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.spring(response: 0.25, damping: 0.85, reduced: reduceMotion), value: hovering)
        .onAppear { model.loadThumb(entry.url) }
        .onTapGesture(count: 2) { model.open([entry]) }
        .onTapGesture { model.select(entry, extending: NSEvent.modifierFlags.contains(.command)) }
        .contextMenu { LibraryMenu(model: model, entries: model.targets(for: entry), hang: hang) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.url.deletingPathExtension().lastPathComponent)
        .accessibilityValue(model.categoryName(entry.category))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.open([entry]) }
        .accessibilityAction(named: L("Hang on the line")) { hang(entry.url) }
        .accessibilityAction(named: L("Show in Finder")) { model.reveal([entry]) }
        .accessibilityAction(named: L("Move to Trash")) { model.trash([entry]) }
    }
}
