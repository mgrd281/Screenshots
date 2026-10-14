import AppKit
import NaturalLanguage
import UniformTypeIdentifiers
import Vision

/// Hide private details, from the menu bar: whatever leaves the line,
/// copied, sent to a chat or dragged out, is a copy of the screenshot with
/// names, addresses, emails, phone numbers, IBANs and card numbers covered.
/// The line shows each photo that way too, so what you see is what goes.
/// The screenshot file itself is never touched.
///
/// Each screenshot is read once, in the background when it hangs, so
/// copying it stays instant. It is a help, not a promise: text the
/// recognition misreads stays as it is.
@MainActor
enum PrivateDetails {
    nonisolated static var hidden: Bool {
        get { UserDefaults.standard.bool(forKey: "hidePrivateDetails") }
        set { UserDefaults.standard.set(newValue, forKey: "hidePrivateDetails") }
    }

    /// For each screenshot as it was when read: its covered copy, or the
    /// file itself when there was nothing to hide.
    private static var results: [String: URL] = [:]
    private static var inProgress: Set<String> = []

    /// Called once a screenshot has been read, with the screenshot and what
    /// to hand out for it, so the line can show it that way.
    static var onRead: ((URL, URL) -> Void)?

    /// What to hand out for a screenshot.
    static func shareable(_ url: URL) -> URL {
        guard hidden, !isRecording(url), let key = key(for: url) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let done = Cover.copy(of: url) ?? url
        results[key] = done
        onRead?(url, done)
        return done
    }

    /// What to show on the line for a screenshot already read, while the
    /// option is on.
    static func shown(_ url: URL) -> URL? {
        guard hidden, let key = key(for: url) else { return nil }
        return cached(key)
    }

    /// Reads a screenshot ahead of time, off the main thread.
    static func prepare(_ url: URL) {
        guard hidden, !isRecording(url), let key = key(for: url) else { return }
        if let done = cached(key) {
            onRead?(url, done)
            return
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let done = Cover.copy(of: url) ?? url
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

    /// The file and when it last changed, so a screenshot edited in Markup
    /// is read again.
    private static func key(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)"
    }
}

/// Finding private details in a screenshot and drawing a copy with them
/// covered. The text is read on this Mac, with the recognition Live Text
/// uses, and goes nowhere else.
enum Cover {
    /// Where the covered copies wait to be pasted. Emptied at each launch.
    private static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Covered", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        return folder
    }()

    /// A copy of the screenshot with its private details covered, under
    /// the same name. Nil when there is nothing to hide.
    static func copy(of url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let boxes = privateBoxes(in: image)
        guard !boxes.isEmpty else { return nil }

        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        for box in boxes {
            // Vision measures from the bottom left, as Core Graphics draws.
            let text = VNImageRectForNormalizedRect(box, image.width, image.height)
            let rect = text.insetBy(dx: -text.height * 0.25, dy: -text.height * 0.2)
            let radius = min(rect.height / 4, rect.width / 2, 8)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        guard let covered = context.makeImage() else { return nil }

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

    /// Where the private details are, in Vision's normalized coordinates.
    private static func privateBoxes(in image: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Numbers and addresses are read as they are, not corrected into words.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            log.error("Could not read a screenshot: \(error.localizedDescription, privacy: .public)")
            return []
        }
        // All the text at once, a line per row, so an address or a name
        // that runs over two lines is still found.
        var full = ""
        var spans: [(text: VNRecognizedText, range: NSRange)] = []
        for line in request.results ?? [] {
            guard let text = line.topCandidates(1).first else { continue }
            spans.append((text: text, range: NSRange(location: full.utf16.count, length: text.string.utf16.count)))
            full += text.string + "\n"
        }
        var boxes: [CGRect] = []
        for found in privateRanges(in: full) {
            for span in spans {
                let overlap = NSIntersectionRange(found, span.range)
                guard overlap.length > 0,
                      let range = Range(NSRange(location: overlap.location - span.range.location, length: overlap.length),
                                        in: span.text.string),
                      let box = try? span.text.boundingBox(for: range)?.boundingBox else { continue }
                boxes.append(box)
            }
        }
        return boxes
    }

    /// The private parts of the text in a screenshot.
    static func privateRanges(in text: String) -> [NSRange] {
        let whole = NSRange(text.startIndex..., in: text)
        func matches(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [NSRange] {
            (try? NSRegularExpression(pattern: pattern, options: options))?
                .matches(in: text, range: whole).map(\.range) ?? []
        }
        var found: [NSRange] = []
        // Email addresses.
        found += matches(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, .caseInsensitive)
        // IBANs, in groups of four with or without spaces between them.
        found += matches(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#)
        // Card numbers: 13 to 19 digits, grouped or not, that pass the Luhn check.
        found += matches(#"\b\d(?:[ -]?\d){12,18}\b"#)
            .filter { passesLuhn((text as NSString).substring(with: $0)) }
        // Phone numbers and postal addresses, as Mail and Messages recognize them.
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .address]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            found += detector.matches(in: text, range: whole).map(\.range)
        }
        // People's names, as the Natural Language framework tells them apart.
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .personalName { found.append(NSRange(range, in: text)) }
            return true
        }
        return found
    }

    private static func passesLuhn(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, digit) in digits.reversed().enumerated() {
            let doubled = digit * 2
            sum += i % 2 == 1 ? (doubled > 9 ? doubled - 9 : doubled) : digit
        }
        return sum % 10 == 0
    }
}
