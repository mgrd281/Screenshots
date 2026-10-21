import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A photo chosen to scan: the picture upright, the lens its notes give,
/// and where the page is in it when that is known already.
struct ScanPhoto {
    let image: CGImage
    var focal: Double? = nil
    var quad: ScanQuad? = nil

    /// A photo from its data as Photos gives it, turned upright; nil when
    /// it cannot be read.
    init?(data: Data) {
        guard let image = Covering.upright(data) else { return nil }
        self.image = image
        focal = ScanCleaner.focalLength(of: data, width: image.width, height: image.height)
    }

    init(image: CGImage, focal: Double? = nil, quad: ScanQuad? = nil) {
        self.image = image
        self.focal = focal
        self.quad = quad
    }

    /// The photos chosen in the picker, in the order chosen, leaving out
    /// any that cannot be read.
    static func read(_ items: [PhotosPickerItem]) async -> [ScanPhoto] {
        var photos: [ScanPhoto] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let photo = ScanPhoto(data: data) else { continue }
            photos.append(photo)
        }
        return photos
    }
}

/// Why the scanned pages could not leave, in words for a note.
struct ScanProblem: Error {
    let message: String
}

/// The pages scanned while the app runs, in the document's order: from the
/// camera, or photos chosen; each made flat, upright and level, cleaned in
/// the document's colours and checked (`ScanCleaner`), one after another
/// off the main thread, and covered in its editor like any screenshot. Each
/// page keeps the protection of the editor it was opened in, so it opens
/// again as it was left and what leaves takes it as it is. Nothing is ever
/// written anywhere but what the owner saves or shares.
@MainActor
final class ScannedPages: ObservableObject {
    static let shared = ScannedPages()

    /// Where a page came from.
    enum Origin: Equatable {
        case camera, photo
    }

    struct Page: Identifiable {
        enum State: Equatable {
            /// Waiting its turn to be made ready.
            case waiting
            /// Being made flat, cleaned and checked.
            case improving
            /// Vision was not sure where the page is in the photo: its
            /// corners wait to be set by hand.
            case needsCorners
            case ready
            /// The picture could not be read.
            case failed
        }

        let id = UUID()
        let origin: Origin
        /// The picture as it came: the camera's page, or the photo.
        let source: CGImage
        /// The photo's lens, in pixels, where its notes say, for the page's true shape.
        let focal: Double?
        /// Where the page is in the photo, from 0 to 1 from the bottom left;
        /// nil for a camera's page, taken whole.
        var quad: ScanQuad?
        /// Quarter turns clockwise and the lean taken away; nil until found.
        var way: (turns: Int, skew: Double)?
        /// Before and after cleaning, once made.
        var straightened: CGImage?
        var cleaned: CGImage?
        /// Before as the editor shows it, made once.
        var before: UIImage?
        /// The cleaned page small, for the strip and the cards.
        var thumbnail: UIImage?
        var issues: [ScanIssue] = []
        /// Whether every number read before cleaning was read after; nil
        /// where no text was read.
        var textKept: Bool?
        /// The cleaned page as it was read, for a PDF's text.
        var reading: [Finder.TextLine] = []
        var state = State.waiting
        /// Each new shape or picture, so its editor starts afresh.
        var revision = 0
        /// Its cleaning has been shown in the editor, with the wipe.
        var shown = false
        /// Whether its shape must be found again, not only its colours.
        fileprivate var reshape = true
        /// Each time it is asked for again, so work begun before is dropped.
        fileprivate var job = 0

        init(origin: Origin, source: CGImage, focal: Double? = nil, quad: ScanQuad? = nil) {
            self.origin = origin
            self.source = source
            self.focal = focal
            self.quad = quad
        }

        /// What is covered and leaves: the cleaned page, or the page as it
        /// came while it is made.
        var image: CGImage { cleaned ?? source }

        /// What is wrong with it, most important first, and the place of
        /// each, for the editor's highlights.
        var places: [CGRect] { issues.compactMap(\.area) }
    }

    @Published private(set) var pages: [Page] = []
    /// How the document keeps its colours, every page alike.
    @Published private(set) var mode = ScanColor.color
    /// The page being made ready, counted from 1, for its note; nil while none is.
    @Published private(set) var improving: Int?
    /// The page being covered for a file or an app, counted from 1; nil while none is.
    @Published private(set) var making: Int?
    /// The app the pages are going to, while they are covered.
    @Published private(set) var sendingTo: ChatTarget?
    /// A photo whose page Vision was not sure of, waiting for its corners.
    @Published var cornersWanted: UUID?
    @Published private var sessions: [UUID: ProtectSession] = [:]
    private var worker: Task<Void, Never>?
    private var waiting: [UUID: [CheckedContinuation<CGImage?, Never>]] = [:]
    /// The pages whose warnings were said, so each is said once.
    private var said: Set<UUID> = []

    /// Vision's certainty of a photo's page under which its corners are set by hand.
    static let sure: Float = 0.65

    // MARK: Adding

    /// Pages from the camera, after those before, given back; a light tap says they came.
    @discardableResult
    func add(camera images: [CGImage], at index: Int? = nil) -> [Page] {
        insert(images.map { Page(origin: .camera, source: $0) }, at: index)
    }

    /// Photos chosen, after those before. With `unsure`, their corners are
    /// set by hand before anything else, as when Vision is not sure.
    @discardableResult
    func add(photos: [ScanPhoto], unsure: Bool = false, at index: Int? = nil) -> [Page] {
        var new = photos.map { Page(origin: .photo, source: $0.image, focal: $0.focal, quad: $0.quad) }
        if unsure {
            for i in new.indices {
                new[i].quad = new[i].quad ?? .inset(0.06)
                new[i].state = .needsCorners
            }
        }
        let added = insert(new, at: index)
        if unsure, cornersWanted == nil { cornersWanted = added.first?.id }
        return added
    }

    private func insert(_ new: [Page], at index: Int?) -> [Page] {
        guard !new.isEmpty else { return [] }
        pages.insert(contentsOf: new, at: min(index ?? pages.count, pages.count))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        improve()
        return new
    }

    /// A page taken again: the new pages in its place, it gone.
    @discardableResult
    func replace(_ id: UUID, camera images: [CGImage] = [], photos: [ScanPhoto] = []) -> [Page] {
        guard let index = index(of: id), !(images.isEmpty && photos.isEmpty) else { return [] }
        remove(id)
        return images.isEmpty ? add(photos: photos, at: index) : add(camera: images, at: index)
    }

    func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
        sessions[id] = nil
        if cornersWanted == id { cornersWanted = pages.first { $0.state == .needsCorners }?.id }
        settle(id)
    }

    func clear() {
        let gone = pages.map(\.id)
        pages = []
        sessions = [:]
        cornersWanted = nil
        gone.forEach(settle)
    }

    /// A page moved to another place in the document.
    func move(_ id: UUID, to place: Int) {
        guard let from = index(of: id) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: min(max(place, 0), pages.count))
    }

    // MARK: Finding

    func index(of id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    func page(_ id: UUID) -> Page? { pages.first { $0.id == id } }

    /// The page as it is covered: cleaned once it is ready.
    func image(_ id: UUID) -> CGImage? { page(id)?.image }

    /// The cleaned page once it is ready, waiting for it; nil when it could
    /// not be made or was taken away.
    func ready(_ id: UUID) async -> CGImage? {
        guard let page = page(id) else { return nil }
        switch page.state {
        case .ready: return page.cleaned
        case .failed: return nil
        default: return await withCheckedContinuation { waiting[id, default: []].append($0) }
        }
    }

    private func settle(_ id: UUID) {
        let image = page(id).flatMap { $0.state == .ready ? $0.cleaned : nil }
        waiting.removeValue(forKey: id)?.forEach { $0.resume(returning: image) }
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

    /// The cleaning was shown once, with the wipe.
    func markShown(_ id: UUID) {
        guard let index = index(of: id) else { return }
        pages[index].shown = true
    }

    /// Whether a page's warning is yet to be said; once asked, it is said.
    func sayOnce(_ id: UUID) -> Bool {
        said.insert(id).inserted
    }

    // MARK: Changing

    /// Every page in other colours, kept where it is and covered as it was.
    func setMode(_ mode: ScanColor) {
        guard mode != self.mode else { return }
        self.mode = mode
        for index in pages.indices where pages[index].state != .needsCorners {
            again(index, reshape: false)
        }
        improve()
    }

    /// A page turned a quarter clockwise; its covers are found again.
    func turn(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let way = pages[index].way ?? (0, 0)
        pages[index].way = ((way.turns + 1) % 4, way.skew)
        restart(index)
    }

    /// A page cut from its picture by new corners; its covers are found again.
    func setCorners(_ id: UUID, _ quad: ScanQuad) {
        guard let index = index(of: id) else { return }
        pages[index].quad = quad
        // The lean is found again for the new cut; the quarter turns stay.
        if let way = pages[index].way { pages[index].way = (way.turns, 0) }
        restart(index)
        if cornersWanted == id { cornersWanted = pages.first { $0.state == .needsCorners }?.id }
    }

    private func restart(_ index: Int) {
        sessions[pages[index].id] = nil
        pages[index].revision += 1
        pages[index].shown = false
        again(index, reshape: true)
        improve()
    }

    private func again(_ index: Int, reshape: Bool) {
        pages[index].job += 1
        pages[index].reshape = pages[index].reshape || reshape
        pages[index].state = .waiting
    }

    // MARK: Making ready

    /// Makes the waiting pages ready, one after another, while any wait.
    private func improve() {
        guard worker == nil else { return }
        worker = Task {
            while let id = pages.first(where: { $0.state == .waiting })?.id {
                await prepare(id)
            }
            improving = nil
            worker = nil
        }
    }

    private func prepare(_ id: UUID) async {
        guard let index = index(of: id) else { return }
        improving = index + 1
        let job = pages[index].job
        // A photo's page is found first; where Vision is not sure, its corners wait for the owner.
        if pages[index].origin == .photo, pages[index].quad == nil {
            let source = pages[index].source
            let found = await Task.detached(priority: .userInitiated) { ScanCleaner.page(in: source) }.value
            guard let at = self.index(of: id), pages[at].job == job else { return }
            if let found, found.confidence >= Self.sure {
                pages[at].quad = found.quad
            } else {
                pages[at].quad = found?.quad ?? .inset(0.06)
                pages[at].state = .needsCorners
                if cornersWanted == nil { cornersWanted = id }
                return
            }
        }
        guard let at = self.index(of: id) else { return }
        pages[at].state = .improving
        let page = pages[at], mode = self.mode
        let photo = page.origin == .photo ? page.source : nil
        let prepared: ScanCleaner.Prepared?
        if !page.reshape, let straight = page.straightened, let way = page.way {
            prepared = await Task.detached(priority: .userInitiated) {
                await ScanCleaner.finished(straight, turns: way.turns, skew: way.skew, mode: mode, photo: photo)
            }.value
        } else {
            let source = page.source, quad = page.quad, way = page.way, focal = page.focal
            prepared = await Task.detached(priority: .userInitiated) {
                await ScanCleaner.prepare(source, quad: quad, way: way, focal: focal, mode: mode)
            }.value
        }
        let thumbnail = await Task.detached(priority: .userInitiated) {
            prepared.flatMap { ScanCleaner.smaller($0.cleaned, longest: 240) }.map { UIImage(cgImage: $0) }
        }.value
        // Asked for again meanwhile: what was made is dropped, and it waits its turn.
        guard let done = self.index(of: id), pages[done].job == job, self.mode == mode else { return }
        guard let prepared else {
            pages[done].state = .failed
            settle(id)
            return
        }
        let colorsOnly = !page.reshape
        if pages[done].straightened !== prepared.straightened { pages[done].before = UIImage(cgImage: prepared.straightened) }
        pages[done].straightened = prepared.straightened
        pages[done].cleaned = prepared.cleaned
        pages[done].thumbnail = thumbnail
        pages[done].way = (prepared.turns, prepared.skew)
        pages[done].issues = prepared.checked.issues
        pages[done].textKept = prepared.checked.textKept
        pages[done].reading = prepared.checked.reading
        pages[done].reshape = false
        pages[done].state = .ready
        // An editor open on it keeps its covers on the page in its new colours.
        if colorsOnly, let session = sessions[id] { session.replace(prepared.cleaned) }
        settle(id)
        if !colorsOnly, prepared.checked.issues.contains(where: \.asksForRetake) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    // MARK: Leaving

    /// Every page covered, in their order, with where each is covered: one
    /// opened before as it was left there, once its copy is checked, any
    /// other as Settings says. Throws, saying which page, when one is not
    /// ready or cannot be covered; `failing` names a page that cannot.
    func covered(failing: String) async throws -> [(image: CGImage, places: [CGRect])] {
        var done: [(image: CGImage, places: [CGRect])] = []
        defer { making = nil }
        for (index, page) in pages.enumerated() {
            making = index + 1
            if let session = sessions[page.id] {
                guard let copy = await checked(session) else {
                    throw ScanProblem(message: String(format: L("Page %d is not ready yet. Open it to check it."), index + 1))
                }
                done.append(copy)
            } else {
                guard let image = await ready(page.id), let made = await Covering.cover(image, Choice.details) else {
                    throw ScanProblem(message: String(format: failing, index + 1))
                }
                done.append((made.image, made.report.places))
            }
        }
        return done
    }

    /// A page's copy as its editor left it, once made and checked: waited
    /// for a little while it is made again after a change; nil when it is
    /// not ready by then or could not be made.
    private func checked(_ session: ProtectSession) async -> (image: CGImage, places: [CGRect])? {
        for _ in 0..<100 {
            if session.isReady, let copy = session.copy?.cgImage { return (copy, session.plan.covered.map(\.rect)) }
            if case .failed = session.stage { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// The pages as they leave without covers: cleaned only, with what was
    /// read on them. Throws while one is not ready.
    func uncovered() async throws -> [(image: CGImage, reading: [Finder.TextLine])] {
        var done: [(image: CGImage, reading: [Finder.TextLine])] = []
        for (index, page) in pages.enumerated() {
            guard let image = await ready(page.id), let kept = self.page(page.id) else {
                throw ScanProblem(message: String(format: L("Page %d could not be read."), index + 1))
            }
            done.append((image, kept.reading))
        }
        return done
    }

    /// The document as one PDF: covered, its text read again on the covered
    /// pages and none of it from under a cover; or not covered, with all of
    /// its text. Without `text`, pictures only.
    func pdf(covered: Bool, text: Bool) async throws -> Data {
        let mode = self.mode
        let file: Data?
        if covered {
            let pages = try await self.covered(failing: L("Page %d could not be covered, so no PDF was made."))
            file = await Task.detached(priority: .userInitiated) {
                let made = pages.compactMap { page -> ScanPDF.Page? in
                    let words = text ? ScanCleaner.words(in: Finder.lines(in: page.image) ?? [], hiding: page.places) : []
                    return ScanCleaner.pdfPage(page.image, mode: mode, words: words)
                }
                return made.count == pages.count ? ScanPDF.make(made) : nil
            }.value
        } else {
            let pages = try await uncovered()
            file = await Task.detached(priority: .userInitiated) {
                let made = pages.compactMap { page in
                    ScanCleaner.pdfPage(page.image, mode: mode, words: text ? ScanCleaner.words(in: page.reading) : [])
                }
                return made.count == pages.count ? ScanPDF.make(made) : nil
            }.value
        }
        guard let file else { throw ScanProblem(message: L("The file could not be made.")) }
        return file
    }

    /// The pages as PNGs, full size, without notes: covered, or cleaned only.
    func pngs(covered: Bool) async throws -> [Data] {
        let images: [CGImage]
        if covered {
            images = try await self.covered(failing: L("Page %d could not be covered, so nothing was saved.")).map(\.image)
        } else {
            images = try await uncovered().map(\.image)
        }
        let pngs = await Task.detached(priority: .userInitiated) { images.compactMap(Covering.png) }.value
        guard pngs.count == images.count else { throw ScanProblem(message: L("The file could not be made.")) }
        return pngs
    }

    /// Covers every page and hands them to the app: one page straight to
    /// WhatsApp, or to an AI chat opened with it copied, else through the
    /// share sheet, where the app is tapped (`Handoff`). If a page cannot
    /// be covered, nothing goes at all.
    func send(to chat: ChatTarget) {
        guard making == nil, !pages.isEmpty else { return }
        sendingTo = chat
        Task {
            defer { sendingTo = nil }
            let finished: [(image: CGImage, places: [CGRect])]
            do {
                finished = try await covered(failing: L("Page %d could not be covered, so nothing was sent."))
            } catch {
                return QuickCoverer.shared.show((error as? ScanProblem)?.message ?? L("The copy could not be made."), for: 4)
            }
            let images = finished.map(\.image)
            let pngs = await Task.detached(priority: .userInitiated) { images.compactMap(Covering.png) }.value
            guard pngs.count == images.count else {
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

    /// The name the files are offered under: the app and the day.
    static var fileName: String {
        "Snapfly " + Date.now.formatted(.iso8601.year().month().day())
    }
}
