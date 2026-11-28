import AppKit
import AVFoundation
import CoreText
import CryptoKit

/// When a recording was made, in a form that holds up outside the Mac: a
/// time stamp from an independent authority (`TrustedTime`), qualified
/// under the EU's eIDAS regulation, on the recording's SHA-256 fingerprint.
/// The time is the authority's, never the Mac's clock, and only the
/// fingerprint goes out, never the recording.
///
/// It is off until turned on in Settings; then each new recording gets its
/// proof as it hangs, kept with the file wherever it goes on this Mac. Save
/// Proof of Time… in a recording's or a screenshot's menu puts the file, the
/// authority's signed answer and a page that says what it proves and how to
/// check it into one folder, ready to hand to a lawyer. A file with no proof,
/// or one changed since, gets one first.
enum TimeProof {
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "timeProof") }
        set { UserDefaults.standard.set(newValue, forKey: "timeProof") }
    }

    /// One file's proof, kept with the file.
    struct Record: Codable, Equatable, Sendable {
        /// SHA-256 of the file as it was proved.
        var fingerprint: String
        /// By the authority's clock, and signed by it.
        var signed: Date
        var accuracy: Double?
        var authority: String
        var qualified: Bool
        var serial: String
        /// The authority's whole answer, as it came: the proof itself.
        var response: Data
        /// When the recording began, by the atomic clock when `atomic`, by
        /// the Mac's clock otherwise. Snapfly's own reading, not signed.
        var began: Date?
        var atomic: Bool
        var duration: Double?
    }

    // MARK: New recordings

    /// When recordings Snapfly made began, by the Mac's clock, until their
    /// proof is made.
    @MainActor private static var beginnings: [String: Date] = [:]
    /// The recordings proved since Snapfly started, so a change Snapfly
    /// makes to one, as drawing its pointer in, gets a new proof.
    @MainActor private static var proved: Set<String> = []

    /// A recording Snapfly made began at this moment by the Mac's clock.
    @MainActor
    static func began(_ url: URL, at moment: Date) {
        beginnings[url.path] = moment
    }

    /// A new recording, as it hangs: it gets its proof now, while the
    /// moment is fresh. One hung again from the history keeps what it has.
    @MainActor
    static func arrive(_ url: URL) {
        let began = beginnings.removeValue(forKey: url.path)
        guard isOn, isRecording(url), let made = modified(url), Date().timeIntervalSince(made) < 120,
              record(of: url) == nil else { return }
        proved.insert(url.path)
        prove(url, began: began) { record in
            if record != nil {
                Notice.show(L("The recording has its proof of time. To hand it on, choose Save Proof of Time… in its menu."),
                            done: true, lasting: 6)
            } else {
                Notice.show(L("Could not get a proof of time for the recording. Choose Save Proof of Time… in its menu to try again."),
                            lasting: 8)
            }
        }
    }

    /// A recording Snapfly itself changed, as by drawing its pointer in: a
    /// proof made of it before is made again, of the file as it is now, and
    /// keeps when it began.
    @MainActor
    static func changed(_ url: URL) {
        guard isOn, proved.contains(url.path) else { return }
        prove(url, began: record(of: url)?.began, again: true) { _ in }
    }

    // MARK: Making a proof

    /// Who waits for a file's proof while it is being made.
    @MainActor private static var waiting: [String: [@MainActor (Record?) -> Void]] = [:]
    /// Files changed while their proof was being made, so it is made again.
    @MainActor private static var stale: Set<String> = []

    /// Asks for a proof of the file as it is now and keeps it with the
    /// file. Calls back on the main thread, with nil when no authority
    /// answered or the file could not be read.
    @MainActor
    static func prove(_ url: URL, began: Date? = nil, again: Bool = false,
                      then done: @escaping @MainActor (Record?) -> Void) {
        let path = url.path
        if waiting[path] != nil {
            waiting[path]?.append(done)
            if again { stale.insert(path) }
            return
        }
        waiting[path] = [done]
        AtomicTime.offset { offset in
            Task.detached(priority: .utility) {
                let made = await make(url, began: began, offset: offset)
                await MainActor.run { finished(url, began: began, made) }
            }
        }
    }

    @MainActor
    private static func finished(_ url: URL, began: Date?, _ made: Record?) {
        let path = url.path
        let callbacks = waiting.removeValue(forKey: path) ?? []
        if stale.remove(path) != nil {
            // Made of the file as it was before the change: once more.
            prove(url, began: began) { record in callbacks.forEach { $0(record) } }
            return
        }
        if let made { write(made, to: url) }
        callbacks.forEach { $0(made) }
    }

    nonisolated private static func make(_ url: URL, began: Date?, offset: TimeInterval?) async -> Record? {
        guard let digest = sha256(of: url) else { return nil }
        guard let (stamp, authority) = await TrustedTime.stamp(sha256: digest) else {
            log.error("No time stamping authority answered")
            return nil
        }
        let duration = isRecording(url) ? await length(of: url) : nil
        return Record(fingerprint: hex(digest), signed: stamp.time, accuracy: stamp.accuracy, authority: authority.name,
                      qualified: stamp.qualified, serial: stamp.serial, response: stamp.response,
                      began: began.map { $0.addingTimeInterval(offset ?? 0) }, atomic: began != nil && offset != nil,
                      duration: duration)
    }

    /// The file's SHA-256, read a little at a time, as a recording can be
    /// larger than the memory.
    nonisolated static func sha256(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                let more: Bool = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
                    hasher.update(data: chunk)
                    return true
                }
                if !more { break }
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize())
    }

    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func length(of url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration).seconds,
              duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    nonisolated private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Kept with the file

    private static let recordName = "com.snapfly.time-proof"

    static func record(of url: URL) -> Record? {
        url.withUnsafeFileSystemRepresentation { path -> Record? in
            guard let path else { return nil }
            let size = getxattr(path, recordName, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, recordName, $0.baseAddress, size, 0, 0) }
            guard read == size else { return nil }
            return try? JSONDecoder().decode(Record.self, from: data)
        }
    }

    private static func write(_ record: Record, to url: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes { setxattr(path, recordName, $0.baseAddress, data.count, 0, 0) }
        }
    }

    // MARK: Handing it on

    /// Save Proof of Time…: the proof kept with the file when it is still
    /// of the file as it is, else a new one; then the folder to put it in.
    @MainActor
    static func save(_ url: URL) {
        let note = Notice.show(L("Getting the proof of time…"), working: true)
        let kept = record(of: url)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = sha256(of: url).map(hex)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let kept, let now, kept.fingerprint == now {
                        Notice.end(note)
                        choosePlace(for: url, kept)
                        return
                    }
                    // Changed since, as by Trim: what it began at no longer holds.
                    prove(url) { record in
                        Notice.end(note)
                        guard let record else {
                            Notice.show(L("Could not get a proof of time. Check the internet connection and try again."),
                                        lasting: 6)
                            return
                        }
                        choosePlace(for: url, record)
                    }
                }
            }
        }
    }

    @MainActor
    private static func choosePlace(for url: URL, _ record: Record) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(format: L("%@ – proof of time"), url.deletingPathExtension().lastPathComponent)
        panel.message = L("A folder with the file, the signed time stamp and a page that explains it, for a lawyer or a court.")
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let text = page(record, file: url.lastPathComponent)
        let pageName = L("Proof of Time")
        // The same words as a PDF, with what the time stamp kept of the
        // moment, read now.
        let words = paragraphs(record, file: url.lastPathComponent)
        let kept = Self.seen(url)
        let recording = isRecording(url)
        let rightToLeft = TimeStamp.rightToLeft
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let target = panel.url else { return }
                let note = Notice.show(L("Saving the proof of time…"), working: true)
                Task.detached(priority: .userInitiated) {
                    let saved = write(url, record, page: text, named: pageName, into: target)
                    if saved {
                        await writeDocument(of: url, words, kept, recording: recording, rightToLeft: rightToLeft,
                                            title: pageName,
                                            to: target.appendingPathComponent(pageName).appendingPathExtension("pdf"))
                    }
                    await MainActor.run {
                        Notice.end(note)
                        if saved {
                            Notice.savedCopy(target)
                        } else {
                            Notice.show(L("Could not save the proof of time."))
                        }
                    }
                }
            }
        }
    }

    /// The folder: the file exactly as it is, the authority's answer named
    /// after it (".tsr", as RFC 3161 tools expect), and the page.
    nonisolated private static func write(_ url: URL, _ record: Record, page: String, named pageName: String,
                                          into folder: URL) -> Bool {
        let fm = FileManager.default
        do {
            // The panel has already asked whether to replace it.
            if fm.fileExists(atPath: folder.path) { try fm.trashItem(at: folder, resultingItemURL: nil) }
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            try fm.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            try record.response.write(to: folder.appendingPathComponent(url.lastPathComponent + ".tsr"))
            try Data(page.utf8).write(to: folder.appendingPathComponent(pageName).appendingPathExtension("txt"))
            return true
        } catch {
            log.error("Could not save a proof of time: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    // MARK: The page

    /// One paragraph of the page, and how the PDF sets it: an empty one
    /// stands for the room between parts.
    struct Paragraph: Equatable, Sendable {
        enum Kind: Sendable { case title, text, strong, code, link, gap }
        var text: String
        var kind: Kind
        /// Where a link leads.
        var url: URL? = nil
    }

    /// What the proof says, what it proves and how to check it without
    /// Snapfly, in the Mac's language, with the time in UTC beside it.
    static func page(_ record: Record, file name: String, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        paragraphs(record, file: name, locale: locale, timeZone: timeZone).map(\.text).joined(separator: "\n") + "\n"
    }

    /// The page's paragraphs, as the text file and the PDF both have them.
    static func paragraphs(_ record: Record, file name: String, locale: Locale = .autoupdatingCurrent,
                           timeZone: TimeZone = .autoupdatingCurrent) -> [Paragraph] {
        let when = DateFormatter()
        when.locale = locale
        when.timeZone = timeZone
        when.dateStyle = .long
        when.timeStyle = .long
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"

        let gap = Paragraph(text: "", kind: .gap)
        func text(_ words: String) -> Paragraph { Paragraph(text: words, kind: .text) }
        var lines = [Paragraph(text: L("Proof of Time"), kind: .title), gap]
        lines.append(text(String(format: L("File: %@"), name)))
        lines.append(text(String(format: L("Fingerprint (SHA-256): %@"), record.fingerprint)))
        lines.append(gap)
        lines.append(text(String(format: L("Signed time: %@"), when.string(from: record.signed) + " · " + utc.string(from: record.signed))))
        if let accuracy = record.accuracy {
            let number = NumberFormatter()
            number.locale = locale
            number.maximumFractionDigits = 3
            lines.append(text(String(format: L("Accuracy: ± %@ s"), number.string(from: NSNumber(value: accuracy)) ?? "\(accuracy)")))
        }
        lines.append(text(String(format: L("Time stamping authority: %@"), record.authority)))
        lines.append(text(record.qualified
            ? L("A qualified electronic time stamp under the EU’s eIDAS regulation (Article 41).")
            : L("A time stamp under RFC 3161, though not a qualified one.")))
        lines.append(text(String(format: L("Serial number: %@"), record.serial)))
        if record.began != nil || record.duration != nil { lines.append(gap) }
        if let began = record.began {
            let format = record.atomic
                ? L("Recording began: %@, by the PTB’s atomic clock, as Snapfly read it (not signed).")
                : L("Recording began: %@, by the Mac’s clock (not signed).")
            lines.append(text(String(format: format, when.string(from: began))))
        }
        if let duration = record.duration {
            let length = DateComponentsFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            length.calendar = calendar
            length.unitsStyle = .full
            length.allowedUnits = [.hour, .minute, .second]
            lines.append(text(String(format: L("Length: %@"), length.string(from: duration.rounded()) ?? "")))
        }
        lines.append(gap)
        lines.append(text(L("What it proves: this very file, byte for byte, existed no later than the signed time. Changed in any way, even by one byte, it no longer matches. It does not prove who made it or what it shows.")))
        lines.append(gap)
        let answer = name + ".tsr"
        lines.append(text(String(format: L("How to check it without Snapfly: “%@” is the authority’s signed answer (RFC 3161). Any program that reads RFC 3161 time stamps can check it against the file, OpenSSL for example:"), answer)))
        lines.append(gap)
        lines.append(Paragraph(text: "openssl ts -reply -in \"\(answer)\" -text", kind: .code))
        lines.append(Paragraph(text: "openssl ts -verify -in \"\(answer)\" -data \"\(name)\" -CAfile \"root.pem\"", kind: .code))
        lines.append(gap)
        lines.append(text(L("“root.pem” stands for the authority’s root certificate, from its own website.")))
        return lines
    }

    // MARK: The PDF

    /// What the time stamp kept of the moment, beside the proof: the page in
    /// front as a screenshot was taken, or the pages a recording showed,
    /// each from when it was opened, and the stamp on a screenshot. Snapfly's
    /// own reading, not signed.
    struct Seen: Equatable, Sendable {
        struct Page: Equatable, Sendable {
            /// Seconds into the recording; nil for a screenshot.
            var at: Double?
            /// The page's whole address.
            var address: String
        }

        var pages: [Page] = []
        /// What the band on a screenshot says, to draw its picture with.
        var stamp: TimeStamp.Mark?
    }

    /// What the time stamp kept of a file, while the stamp is on.
    @MainActor
    static func seen(_ url: URL) -> Seen {
        guard TimeStamp.isOn else { return Seen() }
        if isRecording(url) {
            return Seen(pages: VideoStamp.record(of: url).map(pages(in:)) ?? [])
        }
        guard let stamp = TimeStamp.mark(for: url) else { return Seen() }
        let address = TimeStamp.record(of: url)?.page.flatMap(StampSite.address(of:))
        return Seen(pages: address.map { [Seen.Page(at: nil, address: $0)] } ?? [], stamp: stamp)
    }

    /// The websites a recording showed, each from when it was opened; a
    /// moment with no website in front is left out.
    static func pages(in record: VideoStamp.Record) -> [Seen.Page] {
        var pages: [Seen.Page] = []
        var previous: String?
        for page in record.pages.sorted(by: { $0.at < $1.at }) {
            let address = page.address.flatMap(StampSite.address(of:))
            if let address, address != previous {
                pages.append(Seen.Page(at: page.at.isFinite ? max(0, page.at) : 0, address: address))
            }
            previous = address
        }
        return pages
    }

    /// A moment into a recording as a player shows it: 0:12, 12:05, 1:02:03.
    static func moment(_ seconds: Double) -> String {
        let whole = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
        let hours = whole / 3600, minutes = whole % 3600 / 60, rest = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// One piece of the PDF, set down its pages in order.
    enum Block {
        case words(Paragraph)
        /// A picture, no larger than `largest` in points, with links over it
        /// in its pixels from its top left.
        case picture(CGImage, links: [TimeStamp.Link], largest: CGSize)
    }

    /// The PDF's pieces: the page's words, then the pages in front with
    /// their addresses as links, a recording's with a picture of it as each
    /// was opened, and a screenshot's stamped picture.
    /// - Parameters:
    ///   - picture: the screenshot with its band, and where the band's links are.
    ///   - frames: the recording as each page was opened, where a picture could be made.
    static func blocks(_ paragraphs: [Paragraph], seen: Seen, recording: Bool, picture: TimeStamp.Band? = nil,
                       frames: [CGImage?] = []) -> [Block] {
        var blocks = paragraphs.map(Block.words)
        if !seen.pages.isEmpty {
            blocks.append(.words(Paragraph(text: "", kind: .gap)))
            blocks.append(.words(Paragraph(text: recording
                ? L("The pages open in the browser in front during the recording, each from when it was opened, as Snapfly read them (not signed):")
                : L("The page open in the browser in front as the screenshot was taken, as Snapfly read it (not signed):"),
                kind: .text)))
            for (index, page) in seen.pages.enumerated() {
                if recording, let at = page.at {
                    blocks.append(.words(Paragraph(text: String(format: L("From %@"), moment(at)), kind: .strong)))
                }
                blocks.append(.words(Paragraph(text: page.address, kind: .link, url: URL(string: page.address))))
                if index < frames.count, let frame = frames[index] {
                    blocks.append(.picture(frame, links: [], largest: CGSize(width: 260, height: 200)))
                }
            }
        }
        if let picture {
            blocks.append(.words(Paragraph(text: "", kind: .gap)))
            blocks.append(.words(Paragraph(text: L("The screenshot with the time stamp Snapfly drew on it (not signed):"),
                                           kind: .text)))
            blocks.append(.picture(picture.image, links: picture.links,
                                   largest: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)))
        }
        return blocks
    }

    /// A piece set on a page, in the page's points from its bottom left: a
    /// frame of words or a picture, with its links.
    struct Placed {
        var page: Int
        var frame: CTFrame?
        var picture: CGImage?
        var rect: CGRect
        var links: [(rect: CGRect, url: URL)]
    }

    /// An A4 page, and the room round what is on it.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 56

    /// Sets the pieces down A4 pages, starting a new page wherever the next
    /// does not fit, and a long paragraph goes on over the next.
    static func layOut(_ blocks: [Block], rightToLeft: Bool) -> [Placed] {
        let width = pageSize.width - 2 * margin
        let pageTop = pageSize.height - margin
        var placed: [Placed] = []
        var page = 0
        var top = pageTop
        func newPage() {
            page += 1
            top = pageTop
        }
        for block in blocks {
            switch block {
            case .words(let paragraph):
                if paragraph.kind == .gap {
                    if top < pageTop { top -= 8 }
                    continue
                }
                // A moment stays with the address after it.
                if paragraph.kind == .strong, top - margin < 64, top < pageTop { newPage() }
                let text = attributed(paragraph, rightToLeft: rightToLeft)
                let setter = CTFramesetterCreateWithAttributedString(text)
                var start = 0
                while start < text.length {
                    let rect = CGRect(x: margin, y: margin, width: width, height: max(0, top - margin))
                    let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0),
                                                         CGPath(rect: rect, transform: nil), nil)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
                    guard visible.length > 0, !lines.isEmpty else {
                        // Not a line fits here: on the next page, unless this one is empty.
                        if top < pageTop {
                            newPage()
                            continue
                        }
                        break
                    }
                    var origins = [CGPoint](repeating: .zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                    var links: [(rect: CGRect, url: URL)] = []
                    var bottom = top
                    for (line, origin) in zip(lines, origins) {
                        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                        let box = CGRect(x: rect.minX + origin.x, y: rect.minY + origin.y - descent,
                                         width: lineWidth, height: ascent + descent)
                        bottom = min(bottom, box.minY - leading)
                        if let url = paragraph.url { links.append((rect: box, url: url)) }
                    }
                    placed.append(Placed(page: page, frame: frame, picture: nil, rect: rect, links: links))
                    top = bottom
                    start += visible.length
                    if start < text.length { newPage() }
                }
                top -= paragraph.kind == .title ? 6 : 3
            case let .picture(image, links, largest):
                let w = CGFloat(image.width), h = CGFloat(image.height)
                guard w > 0, h > 0 else { continue }
                // Never larger than its pixels, nor than a page.
                let scale = min(1, width / w, largest.width / w, largest.height / h, (pageTop - margin) / h)
                let size = CGSize(width: w * scale, height: h * scale)
                if top - margin < size.height, top < pageTop { newPage() }
                let x = rightToLeft ? pageSize.width - margin - size.width : margin
                let rect = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
                let over = links.map { link in
                    (rect: CGRect(x: rect.minX + link.rect.minX * scale, y: rect.maxY - link.rect.maxY * scale,
                                  width: link.rect.width * scale, height: link.rect.height * scale), url: link.url)
                }
                placed.append(Placed(page: page, frame: nil, picture: image, rect: rect, links: over))
                top = rect.minY - 10
            }
        }
        return placed
    }

    /// Writes the pieces as a PDF of A4 pages, each numbered at its foot
    /// when there are several.
    static func writePDF(_ blocks: [Block], title: String, rightToLeft: Bool, to url: URL) -> Bool {
        let placed = layOut(blocks, rightToLeft: rightToLeft)
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly", kCGPDFContextTitle: title]
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return false }
        let count = (placed.map(\.page).max() ?? 0) + 1
        for page in 0..<count {
            context.beginPDFPage(nil)
            for item in placed where item.page == page {
                if let frame = item.frame {
                    context.saveGState()
                    context.textMatrix = .identity
                    CTFrameDraw(frame, context)
                    context.restoreGState()
                }
                if let picture = item.picture {
                    context.saveGState()
                    context.interpolationQuality = .high
                    context.draw(picture, in: item.rect)
                    // A hairline round it, so a picture with white edges keeps its shape on the page.
                    context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
                    context.setLineWidth(0.5)
                    context.stroke(item.rect.insetBy(dx: -0.25, dy: -0.25))
                    context.restoreGState()
                }
                for link in item.links {
                    context.setURL(link.url as CFURL, for: link.rect)
                }
            }
            if count > 1 { drawNumber(page + 1, of: count, in: context) }
            context.endPDFPage()
        }
        context.closePDF()
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// "2 / 3", in the middle of the page's foot.
    private static func drawNumber(_ number: Int, of count: Int, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.5, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number) / \(count)", attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: (pageSize.width - width) / 2, y: margin / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// A paragraph in its size and weight. Commands and addresses read left
    /// to right in every language, and break anywhere, as they have no
    /// spaces to break at; the rest reads the Mac's way.
    private static func attributed(_ paragraph: Paragraph, rightToLeft: Bool) -> NSAttributedString {
        let font: NSFont
        var color = CGColor(gray: 0.1, alpha: 1)
        switch paragraph.kind {
        case .title: font = .systemFont(ofSize: 18, weight: .semibold)
        case .strong: font = .systemFont(ofSize: 10, weight: .semibold)
        case .code:
            font = .monospacedSystemFont(ofSize: 8.5, weight: .regular)
            color = CGColor(gray: 0.25, alpha: 1)
        case .link:
            // Link blue, as the band has it.
            font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            color = CGColor(srgbRed: 0.04, green: 0.36, blue: 0.82, alpha: 1)
        case .text, .gap: font = .systemFont(ofSize: 10)
        }
        let latin = paragraph.kind == .code || paragraph.kind == .link
        var alignment: CTTextAlignment = rightToLeft ? .right : .left
        var breaking: CTLineBreakMode = latin ? .byCharWrapping : .byWordWrapping
        var direction: CTWritingDirection = rightToLeft && !latin ? .rightToLeft : .leftToRight
        var spacing: CGFloat = paragraph.kind == .text ? 2 : 1
        let style = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &breaking) { b in
                withUnsafeBytes(of: &direction) { d in
                    withUnsafeBytes(of: &spacing) { s in
                        let settings = [
                            CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: b.count, value: b.baseAddress!),
                            CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: d.count, value: d.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: s.count, value: s.baseAddress!),
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ]
        return NSAttributedString(string: paragraph.text, attributes: attributes)
    }

    /// The PDF beside the page: its words, the pages in front with their
    /// addresses as links, a recording's with a picture of it as each was
    /// opened, and a screenshot's stamped picture.
    nonisolated private static func writeDocument(of url: URL, _ paragraphs: [Paragraph], _ seen: Seen, recording: Bool,
                                                  rightToLeft: Bool, title: String, to target: URL) async {
        var picture: TimeStamp.Band?
        if let stamp = seen.stamp, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            picture = TimeStamp.stamped(image, stamp)
        }
        var pictures: [CGImage?] = []
        if recording { pictures = await frames(of: url, at: seen.pages.map { $0.at ?? 0 }) }
        let pieces = blocks(paragraphs, seen: seen, recording: recording, picture: picture, frames: pictures)
        if !writePDF(pieces, title: title, rightToLeft: rightToLeft, to: target) {
            log.error("Could not write the PDF of a proof of time")
        }
    }

    /// The recording as it showed at each moment, small; nil where no
    /// picture could be made. The first few pages have one, the rest their
    /// address alone.
    nonisolated private static func frames(of url: URL, at moments: [Double]) async -> [CGImage?] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var pictures: [CGImage?] = []
        for (index, moment) in moments.enumerated() {
            guard index < 24 else {
                pictures.append(nil)
                continue
            }
            let frame = try? await generator.image(at: CMTime(seconds: moment, preferredTimescale: 600)).image
            pictures.append(frame)
        }
        return pictures
    }
}
