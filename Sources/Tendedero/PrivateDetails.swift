import AppKit
import NaturalLanguage
import UniformTypeIdentifiers
import Vision

/// The kinds of private detail that can be covered, each chosen on its own
/// under Hide private details in the menu bar.
enum PrivateDetail: String, CaseIterable {
    case names, addresses, emails, phones, bank, health

    var title: String {
        switch self {
        case .names: L("Names")
        case .addresses: L("Addresses")
        case .emails: L("Emails")
        case .phones: L("Phone numbers")
        case .bank: L("Bank cards and accounts")
        case .health: L("Health details")
        }
    }
}

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
        guard !chosen.isEmpty || !hand.isEmpty, isImage(url),
              let key = key(for: url, chosen, hand) else { return url }
        if let done = cached(key) { return done }
        // Not read yet, like a capture copied the instant it hangs.
        let done = Cover.copy(of: url, chosen, hand: hand) ?? url
        results[key] = done
        onRead?(url, done)
        return done
    }

    /// What to show on the line for a screenshot already read.
    static func shown(_ url: URL) -> URL? {
        let chosen = details
        let hand = Self.hand(url)
        guard !chosen.isEmpty || !hand.isEmpty, let key = key(for: url, chosen, hand) else { return nil }
        return cached(key)
    }

    /// Reads a screenshot ahead of time, off the main thread.
    static func prepare(_ url: URL) {
        let chosen = details
        let hand = Self.hand(url)
        guard !chosen.isEmpty || !hand.isEmpty, isImage(url),
              let key = key(for: url, chosen, hand) else { return }
        if let done = cached(key) {
            onRead?(url, done)
            return
        }
        guard !inProgress.contains(key) else { return }
        inProgress.insert(key)
        DispatchQueue.global(qos: .utility).async {
            let done = Cover.copy(of: url, chosen, hand: hand) ?? url
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

    /// The file, when it last changed and what to cover, so a screenshot
    /// edited in Markup, a new choice or a part hidden by hand is read again.
    private static func key(for url: URL, _ chosen: Set<PrivateDetail>, _ hand: [CGRect]) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let kinds = chosen.map(\.rawValue).sorted().joined(separator: ",")
        let parts = hand.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(kinds)|\(parts)"
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
        guard !chosen.isEmpty else { return [] }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        return Finder.boxes(in: image, chosen).map { box in
            // Vision measures from the bottom left, as Core Graphics draws.
            let text = VNImageRectForNormalizedRect(box, image.width, image.height)
            let rect = text.insetBy(dx: -text.height * 0.25, dy: -text.height * 0.2)
            return CGRect(x: rect.minX / width, y: rect.minY / height,
                          width: rect.width / width, height: rect.height / height)
        }
    }

    /// A copy of the screenshot with the chosen details and the parts hidden
    /// by hand covered, under the same name. Nil when there is nothing to hide.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect] = []) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let boxes = areas(in: image, chosen) + hand
        guard !boxes.isEmpty else { return nil }

        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        for box in boxes {
            let rect = VNImageRectForNormalizedRect(box, image.width, image.height)
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
}

/// Finds private details in the text of a screenshot, three ways together:
/// patterns that are private wherever they appear, like an email address;
/// labels that announce one, like "Rechnungsadresse" above a name and an
/// address; and names found once and met again elsewhere.
enum Finder {
    struct TextLine {
        let text: VNRecognizedText
        /// Normalized, from the bottom left, as Vision measures.
        let box: CGRect
        var string: String { text.string }
    }

    /// One thing to cover: part of a line, or all of it.
    fileprivate struct Hit {
        let line: Int
        let range: NSRange?
    }

    /// What a label announces: the kind of its first line, the kind of the
    /// lines after it, and how many lines it can take.
    private struct Block {
        let first: PrivateDetail
        let rest: PrivateDetail
        let lines: Int
    }

    private static let person = Block(first: .names, rest: .addresses, lines: 6)
    private static let name = Block(first: .names, rest: .names, lines: 1)
    private static let health = Block(first: .health, rest: .health, lines: 4)
    private static let bank = Block(first: .bank, rest: .bank, lines: 1)

    /// Labels, lowercased, in the languages screenshots tend to come in.
    private static let labels: [String: Block] = {
        var labels: [String: Block] = [:]
        for label in ["rechnungsadresse", "lieferadresse", "versandadresse", "anschrift", "adresse",
                      "billing address", "shipping address", "delivery address", "address",
                      "ship to", "bill to", "sold to", "absender", "empfänger", "empfaenger",
                      "sender", "recipient", "from", "to", "von", "an",
                      "المرسل", "المستلم", "العنوان"] {
            labels[label] = person
        }
        for label in ["kunde", "kundin", "customer", "käufer", "buyer", "kontoinhaber", "account holder",
                      "name", "patient", "patientin", "versicherter", "الاسم", "العميل", "المريض"] {
            labels[label] = name
        }
        for label in ["diagnose", "diagnosis", "befund", "medikament", "medikamente", "medikation",
                      "medication", "medications", "medicine", "arzneimittel", "rezept", "prescription",
                      "behandlung", "treatment", "therapie", "therapy", "symptome", "symptoms",
                      "allergien", "allergies", "التشخيص", "الدواء", "الأدوية", "العلاج", "الوصفة"] {
            labels[label] = health
        }
        for label in ["iban", "bic", "swift", "kontonummer", "account number", "kartennummer", "card number",
                      "blz", "bankleitzahl", "sort code", "routing number", "cvv", "cvc"] {
            labels[label] = bank
        }
        return labels
    }()

    /// Where the chosen details are, in Vision's normalized coordinates.
    static func boxes(in image: CGImage, _ chosen: Set<PrivateDetail>) -> [CGRect] {
        let lines = read(image)
        return hits(in: lines, chosen).compactMap { hit -> CGRect? in
            let line = lines[hit.line]
            guard let range = hit.range else { return line.box }
            guard let part = Range(range, in: line.string) else { return nil }
            return try? line.text.boundingBox(for: part)?.boundingBox
        }
    }

    /// What a screenshot says, a line per row, with the chosen details and
    /// the words under the parts hidden by hand left out as dots. Copy Text,
    /// translations and descriptions all start from it.
    struct Reading {
        let lines: [String]
        /// How tall each line's letters are, from 0 to 1 of the screenshot.
        let heights: [CGFloat]

        var text: String { lines.joined(separator: "\n") }

        /// The biggest words, most often the page's title, like "Order #1024".
        var headline: String? {
            lines.indices
                .filter { i in lines[i].unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 3 }
                .max { heights[$0] < heights[$1] }
                .map { lines[$0].trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Every line of text in a screenshot, as read, with where it sits,
    /// from 0 to 1 from the bottom left. Search looks through these.
    static func lines(of url: URL) -> [(text: String, box: CGRect)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return read(image).map { ($0.string, $0.box) }
    }

    /// The lines as read, so a part of one can be found and boxed.
    static func textLines(of url: URL) -> [TextLine] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return read(image)
    }

    static func text(of url: URL, hiding chosen: Set<PrivateDetail>, hand: [CGRect] = []) -> String {
        reading(of: url, hiding: chosen, hand: hand).text
    }

    static func reading(of url: URL, hiding chosen: Set<PrivateDetail>, hand: [CGRect] = []) -> Reading {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return Reading(lines: [], heights: []) }
        let lines = read(image)
        var hidden = [IndexSet](repeating: IndexSet(), count: lines.count)
        for hit in hits(in: lines, chosen) {
            let length = lines[hit.line].string.utf16.count
            let range = hit.range ?? NSRange(location: 0, length: length)
            let end = min(range.location + range.length, length)
            if range.location < end { hidden[hit.line].insert(integersIn: range.location..<end) }
        }
        for (i, line) in lines.enumerated() where hand.contains(where: { $0.intersects(line.box) }) {
            let string = line.string
            let all = NSRange(location: 0, length: string.utf16.count)
            for word in Self.word.matches(in: string, range: all) {
                guard let part = Range(word.range, in: string),
                      let box = try? line.text.boundingBox(for: part)?.boundingBox,
                      hand.contains(where: { $0.contains(CGPoint(x: box.midX, y: box.midY)) }) else { continue }
                hidden[i].insert(integersIn: word.range.location..<(word.range.location + word.range.length))
            }
        }
        let kept = lines.indices.map { i -> String in
            let line = lines[i].string as NSString
            var kept = ""
            var from = 0
            for run in hidden[i].rangeView {
                kept += line.substring(with: NSRange(location: from, length: run.lowerBound - from)) + "•••"
                from = run.upperBound
            }
            return kept + line.substring(from: from)
        }
        return Reading(lines: kept, heights: lines.map(\.box.height))
    }

    private static let word = try! NSRegularExpression(pattern: "\\S+")

    /// Everything to leave out, all three ways.
    private static func hits(in lines: [TextLine], _ chosen: Set<PrivateDetail>) -> [Hit] {
        guard !lines.isEmpty, !chosen.isEmpty else { return [] }
        let text = Text(lines)
        var learned = Set<String>()
        var hits = patterns(in: text, chosen)
        hits += labelled(in: lines, chosen, learned: &learned)
        if chosen.contains(.names) { hits += names(in: text, learned: learned) }
        if chosen.contains(.health) { hits += medicines(in: lines) }
        return hits
    }

    private static func read(_ image: CGImage) -> [TextLine] {
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
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { TextLine(text: $0, box: observation.boundingBox) }
        }
    }

    /// All the text at once, a line per row, so a match that runs over two
    /// lines, like an address, is still found.
    fileprivate struct Text {
        let lines: [TextLine]
        let full: String
        let starts: [Int]

        init(_ lines: [TextLine]) {
            self.lines = lines
            var full = ""
            var starts: [Int] = []
            for line in lines {
                starts.append(full.utf16.count)
                full += line.string + "\n"
            }
            self.full = full
            self.starts = starts
        }

        var whole: NSRange { NSRange(full.startIndex..., in: full) }

        /// A range of the whole text, line by line.
        func hits(_ range: NSRange) -> [Hit] {
            lines.indices.compactMap { i -> Hit? in
                let span = NSRange(location: starts[i], length: lines[i].string.utf16.count)
                let overlap = NSIntersectionRange(range, span)
                guard overlap.length > 0 else { return nil }
                return Hit(line: i, range: NSRange(location: overlap.location - span.location, length: overlap.length))
            }
        }

        func matches(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [NSRange] {
            (try? NSRegularExpression(pattern: pattern, options: options))?
                .matches(in: full, range: whole).map(\.range) ?? []
        }
    }

    private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#

    /// Details that are private wherever they appear.
    private static func patterns(in text: Text, _ chosen: Set<PrivateDetail>) -> [Hit] {
        var found: [NSRange] = []
        if chosen.contains(.emails) {
            found += text.matches(emailPattern, .caseInsensitive)
        }
        if chosen.contains(.bank) {
            // IBANs, in groups of four with or without spaces between them.
            found += text.matches(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#)
            // Card numbers: 13 to 19 digits, grouped or not, that pass the Luhn check.
            found += text.matches(#"\b\d(?:[ -]?\d){12,18}\b"#)
                .filter { passesLuhn((text.full as NSString).substring(with: $0)) }
        }
        if chosen.contains(.phones),
           let phones = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            found += phones.matches(in: text.full, range: text.whole).map(\.range)
        }
        var hits = found.flatMap { text.hits($0) }
        if chosen.contains(.addresses),
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            for match in addresses.matches(in: text.full, range: text.whole) {
                let lines = text.hits(match.range)
                hits += lines
                // The detector often stops at the street. The postcode, the
                // town and the country follow just below.
                guard var last = lines.last?.line else { continue }
                for _ in 0..<3 {
                    guard let next = Self.line(below: last, in: text.lines, gap: 1.1),
                          looksLikeAddress(text.lines[next].string) else { break }
                    hits.append(Hit(line: next, range: nil))
                    last = next
                }
            }
        }
        return hits
    }

    /// A postcode with its town, or a town or country on its own.
    private static func looksLikeAddress(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        if line.range(of: #"(^|\s)\d{4,6}(\s|$)"#, options: .regularExpression) != nil { return words.count <= 6 }
        return (1...3).contains(words.count) && line.first?.isUppercase == true
            && line.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" }
    }

    /// Details announced by a label: on the same line, as in "IBAN: DE89…",
    /// or in the lines under it, as a name and an address under
    /// "Rechnungsadresse".
    private static func labelled(in lines: [TextLine], _ chosen: Set<PrivateDetail>,
                                 learned: inout Set<String>) -> [Hit] {
        var hits: [Hit] = []
        for (i, line) in lines.enumerated() {
            let text = line.string.trimmingCharacters(in: .whitespaces)
            var label = normalized(text)
            if let colon = text.firstIndex(of: ":"), let block = labels[normalized(String(text[..<colon]))] {
                let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    let detail = kind(of: value, first: true, in: block)
                    if chosen.contains(detail), let part = line.string.range(of: value) {
                        hits.append(Hit(line: i, range: NSRange(part, in: line.string)))
                        if detail == .names { learn(value, into: &learned) }
                    }
                    continue
                }
                label = normalized(String(text[..<colon]))
            }
            guard let block = labels[label] else { continue }
            var last = i
            for n in 0..<block.lines {
                // A label sits a little further from its first line than the
                // lines from each other.
                guard let next = Self.line(below: last, in: lines, gap: n == 0 ? 2 : 1.1),
                      labels[normalized(lines[next].string)] == nil else { break }
                let detail = kind(of: lines[next].string, first: n == 0, in: block)
                if chosen.contains(detail) {
                    hits.append(Hit(line: next, range: nil))
                    if detail == .names { learn(lines[next].string, into: &learned) }
                }
                last = next
            }
        }
        return hits
    }

    /// The first line under a person's label is their name, when it reads
    /// like one; otherwise, like a street, it is part of the address.
    private static func kind(of line: String, first: Bool, in block: Block) -> PrivateDetail {
        guard first else { return block.rest }
        guard block.first == .names, block.rest != .names else { return block.first }
        return nameWords(line) != nil ? .names : block.rest
    }

    private static func learn(_ name: String, into learned: inout Set<String>) {
        if let words = nameWords(name) { learned.formUnion(words) }
    }

    /// The line right under another, starting in the same column, or nil
    /// when the gap is one a new section would leave.
    private static func line(below index: Int, in lines: [TextLine], gap: CGFloat) -> Int? {
        let above = lines[index].box
        var best: Int?
        for (i, line) in lines.enumerated() where i != index {
            let box = line.box
            guard box.maxY <= above.minY + above.height * 0.3,
                  above.minY - box.maxY < above.height * gap,
                  abs(box.minX - above.minX) < 0.03 else { continue }
            if let current = best, lines[current].box.maxY >= box.maxY { continue }
            best = i
        }
        return best
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":"))).lowercased()
    }

    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static let particles: Set<String> = ["van", "von", "de", "da", "del", "der", "den", "la", "le",
                                                 "bin", "ibn", "al", "el", "di", "du"]

    /// The words of a line that reads like a person's name: two to five
    /// words, at least two of them capitalized, and no digits. German
    /// capitalizes every noun, so the shape alone is never enough.
    private static func nameWords(_ line: String) -> [String]? {
        let words = line.split(separator: " ").map(String.init)
        guard (2...5).contains(words.count), !line.contains(where: \.isNumber) else { return nil }
        var names: [String] = []
        for word in words where !particles.contains(word) {
            guard word.first?.isUppercase == true,
                  word.allSatisfy({ $0.isLetter || "'’.-".contains($0) }) else { return nil }
            names.append(fold(word))
        }
        return names.count >= 2 ? names : nil
    }

    /// Names: a line shaped like one that something vouches for. It was
    /// under a label, the Natural Language framework calls it a person's
    /// name, it is in an email address, or it repeats a name found elsewhere.
    private static func names(in text: Text, learned: Set<String>) -> [Hit] {
        var tagged = Set<Int>()
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text.full
        tagger.enumerateTags(in: text.full.startIndex..<text.full.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            // A whole name, not a lone word: German capitalizes every noun,
            // and the tagger takes some of them for names.
            if tag == .personalName, text.full[range].contains(" ") {
                for hit in text.hits(NSRange(range, in: text.full)) { tagged.insert(hit.line) }
            }
            return true
        }
        let emails = text.matches(emailPattern, .caseInsensitive).map { range -> String in
            let address = (text.full as NSString).substring(with: range)
            return fold(String(address.prefix { $0 != "@" }))
        }

        let candidates = text.lines.indices.compactMap { i in nameWords(text.lines[i].string).map { (i, $0) } }
        var known = learned
        var found = Set<Int>()
        // Twice, so a name vouched for further down covers its earlier
        // mentions too.
        for _ in 0..<2 {
            for (i, words) in candidates where !found.contains(i) {
                let inEmail = words.contains { word in word.count >= 4 && emails.contains { $0.contains(word) } }
                if tagged.contains(i) || inEmail || words.allSatisfy(known.contains) {
                    found.insert(i)
                    known.formUnion(words)
                }
            }
        }
        return found.map { Hit(line: $0, range: nil) }
    }

    /// Lines with a dose or a pharmacy number, where medicines are named.
    private static func medicines(in lines: [TextLine]) -> [Hit] {
        let dose = #"\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ml|ie|iu|tbl|tabletten|tablets?|kapseln|capsules?)\b"#
        let pharmacy = #"\bPZN[:\s-]*\d{7,8}\b"#
        return lines.indices.compactMap { i -> Hit? in
            let line = lines[i].string
            let named = line.range(of: dose, options: [.regularExpression, .caseInsensitive]) != nil
                || line.range(of: pharmacy, options: .regularExpression) != nil
            return named ? Hit(line: i, range: nil) : nil
        }
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
