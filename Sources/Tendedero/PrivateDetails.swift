import AppKit
import NaturalLanguage
import UniformTypeIdentifiers
import Vision

/// Hide private details, from the menu bar: whatever leaves the line,
/// copied, sent to a chat or dragged out, is a copy of the screenshot with
/// the chosen kinds of detail covered. The line shows each photo that way
/// too, so what you see is what goes. The screenshot file itself is never
/// touched.
///
/// Each screenshot is read once, in the background when it hangs, so
/// copying it stays instant. It is a help, not a promise: text the
/// recognition misreads stays as it is.
@MainActor
enum PrivateDetails {
    /// What to cover. Before there was a choice, one switch covered
    /// everything it knew.
    nonisolated static var details: Set<PrivateDetail> {
        get {
            _ = upToDate
            if let raw = UserDefaults.standard.stringArray(forKey: "hiddenDetails") {
                return Set(raw.compactMap(PrivateDetail.init(rawValue:)))
            }
            return UserDefaults.standard.bool(forKey: "hidePrivateDetails") ? PrivateDetail.recommended : []
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenDetails") }
    }

    /// The saved choice, and the one the menu's switch keeps while it is
    /// off, brought up to date once before either is read: a recommended
    /// kind added since starts on. The owner's name, saved as a word before
    /// there were details, becomes the name detail then too, so it is
    /// covered however it is written, whichever names are chosen.
    private nonisolated static let upToDate: Void = {
        PrivateDetail.bringUpToDate(["hiddenDetails", "hiddenDetailsBefore"])
        OwnRules.adoptName()
    }()

    nonisolated static var hidden: Bool { !details.isEmpty }

    /// Whether the owner's own details or rules cover something now. Always
    /// Hide covers them in every picture, whatever kinds are chosen, also
    /// with Hide private details off.
    nonisolated static var alwaysHides: Bool { OwnRules.all.contains(where: \.isActive) }

    static func toggle(_ detail: PrivateDetail) {
        var chosen = details
        if chosen.contains(detail) { chosen.remove(detail) } else { chosen.insert(detail) }
        details = chosen
    }

    // MARK: Hidden by hand

    private static let handKey = "handCovers"

    /// The parts of a screenshot hidden by hand with Hide Part, from 0 to 1
    /// from the bottom left. They are covered whatever is chosen above.
    static func hand(_ url: URL) -> [CGRect] {
        let saved = UserDefaults.standard.dictionary(forKey: handKey)?[url.path] as? [[Double]] ?? []
        return saved.compactMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
    }

    static func setHand(_ boxes: [CGRect], for url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: handKey) ?? [:]
        all[url.path] = boxes.isEmpty ? nil : boxes.map {
            [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)]
        }
        UserDefaults.standard.set(all, forKey: handKey)
    }

    /// Forgets what was hidden in screenshots that have left the line, and
    /// can come back neither from the History nor from a note.
    static func keepHand(only paths: Set<String>) {
        guard let all = UserDefaults.standard.dictionary(forKey: handKey),
              all.keys.contains(where: { !paths.contains(owner(ofHandKey: $0)) }) else { return }
        UserDefaults.standard.set(all.filter { paths.contains(owner(ofHandKey: $0.key)) }, forKey: handKey)
    }

    /// What was hidden by hand goes with a file that moves, like into the
    /// History and back, a PDF's pages too, so it leaves covered from there
    /// as it did from the line.
    static func moveHand(from old: URL, to new: URL) {
        guard var all = UserDefaults.standard.dictionary(forKey: handKey) else { return }
        let keys = all.keys.filter { owner(ofHandKey: $0) == old.path }
        guard !keys.isEmpty else { return }
        for key in keys {
            let boxes = all.removeValue(forKey: key)
            all[new.path + String(key.dropFirst(old.path.count))] = boxes
        }
        UserDefaults.standard.set(all, forKey: handKey)
    }

    /// Forgets what was hidden by hand in a file, a PDF's pages too, as it
    /// leaves the History for good.
    static func forgetHand(_ url: URL) {
        guard let all = UserDefaults.standard.dictionary(forKey: handKey),
              all.keys.contains(where: { owner(ofHandKey: $0) == url.path }) else { return }
        UserDefaults.standard.set(all.filter { owner(ofHandKey: $0.key) != url.path }, forKey: handKey)
    }

    // MARK: A PDF's pages

    /// What was hidden by hand on a page of a PDF, kept like a screenshot's
    /// under the file and the page's number, from 1.
    static func hand(_ url: URL, page: Int) -> [CGRect] {
        hand(URL(fileURLWithPath: pageKey(url, page)))
    }

    static func setHand(_ boxes: [CGRect], for url: URL, page: Int) {
        setHand(boxes, for: URL(fileURLWithPath: pageKey(url, page)))
    }

    /// Every page of a PDF with something hidden by hand.
    static func handPages(_ url: URL) -> [Int: [CGRect]] {
        let prefix = url.path + "#"
        var pages: [Int: [CGRect]] = [:]
        for key in (UserDefaults.standard.dictionary(forKey: handKey) ?? [:]).keys where key.hasPrefix(prefix) {
            guard let page = Int(key.dropFirst(prefix.count)) else { continue }
            let boxes = hand(url, page: page)
            if !boxes.isEmpty { pages[page] = boxes }
        }
        return pages
    }

    nonisolated static func pageKey(_ url: URL, _ page: Int) -> String {
        "\(url.path)#\(page)"
    }

    /// The file a saved hand belongs to: a page's ends in "#" and its number.
    nonisolated static func owner(ofHandKey key: String) -> String {
        guard let mark = key.lastIndex(of: "#"), Int(key[key.index(after: mark)...]) != nil else { return key }
        return String(key[..<mark])
    }

    // MARK: What leaves

    /// Whether anything is covered in a screenshot: details chosen, the
    /// owner's own details and rules, or parts hidden by hand. A PDF of
    /// Snapfly's own was covered as it was made.
    static func covers(_ url: URL) -> Bool {
        if isDocument(url) { return coversDocument(url, details) }
        return hidden || alwaysHides || !hand(url).isEmpty
    }

    /// Whether a screenshot leaves the line changed: covered, stamped with
    /// the time, drawn on, or all of them. A photo also leaves without where
    /// it was taken.
    static func alters(_ url: URL) -> Bool {
        if isDocument(url) { return covers(url) }
        return covers(url) || TimeStamp.mark(for: url) != nil || strips(url) || !Drawings.saved(url).isEmpty
    }

    /// Whether a picture carries where or with what it was taken, read once
    /// for each version of the file.
    static func strips(_ url: URL) -> Bool {
        guard isImage(url), let date = modified(url) else { return false }
        let key = "\(url.path)|\(date.timeIntervalSinceReferenceDate)"
        if let known = stripping[key] { return known }
        let strips = Cover.strips(url)
        stripping[key] = strips
        return strips
    }

    private static var stripping: [String: Bool] = [:]

    /// Called when a PDF starts being covered, which can take a while, so
    /// the line can show it is still working.
    static var onStart: ((URL) -> Void)?

    /// For each screenshot as it was when read, with what was chosen then:
    /// its covered copy, or the file itself when there was nothing to hide.
    private static var results: [String: URL] = [:]
    private static var inProgress: Set<String> = []
    /// Versions whose reading in the background failed: made as they leave
    /// instead, and covered whole if that fails too, never waited for again.
    private static var failedKeys: Set<String> = []
    /// Pictures read two at a time, the newest first (`ReadingQueue`).
    private static let reading = ReadingQueue(width: 2)

    /// Called once a screenshot has been read, with the screenshot and what
    /// to hand out for it, so the line can show it that way.
    static var onRead: ((URL, URL) -> Void)?

    /// What was covered in each version read, under the same key as its
    /// copy, and the key of the version each file last showed.
    private static var reports: [String: CoverReport] = [:]
    private static var shownKeys: [String: String] = [:]
    /// Versions being read that the line is to show once they are: not the
    /// copies read only for AI chats.
    private static var waitingToShow: Set<String> = []

    /// What was covered in what the line shows for a screenshot or a PDF;
    /// nil until it has been read.
    static func report(for url: URL) -> CoverReport? {
        shownKeys[url.path].flatMap { reports[$0] }
    }

    /// What was covered in the copy with the given kinds covered, like the
    /// one for AI chats; nil until it has been made.
    static func report(for url: URL, covering chosen: Set<PrivateDetail>) -> CoverReport? {
        if chosen == details { return report(for: url) }
        if isDocument(url) { return documentKey(url, chosen).flatMap { reports[$0] } }
        return key(for: url, chosen, hand(url), TimeStamp.mark(for: url), strips(url), Drawings.saved(url))
            .flatMap { reports[$0] }
    }

    /// What was covered in what went out with the given kinds covered, as
    /// `CoverReport.keys`, for the send log.
    static func coveredKeys(_ url: URL, covering chosen: Set<PrivateDetail>) -> [String] {
        if chosen == details { return isCovered(url) ? report(for: url)?.keys ?? [] : [] }
        return report(for: url, covering: chosen)?.keys ?? []
    }

    /// Whether what leaves the line has anything covered: something is to
    /// be, and, once read, something was found. A PDF is drawn again page by
    /// page whatever is found, so it counts as covered once read.
    static func isCovered(_ url: URL) -> Bool {
        if isDocument(url) { return covers(url) }
        return covers(url) && report(for: url).map { !$0.isEmpty } != false
    }

    /// What to hand out for a screenshot.
    static func shareable(_ url: URL) -> URL {
        shareable(url, covering: details)
    }

    /// What to hand out with the given kinds covered: what Settings checks,
    /// or more, like every kind for an AI chat. The line goes on showing
    /// the photo as Settings covers it.
    static func shareable(_ url: URL, covering chosen: Set<PrivateDetail>) -> URL {
        let done = handOut(url, covering: chosen)
        // With nothing to change, a picture still leaves as a fresh file.
        return done == url && isImage(url) ? plain(url, chosen) : done
    }

    private static func handOut(_ url: URL, covering chosen: Set<PrivateDetail>) -> URL {
        if isDocument(url) { return shareableDocument(url, chosen) }
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        // The owner's own details and rules are covered whatever is chosen.
        guard !chosen.isEmpty || alwaysHides || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty,
              isImage(url), let key = key(for: url, chosen, hand, stamp, clean, drawing) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let failures = Finder.failures
        let made = Cover.covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)
        // Nothing found where Vision could not read is no proof that nothing
        // is there, and a copy that could not be made is none: the whole
        // picture goes covered instead, never kept as its reading nor shown
        // on the line as read, so it is read again the next time.
        guard let made, Finder.failures == failures else { return coveredWhole(url) }
        // Made here, on the main thread, where Apple Intelligence or the
        // assistant never reads along: it leaves now, but is not kept nor
        // shown on the line as read; the reading in the background, with
        // them, is.
        if readsAlong(chosen) {
            prepare(url, covering: chosen, shows: chosen == details)
            return made.url
        }
        results[key] = made.url
        reports[key] = made.report
        failedKeys.remove(key)
        if chosen == details {
            shownKeys[url.path] = key
            onRead?(url, made.url)
        }
        return made.url
    }

    /// Whether Apple Intelligence, or the AI assistant, reads along for
    /// these kinds, as it does off the main thread only.
    private static func readsAlong(_ chosen: Set<PrivateDetail>) -> Bool {
        guard !chosen.isDisjoint(with: Finder.intelligentKinds.values) else { return false }
        return Finder.asksAssistant || Finder.usesIntelligence && Finder.intelligenceAvailable
    }

    /// What leaves for a picture whose reading or covers failed: all of it
    /// covered, with a note saying so.
    private static func coveredWhole(_ url: URL) -> URL {
        log.error("A picture could not be read or covered, so all of it leaves covered")
        Notice.show(L("Could not read this picture, so all of it is covered."))
        return Cover.inked(url)
    }

    /// What to show on the line for a screenshot already read.
    static func shown(_ url: URL) -> URL? {
        if isDocument(url) { return documentKey(url, details).flatMap(cached) }
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        guard !chosen.isEmpty || alwaysHides || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty,
              let key = key(for: url, chosen, hand, stamp, clean, drawing), let done = cached(key) else { return nil }
        shownKeys[url.path] = key
        return done
    }

    /// Reads a screenshot ahead of time, off the main thread, and, with
    /// Cover Everything in AI Chats on, its copy for them too.
    static func prepare(_ url: URL) {
        prepare(url, covering: details, shows: true)
        prepareForAIChats(url)
    }

    /// The copy for AI chats, read ahead of time while Cover Everything in
    /// AI Chats is on, so sending into one stays instant.
    static func prepareForAIChats(_ url: URL) {
        guard CoveringProfile.coversAllInAIChats else { return }
        prepare(url, covering: CoveringProfile.everything, shows: false)
    }

    /// - Parameter shows: whether the line shows this version once read.
    private static func prepare(_ url: URL, covering chosen: Set<PrivateDetail>, shows: Bool) {
        if isDocument(url) { return prepareDocument(url, chosen, shows: shows) }
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        guard !chosen.isEmpty || alwaysHides || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty,
              isImage(url), let key = key(for: url, chosen, hand, stamp, clean, drawing) else {
            // Nothing to change: it leaves as a fresh file all the same.
            preparePlain(url, chosen)
            return
        }
        if let done = cached(key) {
            if done == url { preparePlain(url, chosen) }
            if shows {
                shownKeys[url.path] = key
                onRead?(url, done)
            }
            return
        }
        if shows { waitingToShow.insert(key) }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        // A few at a time, the newest first, so a line full of photos read
        // again never reads them all at once.
        reading.add {
            let failures = Finder.failures
            let made = Cover.covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)
            // Read only where Vision could read it and its copy was made, as
            // when it is handed out (`handOut`).
            let read = Finder.failures == failures ? made : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    inProgress.remove(key)
                    // Not kept, nor shown on the line as read: it is read
                    // again as it leaves, and goes covered whole if that
                    // fails too.
                    guard let read else {
                        failedKeys.insert(key)
                        waitingToShow.remove(key)
                        return
                    }
                    failedKeys.remove(key)
                    results[key] = read.url
                    reports[key] = read.report
                    if read.url == url { preparePlain(url, chosen) }
                    guard waitingToShow.remove(key) != nil else { return }
                    shownKeys[url.path] = key
                    onRead?(url, read.url)
                }
            }
        }
    }

    // MARK: A fresh file

    /// A picture as a fresh file, made once for each version of it and each
    /// choice its name is checked against (`Cover.newCopy`).
    private static func plain(_ url: URL, _ chosen: Set<PrivateDetail>) -> URL {
        guard let key = plainKey(url, chosen) else { return url }
        if let done = cached(key) { return done }
        let done = Cover.plain(url, covering: chosen) ?? url
        results[key] = done
        return done
    }

    private static func plainKey(_ url: URL, _ chosen: Set<PrivateDetail>) -> String? {
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        return modified(url).map {
            "plain|\(url.path)|\($0.timeIntervalSinceReferenceDate)|\(Cover.plainNames)|\(kinds)|\(OwnRules.fingerprint)"
        }
    }

    /// The fresh file made ahead of time, off the main thread, so copying a
    /// picture with nothing to cover stays instant.
    private static func preparePlain(_ url: URL, _ chosen: Set<PrivateDetail>) {
        guard isImage(url), let key = plainKey(url, chosen), cached(key) == nil, !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let made = Cover.plain(url, covering: chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    results[key] = made ?? url
                    inProgress.remove(key)
                }
            }
        }
    }

    /// Whether its covered copy is still being made, off the main thread,
    /// so it cannot leave yet: a note says so, and it leaves a moment later.
    /// One not made yet, like a photo or PDF in the History, starts being
    /// made now, rather than on the main thread, where the screen would
    /// wait for it and Apple Intelligence cannot read along. One whose
    /// reading failed is made as it leaves, covered whole if that fails too.
    static func stillCovering(_ url: URL, _ chosen: Set<PrivateDetail>) -> Bool {
        guard let key = workKey(url, chosen), cached(key) == nil, !failedKeys.contains(key) else { return false }
        if !inProgress.contains(key) { prepare(url, covering: chosen, shows: chosen == details) }
        return inProgress.contains(key)
    }

    /// The version a picture or PDF leaves as, when something is to be done
    /// to it: covered, stamped, drawn on or cleaned; nil when it leaves as it is.
    private static func workKey(_ url: URL, _ chosen: Set<PrivateDetail>) -> String? {
        if isDocument(url) { return coversDocument(url, chosen) ? documentKey(url, chosen) : nil }
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        guard !chosen.isEmpty || alwaysHides || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty,
              isImage(url) else { return nil }
        return key(for: url, chosen, hand, stamp, clean, drawing)
    }

    // MARK: A PDF from outside

    /// Its protected copy, made now if it is not ready yet, so nothing
    /// private leaves uncovered. A PDF with nothing to cover goes as it is.
    private static func shareableDocument(_ url: URL, _ chosen: Set<PrivateDetail>) -> URL {
        guard coversDocument(url, chosen), let key = documentKey(url, chosen) else { return url }
        if let done = cached(key) { return done }
        guard let made = DocumentCover.covering(url, chosen, hand: handPages(url)) else {
            log.error("Could not cover \(url.lastPathComponent, privacy: .private)")
            // Never the original, with its text: its pages painted whole,
            // and not kept, so it is covered afresh the next time.
            Notice.show(L("Could not read this PDF, so every page is covered whole."))
            return DocumentCover.inked(url)
        }
        results[key] = made.url
        reports[key] = made.report
        inProgress.remove(key)
        failedKeys.remove(key)
        if chosen == details {
            shownKeys[url.path] = key
            onRead?(url, made.url)
        }
        return made.url
    }

    /// Covers every page in the background as soon as it hangs, which for
    /// a long document takes a while; the line shows it is working.
    private static func prepareDocument(_ url: URL, _ chosen: Set<PrivateDetail>, shows: Bool) {
        guard coversDocument(url, chosen), let key = documentKey(url, chosen) else { return }
        if let done = cached(key) {
            if shows {
                shownKeys[url.path] = key
                onRead?(url, done)
            }
            return
        }
        if shows {
            waitingToShow.insert(key)
            onStart?(url)
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        let hand = handPages(url)
        DispatchQueue.global(qos: .userInitiated).async {
            let made = DocumentCover.covering(url, chosen, hand: hand)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    inProgress.remove(key)
                    if let made {
                        results[key] = made.url
                        reports[key] = made.report
                        failedKeys.remove(key)
                    } else {
                        failedKeys.insert(key)
                    }
                    guard waitingToShow.remove(key) != nil else { return }
                    if made != nil {
                        shownKeys[url.path] = key
                    } else {
                        // Not kept: it is covered again as it leaves, and goes
                        // painted whole if that fails too (`shareableDocument`).
                        // The line only stops showing it is working.
                        Notice.show(L("Could not cover the private details in this PDF."))
                    }
                    onRead?(url, made?.url ?? url)
                }
            }
        }
    }

    /// Whether anything is to be covered in a PDF brought in: kinds chosen,
    /// the owner's own details and rules, or parts hidden by hand. Make
    /// PDF's own were covered as Settings checks; more than that, like every
    /// kind for an AI chat, is covered in them again.
    private static func coversDocument(_ url: URL, _ chosen: Set<PrivateDetail>) -> Bool {
        let protects = DocumentCover.protects(url) || (isDocument(url) && !chosen.isSubset(of: details))
        return protects && (!chosen.isEmpty || alwaysHides || !handPages(url).isEmpty)
    }

    /// The file, when it last changed, what to cover, what was hidden by
    /// hand on each page, how covers look and what the copy is called.
    private static func documentKey(_ url: URL, _ chosen: Set<PrivateDetail>) -> String? {
        guard let date = modified(url) else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let pages = handPages(url).sorted { $0.key < $1.key }.map { page, boxes in
            "\(page):" + boxes.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        }.joined(separator: "/")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(pages)|\(OwnRules.fingerprint)|\(Finder.lookKey)|\(Cover.plainNames)"
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// A covered copy dragged into a folder is no longer there to hand out.
    private static func cached(_ key: String) -> URL? {
        guard let done = results[key] else { return nil }
        guard FileManager.default.fileExists(atPath: done.path) else {
            results[key] = nil
            return nil
        }
        return done
    }

    /// The file, when it last changed, what to cover, the stamp and the
    /// drawing, so a screenshot edited in Markup, a new choice, a part hidden
    /// by hand, new words on the stamp, a changed drawing, a changed rule of
    /// the owner's or a new look for covers are drawn again.
    private static func key(for url: URL, _ chosen: Set<PrivateDetail>, _ hand: [CGRect],
                            _ stamp: TimeStamp.Mark?, _ clean: Bool, _ drawing: Drawing) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let parts = hand.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(parts)|\(stamp?.key ?? "")|\(clean)|\(drawing.key)|\(OwnRules.fingerprint)|\(Cover.plainNames)|\(Finder.lookKey)"
    }
}

/// Drawing a copy of a screenshot with its private details covered. The
/// text is read on this Mac, with the recognition Live Text uses, and goes
/// nowhere else.
enum Cover {
    /// Where the covered copies wait to be pasted. Emptied at each launch.
    static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Covered", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        return folder
    }()

    /// Where the chosen details are, as they are covered: from 0 to 1 from
    /// the bottom left, with a margin around the text.
    static func areas(in image: CGImage, _ chosen: Set<PrivateDetail>) -> [CGRect] {
        Finder.areas(in: image, chosen)
    }

    /// The picture as it is covered, upright and with nothing of the file but
    /// its pixels, and what was covered in it: what a copy saved beside the
    /// original is made from, or sent from Hide Private Details. Nil when it
    /// could not be read or covered, Vision's reading too, so no such copy is
    /// made uncovered.
    static func covered(of url: URL, _ chosen: Set<PrivateDetail>,
                        hand: [CGRect]) -> (image: CGImage, report: CoverReport)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = upright(source) else { return nil }
        let failures = Finder.failures
        guard let made = Finder.covered(image, chosen, hand: hand), Finder.failures == failures else { return nil }
        return (made.image, CoverReport(made.areas, hand: hand.count))
    }

    /// A copy of the screenshot with the chosen details and the parts hidden
    /// by hand covered, what was drawn on it, and the time stamped when there
    /// is a stamp, under the same name. The screenshot itself when there is
    /// nothing to hide, draw or stamp; nil when the copy could not be made.
    /// - Parameter clean: a photo that carries where or with what it was
    ///   taken: a copy is made even with nothing to cover, without any of
    ///   it, and as a JPEG, which suits a photo and keeps it small to send.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                     stamp: TimeStamp.Mark? = nil, clean: Bool = false, drawing: Drawing = .empty) -> URL? {
        covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)?.url
    }

    /// The same copy, with what was covered in it: the screenshot itself,
    /// with nothing covered, when there is nothing to hide, draw or stamp.
    /// Nil only when the picture could not be read as a picture, or its copy
    /// could not be drawn or written, so a failure is never taken for
    /// nothing to cover. Whether Vision could read it says `Finder.failures`.
    /// - Parameter drawing: drawn over what is covered, then cut to the part
    ///   kept. What the reading covers is found in the whole picture first.
    static func covering(_ url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                         stamp: TimeStamp.Mark? = nil, clean: Bool = false,
                         drawing: Drawing = .empty) -> (url: URL, report: CoverReport)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = upright(source) else { return nil }
        // Covered, then read again as anyone could, and covered more if need be.
        guard let made = Finder.covered(image, chosen, hand: hand) else { return nil }
        let found = made.areas
        guard !found.isEmpty || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty else {
            return (url, CoverReport())
        }

        var covered = made.image
        var crop: CGRect?
        if !drawing.isEmpty {
            // What was drawn, like ink over a part or a crop, may hide
            // something too: a copy without it is no copy.
            guard let drawn = Drawing.render(covered, drawing) else { return nil }
            // Cut only when the part kept is not the whole picture.
            if drawn.width != covered.width || drawn.height != covered.height { crop = drawing.crop }
            covered = drawn
        }
        let picture = CGFloat(covered.height)
        // The stamp's band goes above the picture, which grows by its height.
        if let stamp, let stamped = TimeStamp.render(covered, stamp) { covered = stamped }
        // Where it is covered, as the copy shows it, for the lock.
        var places = CoverReport.places(found.map(\.rect) + hand, crop: crop,
                                        share: picture / CGFloat(max(1, covered.height)))
        // Set on its colour last, round everything else.
        if let backdrop = drawing.backdrop, let framed = Backdrop.render(covered, backdrop) {
            covered = framed.image
            places = places.map { Backdrop.place($0, in: framed.layout) }
        }

        // A folder of its own, so the copy keeps the screenshot's name.
        let type = clean ? UTType.jpeg : UTType.png
        guard let target = newCopy(of: url, ext: clean ? "jpg" : "png", covering: chosen),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = clean ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, covered, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (target, CoverReport(found, hand: hand.count, places: places))
    }

    /// Where a copy goes: a folder of its own, so it keeps the original's
    /// name, which is what the chat shows. With Plain file names on, or
    /// where the name itself holds a detail of a kind covered or one of the
    /// owner's own rules, like an account number in a statement's name, it
    /// is called “Image”, or “Document” for a PDF.
    static func newCopy(of url: URL, ext: String,
                        covering chosen: Set<PrivateDetail> = PrivateDetails.details) -> URL? {
        let own = url.deletingPathExtension().lastPathComponent
        let plainName = ext == "pdf" ? L("Document") : L("Image")
        let name = plainNames || nameHolds(own, chosen) ? plainName : own
        let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
        guard (try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)) != nil else { return nil }
        return target
    }

    /// Whether a file's name holds a detail of a kind covered, found by its
    /// shape and fitting its kind as a find of the patterns must
    /// (`Finder.fit`), so a screenshot's date and time are no phone number,
    /// or one of the owner's own rules, which count whatever kinds are
    /// covered, as they are covered so. People's names are not looked for
    /// in it: Plain file names leaves every name out.
    static func nameHolds(_ name: String, _ chosen: Set<PrivateDetail>) -> Bool {
        // The words of a file's name are often joined with underscores.
        let words = name.replacingOccurrences(of: "_", with: " ")
        if !Finder.ruleRanges(in: words, OwnRules.all).isEmpty { return true }
        guard !chosen.isEmpty else { return false }
        return chosen.contains { kind in
            Finder.patternRanges(in: words, [kind]).contains { found in
                Range(found, in: words).map { Finder.fit(kind, $0, in: words, medical: false) != .no } ?? false
            }
        }
    }

    /// Plain file names, from Settings › Privacy: pictures leave named
    /// “Image”, and PDFs “Document”, not after the file, whose name often
    /// says when it was taken or what it holds. Off unless turned on.
    static var plainNames: Bool {
        get { UserDefaults.standard.bool(forKey: "plainFileNames") }
        set { UserDefaults.standard.set(newValue, forKey: "plainFileNames") }
    }

    /// What leaves in place of a picture whose reading or covers failed: a
    /// picture of its size, at most 4096 pixels on its longer side, painted
    /// whole in the covers' ink (cover-ink in DESIGN.md). Made without
    /// reading what the picture shows, so nothing of it can show through.
    /// Where not even that can be written, a file that is not there, so
    /// that nothing at all leaves.
    static func inked(_ url: URL) -> URL {
        let properties = CGImageSourceCreateWithURL(url as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        // A photo stored turned a quarter shows the other way up, as its copy would.
        if ((properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5 { swap(&width, &height) }
        if width <= 0 || height <= 0 { (width, height) = (1600, 1000) }
        let scale = min(1, 4096 / Double(max(width, height)))
        width = max(1, Int((Double(width) * scale).rounded()))
        height = max(1, Int((Double(height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nowhere(ext: "png") }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(), let target = newCopy(of: url, ext: "png"),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nowhere(ext: "png") }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? target : nowhere(ext: "png")
    }

    /// A file that is not there, in a folder that is not there either: what
    /// is handed out when not even a picture covered whole could be written,
    /// so pasting, dragging or sending it gives nothing at all.
    static func nowhere(ext: String) -> URL {
        folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Snapfly")
            .appendingPathExtension(ext)
    }

    /// A fresh copy of a picture with nothing of the file but what it shows:
    /// none of the notes a file carries on when, where and with what it was
    /// made, and none of the Finder's, like where it was downloaded from. A
    /// PNG stays a PNG, pixel for pixel; a JPEG or HEIC photo goes as a JPEG,
    /// any other picture as a PNG. Nil for a GIF, which goes as itself so it
    /// keeps moving, and for what cannot be read.
    /// - Parameter chosen: what is covered, which its name is checked for.
    static func plain(_ url: URL, covering chosen: Set<PrivateDetail> = PrivateDetails.details) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1 else { return nil }
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        if type?.conforms(to: .gif) == true { return nil }
        guard let image = upright(source) else { return nil }
        let photo = type.map { $0.conforms(to: .jpeg) || $0.conforms(to: .heic) || $0.conforms(to: .heif) } ?? false
        guard let target = newCopy(of: url, ext: photo ? "jpg" : "png", covering: chosen),
              let destination = CGImageDestinationCreateWithURL(
                target as CFURL, (photo ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = photo ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return target
    }

    /// The picture as it is meant to be seen: a photo from a phone is often
    /// stored turned, with a note to turn it back. A screenshot never is.
    static func upright(_ source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard orientation != 1,
              let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Whether a picture carries where or with what it was taken, as a
    /// photo from a phone or a camera does: the place, the camera, or
    /// captions and names. A screenshot carries none of it.
    static func strips(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        if properties[kCGImagePropertyGPSDictionary] != nil || properties[kCGImagePropertyIPTCDictionary] != nil {
            return true
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return tiff?[kCGImagePropertyTIFFMake] != nil || tiff?[kCGImagePropertyTIFFModel] != nil
    }
}
