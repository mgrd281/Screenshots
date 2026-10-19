import CoreTransferable
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
        guard let image = await Self.load(source) else {
            failure = L("The picture could not be read.")
            return
        }
        self.image = image
        original = UIImage(cgImage: image)
        let chosen = chosen, rules = rules
        // What the patterns, the labels and the names find, without waiting
        // for Apple Intelligence.
        let first = await Self.background {
            Finder.analysis(in: image, chosen, rules: rules, intelligence: false)
        }
        guard !Task.isCancelled else { return }
        plan.add(found: first.areas, possible: first.possible)
        found = true
        log.info("First places shown after \(Timing.milliseconds(since: started), privacy: .public) ms")
        intelligencePending = asksIntelligence
        await make()
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

    func cover(_ rect: CGRect) {
        let count = plan.marks.count
        plan.cover(rect)
        if plan.marks.count != count { changed() }
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

    /// The copy, to share as a PNG file of its own, with nothing of the
    /// original's notes in it.
    var shared: CoveredPicture? { png.map(CoveredPicture.init(png:)) }

    // MARK: Helpers

    private static func load(_ source: Source) async -> CGImage? {
        switch source {
        case .asset(let id):
            guard let asset = Library.asset(id) else { return nil }
            return await Library.image(of: asset)
        case .picture(let id):
            return Imported.shared.image(id)
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

/// A covered copy, shared as a PNG file.
struct CoveredPicture: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
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

    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func note(_ id: String) {
        let kept = [id] + ids.filter { $0 != id }
        UserDefaults.standard.set(Array(kept.prefix(12)), forKey: key)
    }
}
