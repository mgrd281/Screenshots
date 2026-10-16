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
              all.keys.contains(where: { !paths.contains($0) }) else { return }
        UserDefaults.standard.set(all.filter { paths.contains($0.key) }, forKey: handKey)
    }

    /// Whether anything is covered in a screenshot: details chosen, or parts
    /// hidden by hand.
    static func covers(_ url: URL) -> Bool {
        hidden || !hand(url).isEmpty
    }

    /// Whether a screenshot leaves the line changed: covered, stamped with
    /// the time, or both.
    static func alters(_ url: URL) -> Bool {
        covers(url) || TimeStamp.mark(for: url) != nil
    }

    /// For each screenshot as it was when read, with what was chosen then:
    /// its covered copy, or the file itself when there was nothing to hide.
    private static var results: [String: URL] = [:]
    private static var inProgress: Set<String> = []

    /// Called once a screenshot has been read, with the screenshot and what
    /// to hand out for it, so the line can show it that way.
    static var onRead: ((URL, URL) -> Void)?

    /// What to hand out for a screenshot.
    static func shareable(_ url: URL) -> URL {
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil, isImage(url),
              let key = key(for: url, chosen, hand, stamp) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let done = Cover.copy(of: url, chosen, hand: hand, stamp: stamp) ?? url
        results[key] = done
        onRead?(url, done)
        return done
    }

    /// What to show on the line for a screenshot already read.
    static func shown(_ url: URL) -> URL? {
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil,
              let key = key(for: url, chosen, hand, stamp) else { return nil }
        return cached(key)
    }

    /// Reads a screenshot ahead of time, off the main thread.
    static func prepare(_ url: URL) {
        let chosen = details
        let hand = Self.hand(url)
        let stamp = TimeStamp.mark(for: url)
        guard !chosen.isEmpty || !hand.isEmpty || stamp != nil, isImage(url),
              let key = key(for: url, chosen, hand, stamp) else { return }
        if let done = cached(key) {
            onRead?(url, done)
            return
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let done = Cover.copy(of: url, chosen, hand: hand, stamp: stamp) ?? url
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    results[key] = done
                    inProgress.remove(key)
                    onRead?(url, done)
                }
            }
        }
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
                            _ stamp: TimeStamp.Mark?) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let parts = hand.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(parts)|\(stamp?.key ?? "")"
    }
}

/// Drawing a copy of a screenshot with its private details covered. The
/// text is read on this Mac, with the recognition Live Text uses, and goes
/// nowhere else.
enum Cover {
    /// Where the covered copies wait to be pasted. Emptied at each launch.
    private static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Covered", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        return folder
    }()

    /// Where the chosen details are, as they are covered: from 0 to 1 from
    /// the bottom left, with a margin around the text.
    static func areas(in image: CGImage, _ chosen: Set<PrivateDetail>) -> [CGRect] {
        Finder.areas(in: image, chosen)
    }

    /// A copy of the screenshot with the chosen details and the parts hidden
    /// by hand covered, and the time stamped when there is a stamp, under
    /// the same name. Nil when there is nothing to hide or stamp.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                     stamp: TimeStamp.Mark? = nil) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let boxes = areas(in: image, chosen) + hand
        guard !boxes.isEmpty || stamp != nil else { return nil }

        guard var covered = Finder.cover(image, boxes) else { return nil }
        // The stamp's band goes above the picture, which grows by its height.
        if let stamp, let stamped = TimeStamp.render(covered, stamp) { covered = stamped }

        // A folder of its own, so the copy keeps the screenshot's name.
        let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
        guard (try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)) != nil,
              let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, covered, nil)
        return CGImageDestinationFinalize(destination) ? target : nil
    }
}
