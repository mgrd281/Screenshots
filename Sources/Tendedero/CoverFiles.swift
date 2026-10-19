import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Cover Files…: PDFs and pictures by the hundred, dropped or chosen, files
/// and whole folders, each saved as a covered copy in a new folder with the
/// folders they came in kept. Choose what to cover, like names alone, and
/// the rest is read on this Mac, a few files at a time. The files themselves
/// are never changed, and a file that cannot be covered gets no copy at all,
/// so nothing leaves uncovered by mistake.
@MainActor
final class CoverFiles: NSObject, NSWindowDelegate {
    static let shared = CoverFiles()

    let model = CoverFilesModel()
    private var window: NSWindow?

    /// Shows the window, with these files added to what is there.
    func open(with urls: [URL] = []) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = L("Cover Files")
            window.contentMinSize = NSSize(width: 760, height: 480)
            let hosting = NSHostingView(rootView: CoverFilesView(model: model))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("CoverFiles")
            if !window.setFrameUsingName("CoverFiles") { window.center() }
            self.window = window
        }
        if !urls.isEmpty { model.add(urls) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var isKey: Bool { window?.isKeyWindow ?? false }

    /// Closing while files are being covered asks first, then stops.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.phase == .running else { return true }
        let alert = NSAlert()
        alert.messageText = L("Stop covering?")
        alert.informativeText = L("The copies saved so far stay in their folder.")
        alert.addButton(withTitle: L("Stop"))
        alert.addButton(withTitle: L("Keep Covering"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        model.stop()
        return true
    }
}

/// The files to cover, what to cover in them, and how far a run has got.
@MainActor
final class CoverFilesModel: ObservableObject {
    enum Failure: Equatable {
        case locked, tooLong, unreadable
    }

    enum State: Equatable {
        case waiting, working, covered(Int), nothing, failed(Failure), stopped
    }

    enum Phase: Equatable {
        case idle, running, done
    }

    /// Which rows the list shows.
    enum Filter: Hashable {
        case all, covered, nothing, failed
    }

    struct Row: Identifiable {
        var item: CoverBatch.Item
        var state = State.waiting
        var copy: URL?

        var id: String { item.id }
    }

    /// The most one window takes, so a run stays one a Mac can finish.
    static let limit = 10_000

    @Published private(set) var rows: [Row] = []
    @Published private(set) var unsupported: [URL] = []
    @Published private(set) var phase = Phase.idle
    @Published private(set) var scanning = false
    @Published private(set) var finished = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var destination: URL?
    @Published var selection: Set<String> = []
    @Published var filter = Filter.all
    @Published var chosen: Set<PrivateDetail> {
        didSet { UserDefaults.standard.set(chosen.map(\.rawValue).sorted(), forKey: Self.kindsKey) }
    }

    private var places: [String: Int] = [:]
    private var queue: OperationQueue?
    private var stopping = false
    private var activity: NSObjectProtocol?
    private var opened: URL?

    /// What Cover Files covered last time; names alone the first time.
    private static let kindsKey = "coverFilesKinds"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.kindsKey)?.compactMap(PrivateDetail.init(rawValue:))
        chosen = saved.map(Set.init) ?? [.names]
    }

    // MARK: The files

    /// Adds files and whole folders, opened off the main thread. A file
    /// already listed is not listed twice.
    func add(_ urls: [URL]) {
        guard phase != .running, !urls.isEmpty else { return }
        if phase == .done { startOver() }
        scanning = true
        let room = Self.limit - rows.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scan = CoverBatch.scan(urls, limit: max(0, room))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let known = Set(self.rows.map(\.id))
                    self.rows += scan.items.filter { !known.contains($0.id) }.map { Row(item: $0) }
                    self.unsupported += scan.unsupported
                    self.reindex()
                    self.scanning = false
                    if scan.items.count >= room {
                        Notice.show(String(format: L("Up to %d files at a time."), Self.limit))
                    }
                }
            }
        }
    }

    /// Choose Files…: files and folders, as many as wanted.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        panel.message = L("Choose PDFs and pictures, or whole folders of them.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func remove(_ ids: Set<String>) {
        guard phase != .running, !ids.isEmpty else { return }
        rows.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        reindex()
    }

    func clear() {
        guard phase != .running else { return }
        rows = []
        unsupported = []
        selection = []
        startOver()
        reindex()
    }

    /// Back to the list as it was before the run, to change it or run again.
    func startOver() {
        guard phase != .running else { return }
        for i in rows.indices {
            rows[i].state = .waiting
            rows[i].copy = nil
        }
        finished = 0
        startedAt = nil
        filter = .all
        phase = .idle
    }

    private func reindex() {
        places = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
    }

    var shown: [Row] {
        switch filter {
        case .all: return rows
        case .covered: return rows.filter { if case .covered = $0.state { return true }; return false }
        case .nothing: return rows.filter { $0.state == .nothing }
        case .failed: return rows.filter { if case .failed = $0.state { return true }; return false }
        }
    }

    var documents: Int { rows.filter { $0.item.kind == .document }.count }

    struct Tally {
        var covered = 0, nothing = 0, failed = 0, stopped = 0
    }

    var tally: Tally {
        rows.reduce(into: Tally()) { tally, row in
            switch row.state {
            case .covered: tally.covered += 1
            case .nothing: tally.nothing += 1
            case .failed: tally.failed += 1
            case .stopped: tally.stopped += 1
            case .waiting, .working: break
            }
        }
    }

    /// Something to cover: a kind chosen, or a rule of the owner's own.
    var canCover: Bool {
        !chosen.isEmpty || OwnRules.all.contains { !$0.isBlank }
    }

    // MARK: Covering

    /// Asks where to save, makes a new folder there, and covers every file
    /// into it, a few at a time.
    func start() {
        guard phase != .running, !rows.isEmpty, canCover, !scanning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Save Here")
        panel.message = L("Choose where to save the covered copies. A new folder is made there for them.")
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        if parent.startAccessingSecurityScopedResource() { opened = parent }

        let fm = FileManager.default
        let name = CoverBatch.folderName(at: Date(), prefix: L("Covered"))
        var folder = parent.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            log.error("Could not make the folder for covered copies: \(error.localizedDescription, privacy: .public)")
            Notice.show(L("Could not make a folder there. Choose another place."))
            close()
            return
        }

        startOver()
        destination = folder
        phase = .running
        startedAt = Date()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Covering files")
        let queue = OperationQueue()
        queue.name = "Snapfly.CoverFiles"
        queue.qualityOfService = .utility
        // Reading a page is heavy: a few at a time keeps the Mac usable.
        queue.maxConcurrentOperationCount = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
        self.queue = queue

        let chosen = chosen
        let outputs = CoverBatch.outputs(for: rows.map(\.item))
        for (row, output) in zip(rows, outputs) {
            let item = row.item
            let target = folder.appendingPathComponent(output)
            queue.addOperation { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.set(item.id, .working) } }
                let state = autoreleasepool { CoverFilesModel.cover(item, chosen, to: target) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finish(item.id, state, copy: target) }
                }
            }
        }
    }

    /// One file's covered copy, or why it has none. Nothing is left behind
    /// for a file that could not be covered.
    nonisolated static func cover(_ item: CoverBatch.Item, _ chosen: Set<PrivateDetail>, to target: URL) -> State {
        if item.kind == .document {
            guard let document = PDFDocument(url: item.url) else { return .failed(.unreadable) }
            if document.isLocked { return .failed(.locked) }
            if document.pageCount > DocumentCover.maxPages { return .failed(.tooLong) }
            if document.pageCount == 0 { return .failed(.unreadable) }
        }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            return .failed(.unreadable)
        }
        guard let report = FolderCover.coverCopy(of: item.url, chosen, to: target) else {
            try? FileManager.default.removeItem(at: target)
            return .failed(.unreadable)
        }
        return report.isEmpty ? .nothing : .covered(report.total)
    }

    /// Stops after the files being read now; the rest get no copy. The run
    /// ends once those being read are saved.
    func stop() {
        guard phase == .running, !stopping, let queue else { return }
        stopping = true
        queue.cancelAllOperations()
        for i in rows.indices where rows[i].state == .waiting {
            rows[i].state = .stopped
        }
        queue.addBarrierBlock { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.complete() } }
        }
    }

    private func set(_ id: String, _ state: State) {
        guard let i = places[id], rows[i].state == .waiting else { return }
        rows[i].state = state
    }

    private func finish(_ id: String, _ state: State, copy: URL) {
        guard let i = places[id] else { return }
        rows[i].state = state
        switch state {
        case .covered, .nothing: rows[i].copy = copy
        default: rows[i].copy = nil
        }
        finished += 1
        finishIfDone()
    }

    private func finishIfDone() {
        guard phase == .running, !stopping,
              !rows.contains(where: { $0.state == .waiting || $0.state == .working }) else { return }
        complete()
    }

    private func complete() {
        guard phase == .running else { return }
        stopping = false
        // A file whose reading began as it was stopped, if any, says so.
        for i in rows.indices where rows[i].state == .working || rows[i].state == .waiting {
            rows[i].state = .stopped
        }
        phase = .done
        queue = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        close()
        let saved = tally.covered + tally.nothing
        guard !CoverFiles.shared.isKey, saved > 0, let destination else { return }
        Notice.show(String(format: L("Covered copies saved: %ld"), saved), done: true, lasting: 8) {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func close() {
        opened?.stopAccessingSecurityScopedResource()
        opened = nil
    }

    var remaining: TimeInterval? {
        guard let startedAt else { return nil }
        return CoverBatch.remaining(done: finished, total: rows.count - tally.stopped,
                                    elapsed: Date().timeIntervalSince(startedAt))
    }

    func revealDestination() {
        guard let destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}

extension CoverFilesModel.State {
    var title: String {
        switch self {
        case .waiting: return L("Waiting")
        case .working: return L("Covering…")
        case .covered(let n): return n == 1 ? L("1 place covered") : String(format: L("%d places covered"), n)
        case .nothing: return L("Nothing to cover")
        case .failed(.locked): return L("Locked with a password")
        case .failed(.tooLong): return String(format: L("Over %d pages"), DocumentCover.maxPages)
        case .failed(.unreadable): return L("Could not be read")
        case .stopped: return L("Stopped")
        }
    }
}

// MARK: - The window

private struct CoverFilesView: View {
    @ObservedObject var model: CoverFilesModel
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.rows.isEmpty {
                    dropZone
                } else {
                    listHeader
                    Divider()
                    list
                    Divider()
                    footer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard model.phase != .running else { return false }
                Self.urls(from: providers) { model.add($0) }
                return true
            }
            Divider()
            CoverFilesInspector(model: model)
                .frame(width: 300)
        }
    }

    /// The URLs dropped, read one by one, then handed over together.
    private static func urls(from providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? NSURL {
                    lock.lock()
                    urls.append(url as URL)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }

    // MARK: Empty

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(L("Drop files or folders here"))
                .font(.title2.weight(.semibold))
            Text(L("PDFs and pictures, as many as you like. Each gets a covered copy in a new folder; the files themselves stay as they are."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(L("Choose Files…")) { model.choose() }
                .controlSize(.large)
                .padding(.top, 4)
            if model.scanning { ProgressView().controlSize(.small) }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(20)
        }
    }

    // MARK: The list

    private var listHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.rows.count == 1 ? L("1 file") : String(format: L("%d files"), model.rows.count))
                    .font(.headline)
                    .monospacedDigit()
                Text(String(format: L("%1$d PDFs · %2$d pictures"), model.documents, model.rows.count - model.documents))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if model.phase == .done {
                Picker(L("Show"), selection: $model.filter) {
                    Text(L("All")).tag(CoverFilesModel.Filter.all)
                    Text(L("Covered")).tag(CoverFilesModel.Filter.covered)
                    Text(L("Nothing to cover")).tag(CoverFilesModel.Filter.nothing)
                    Text(L("Not covered")).tag(CoverFilesModel.Filter.failed)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } else {
                if model.scanning { ProgressView().controlSize(.small) }
                Button(L("Add…")) { model.choose() }
                    .disabled(model.phase == .running)
                Button(L("Remove")) { model.remove(model.selection) }
                    .disabled(model.phase == .running || model.selection.isEmpty)
                Button(L("Clear")) { model.clear() }
                    .disabled(model.phase == .running)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        Table(model.shown, selection: $model.selection) {
            TableColumn("") { row in
                StateIcon(state: row.state)
            }
            .width(22)
            TableColumn(L("Name")) { row in
                Text(row.item.relative)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.item.url.path)
            }
            .width(min: 200, ideal: 340)
            TableColumn(L("Kind")) { row in
                Text(row.item.kind == .document ? L("PDF") : L("Picture"))
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
            TableColumn(L("Result")) { row in
                Text(row.state.title)
                    .foregroundStyle(row.state == .waiting ? .tertiary : .secondary)
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let picked = model.rows.filter { ids.contains($0.id) }
            if !picked.isEmpty {
                Button(L("Show Original in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(picked.map(\.item.url))
                }
                let copies = picked.compactMap(\.copy)
                if !copies.isEmpty {
                    Button(L("Show Copy in Finder")) { NSWorkspace.shared.activateFileViewerSelecting(copies) }
                    Button(L("Quick Look")) { QuickLook.shared.show(copies, at: 0) }
                }
                if model.phase == .idle {
                    Divider()
                    Button(L("Remove")) { model.remove(ids) }
                }
            }
        } primaryAction: { ids in
            let copies = model.rows.filter { ids.contains($0.id) }.compactMap(\.copy)
            if !copies.isEmpty { QuickLook.shared.show(copies, at: 0) }
        }
        .onDeleteCommand { model.remove(model.selection) }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .idle:
            if !model.unsupported.isEmpty {
                HStack {
                    Label(String(format: L("%d files are neither PDFs nor pictures and get no copy."),
                                 model.unsupported.count),
                          systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        case .running:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 12) {
                    ProgressView(value: Double(model.finished), total: Double(max(1, model.rows.count)))
                    Text(progressText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                    Button(L("Stop")) { model.stop() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        case .done:
            let tally = model.tally
            HStack(spacing: 16) {
                Label("\(tally.covered)", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .help(L("Covered"))
                Label("\(tally.nothing)", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .help(L("Nothing to cover"))
                Label("\(tally.failed)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .help(L("Not covered"))
                if tally.stopped > 0 {
                    Label("\(tally.stopped)", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                        .help(L("Stopped"))
                }
                Spacer()
                if tally.nothing > 0 {
                    Text(L("Look at those with nothing to cover before sending them."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }

    private var progressText: String {
        var text = String(format: L("%1$d of %2$d"), model.finished, model.rows.count)
        if let left = model.remaining {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = left >= 3600 ? [.hour, .minute] : (left >= 60 ? [.minute] : [.second])
            formatter.maximumUnitCount = 2
            if let time = formatter.string(from: max(1, left)) {
                text += " · " + String(format: L("about %@ left"), time)
            }
        }
        return text
    }
}

/// A row's state as a symbol, the same in the list and the summary.
private struct StateIcon: View {
    let state: CoverFilesModel.State

    var body: some View {
        Group {
            switch state {
            case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
            case .working: ProgressView().controlSize(.mini)
            case .covered: Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            case .nothing: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .stopped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(state.title)
    }
}

/// What to cover, in the kinds Settings › Privacy lists, with one-click
/// choices, and the button that starts.
private struct CoverFilesInspector: View {
    @ObservedObject var model: CoverFilesModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 6) {
                        quick(L("Names Only")) { model.chosen = [.names] }
                        quick(L("As in Settings")) { model.chosen = PrivateDetails.details }
                    }
                    HStack(spacing: 6) {
                        quick(L("All")) { model.chosen = Set(PrivateDetail.allCases) }
                        quick(L("None")) { model.chosen = [] }
                    }
                } header: {
                    Text(L("What to cover"))
                }
                ForEach(PrivateDetail.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(group.kinds, id: \.self) { kind in
                            Toggle(kind.title, isOn: Binding(
                                get: { model.chosen.contains(kind) },
                                set: { on in
                                    if on { model.chosen.insert(kind) } else { model.chosen.remove(kind) }
                                }))
                        }
                    } header: {
                        Text(group.title)
                    }
                }
                Section {
                    Text(L("Your own rules from Settings › Privacy apply too. Every copy is read again, and covered more if anything still shows."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(readWhere)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(model.phase == .running)
            Divider()
            action
                .padding(16)
        }
    }

    /// Where the files are read: on this Mac, or with the words also sent
    /// to the AI assistant, when Settings › Privacy says so.
    private var readWhere: String {
        Finder.asksAssistant
            ? String(format: L("The words of each file also go to %@, as set in Settings › Privacy."), AIAccount.provider.name)
            : L("Read on this Mac. Nothing is sent anywhere.")
    }

    private func quick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    @ViewBuilder private var action: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: 6) {
                Button {
                    model.start()
                } label: {
                    Text(model.rows.count == 1 ? L("Cover 1 File") : String(format: L("Cover %d Files"), model.rows.count))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.rows.isEmpty || !model.canCover || model.scanning)
                if !model.canCover {
                    Text(L("Choose at least one kind to cover."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        case .running:
            Text(L("You can keep working; the window can stay open in the background."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .done:
            VStack(spacing: 8) {
                Button {
                    model.revealDestination()
                } label: {
                    Text(L("Show in Finder")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(L("Start Over")) { model.startOver() }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
