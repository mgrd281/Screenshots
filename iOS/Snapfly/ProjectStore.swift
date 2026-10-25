import CryptoKit
import ImageIO
import PDFKit
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The project shown over the app, while its pages' overview or editor is open.
struct ProjectRef: Identifiable, Equatable {
    let id: UUID
}

/// How far a long piece of work is, for the floating note.
struct ProjectProgress: Equatable {
    let done: Int
    let total: Int
}

/// Said once, in an alert: a signed PDF, or files that could not be read.
enum ProjectNotice: Identifiable, Equatable {
    case signed
    case unreadable(Int)

    var id: String {
        switch self {
        case .signed: "signed"
        case .unreadable(let count): "unreadable-\(count)"
        }
    }
}

/// A short dark note over the bottom after a page operation, with Undo
/// and then Redo.
struct ProjectToast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    /// Undone already: the note offers Redo instead.
    var undone = false
}

/// What is added to a project.
enum ProjectImport {
    /// PDFs and pictures from Files, Mail or Safari.
    case files([URL])
    /// Photos chosen in Photos, in the order chosen.
    case photos([PhotosPickerItem])
    /// Pictures made here: pages from the camera, or the Scan tab's pages.
    case pictures([CGImage], origin: PictureOrigin, kind: PaperKind? = nil)
    /// Screenshots from the Protected tab, by their identifier in Photos.
    case screenshots([String])

    var count: Int {
        switch self {
        case .files(let urls): urls.count
        case .photos(let items): items.count
        case .pictures(let images, _, _): images.count
        case .screenshots(let ids): ids.count
        }
    }
}

/// How a project leaves as a PDF.
struct ProjectExport: Equatable {
    var covered = true
    var searchable = true
    var paper = PaperSize.original
    var quality = ExportQuality.medium
}

/// The PDF projects kept on this iPhone: each in a folder of its own in
/// Snapfly's container, with complete file protection, so nothing in it can
/// be read while the iPhone is locked, and never in a backup. Each holds the
/// files its pages come from, copied in as they came and never changed,
/// and what the project is (`PDFProject`), written a moment after each
/// change, so a project opens again where it was left, even after Snapfly
/// was closed by force. A PDF's password is asked each time it opens and
/// never kept. Every page operation can be undone, and done again, one
/// step at a time.
@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    /// Every project, the one changed last first.
    @Published private(set) var projects: [PDFProject] = []
    /// The project open.
    @Published private(set) var project: PDFProject?
    /// The project shown over the app.
    @Published var shown: ProjectRef?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// Files, photos or screenshots being added.
    @Published private(set) var adding: ProjectProgress?
    /// Pages being covered for a PDF or pictures.
    @Published private(set) var making: ProjectProgress?
    /// A PDF waiting for its password; whether the last one tried was wrong.
    @Published private(set) var locked: ProjectFile?
    @Published private(set) var wrongPassword = false
    @Published var notice: ProjectNotice?
    /// Save and Share opens as the project opens, as Share on the Scan tab asks.
    @Published var sharesOnOpen = false
    @Published var toast: ProjectToast?
    /// Each page's shape, counted up when it is turned, so its editor starts afresh.
    @Published private(set) var revisions: [UUID: Int] = [:]

    /// The project's own undo, which the system's gestures reach too.
    let undoManager = UndoManager()
    private var history = ProjectHistory()
    /// Each page's protection once opened: kept while the app runs, the
    /// newest few, and every one with changes made by hand.
    private var sessions: [UUID: ProtectSession] = [:]
    private var used: [UUID] = []
    private var sources: [UUID: PDFSource] = [:]
    /// The PDFs still waiting for their password.
    private var stillLocked: Set<UUID> = []
    private var aspects: [String: CGFloat] = [:]
    private let thumbnails = NSCache<NSString, UIImage>()
    /// The projects' first pages covered, for the Scan tab, by what they were drawn from.
    private let coveredFirst = NSCache<NSString, UIImage>()
    /// The same, veiled (`ScanVeil`), by the covered picture they were made from.
    private let veiledFirst = NSCache<UIImage, UIImage>()
    /// Covered one after another, the newest asked last.
    private var covering: Task<UIImage?, Never>?
    private let wanted = Wanted()
    private var saving: Task<Void, Never>?
    private var unlocking: CheckedContinuation<Bool, Never>?
    /// Written in order, one after another.
    private let writer = DispatchQueue(label: "de.ghazarian.Snapfly.projects", qos: .utility)
    private let small = DispatchQueue(label: "de.ghazarian.Snapfly.thumbnails", qos: .utility)
    private let large = DispatchQueue(label: "de.ghazarian.Snapfly.pages", qos: .userInitiated)

    /// The project open when Snapfly was left, to open again.
    private static let openKey = "openProject"
    /// How many protections are kept besides those with changes made by hand.
    private static let keptSessions = 6

    private init() {
        // Each change is a step of its own, even two made in the same moment.
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = ProjectHistory.limit
        thumbnails.totalCostLimit = 80 * 1024 * 1024
        load()
    }

    // MARK: Where projects are kept

    nonisolated static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Projects", isDirectory: true)
    }

    nonisolated static func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated static func filesFolder(_ id: UUID) -> URL {
        folder(id).appendingPathComponent("Files", isDirectory: true)
    }

    func url(of file: UUID) -> URL? {
        guard let project, let stored = project.file(file)?.stored else { return nil }
        return Self.filesFolder(project.id).appendingPathComponent(stored)
    }

    /// A folder only Snapfly reads, closed while the iPhone is locked and left out of backups.
    nonisolated private static func make(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var root = Self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    private func load() {
        Task {
            var found = await Self.run(on: writer) { Self.readAll() }
            #if DEBUG
            // Made-up starts begin without documents; one started meanwhile stays.
            if ScanDemo.clearsDocuments {
                for old in found { delete(old.id) }
                found = []
            }
            #endif
            // A project started while they were read, as by a PDF opened in Snapfly, stays.
            let known = Set(found.map(\.id))
            projects = (found + projects.filter { !known.contains($0.id) }).sorted { $0.modified > $1.modified }
            #if DEBUG
            if ProjectDemo.makes { return ProjectDemo.start(self) }
            #endif
            // Where Snapfly was left with a project open, it opens again there.
            if project == nil, let id = UserDefaults.standard.string(forKey: Self.openKey).flatMap(UUID.init(uuidString:)) {
                open(id)
            }
        }
    }

    nonisolated private static func readAll() -> [PDFProject] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")) else { return nil }
            return try? JSONDecoder().decode(PDFProject.self, from: data)
        }
    }

    /// Writes the project a moment after the last change.
    private func scheduleSave() {
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Writes the open project now, as when Snapfly goes to the background.
    func flush() {
        saving?.cancel()
        guard let project, let data = try? JSONEncoder().encode(project) else { return }
        let folder = Self.folder(project.id)
        writer.async {
            try? Self.make(folder)
            try? data.write(to: folder.appendingPathComponent("project.json"), options: [.atomic, .completeFileProtection])
        }
    }

    // MARK: Opening and closing

    /// A new project, opened at once over the app, with what is added.
    func start(_ items: ProjectImport? = nil) {
        let new = PDFProject(name: ProjectNaming.name(files: [], pages: [], at: .now))
        // The project open before is kept, unless nothing was ever added to it.
        if let old = project, old.pages.isEmpty { delete(old.id) }
        flush()
        reset()
        project = new
        projects.insert(new, at: 0)
        UserDefaults.standard.set(new.id.uuidString, forKey: Self.openKey)
        shown = ProjectRef(id: new.id)
        flush()
        guard let items else { return }
        Task {
            await add(items)
            guard var now = project, now.id == new.id else { return }
            // Named once there is something to name it by.
            now.name = ProjectNaming.name(files: now.files, pages: now.pages, at: now.created)
            project = now
            remember(now)
            flush()
        }
    }

    func open(_ id: UUID) {
        guard let found = projects.first(where: { $0.id == id }) else {
            UserDefaults.standard.removeObject(forKey: Self.openKey)
            return
        }
        if project?.id != id {
            reset()
            project = found
            tidy()
        }
        UserDefaults.standard.set(id.uuidString, forKey: Self.openKey)
        openSources()
        shown = ProjectRef(id: id)
    }

    /// The overview closed: the project stays among the recent ones, unless
    /// nothing was ever added to it.
    func close() {
        flush()
        if let project, project.pages.isEmpty { delete(project.id) }
        shown = nil
        project = nil
        UserDefaults.standard.removeObject(forKey: Self.openKey)
        reset()
    }

    func delete(_ id: UUID) {
        if project?.id == id {
            project = nil
            shown = nil
            UserDefaults.standard.removeObject(forKey: Self.openKey)
            reset()
        }
        projects.removeAll { $0.id == id }
        let folder = Self.folder(id)
        writer.async { try? FileManager.default.removeItem(at: folder) }
    }

    /// Any project renamed, open or not, as the Scan tab's Rename asks.
    func rename(_ id: UUID, to name: String) {
        if project?.id == id { return rename(name) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var now = projects.first(where: { $0.id == id }), now.name != trimmed else { return }
        now.name = trimmed
        now.modified = .now
        guard let data = try? JSONEncoder().encode(now) else { return }
        remember(now)
        let folder = Self.folder(id)
        writer.async {
            try? data.write(to: folder.appendingPathComponent("project.json"), options: [.atomic, .completeFileProtection])
        }
    }

    /// A project opened with Save and Share over it, as the Scan tab's Share asks.
    func share(_ id: UUID) {
        sharesOnOpen = true
        open(id)
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var now = project, now.name != trimmed else { return }
        now.name = trimmed
        now.modified = .now
        project = now
        remember(now)
        scheduleSave()
    }

    /// The page open in the editor, to open there again.
    func setOpenPage(_ id: UUID?) {
        guard var now = project, now.openPage != id else { return }
        now.openPage = id
        project = now
        remember(now)
        scheduleSave()
    }

    /// The project's export settings, kept with it.
    func setExport(paper: PaperSize, quality: ExportQuality) {
        guard var now = project, now.paper != paper || now.quality != quality else { return }
        now.paper = paper
        now.quality = quality
        project = now
        remember(now)
        scheduleSave()
    }

    private func reset() {
        saving?.cancel()
        history.clear()
        undoManager.removeAllActions()
        sessions = [:]
        used = []
        sources = [:]
        stillLocked = []
        aspects = [:]
        revisions = [:]
        thumbnails.removeAllObjects()
        locked = nil
        wrongPassword = false
        toast = nil
        // A PDF being added while its password was asked is left out.
        if let waiting = unlocking {
            unlocking = nil
            waiting.resume(returning: false)
        }
        updateUndo()
    }

    /// Files no page shows any more are let go, once nothing can be undone to them.
    private func tidy() {
        guard var now = project, !now.unused.isEmpty else { return }
        let gone = now.unused
        now.files.removeAll { file in gone.contains { $0.id == file.id } }
        project = now
        remember(now)
        let folder = Self.filesFolder(now.id)
        writer.async {
            for file in gone { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file.stored)) }
        }
        flush()
    }

    private func remember(_ project: PDFProject) {
        projects.removeAll { $0.id == project.id }
        projects.insert(project, at: 0)
    }

    // MARK: PDFs and their passwords

    private func openSources() {
        guard let project else { return }
        for file in project.files where file.kind == .pdf && sources[file.id] == nil {
            if let url = url(of: file.id), let source = PDFSource(url: url) {
                sources[file.id] = source
                if source.isLocked { stillLocked.insert(file.id) }
            }
        }
        askForLocked()
    }

    /// The first PDF still locked whose pages the project shows asks for its password.
    private func askForLocked() {
        guard locked == nil, let project else { return }
        locked = project.files.first { file in
            stillLocked.contains(file.id) && project.pages.contains { $0.source.file == file.id }
        }
    }

    /// Opens the PDF waiting with its password, kept in memory only while
    /// the project is open. False when it is not its password.
    @discardableResult
    func unlock(_ password: String) -> Bool {
        guard let file = locked, let source = sources[file.id] else { return false }
        guard source.unlock(password) else {
            wrongPassword = true
            return false
        }
        wrongPassword = false
        locked = nil
        stillLocked.remove(file.id)
        // Its pages can be drawn now, and an editor open on one starts afresh.
        aspects = aspects.filter { !$0.key.contains(file.id.uuidString) }
        for page in project?.pages ?? [] where page.source.file == file.id {
            sessions[page.id] = nil
            revisions[page.id, default: 0] += 1
        }
        objectWillChange.send()
        if let waiting = unlocking {
            unlocking = nil
            waiting.resume(returning: true)
        }
        askForLocked()
        return true
    }

    /// Not opened: its pages show locked, or, as it was being added, it is left out.
    func cancelUnlock() {
        locked = nil
        wrongPassword = false
        if let waiting = unlocking {
            unlocking = nil
            waiting.resume(returning: false)
        }
    }

    private func password(for file: ProjectFile) async -> Bool {
        // A PDF asked about before, while another was being added, is left out.
        if let waiting = unlocking {
            unlocking = nil
            waiting.resume(returning: false)
        }
        locked = file
        wrongPassword = false
        return await withCheckedContinuation { unlocking = $0 }
    }

    /// Whether a page's PDF waits for its password.
    func isLocked(_ page: ProjectPage) -> Bool {
        guard case .pdf(let file, _) = page.source else { return false }
        return sources[file] == nil || stillLocked.contains(file)
    }

    // MARK: Adding

    /// Files, photos, pictures or screenshots added after the page at
    /// `index`, or at the end, each copied into the project as it came: a
    /// PDF with all its pages, a picture as a page. Undone as one step.
    func add(_ items: ProjectImport, at index: Int? = nil) async {
        guard let id = project?.id else { return }
        var files: [ProjectFile] = []
        var pages: [ProjectPage] = []
        var failed = 0
        var signed = false
        let total = items.count
        adding = ProjectProgress(done: 0, total: total)
        defer { adding = nil }
        func added(_ file: ProjectFile, origin: PictureOrigin, kind: PaperKind? = nil) {
            files.append(file)
            pages += file.pages(origin: origin, kind: kind)
        }
        switch items {
        case .files(let urls):
            for (n, url) in urls.enumerated() {
                guard project?.id == id else { break }
                adding = ProjectProgress(done: n, total: total)
                guard let copied = await Self.run(on: writer, { Self.copy(url, into: id) }) else {
                    failed += 1
                    continue
                }
                if copied.kind == .picture {
                    added(copied, origin: .file)
                    continue
                }
                switch await opened(copied, in: id) {
                case .file(let file):
                    signed = signed || sources[file.id]?.isSigned == true
                    added(file, origin: .file)
                case .unreadable:
                    failed += 1
                case .left:
                    break
                }
            }
        case .photos(let items):
            for (n, item) in items.enumerated() {
                guard project?.id == id else { break }
                adding = ProjectProgress(done: n, total: total)
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }
                let ending = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                guard let file = await Self.run(on: writer, { Self.store(data, ending: ending, name: L("Photo"), into: id) })
                else {
                    failed += 1
                    continue
                }
                added(file, origin: .photo)
            }
        case .pictures(let images, let origin, let kind):
            for (n, image) in images.enumerated() {
                guard project?.id == id else { break }
                adding = ProjectProgress(done: n, total: total)
                let file = await Self.run(on: writer) { () -> ProjectFile? in
                    guard let jpeg = PictureTools.jpeg(image, quality: 0.92) else { return nil }
                    return Self.store(jpeg, ending: "jpg", name: L("Scanned"), into: id)
                }
                guard let file else {
                    failed += 1
                    continue
                }
                added(file, origin: origin, kind: kind)
            }
        case .screenshots(let ids):
            for (n, asset) in Library.assets(ids).enumerated() {
                guard project?.id == id else { break }
                adding = ProjectProgress(done: n, total: total)
                guard let image = await Library.image(of: asset), let png = Covering.png(image),
                      let file = await Self.run(on: writer, { Self.store(png, ending: "png", name: L("Screenshot"), into: id) })
                else {
                    failed += 1
                    continue
                }
                added(file, origin: .screenshot)
            }
        }
        guard project?.id == id else {
            // Closed while they were added: the copies go, or the whole folder once the project is gone.
            let gone = !projects.contains { $0.id == id }
            let folder = Self.filesFolder(id), whole = Self.folder(id), copies = files.map(\.stored)
            writer.async {
                if gone {
                    try? FileManager.default.removeItem(at: whole)
                } else {
                    for stored in copies { try? FileManager.default.removeItem(at: folder.appendingPathComponent(stored)) }
                }
            }
            return
        }
        if !pages.isEmpty {
            let count = pages.count
            change(count == 1 ? L("Add Page") : L("Add Pages")) { project in
                project.files += files
                project.insert(pages, at: index)
            }
            toast = ProjectToast(text: count == 1 ? L("1 page added") : String(format: L("%d pages added"), count))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            readKinds(files.filter { file in
                pages.contains { page in
                    guard case .picture(let shown, let origin, let kind) = page.source else { return false }
                    return shown == file.id && kind == nil && (origin == .photo || origin == .scan)
                }
            })
        }
        if failed > 0 {
            notice = .unreadable(failed)
        } else if signed {
            notice = .signed
        }
    }

    /// A PDF added: opened, or one that could not be read, or one left out
    /// because its password was not given.
    private enum Opened {
        case file(ProjectFile)
        case unreadable
        case left
    }

    /// A PDF copied in, opened, and asked for its password where it has
    /// one; where it cannot be read or its password was not given, its copy
    /// goes again.
    private func opened(_ copied: ProjectFile, in project: UUID) async -> Opened {
        let url = Self.filesFolder(project).appendingPathComponent(copied.stored)
        func drop() {
            sources[copied.id] = nil
            stillLocked.remove(copied.id)
            writer.async { try? FileManager.default.removeItem(at: url) }
        }
        guard let source = PDFSource(url: url) else {
            drop()
            return .unreadable
        }
        sources[copied.id] = source
        if source.isLocked {
            stillLocked.insert(copied.id)
            let given = await password(for: copied)
            guard given else {
                drop()
                return .left
            }
        }
        let count = source.pageCount
        guard count > 0 else {
            drop()
            return .unreadable
        }
        return .file(ProjectFile(id: copied.id, kind: .pdf, name: copied.name, stored: copied.stored, pageCount: count,
                                 digest: copied.digest))
    }

    /// A file copied into the project's folder as it came: a PDF, or a
    /// picture Image I/O can read; nil for anything else. Its digest is taken
    /// from what was read, so it shows the copy is the file as it came.
    nonisolated private static func copy(_ url: URL, into project: UUID) -> ProjectFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let name = url.lastPathComponent
        let file: ProjectFile?
        if PDFFacts.isPDF(data) {
            file = store(data, ending: "pdf", name: name, kind: .pdf, into: project)
        } else if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
            let ending = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
            file = store(data, ending: ending, name: name, into: project)
        } else {
            file = nil
        }
        // The copy iOS put in Snapfly's own Inbox for "Open in" goes once it is kept; the file itself stays where it was.
        if file != nil, url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        return file
    }

    /// Bytes kept in the project's folder, protected, under a name of their own.
    nonisolated private static func store(_ data: Data, ending: String, name: String, kind: ProjectFile.Kind = .picture,
                                          into project: UUID) -> ProjectFile? {
        let folder = filesFolder(project)
        let stored = UUID().uuidString + "." + ending
        do {
            try make(folder)
            try data.write(to: folder.appendingPathComponent(stored), options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ProjectFile(kind: kind, name: name, stored: stored, pageCount: kind == .pdf ? 0 : 1, digest: digest)
    }

    /// What kind of paper each photo or scan shows, from its words, read on
    /// this iPhone after it was added: "Foto · Beleg".
    private func readKinds(_ files: [ProjectFile]) {
        guard let id = project?.id, !files.isEmpty else { return }
        let urls = files.compactMap { file in url(of: file.id).map { (file.id, $0) } }
        Task {
            for (file, url) in urls {
                let kind = await Self.run(on: small) { () -> PaperKind? in
                    guard let image = PictureTools.read(url, longest: 2000), let lines = Finder.lines(in: image) else { return nil }
                    return ScanNaming.kind(of: lines.map(\.string))
                }
                guard let kind, var now = project, now.id == id else { continue }
                now.kinds[file.uuidString] = kind
                project = now
                remember(now)
                scheduleSave()
            }
        }
    }

    // MARK: Page operations

    /// A change to the pages, one step to undo: the project as it was is
    /// kept, the change is written a moment later. False where nothing changed.
    @discardableResult
    func change(_ name: String, _ body: (inout PDFProject) -> Void) -> Bool {
        guard var now = project else { return false }
        let before = now.pages
        body(&now)
        guard now.pages != before || now.files != project?.files else { return false }
        now.modified = .now
        project = now
        remember(now)
        if now.pages != before {
            history.record(before)
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.stepBack() } }
            undoManager.setActionName(name)
            undoManager.endUndoGrouping()
            settle(before, now.pages)
        }
        updateUndo()
        scheduleSave()
        return true
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
    }

    private func stepBack() {
        guard var now = project, let pages = history.undo(now.pages) else { return }
        let before = now.pages
        now.pages = pages
        now.modified = .now
        project = now
        remember(now)
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.stepForward() } }
        undoManager.endUndoGrouping()
        settle(before, pages)
        updateUndo()
        scheduleSave()
    }

    private func stepForward() {
        guard var now = project, let pages = history.redo(now.pages) else { return }
        let before = now.pages
        now.pages = pages
        now.modified = .now
        project = now
        remember(now)
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.stepBack() } }
        undoManager.endUndoGrouping()
        settle(before, pages)
        updateUndo()
        scheduleSave()
    }

    private func updateUndo() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    /// A page turned another way has its private details found again on it.
    private func settle(_ before: [ProjectPage], _ after: [ProjectPage]) {
        let was = Dictionary(before.map { ($0.id, $0.turns) }, uniquingKeysWith: { first, _ in first })
        for page in after where was[page.id].map({ $0 != page.turns }) == true {
            sessions[page.id] = nil
            used.removeAll { $0 == page.id }
            revisions[page.id, default: 0] += 1
        }
    }

    func turn(_ ids: Set<UUID>) {
        let count = project?.pages.filter { ids.contains($0.id) }.count ?? 0
        guard count > 0, change(L("Turn"), { $0.turn(ids) }) else { return }
        toast = ProjectToast(text: count == 1 ? L("1 page turned") : String(format: L("%d pages turned"), count))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @discardableResult
    func duplicate(_ ids: Set<UUID>) -> [UUID] {
        var made: [UUID] = []
        change(L("Duplicate")) { made = $0.duplicate(ids) }
        if !made.isEmpty {
            toast = ProjectToast(text: made.count == 1 ? L("1 page duplicated") : String(format: L("%d pages duplicated"), made.count))
        }
        return made
    }

    /// Pages taken away at once, without asking: a dark note says how many,
    /// with Undo.
    func delete(_ ids: Set<UUID>) {
        let count = project?.pages.filter { ids.contains($0.id) }.count ?? 0
        guard count > 0, change(L("Delete"), { $0.remove(ids) }) else { return }
        toast = ProjectToast(text: count == 1 ? L("1 page deleted") : String(format: L("%d pages deleted"), count))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func move(from: Int, to place: Int) {
        guard from != place, change(L("Move"), { $0.move(from: from, to: place) }) else { return }
        toast = ProjectToast(text: L("Page moved"))
    }

    func move(_ id: UUID, to place: Int) {
        guard let from = project?.index(of: id) else { return }
        move(from: from, to: place)
    }

    /// An empty page after the page at `index`, or at the end, of the paper used where the owner lives.
    @discardableResult
    func addBlank(at index: Int?) -> UUID? {
        var made: UUID?
        let size = PaperSize.blank(region: Locale.current.region?.identifier)
        change(L("Add Blank Page")) { project in
            made = project.insertBlank(at: index ?? project.pages.count, size: size)
        }
        if made != nil { toast = ProjectToast(text: L("Blank page added")) }
        return made
    }

    /// The toast's Undo, and then its Redo.
    func toastUndo() {
        guard var note = toast else { return }
        if note.undone { redo() } else { undo() }
        note.undone.toggle()
        toast = note
    }

    // MARK: Pictures of the pages

    /// A page's width over its height, upright as it came, before the owner's turns.
    func aspect(_ source: PageSource) -> CGFloat {
        let key = Self.key(source)
        if let known = aspects[key] { return known }
        var found: CGFloat?
        switch source {
        case .pdf(let file, let index):
            if let size = sources[file]?.size(of: index, turns: 0), size.height > 0 { found = size.width / size.height }
        case .picture(let file, _, _):
            if let url = url(of: file), let size = PictureTools.size(url), size.height > 0 { found = size.width / size.height }
        case .blank(let width, let height):
            found = height > 0 ? CGFloat(width / height) : nil
        }
        guard let found else { return PaperSize.a4Size.width / PaperSize.a4Size.height }
        aspects[key] = found
        return found
    }

    /// A page small, upright as it came, for the overview and the strip:
    /// drawn once and kept a while. Nil while its PDF is locked.
    func thumbnail(_ source: PageSource) async -> UIImage? {
        let key = Self.key(source)
        if let known = thumbnails.object(forKey: key as NSString) { return known }
        let wanted = self.wanted
        wanted.insert(key)
        let drawn = await withTaskCancellationHandler {
            await picture(of: source, turns: 0, longest: 360, dpi: 200, on: small, while: key)
        } onCancel: {
            wanted.remove(key)
        }
        if !Task.isCancelled { wanted.remove(key) }
        guard let drawn else { return nil }
        let image = UIImage(cgImage: drawn)
        thumbnails.setObject(image, forKey: key as NSString, cost: drawn.width * drawn.height * 4)
        return image
    }

    /// The page in the editor: as sharp as a phone's screen zoomed in a way
    /// needs, turned as the owner turned it.
    func picture(_ id: UUID) async -> CGImage? {
        guard let page = project?.pages.first(where: { $0.id == id }) else { return nil }
        return await picture(of: page.source, turns: page.turns, longest: 2400, dpi: 220, on: large)
    }

    private func picture(of source: PageSource, turns: Int, longest: Int, dpi: Double, on queue: DispatchQueue,
                         while key: String? = nil) async -> CGImage? {
        let wanted = self.wanted
        switch source {
        case .pdf(let file, let index):
            guard let pdf = sources[file] else { return nil }
            return await Self.run(on: queue) { () -> CGImage? in
                if let key, !wanted.contains(key) { return nil }
                return pdf.render(index, turns: turns, dpi: dpi, longest: longest)
            }
        case .picture(let file, _, _):
            guard let url = url(of: file) else { return nil }
            return await Self.run(on: queue) { () -> CGImage? in
                if let key, !wanted.contains(key) { return nil }
                return PictureTools.read(url, longest: longest).flatMap { PictureTools.turned($0, quarters: turns) }
            }
        case .blank(let width, let height):
            let size = PDFPageGeometry.shown(CGRect(x: 0, y: 0, width: width, height: height), rotation: turns % 2 * 90)
            let scale = min(dpi / 72, Double(longest) / Double(max(size.width, size.height)))
            return PictureTools.blank(width: max(1, Int(Double(size.width) * scale)), height: max(1, Int(Double(size.height) * scale)))
        }
    }

    private static func key(_ source: PageSource) -> String {
        switch source {
        case .pdf(let file, let index): "pdf-\(file.uuidString)-\(index)"
        case .picture(let file, _, _): "picture-\(file.uuidString)"
        case .blank(let width, let height): "blank-\(width)x\(height)"
        }
    }

    /// Before a PDF's page is covered, its words are taken from its text
    /// where it has text, letter for letter, and from the picture only
    /// where the text has none, as in a photo pasted on the page.
    func prepareReading(_ id: UUID, for image: CGImage) async {
        guard let page = project?.pages.first(where: { $0.id == id }) else { return }
        await prepareReading(page, for: image)
    }

    private func prepareReading(_ page: ProjectPage, for image: CGImage) async {
        guard case .pdf(let file, let index) = page.source, let pdf = sources[file] else { return }
        let turns = page.turns
        await Self.run(on: large) {
            guard let layer = pdf.lines(index, turns: turns) else { return }
            let read = Finder.lines(in: image) ?? []
            let extra = PDFTextLayer.added(read: read.map(\.box), over: layer.map(\.box)).map { read[$0] }
            Finder.remember(layer + extra, for: image)
        }
    }

    // MARK: The first page covered, for the Scan tab

    /// A project's first page, small and covered as Settings says, for the
    /// Scan tab's recent documents: drawn and covered once, then kept in
    /// memory and beside the project, closed while the iPhone is locked.
    /// Nil where it cannot be read or covered, or its PDF is locked: an
    /// uncovered page never shows there.
    func coveredFirstPage(_ project: PDFProject) async -> UIImage? {
        guard let page = project.pages.first else { return nil }
        let details = Choice.details.map(\.rawValue).sorted().joined(separator: ",")
        let made = "\(Self.key(page.source))-\(page.turns)-\(details)-\(CoverStyle.current)-\(OwnRules.all.count)"
        let name = "Cover-" + SHA256.hash(data: Data(made.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() + ".jpg"
        if let known = coveredFirst.object(forKey: name as NSString) { return known }
        let folder = Self.folder(project.id)
        let previous = covering
        let task = Task { [weak self] () -> UIImage? in
            _ = await previous?.value
            guard let self else { return nil }
            if let known = self.coveredFirst.object(forKey: name as NSString) { return known }
            let kept = await Self.run(on: self.small) { () -> CGImage? in
                PictureTools.read(folder.appendingPathComponent(name), longest: 480)
            }
            if let kept {
                let image = UIImage(cgImage: kept)
                self.coveredFirst.setObject(image, forKey: name as NSString)
                return image
            }
            guard let drawn = await Self.firstPage(page, of: project, on: self.small),
                  let covered = await Covering.cover(drawn, Choice.details)?.image else { return nil }
            let small = await Self.run(on: self.small) { () -> CGImage? in
                let small = ScanCleaner.smaller(covered, longest: 480) ?? covered
                // Kept beside the project, in place of the one drawn before.
                let old = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for file in old where file.hasPrefix("Cover-") {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
                }
                if let jpeg = ScanCleaner.jpeg(small, quality: 0.8) {
                    try? jpeg.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
                }
                return small
            }
            guard let small else { return nil }
            let image = UIImage(cgImage: small)
            self.coveredFirst.setObject(image, forKey: name as NSString)
            return image
        }
        covering = task
        return await task.value
    }

    /// A project's first page covered, then veiled (`ScanVeil`), as the Scan
    /// tab shows it until the owner shows the pictures: made from the
    /// covered copy only, never from the page without its covers.
    func veiledFirstPage(_ project: PDFProject) async -> UIImage? {
        guard let covered = await coveredFirstPage(project) else { return nil }
        if let known = veiledFirst.object(forKey: covered) { return known }
        guard let source = covered.cgImage else { return nil }
        let made = await Self.run(on: small) { ScanVeil.image(source) }
        guard let made else { return nil }
        let image = UIImage(cgImage: made)
        veiledFirst.setObject(image, forKey: covered)
        return image
    }

    /// A project's first page as it shows, drawn from its copy in the
    /// project's folder, whether the project is open or not; nil while its
    /// PDF is locked.
    nonisolated private static func firstPage(_ page: ProjectPage, of project: PDFProject,
                                              on queue: DispatchQueue) async -> CGImage? {
        let files = filesFolder(project.id)
        return await run(on: queue) { () -> CGImage? in
            switch page.source {
            case .pdf(let file, let index):
                guard let stored = project.file(file)?.stored, let pdf = PDFSource(url: files.appendingPathComponent(stored)),
                      !pdf.isLocked else { return nil }
                return pdf.render(index, turns: page.turns, dpi: 150, longest: 1400)
            case .picture(let file, _, _):
                guard let stored = project.file(file)?.stored else { return nil }
                return PictureTools.read(files.appendingPathComponent(stored), longest: 1400)
                    .flatMap { PictureTools.turned($0, quarters: page.turns) }
            case .blank(let width, let height):
                let size = PDFPageGeometry.shown(CGRect(x: 0, y: 0, width: width, height: height), rotation: page.turns % 2 * 90)
                let scale = 480 / Double(max(size.width, size.height))
                return PictureTools.blank(width: max(1, Int(Double(size.width) * scale)),
                                          height: max(1, Int(Double(size.height) * scale)))
            }
        }
    }

    // MARK: The editor's protections

    /// A page's protection, made the first time it is opened and kept, so
    /// it opens again as it was left and the PDF takes it as it is.
    func session(_ id: UUID) -> ProtectSession {
        if let session = sessions[id] {
            touch(id)
            return session
        }
        let session = ProtectSession(source: .page(id))
        sessions[id] = session
        touch(id)
        return session
    }

    func opened(_ id: UUID) -> ProtectSession? { sessions[id] }

    private func touch(_ id: UUID) {
        used.removeAll { $0 == id }
        used.append(id)
        // The oldest let go, unless something was changed on them by hand.
        while used.count > Self.keptSessions,
              let old = used.dropLast().first(where: { sessions[$0]?.plan.isChanged != true }) {
            used.removeAll { $0 == old }
            sessions[old] = nil
        }
    }

    // MARK: Leaving

    /// The pages as one PDF, as `ProjectExport` says: covered, every page
    /// as a picture with its words read again from the covered page; or not.
    /// `only` the pages chosen, else all. Throws, saying which page, when
    /// one cannot be read or covered.
    func pdf(_ options: ProjectExport, only: Set<UUID>? = nil) async throws -> Data {
        guard let project else { throw ScanProblem(message: L("The file could not be made.")) }
        let pages = only.map { project.only($0).pages } ?? project.pages
        guard !pages.isEmpty else { throw ScanProblem(message: L("The file could not be made.")) }
        making = ProjectProgress(done: 0, total: pages.count)
        defer { making = nil }
        var parts: [PDFComposer.Either] = []
        for (index, page) in pages.enumerated() {
            making = ProjectProgress(done: index, total: pages.count)
            parts.append(try await part(page, options, number: index + 1))
        }
        let all = Parts(list: parts)
        guard let file = await Self.run(on: large, { PDFComposer.make(all.list) }) else {
            throw ScanProblem(message: L("The file could not be made."))
        }
        return file
    }

    /// One page of the PDF.
    private func part(_ page: ProjectPage, _ options: ProjectExport, number: Int) async throws -> PDFComposer.Either {
        let own = ownPage(page)
        if case .blank = page.source, let own { return .made(PDFComposer.blank(own)) }
        // Without covers, with its text: a PDF's page stays as it is.
        if !options.covered, options.searchable, case .pdf(let file, let index) = page.source {
            guard let copy = sources[file]?.copy(index, turns: page.turns) else {
                throw ScanProblem(message: String(format: L("Page %d could not be read."), number))
            }
            return .kept(copy)
        }
        guard let image = await picture(of: page.source, turns: page.turns, longest: 5000, dpi: options.quality.dpi, on: large)
        else { throw ScanProblem(message: String(format: L("Page %d could not be read."), number)) }
        let paper = options.paper, quality = options.quality
        if options.covered {
            let made = try await covered(page, image, failing: L("Page %d could not be covered, so no PDF was made."),
                                         number: number)
            let searchable = options.searchable
            let drawn = await Self.run(on: large) { () -> ScanPDF.Page? in
                let words = searchable ? ScanCleaner.words(in: Finder.lines(in: made.image) ?? [], hiding: made.places) : []
                return PDFComposer.page(made.image, ownPage: own, paper: paper, quality: quality, words: words)
            }
            guard let drawn else { throw ScanProblem(message: L("The file could not be made.")) }
            return .made(drawn)
        }
        let searchable = options.searchable
        let made = await Self.run(on: large) { () -> ScanPDF.Page? in
            let words = searchable ? ScanCleaner.words(in: Finder.lines(in: image) ?? []) : []
            return PDFComposer.page(image, ownPage: own, paper: paper, quality: quality, words: words)
        }
        guard let made else { throw ScanProblem(message: L("The file could not be made.")) }
        return .made(made)
    }

    /// The page's own size in the PDF: a PDF's page and an empty page keep
    /// theirs, turned; a picture's is as the paper says.
    private func ownPage(_ page: ProjectPage) -> CGSize? {
        switch page.source {
        case .pdf(let file, let index):
            return sources[file]?.size(of: index, turns: page.turns)
        case .blank(let width, let height):
            return PDFPageGeometry.shown(CGRect(x: 0, y: 0, width: width, height: height), rotation: page.turns % 2 * 90)
        case .picture:
            return nil
        }
    }

    /// A page drawn for the PDF, covered: as its editor left it where it was
    /// opened, once its copy is checked; any other as Settings says.
    private func covered(_ page: ProjectPage, _ image: CGImage, failing: String,
                         number: Int) async throws -> (image: CGImage, places: [CGRect]) {
        await prepareReading(page, for: image)
        if let session = sessions[page.id], !session.hasFailed {
            // A copy being made again after a change is waited for, half a minute at most.
            var waited = 0
            while !session.isReady, waited < 300 {
                if session.hasFailed { break }
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            guard session.isReady else {
                throw ScanProblem(message: String(format: L("Page %d is not ready yet. Open it to check it."), number))
            }
            guard let made = await session.cover(image) else { throw ScanProblem(message: String(format: failing, number)) }
            return made
        }
        guard let made = await Covering.cover(image, Choice.details) else {
            throw ScanProblem(message: String(format: failing, number))
        }
        return (made.image, made.report.places)
    }

    /// The pages as PNGs, each covered, for Save as Pictures.
    func pngs(only: Set<UUID>? = nil) async throws -> [Data] {
        guard let project else { throw ScanProblem(message: L("The copy could not be made.")) }
        let pages = only.map { project.only($0).pages } ?? project.pages
        making = ProjectProgress(done: 0, total: pages.count)
        defer { making = nil }
        var made: [Data] = []
        for (index, page) in pages.enumerated() {
            making = ProjectProgress(done: index, total: pages.count)
            guard let image = await picture(of: page.source, turns: page.turns, longest: 4000,
                                            dpi: ExportQuality.medium.dpi, on: large) else {
                throw ScanProblem(message: String(format: L("Page %d could not be read."), index + 1))
            }
            let covered = try await covered(page, image, failing: L("Page %d could not be covered, so nothing was saved."),
                                            number: index + 1)
            guard let png = Covering.png(covered.image) else { throw ScanProblem(message: L("The copy could not be made.")) }
            made.append(png)
        }
        return made
    }

    /// How large the PDF will be, from a few of its pages made as it would
    /// make them, without covers, which change little; nil where none could be made.
    func estimate(_ options: ProjectExport, only: Set<UUID>? = nil) async -> Int? {
        guard let project else { return nil }
        let pages = only.map { project.only($0).pages } ?? project.pages
        var sizes: [Int] = []
        for index in SizeEstimate.sample(count: pages.count) {
            guard !Task.isCancelled else { return nil }
            let page = pages[index]
            if !options.covered, options.searchable, case .pdf(let file, _) = page.source {
                sizes.append(sources[file]?.bytesPerPage ?? 0)
                continue
            }
            if case .blank = page.source {
                sizes.append(300)
                continue
            }
            guard let image = await picture(of: page.source, turns: page.turns, longest: 5000, dpi: options.quality.dpi,
                                            on: small) else { continue }
            let own = ownPage(page), paper = options.paper, quality = options.quality
            let bytes = await Self.run(on: small) { () -> Int? in
                guard let made = PDFComposer.page(image, ownPage: own, paper: paper, quality: quality, words: []),
                      case .jpeg(let data, _, _, _) = made.picture else { return nil }
                // Its page and contents round the picture.
                return data.count + 400
            }
            if let bytes { sizes.append(bytes) }
        }
        return SizeEstimate.bytes(sampled: sizes, count: pages.count)
    }

    // MARK: Helpers

    /// Work on a queue of its own, off the main thread, waited for.
    nonisolated private static func run<T>(on queue: DispatchQueue, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in
            queue.async { done.resume(returning: work()) }
        }
    }

    /// Pages for the PDF, handed to the queue that writes it.
    private struct Parts: @unchecked Sendable {
        let list: [PDFComposer.Either]
    }

}

/// The thumbnails still wanted, so one no longer on screen is not drawn.
private final class Wanted: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Int] = [:]

    func insert(_ key: String) {
        lock.lock()
        keys[key, default: 0] += 1
        lock.unlock()
    }

    func remove(_ key: String) {
        lock.lock()
        if let count = keys[key] { keys[key] = count > 1 ? count - 1 : nil }
        lock.unlock()
    }

    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return keys[key] != nil
    }
}
