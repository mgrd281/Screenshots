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
            if let raw = UserDefaults.standard.stringArray(forKey: "hiddenDetails") {
                return Set(raw.compactMap(PrivateDetail.init(rawValue:)))
            }
            return UserDefaults.standard.bool(forKey: "hidePrivateDetails") ? Set(PrivateDetail.allCases) : []
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenDetails") }
    }

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
        if isDocument(url) { return DocumentCover.protects(url) && (hidden || !handPages(url).isEmpty) }
        return hidden || !hand(url).isEmpty
    }

    /// Whether a screenshot leaves the line changed: covered, stamped with
    /// the time, or both. A photo also leaves without where it was taken.
    static func alters(_ url: URL) -> Bool {
        if isDocument(url) { return covers(url) }
        return covers(url) || TimeStamp.mark(for: url) != nil || strips(url)
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

    /// What to hand out for a screenshot.
    static func shareable(_ url: URL) -> URL {
        if isDocument(url) { return shareableDocument(url) }
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean, isImage(url),
              let key = key(for: url, chosen, hand, stamp, clean) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let done = Cover.copy(of: url, chosen, hand: hand, stamp: stamp, clean: clean) ?? url
        results[key] = done
        onRead?(url, done)
        return done
    }

    /// What to show on the line for a screenshot already read.
    static func shown(_ url: URL) -> URL? {
        if isDocument(url) { return documentKey(url).flatMap(cached) }
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean,
              let key = key(for: url, chosen, hand, stamp, clean) else { return nil }
        return cached(key)
    }

    /// Reads a screenshot ahead of time, off the main thread.
    static func prepare(_ url: URL) {
        if isDocument(url) { return prepareDocument(url) }
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        let clean = strips(url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil || clean, isImage(url),
              let key = key(for: url, chosen, hand, stamp, clean) else { return }
        if let done = cached(key) {
            onRead?(url, done)
            return
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let done = Cover.copy(of: url, chosen, hand: hand, stamp: stamp, clean: clean) ?? url
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    results[key] = done
                    inProgress.remove(key)
                    onRead?(url, done)
                }
            }
        }
    }

    // MARK: A PDF from outside

    /// Its protected copy, made now if it is not ready yet, so nothing
    /// private leaves uncovered. A PDF with nothing to cover goes as it is.
    private static func shareableDocument(_ url: URL) -> URL {
        guard covers(url), let key = documentKey(url) else { return url }
        if let done = cached(key) { return done }
        guard let done = DocumentCover.copy(of: url, details, hand: handPages(url)) else {
            log.error("Could not cover \(url.lastPathComponent, privacy: .public)")
            return url
        }
        results[key] = done
        inProgress.remove(key)
        onRead?(url, done)
        return done
    }

    /// Covers every page in the background as soon as it hangs, which for
    /// a long document takes a while; the line shows it is working.
    private static func prepareDocument(_ url: URL) {
        guard covers(url), let key = documentKey(url) else { return }
        if let done = cached(key) {
            onRead?(url, done)
            return
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        onStart?(url)
        let chosen = details
        let hand = handPages(url)
        DispatchQueue.global(qos: .userInitiated).async {
            let done = DocumentCover.copy(of: url, chosen, hand: hand)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    inProgress.remove(key)
                    if let done { results[key] = done } else {
                        Notice.show(L("Could not cover the private details in this PDF."))
                    }
                    onRead?(url, done ?? url)
                }
            }
        }
    }

    /// The file, when it last changed, what to cover and what was hidden by
    /// hand on each page.
    private static func documentKey(_ url: URL) -> String? {
        guard let date = modified(url) else { return nil }
        let kinds = details.map(\.rawValue).sorted().joined(separator: ",")
        let pages = handPages(url).sorted { $0.key < $1.key }.map { page, boxes in
            "\(page):" + boxes.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        }.joined(separator: "/")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(pages)"
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

    /// The file, when it last changed, what to cover and the stamp, so a
    /// screenshot edited in Markup, a new choice, a part hidden by hand or
    /// new words on the stamp are drawn again.
    private static func key(for url: URL, _ chosen: Set<PrivateDetail>, _ hand: [CGRect],
                            _ stamp: TimeStamp.Mark?, _ clean: Bool) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let parts = hand.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(parts)|\(stamp?.key ?? "")|\(clean)"
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
    /// by hand covered, and the time stamped when there is a stamp, under
    /// the same name. Nil when there is nothing to hide or stamp.
    /// - Parameter clean: a photo that carries where or with what it was
    ///   taken: a copy is made even with nothing to cover, without any of
    ///   it, and as a JPEG, which suits a photo and keeps it small to send.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                     stamp: TimeStamp.Mark? = nil, clean: Bool = false) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = upright(source) else { return nil }
        let boxes = areas(in: image, chosen) + hand
        guard !boxes.isEmpty || stamp != nil || clean else { return nil }

        guard var covered = Finder.cover(image, boxes) else { return nil }
        // The stamp's band goes above the picture, which grows by its height.
        if let stamp, let stamped = TimeStamp.render(covered, stamp) { covered = stamped }

        // A folder of its own, so the copy keeps the screenshot's name.
        let type = clean ? UTType.jpeg : UTType.png
        guard let target = newCopy(of: url, ext: clean ? "jpg" : "png"),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = clean ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, covered, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? target : nil
    }

    /// Where a copy goes: a folder of its own, so it keeps the original's
    /// name, which is what the chat shows.
    static func newCopy(of url: URL, ext: String) -> URL? {
        let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(ext)
        guard (try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)) != nil else { return nil }
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
