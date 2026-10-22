import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A picture being protected: shown at once, then covered in steps. A first
/// pass without Apple Intelligence marks what the patterns, the labels and
/// the names find; the copy is made and read again as anyone could read it;
/// then, where it is on, Apple Intelligence reads along and adds what it
/// finds. The owner can turn places on and off, cover more by hand and undo.
/// Nothing leaves until the copy is made and checked for the places as they
/// are now.
@MainActor
final class ProtectSession: ObservableObject {
    /// Where the picture comes from.
    enum Source: Hashable {
        /// A screenshot in Photos, by its identifier.
        case asset(String)
        /// A picture chosen from Photos, kept while the app runs.
        case picture(UUID)
        /// A page scanned with the camera, kept while the app runs.
        case scanned(UUID)
        /// A page of the PDF project open, kept with the project (`ProjectStore`).
        case page(UUID)
    }

    /// How far the protection is.
    enum Stage: Equatable {
        case opening
        case finding
        case checking
        case intelligence
        case ready
        case failed(String)
    }

    let source: Source
    /// A small picture shown while the whole one loads.
    @Published private(set) var preview: UIImage?
    @Published private(set) var original: UIImage?
    /// The covered copy, as it leaves; nil while it is made again.
    @Published private(set) var copy: UIImage?
    @Published private(set) var png: Data?
    @Published private(set) var plan = ProtectionPlan()
    /// The first pass is done and its places are marked.
    @Published private(set) var found = false
    /// A copy is being made and checked.
    @Published private(set) var making = false
    /// Apple Intelligence is still reading, and the copy waits for it.
    @Published private(set) var intelligencePending = false
    @Published private(set) var failure: String?
    /// A photo chosen in Photos that looks like a photographed paper
    /// document: where its page is, to offer to straighten and brighten it
    /// as a scan is. Never done unasked, never for a screenshot.
    @Published private(set) var documentPage: ScanQuad?
    /// The page is being straightened and brightened.
    @Published private(set) var cleaning = false
    /// The photo shows straightened and brightened, its covers found again
    /// on it, until Undo.
    @Published private(set) var cleaned = false
    /// Why the photo stayed as it was after Straighten and Brighten.
    @Published var cleaningNote: String?

    private var image: CGImage?
    /// Every word read and where it is, so a tap hides one; in memory only.
    private var words: [(text: String, box: CGRect)] = []
    private let chosen = Choice.details
    private let rules = OwnRules.all
    private let style = CoverStyle.current
    /// Each copy asked for; one made for older places is dropped.
    private var generation = 0
    private var running: Task<Void, Never>?
    private var remaking: Task<Void, Never>?
    /// The photo and its covers as they were before it was cleaned.
    private var beforeCleaning: Kept?

    /// A picture with its covers, as it stood, to go back to.
    private struct Kept {
        let image: CGImage
        let original: UIImage?
        let plan: ProtectionPlan
        let words: [(text: String, box: CGRect)]
        let copy: UIImage?
        let png: Data?
    }

    init(source: Source) {
        self.source = source
    }

    /// The protection for a source: a scanned page's is kept with the page,
    /// so it opens again as it was left and its PDF takes it as it is.
    static func made(for source: Source) -> ProtectSession {
        if case .scanned(let id) = source { return ScannedPages.shared.session(id) }
        if case .page(let id) = source { return ProjectStore.shared.session(id) }
        return ProtectSession(source: source)
    }

    var stage: Stage {
        if let failure { return .failed(failure) }
        if original == nil { return .opening }
        if !found { return .finding }
        if making || png == nil { return .checking }
        if intelligencePending { return .intelligence }
        return .ready
    }

    /// Whether the copy may leave: made and checked for the places as they are.
    var isReady: Bool { stage == .ready }

    /// Whether Apple Intelligence, or the AI assistant, reads along for
    /// the kinds chosen.
    private var asksIntelligence: Bool {
        !chosen.isDisjoint(with: Finder.intelligentKinds.values)
            && (Finder.asksAssistant || Finder.usesIntelligence && Finder.intelligenceAvailable)
    }

    /// Starts once; the work goes on to its end even when the screen is
    /// left, so what Apple Intelligence answers is kept for next time.
    func start() {
        guard running == nil else { return }
        running = Task { await run() }
    }

    /// Starts over, after a failure.
    func retry() {
        running?.cancel()
        remaking?.cancel()
        running = nil
        plan = ProtectionPlan()
        copy = nil
        png = nil
        found = false
        making = false
        intelligencePending = false
        failure = nil
        // From the photo as it came.
        cleaned = false
        beforeCleaning = nil
        start()
    }

    private func run() async {
        let started = Timing.start()
        // A small picture first, so the screen is never empty for long.
        let quick = Task {
            if case .asset(let id) = source, let asset = Library.asset(id) {
                let small = await Library.thumbnail(of: asset, width: 900)
                if original == nil, let small {
                    preview = small
                    Timing.record(.shown, Timing.milliseconds(since: started))
                }
            }
        }
        guard let image = await Self.load(source) else {
            failure = L("The picture could not be read.")
            return
        }
        // A scanned page made again meanwhile, turned or cut, has a new protection: this one stops.
        if case .scanned(let id) = source, ScannedPages.shared.opened(id) !== self { return }
        if case .page(let id) = source, ProjectStore.shared.opened(id) !== self { return }
        self.image = image
        original = UIImage(cgImage: image)
        if preview == nil { Timing.record(.shown, Timing.milliseconds(since: started)) }
        quick.cancel()
        log.info("Picture shown after \(Timing.milliseconds(since: started), privacy: .public) ms")
        // A photo prepared ahead of time is not read again.
        if case .asset(let id) = source, await PhotoIndexer.reuse(for: id, image: image) {
            log.info("Prepared reading reused")
        }
        // A PDF's page is read from its text, letter for letter, where it has text.
        if case .page(let id) = source { await ProjectStore.shared.prepareReading(id, for: image) }
        await analyse(image, started: started, offering: true)
    }

    /// Finds the places on the picture and makes the first copy, then lets
    /// Apple Intelligence read along; for a photo chosen in Photos, first
    /// looks whether it is a photographed document, to offer cleaning it.
    private func analyse(_ image: CGImage, started: Date, offering: Bool) async {
        plan.aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let chosen = chosen, rules = rules
        // What the patterns, the labels and the names find, without waiting
        // for Apple Intelligence, and what Settings leaves visible, listed
        // in Details to cover with a tap.
        let first = await Self.background {
            Finder.analysis(in: image, chosen, rules: rules, intelligence: false, spare: true)
        }
        guard !Task.isCancelled else { return }
        plan.add(found: first.areas, possible: first.possible, spared: first.spared)
        found = true
        // Read already: the words are there at once.
        let read = await Self.background { Finder.words(in: image) }
        guard !Task.isCancelled else { return }
        words = read
        if offering { offerCleaning(image) }
        log.info("First places shown after \(Timing.milliseconds(since: started), privacy: .public) ms")
        intelligencePending = asksIntelligence
        await make()
        if png != nil { Timing.record(.ready, Timing.milliseconds(since: started)) }
        guard intelligencePending, failure == nil else {
            Timing.report(since: started)
            return
        }
        let more = await Self.background {
            Finder.analysis(in: image, chosen, rules: rules, intelligence: true)
        }
        // Not waited for after all: what it found is left out.
        guard !Task.isCancelled, intelligencePending else { return }
        let before = plan.marks.count
        plan.add(found: more.areas, possible: more.possible)
        intelligencePending = false
        if plan.marks.count != before { await make() }
        Timing.report(since: started)
    }

    /// The owner would rather not wait for Apple Intelligence: the copy
    /// made and checked so far may leave, and what it finds later is left out.
    func dontWait() {
        guard intelligencePending, png != nil, !making else { return }
        intelligencePending = false
    }

    // MARK: A photographed document

    /// Looks once whether a photo chosen in Photos is a photographed paper
    /// document, never a screenshot: a page Vision is sure of, with text
    /// on it (`DocumentPhoto`). Then cleaning it is offered; nothing
    /// changes until the owner taps.
    private func offerCleaning(_ image: CGImage) {
        guard case .picture(let id) = source, let info = Imported.shared.info(id), !info.screenshot else { return }
        let count = words.count
        Task {
            let found: (quad: ScanQuad, confidence: Float)?
            if let known = info.page {
                found = (known, 1)
            } else {
                found = await Self.background { ScanCleaner.page(in: image) }
            }
            guard !cleaned, DocumentPhoto.offers(screenshot: info.screenshot, page: found?.quad,
                                                 confidence: found?.confidence, words: count) else { return }
            documentPage = found?.quad
            #if DEBUG
            if DocumentPhotoDemo.cleansAtOnce { clean() }
            #endif
        }
    }

    /// Straightens and brightens the photographed page as a scan is, then
    /// finds its covers again on the cleaned page. Only its shape and light
    /// change; where a number no longer reads after it, the photo stays as
    /// it was and says why.
    func clean() {
        guard let quad = documentPage, let image, found, !cleaning, !cleaned else { return }
        cleaning = true
        cleaningNote = nil
        var focal: Double?
        if case .picture(let id) = source { focal = Imported.shared.info(id)?.focal }
        let lens = focal
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                await ScanCleaner.prepare(image, quad: quad, focal: lens, mode: .color)
            }.value
            cleaning = false
            guard let prepared, prepared.checked.textKept != false else {
                cleaningNote = L("Straightened, some text read less well, so the photo stays as it was.")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            beforeCleaning = Kept(image: image, original: original, plan: plan, words: words, copy: copy, png: png)
            stopWork()
            self.image = prepared.cleaned
            original = UIImage(cgImage: prepared.cleaned)
            plan = ProtectionPlan()
            words = []
            copy = nil
            png = nil
            found = false
            failure = nil
            cleaned = true
            let page = prepared.cleaned
            running = Task { await analyse(page, started: Timing.start(), offering: false) }
        }
    }

    /// Back to the photo as it was, with its covers as they were.
    func undoCleaning() {
        guard let kept = beforeCleaning, !cleaning else { return }
        stopWork()
        image = kept.image
        original = kept.original
        plan = kept.plan
        words = kept.words
        copy = kept.copy
        png = kept.png
        found = true
        failure = nil
        cleaned = false
        beforeCleaning = nil
        // A copy still being made then is made again now.
        if png == nil { changed() }
    }

    /// Whatever was being found or made for the picture before stops.
    private func stopWork() {
        running?.cancel()
        remaking?.cancel()
        running = nil
        generation += 1
        making = false
        intelligencePending = false
    }

    // MARK: The owner's changes

    func toggle(_ id: Int) {
        plan.toggle(id)
        changed()
    }

    /// Agrees with places as they are, so they are checked; nothing on the
    /// picture changes, so the copy stands.
    func decide(_ ids: Set<Int>) {
        plan.decide(ids)
    }

    /// Covers places, or leaves them visible, all at once, as a topic's
    /// switch in Details does.
    func set(_ ids: Set<Int>, covered: Bool) {
        let before = plan
        plan.set(ids, covered: covered)
        if plan != before { changed() }
    }

    /// Hides what is under a shape drawn by hand; its id, if it was big enough.
    @discardableResult
    func draw(_ shape: HandShape) -> Int? {
        let id = plan.draw(shape)
        if id != nil { changed() }
        return id
    }

    /// The word under a finger, hidden by hand with the words it hides, so
    /// the copy is checked for them; its id. Nil where no word is. A detail
    /// found there that Settings leaves visible, like a doctor's name or an
    /// IBAN, is covered whole instead; a line about someone's health only
    /// where the word is.
    func hideWord(at point: CGPoint) -> Int? {
        guard let word = words.filter({ $0.box.insetBy(dx: -0.004, dy: -0.004).contains(point) })
            .min(by: { $0.box.width < $1.box.width }) else { return nil }
        let middle = CGPoint(x: word.box.midX, y: word.box.midY)
        if let detail = plan.marks.first(where: { mark in
            mark.origin == .spared && !mark.covered && mark.kind != .health && mark.rect.contains(middle)
        }) {
            toggle(detail.id)
            return detail.id
        }
        // A little room round the letters, as found places have.
        let box = word.box.insetBy(dx: -word.box.height * 0.15, dy: -word.box.height * 0.2)
        let id = plan.cover(box, text: word.text)
        if id != nil { changed() }
        return id
    }

    func move(_ ids: Set<Int>, by offset: CGPoint) {
        let before = plan
        plan.move(ids, by: offset)
        if plan != before { changed() }
    }

    func resize(_ id: Int, to rect: CGRect) {
        let before = plan
        plan.resize(id, to: rect)
        if plan != before { changed() }
    }

    func turn(_ id: Int, by angle: CGFloat) {
        let before = plan
        plan.turn(id, by: angle)
        if plan != before { changed() }
    }

    func widen(_ ids: Set<Int>, to width: CGFloat) {
        let before = plan
        plan.widen(ids, to: width)
        if plan != before { changed() }
    }

    /// Takes away what is by hand, and uncovers what was found, in one change.
    func remove(_ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        let before = plan
        plan.remove(ids)
        if plan != before { changed() }
    }

    /// What an eraser drawn through these points touches, taken away.
    func erase(along points: [CGPoint], reach: CGFloat) {
        remove(plan.erased(along: points, reach: reach))
    }

    func clearHand() {
        let before = plan
        plan.clearHand()
        if plan != before { changed() }
    }

    func resetToFound() {
        let before = plan
        plan.resetToFound()
        if plan != before { changed() }
    }

    func undo() {
        plan.undo()
        changed()
    }

    func redo() {
        plan.redo()
        changed()
    }

    /// The copy no longer matches the places: nothing leaves until it is
    /// made and checked again, a moment after the last change.
    private func changed() {
        generation += 1
        copy = nil
        png = nil
        // The first pass makes the first copy with every change in it.
        guard found, failure == nil else { return }
        making = true
        remaking?.cancel()
        remaking = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await make()
        }
    }

    /// Makes the copy for the places as they are now, reads it again and
    /// covers what still shows, then makes sure every cover landed. False
    /// when it could not be made, or newer places came first.
    @discardableResult
    private func make() async -> Bool {
        guard let image else { return false }
        generation += 1
        let mine = generation
        making = true
        let areas = plan.covered, left = plan.left
        let chosen = chosen, rules = rules, style = style
        let made = await Self.background { () -> (image: CGImage, added: [Finder.Area], holds: Bool)? in
            guard let done = Finder.finish(image, covering: areas, leaving: left, chosen, rules: rules, style: style)
            else { return nil }
            let places = Finder.checked(areas + done.added, aspect: CGFloat(image.width) / CGFloat(max(1, image.height)))
            if Finder.coversHold(original: image, covered: done.image, areas: places) {
                return (done.image, done.added, true)
            }
            // A look that let something through is made again in ink, the surest.
            guard let ink = Finder.cover(image, areas: areas + done.added, style: .ink) else { return nil }
            return (ink, done.added, Finder.coversHold(original: image, covered: ink, areas: places))
        }
        guard mine == generation, !Task.isCancelled else { return false }
        making = false
        guard let made else {
            failure = L("The copy could not be made.")
            return false
        }
        guard made.holds else {
            failure = L("The copy could not be checked, so it stays here.")
            return false
        }
        plan.add(found: made.added)
        copy = UIImage(cgImage: made.image)
        png = Covering.png(made.image)
        return png != nil
    }

    /// The page drawn again, sharper, for a PDF, covered where the copy is
    /// covered now, read again and checked as the copy is; the page shown
    /// here is not changed. Nil where it could not be made or checked.
    func cover(_ picture: CGImage) async -> (image: CGImage, places: [CGRect])? {
        let areas = plan.covered, left = plan.left
        let chosen = chosen, rules = rules, style = style
        return await Self.background { () -> (image: CGImage, places: [CGRect])? in
            guard let done = Finder.finish(picture, covering: areas, leaving: left, chosen, rules: rules, style: style)
            else { return nil }
            let places = Finder.checked(areas + done.added, aspect: CGFloat(picture.width) / CGFloat(max(1, picture.height)))
            if Finder.coversHold(original: picture, covered: done.image, areas: places) { return (done.image, places) }
            // A look that let something through is made again in ink, the surest.
            guard let ink = Finder.cover(picture, areas: areas + done.added, style: .ink),
                  Finder.coversHold(original: picture, covered: ink, areas: places) else { return nil }
            return (ink, places)
        }
    }

    /// A scanned page in other colours: the same places on it, the copy
    /// made and checked again.
    func replace(_ picture: CGImage) {
        guard image != nil, picture.width > 0 else { return }
        image = picture
        original = UIImage(cgImage: picture)
        changed()
    }

    // MARK: Leaving

    /// Notes the screenshot as protected lately, once its copy has left.
    func left() {
        if case .asset(let id) = source { Recent.note(id) }
        PhoneGuide.shared.happened(.used)
    }

    // MARK: Helpers

    private static func load(_ source: Source) async -> CGImage? {
        switch source {
        case .asset(let id):
            guard let asset = Library.asset(id) else { return nil }
            return await Library.image(of: asset)
        case .picture(let id):
            return Imported.shared.image(id)
        case .scanned(let id):
            // Cleaned first, then covered.
            return await ScannedPages.shared.ready(id)
        case .page(let id):
            return await ProjectStore.shared.picture(id)
        }
    }

    /// Work that takes a while, off the main thread, where Apple
    /// Intelligence may be waited for without holding anything up.
    nonisolated private static func background<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: work()) }
        }
    }
}

/// Pictures chosen from Photos to protect, kept while the app runs and
/// never written anywhere.
@MainActor
final class Imported {
    static let shared = Imported()
    private var pictures: [UUID: (image: CGImage, info: Info)] = [:]

    /// What is known of a picture chosen: whether Photos calls it a
    /// screenshot, its lens in pixels from its notes, and where its page is
    /// where that is known already, as in a made-up photo.
    struct Info {
        var screenshot = false
        var focal: Double?
        var page: ScanQuad?
    }

    /// Keeps a picture, upright, and gives the way back to it.
    func keep(_ image: CGImage, info: Info = Info()) -> UUID {
        // A few at a time, so pictures not looked at again do not pile up.
        if pictures.count >= 4 { pictures.removeAll() }
        let id = UUID()
        pictures[id] = (image, info)
        return id
    }

    func image(_ id: UUID) -> CGImage? { pictures[id]?.image }

    func info(_ id: UUID) -> Info? { pictures[id]?.info }
}

/// The screenshots protected lately, by their identifier in Photos, newest
/// first: only that, so nothing of what they show is kept.
enum Recent {
    private static let key = "recentlyProtected"

    private(set) static var ids: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func note(_ id: String) {
        ids = ProtectedList.noting(id, in: ids)
    }

    /// Takes these off the list; the screenshots stay in Photos. Gives back
    /// what was taken off, to put it back with Undo.
    static func remove(_ gone: Set<String>) -> ProtectedList.Removal {
        let (kept, removal) = ProtectedList.removing(gone, from: ids)
        ids = kept
        return removal
    }

    static func restore(_ removal: ProtectedList.Removal) {
        ids = ProtectedList.restoring(removal, into: ids)
    }
}
