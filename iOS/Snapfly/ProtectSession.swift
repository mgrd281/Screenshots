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

    init(source: Source) {
        self.source = source
    }

    /// The protection for a source: a scanned page's is kept with the page,
    /// so it opens again as it was left and its PDF takes it as it is.
    static func made(for source: Source) -> ProtectSession {
        if case .scanned(let id) = source { return ScannedPages.shared.session(id) }
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
        self.image = image
        original = UIImage(cgImage: image)
        if preview == nil { Timing.record(.shown, Timing.milliseconds(since: started)) }
        quick.cancel()
        log.info("Picture shown after \(Timing.milliseconds(since: started), privacy: .public) ms")
        // A photo prepared ahead of time is not read again.
        if case .asset(let id) = source, await PhotoIndexer.reuse(for: id, image: image) {
            log.info("Prepared reading reused")
        }
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
        words = await Self.background { Finder.words(in: image) }
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
            return ScannedPages.shared.image(id)
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
    private var pictures: [UUID: CGImage] = [:]

    /// Keeps a picture, upright, and gives the way back to it.
    func keep(_ image: CGImage) -> UUID {
        // A few at a time, so pictures not looked at again do not pile up.
        if pictures.count >= 4 { pictures.removeAll() }
        let id = UUID()
        pictures[id] = image
        return id
    }

    func image(_ id: UUID) -> CGImage? { pictures[id] }
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
