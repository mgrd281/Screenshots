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
    /// kind added since starts on.
    private nonisolated static let upToDate: Void = {
        PrivateDetail.bringUpToDate(["hiddenDetails", "hiddenDetailsBefore"])
    }()

    nonisolated static var hidden: Bool { !details.isEmpty }

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

    /// Forgets what was hidden in screenshots that have left the line.
    static func keepHand(only paths: Set<String>) {
        guard let all = UserDefaults.standard.dictionary(forKey: handKey),
              all.keys.contains(where: { !paths.contains(owner(ofHandKey: $0)) }) else { return }
        UserDefaults.standard.set(all.filter { paths.contains(owner(ofHandKey: $0.key)) }, forKey: handKey)
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

    /// Whether anything is covered in a screenshot: details chosen, or parts
    /// hidden by hand. A PDF of Snapfly's own was covered as it was made.
    static func covers(_ url: URL) -> Bool {
        if isDocument(url) { return coversDocument(url, details) }
        return hidden || !hand(url).isEmpty
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
        return done == url && isImage(url) ? plain(url) : done
    }

    private static func handOut(_ url: URL, covering chosen: Set<PrivateDetail>) -> URL {
        if isDocument(url) { return shareableDocument(url, chosen) }
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty, isImage(url),
              let key = key(for: url, chosen, hand, stamp, clean, drawing) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let made = Cover.covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)
        let done = made?.url ?? url
        results[key] = done
        reports[key] = made?.report ?? CoverReport()
        if chosen == details {
            shownKeys[url.path] = key
            onRead?(url, done)
        }
        return done
    }

    /// What to show on the line for a screenshot already read.
    static func shown(_ url: URL) -> URL? {
        if isDocument(url) { return documentKey(url, details).flatMap(cached) }
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        let drawing = Drawings.saved(url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty,
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
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean || !drawing.isEmpty, isImage(url),
              let key = key(for: url, chosen, hand, stamp, clean, drawing) else {
            // Nothing to change: it leaves as a fresh file all the same.
            preparePlain(url)
            return
        }
        if let done = cached(key) {
            if done == url { preparePlain(url) }
            if shows {
                shownKeys[url.path] = key
                onRead?(url, done)
            }
            return
        }
        if shows { waitingToShow.insert(key) }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let made = Cover.covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)
            let done = made?.url ?? url
            let report = made?.report ?? CoverReport()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    results[key] = done
                    reports[key] = report
                    inProgress.remove(key)
                    if done == url { preparePlain(url) }
                    guard waitingToShow.remove(key) != nil else { return }
                    shownKeys[url.path] = key
                    onRead?(url, done)
                }
            }
        }
    }

    // MARK: A fresh file

    /// A picture as a fresh file, made once for each version of it.
    private static func plain(_ url: URL) -> URL {
        guard let key = plainKey(url) else { return url }
        if let done = cached(key) { return done }
        let done = Cover.plain(url) ?? url
        results[key] = done
        return done
    }

    private static func plainKey(_ url: URL) -> String? {
        modified(url).map { "plain|\(url.path)|\($0.timeIntervalSinceReferenceDate)|\(Cover.plainNames)" }
    }

    /// The fresh file made ahead of time, off the main thread, so copying a
    /// picture with nothing to cover stays instant.
    private static func preparePlain(_ url: URL) {
        guard isImage(url), let key = plainKey(url), cached(key) == nil, !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let made = Cover.plain(url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    results[key] = made ?? url
                    inProgress.remove(key)
                }
            }
        }
    }

    /// Whether a PDF is still being covered with the given kinds, so it
    /// cannot leave yet.
    static func stillCovering(_ url: URL, _ chosen: Set<PrivateDetail>) -> Bool {
        guard isDocument(url), let key = documentKey(url, chosen) else { return false }
        return inProgress.contains(key)
    }

    // MARK: A PDF from outside

    /// Its protected copy, made now if it is not ready yet, so nothing
    /// private leaves uncovered. A PDF with nothing to cover goes as it is.
    private static func shareableDocument(_ url: URL, _ chosen: Set<PrivateDetail>) -> URL {
        guard coversDocument(url, chosen), let key = documentKey(url, chosen) else { return url }
        if let done = cached(key) { return done }
        guard let made = DocumentCover.covering(url, chosen, hand: handPages(url)) else {
            log.error("Could not cover \(url.lastPathComponent, privacy: .public)")
            return url
        }
        results[key] = made.url
        reports[key] = made.report
        inProgress.remove(key)
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
                    }
                    guard waitingToShow.remove(key) != nil else { return }
                    if made != nil {
                        shownKeys[url.path] = key
                    } else {
                        Notice.show(L("Could not cover the private details in this PDF."))
                    }
                    onRead?(url, made?.url ?? url)
                }
            }
        }
    }

    /// Whether anything is to be covered in a PDF brought in: kinds chosen,
    /// or parts hidden by hand. Make PDF's own were covered as Settings
    /// checks; more than that, like every kind for an AI chat, is covered
    /// in them again.
    private static func coversDocument(_ url: URL, _ chosen: Set<PrivateDetail>) -> Bool {
        let protects = DocumentCover.protects(url) || (isDocument(url) && !chosen.isSubset(of: details))
        return protects && (!chosen.isEmpty || !handPages(url).isEmpty)
    }

    /// The file, when it last changed, what to cover and what was hidden by
    /// hand on each page.
    private static func documentKey(_ url: URL, _ chosen: Set<PrivateDetail>) -> String? {
        guard let date = modified(url) else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let pages = handPages(url).sorted { $0.key < $1.key }.map { page, boxes in
            "\(page):" + boxes.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        }.joined(separator: "/")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(pages)|\(OwnRules.fingerprint)"
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
    /// by hand, new words on the stamp, a changed drawing or a changed rule
    /// of the owner's are drawn again.
    private static func key(for url: URL, _ chosen: Set<PrivateDetail>, _ hand: [CGRect],
                            _ stamp: TimeStamp.Mark?, _ clean: Bool, _ drawing: Drawing) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let parts = hand.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(parts)|\(stamp?.key ?? "")|\(clean)|\(drawing.key)|\(OwnRules.fingerprint)|\(Cover.plainNames)"
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
    /// its pixels: what a copy saved beside the original is made from.
    static func covered(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect]) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = upright(source) else { return nil }
        return Finder.cover(image, areas(in: image, chosen) + hand)
    }

    /// A copy of the screenshot with the chosen details and the parts hidden
    /// by hand covered, what was drawn on it, and the time stamped when there
    /// is a stamp, under the same name. Nil when there is nothing to hide,
    /// draw or stamp.
    /// - Parameter clean: a photo that carries where or with what it was
    ///   taken: a copy is made even with nothing to cover, without any of
    ///   it, and as a JPEG, which suits a photo and keeps it small to send.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                     stamp: TimeStamp.Mark? = nil, clean: Bool = false, drawing: Drawing = .empty) -> URL? {
        covering(url, chosen, hand: hand, stamp: stamp, clean: clean, drawing: drawing)?.url
    }

    /// The same copy, with what was covered in it.
    /// - Parameter drawing: drawn over what is covered, then cut to the part
    ///   kept. What the reading covers is found in the whole picture first.
    static func covering(_ url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                         stamp: TimeStamp.Mark? = nil, clean: Bool = false,
                         drawing: Drawing = .empty) -> (url: URL, report: CoverReport)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = upright(source) else { return nil }
        let found = Finder.coveredAreas(in: image, chosen)
        let boxes = found.map(\.rect) + hand
        guard !boxes.isEmpty || stamp != nil || clean || !drawing.isEmpty else { return nil }

        guard var covered = Finder.cover(image, boxes) else { return nil }
        if !drawing.isEmpty, let drawn = Drawing.render(covered, drawing) { covered = drawn }
        // The stamp's band goes above the picture, which grows by its height.
        if let stamp, let stamped = TimeStamp.render(covered, stamp) { covered = stamped }

        // A folder of its own, so the copy keeps the screenshot's name.
        let type = clean ? UTType.jpeg : UTType.png
        guard let target = newCopy(of: url, ext: clean ? "jpg" : "png"),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = clean ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, covered, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (target, CoverReport(found, hand: hand.count))
    }

    /// Where a copy goes: a folder of its own, so it keeps the original's
    /// name, which is what the chat shows.
    static func newCopy(of url: URL, ext: String) -> URL? {
        // A PDF keeps its name, which is mostly its title.
        let name = plainNames && ext != "pdf" ? L("Image") : url.deletingPathExtension().lastPathComponent
        let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
        guard (try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)) != nil else { return nil }
        return target
    }

    /// Plain file names, from Settings › Privacy: pictures leave named
    /// “Image”, not after the file, whose name often says when it was taken.
    /// Off unless turned on.
    static var plainNames: Bool {
        get { UserDefaults.standard.bool(forKey: "plainFileNames") }
        set { UserDefaults.standard.set(newValue, forKey: "plainFileNames") }
    }

    /// A fresh copy of a picture with nothing of the file but what it shows:
    /// none of the notes a file carries on when, where and with what it was
    /// made, and none of the Finder's, like where it was downloaded from. A
    /// PNG stays a PNG, pixel for pixel; a JPEG or HEIC photo goes as a JPEG,
    /// any other picture as a PNG. Nil for a GIF, which goes as itself so it
    /// keeps moving, and for what cannot be read.
    static func plain(_ url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1 else { return nil }
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        if type?.conforms(to: .gif) == true { return nil }
        guard let image = upright(source) else { return nil }
        let photo = type.map { $0.conforms(to: .jpeg) || $0.conforms(to: .heic) || $0.conforms(to: .heif) } ?? false
        guard let target = newCopy(of: url, ext: photo ? "jpg" : "png"),
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
