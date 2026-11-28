import AppKit
import CoreText
import CryptoKit
import UniformTypeIdentifiers

/// When a screenshot was taken, as evidence: a band above the picture with
/// the date and time from the PTB's atomic clock, the whole address of the
/// page that was open in the browser, and the screenshot's fingerprint, with
/// a word of the user's own if they want one. The address is a link wherever
/// a link can be followed: in the PDF saved beside the stamped copy, and on
/// the line. It is off until turned on in Settings, and
/// then marks screenshots of the whole screen, or every screenshot.
///
/// The screenshot itself never changes. A stamped copy is saved next to it,
/// and like a covered detail the stamp shows on the photo that hangs and on
/// whatever leaves the line.
enum TimeStamp {
    /// Which screenshots get the stamp.
    enum Scope: String, CaseIterable {
        case wholeScreen
        case all
    }

    /// What is known about one screenshot's moment. Written once, as the
    /// screenshot arrives, and kept with the file.
    struct Record: Codable, Equatable, Sendable {
        /// By the atomic clock when `atomic`, by the Mac's clock otherwise.
        var taken: Date
        var atomic: Bool
        /// The page open in the browser in front, if it was a website, by its
        /// whole address (`StampSite`); one kept from before may hold its
        /// host alone.
        var page: String?
        /// SHA-256 of the screenshot as it arrived.
        var fingerprint: String?
    }

    /// One line of the band.
    struct Row: Equatable, Sendable {
        enum Kind: Sendable { case title, detail, code, link }
        var text: String
        var kind: Kind
        /// Where the row leads, for a page's address.
        var url: URL? = nil
    }

    /// Where a link sits on a stamped picture, in its pixels counted from
    /// the top left, as a PDF page or a view on the line places it.
    struct Link: Equatable, Sendable {
        var rect: CGRect
        var url: URL
    }

    /// A band, or a picture with its band, and where its links are.
    struct Band {
        var image: CGImage
        var links: [Link]
    }

    /// What one stamp says and which way it reads. Made on the main thread,
    /// drawn on any.
    struct Mark: Equatable, Sendable {
        var rows: [Row]
        var rightToLeft: Bool

        /// Changes whenever the stamp would look different.
        var key: String { rows.map(\.text).joined(separator: "|") + "|\(rightToLeft)" }
    }

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "timeStamp") }
        set { UserDefaults.standard.set(newValue, forKey: "timeStamp") }
    }

    /// The user's own words before the date, like a shop's name. Empty
    /// stamps the date and time alone.
    static var text: String {
        get { UserDefaults.standard.string(forKey: "timeStampText") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "timeStampText") }
    }

    static var scope: Scope {
        get { UserDefaults.standard.string(forKey: "timeStampScope").flatMap(Scope.init(rawValue:)) ?? .wholeScreen }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "timeStampScope") }
    }

    /// Screenshots whose atomic time is still on its way. They show
    /// unstamped for that moment rather than with a time that then changes.
    @MainActor private static var pending: Set<String> = []

    /// Whether a screenshot is waiting for the time it is stamped with, so
    /// what leaves for it is not known yet.
    @MainActor static func isPending(_ url: URL) -> Bool {
        pending.contains(url.path)
    }

    /// Called once a screenshot's stamp is ready, so the line can draw it.
    @MainActor static var onReady: ((URL) -> Void)?

    /// The stamp for a screenshot, or nil when it gets none.
    @MainActor
    static func mark(for url: URL) -> Mark? {
        // A photo brought in from elsewhere was not taken now.
        guard isOn, isImage(url), !pending.contains(url.path), scope == .all || isWholeScreen(url),
              !Outside.isBrought(url) else { return nil }
        // A screenshot from before the stamp was turned on has the Mac's
        // clock to go by, and nothing else.
        let known = record(of: url) ?? Record(taken: created(url) ?? Date(), atomic: false)
        return mark(known, text: text, locale: .autoupdatingCurrent, rightToLeft: rightToLeft)
    }

    /// A new screenshot: asks the atomic clock and the browser now, while
    /// the moment is fresh, keeps the answers with the file and saves the
    /// stamped copy next to it.
    @MainActor
    static func arrive(_ url: URL) {
        guard isOn, isImage(url), !pending.contains(url.path), !isStampedCopy(url), record(of: url) == nil,
              scope == .all || isWholeScreen(url) else { return }
        // Only a screenshot just taken: one hung again from the history has
        // no page in front and no moment left to ask about.
        let taken = created(url) ?? Date()
        guard Date().timeIntervalSince(taken) < 60 else { return }
        pending.insert(url.path)
        // The page's whole address, as evidence needs it (`StampSite`).
        let page = ChatButton.pageInFront().flatMap { StampSite.address(of: $0.absoluteString) }
        AtomicTime.offset { offset in
            DispatchQueue.global(qos: .utility).async {
                let record = Record(taken: taken.addingTimeInterval(offset ?? 0), atomic: offset != nil,
                                    page: page, fingerprint: fingerprint(of: url))
                write(record, to: url)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        pending.remove(url.path)
                        if let stamp = mark(for: url) {
                            let name = copyName(for: url)
                            DispatchQueue.global(qos: .utility).async { saveCopy(of: url, named: name, stamp, record) }
                        }
                        onReady?(url)
                    }
                }
            }
        }
    }

    /// The band reads from the trailing side in right-to-left languages.
    static var rightToLeft: Bool {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// Whether a screenshot shows a whole screen: macOS says so for its own,
    /// and a capture whose area is a whole screen is one too.
    @MainActor
    static func isWholeScreen(_ url: URL) -> Bool {
        // A whole page counts too: it is stamped like a whole screen.
        if attribute(fullPageMarker, of: url) != nil { return true }
        if let kind = captureKind(of: url) { return kind == "display" }
        guard let rect = captureRect(of: url) else { return false }
        return isScreen(rect, among: NSScreen.screens.map(\.frame))
    }

    /// An area that is one of the screens, give or take a point.
    static func isScreen(_ rect: CGRect, among screens: [CGRect]) -> Bool {
        screens.contains { screen in
            abs(screen.minX - rect.minX) <= 1 && abs(screen.minY - rect.minY) <= 1
                && abs(screen.width - rect.width) <= 1 && abs(screen.height - rect.height) <= 1
        }
    }

    /// What macOS records about how a screenshot was taken: "display",
    /// "window" or "selection".
    private static func captureKind(of url: URL) -> String? {
        guard let data = attribute("com.apple.metadata:kMDItemScreenCaptureType", of: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? String
    }

    private static func created(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    // MARK: Kept with the file

    private static let recordName = "com.snapfly.stamp"
    /// Marks a screenshot of a whole page (`FullPage`).
    static let fullPageMarker = "com.snapfly.full-page"
    private static let copyMarker = "com.snapfly.stamped-copy"

    static func record(of url: URL) -> Record? {
        attribute(recordName, of: url).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    private static func write(_ record: Record, to url: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        setAttribute(recordName, data, on: url)
    }

    /// A copy Snapfly saved, which is not a new screenshot to hang.
    static func isStampedCopy(_ url: URL) -> Bool {
        attribute(copyMarker, of: url) != nil
    }

    /// The screenshot's SHA-256, so anyone can check the copy was made from
    /// this very file.
    static func fingerprint(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func attribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let read = buffer.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read == size ? buffer : nil
        }
    }

    private static func setAttribute(_ name: String, _ data: Data, on url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
        }
    }

    // MARK: The words

    /// The lines of the band: the user's words and the date and time; where
    /// the time comes from; the page's address, a link; the fingerprint.
    static func mark(_ record: Record, text: String, locale: Locale,
                     timeZone: TimeZone = .autoupdatingCurrent, rightToLeft: Bool) -> Mark {
        var rows = [Row(text: label(text: text, date: record.taken, locale: locale, timeZone: timeZone), kind: .title)]
        rows.append(Row(text: record.atomic ? L("Atomic time from the PTB, Germany") : L("Time from the Mac’s clock"),
                        kind: .detail))
        if let address = record.page.flatMap(StampSite.address(of:)) {
            rows.append(Row(text: String(format: L("Page: %@"), address), kind: .link, url: URL(string: address)))
        }
        if let fingerprint = record.fingerprint {
            rows.append(Row(text: String(format: L("Fingerprint (SHA-256): %@"), fingerprint), kind: .code))
        }
        return Mark(rows: rows, rightToLeft: rightToLeft)
    }

    /// The user's own words, then the date and the time to the second, with
    /// the time zone, in the Mac's own format.
    static func label(text: String, date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .medium
        format.timeStyle = .long
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = format.string(from: date)
        return words.isEmpty ? when : "\(words) · \(when)"
    }

    // MARK: Drawing

    /// The sizes of the band on an image, in its pixels: the text grows with
    /// the image's width, so it reads the same on any screen.
    struct Metrics: Equatable {
        var font: CGFloat
        var padding: CGFloat
        var gap: CGFloat

        init(width: Int) {
            font = max(11, (CGFloat(width) * 0.0095).rounded())
            padding = (font * 0.9).rounded()
            gap = (font * 0.7).rounded()
        }

        func size(of kind: Row.Kind) -> CGFloat {
            switch kind {
            case .title: font
            case .detail, .link: (font * 0.86).rounded()
            case .code: (font * 0.8).rounded()
            }
        }

        /// The room the words have beside the icon, at the icon's largest.
        func room(width: Int) -> CGFloat {
            CGFloat(width) - padding * 2 - font * 3 - gap
        }

        func lineHeight(of kind: Row.Kind) -> CGFloat { (size(of: kind) * 1.4).rounded() }

        /// The band's height for these rows.
        func height(for rows: [Row]) -> CGFloat {
            rows.reduce(padding * 2) { $0 + lineHeight(of: $1.kind) }
        }
    }

    /// The rows as drawn on a band `width` pixels wide: a page's address,
    /// however long, goes on over three lines at most, broken anywhere, as
    /// an address has no spaces to break at.
    static func laidOut(_ mark: Mark, width: Int) -> [Row] {
        let m = Metrics(width: width)
        let room = m.room(width: width)
        guard room > 0 else { return mark.rows }
        return mark.rows.flatMap { row -> [Row] in
            guard row.kind == .link else { return [row] }
            // The face the row is drawn in, so each line fits as drawn.
            let font = NSFont.monospacedSystemFont(ofSize: m.size(of: .link), weight: .regular)
            return wrap(row.text, font: font, room: room, lines: 3).map { Row(text: $0, kind: .link, url: row.url) }
        }
    }

    /// The text in lines no wider than `room`, the last taking the rest.
    static func wrap(_ text: String, font: NSFont, room: CGFloat, lines most: Int) -> [String] {
        let whole = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var lines: [String] = []
        var start = 0
        while start < whole.length {
            if lines.count == most - 1 {
                lines.append(whole.substring(from: start))
                break
            }
            let count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(room))
            guard count > 0 else {
                lines.append(whole.substring(from: start))
                break
            }
            lines.append(whole.substring(with: NSRange(location: start, length: count)))
            start += count
        }
        return lines.isEmpty ? [text] : lines
    }

    /// How tall the band is on a picture `width` pixels wide.
    static func bandHeight(_ mark: Mark, width: Int) -> Int {
        Int(Metrics(width: width).height(for: laidOut(mark, width: width)).rounded(.up))
    }

    /// The band alone, `width` pixels wide: the app icon leading in the
    /// reading direction, then the words, with a hairline along its foot.
    static func band(_ mark: Mark, width: Int) -> Band? {
        let m = Metrics(width: width)
        let rows = laidOut(mark, width: width)
        let height = Int(m.height(for: rows).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Core Graphics counts from the bottom.
        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.fill(full)
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: full.width, height: max(1, (m.font / 16).rounded())))

        let icon = min(full.height - m.padding * 2, m.font * 3)
        let iconX = mark.rightToLeft ? full.width - m.padding - icon : m.padding
        drawIcon(in: CGRect(x: iconX, y: full.maxY - m.padding - icon, width: icon, height: icon), context: context)
        let room = full.width - m.padding * 2 - icon - m.gap

        var links: [Link] = []
        var y = full.maxY - m.padding
        for row in rows {
            let lineHeight = m.lineHeight(of: row.kind)
            y -= lineHeight
            guard room > 0 else { continue }
            let line = textLine(row, size: m.size(of: row.kind), room: room)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let textWidth = min(CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)), room)
            let x = mark.rightToLeft ? iconX - m.gap - textWidth : iconX + icon + m.gap
            context.textPosition = CGPoint(x: x, y: y + (lineHeight - ascent - descent) / 2 + descent)
            CTLineDraw(line, context)
            if let url = row.url {
                links.append(Link(rect: CGRect(x: x, y: full.maxY - y - lineHeight, width: textWidth, height: lineHeight),
                                  url: url))
            }
        }
        guard let image = context.makeImage() else { return nil }
        return Band(image: image, links: links)
    }

    /// The image with the band above it: as wide, and taller by the band.
    static func render(_ image: CGImage, _ mark: Mark) -> CGImage? {
        stamped(image, mark)?.image
    }

    /// The image with the band above it, and where the band's links are on
    /// it: the band is on top, so they are where the band has them.
    static func stamped(_ image: CGImage, _ mark: Mark) -> Band? {
        guard let band = band(mark, width: image.width) else { return nil }
        let width = image.width, height = image.height + band.image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The picture below, the band on top.
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(band.image, in: CGRect(x: 0, y: image.height, width: width, height: band.image.height))
        guard let made = context.makeImage() else { return nil }
        return Band(image: made, links: band.links)
    }

    /// One row in its weight and colour, cut short with an ellipsis where
    /// the image is too narrow for it.
    private static func textLine(_ row: Row, size: CGFloat, room: CGFloat) -> CTLine {
        let font: NSFont
        let gray: CGFloat
        switch row.kind {
        case .title: font = .monospacedDigitSystemFont(ofSize: size, weight: .semibold); gray = 0.08
        case .detail: font = .systemFont(ofSize: size); gray = 0.32
        case .code, .link: font = .monospacedSystemFont(ofSize: size, weight: .regular); gray = 0.4
        }
        // A link in link blue, 6:1 on the band.
        let color = row.kind == .link ? CGColor(srgbRed: 0.04, green: 0.36, blue: 0.82, alpha: 1)
                                      : CGColor(gray: gray, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: row.text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(room), .end, ellipsis) ?? line
    }

    private static func drawIcon(in rect: CGRect, context: CGContext) {
        guard rect.width > 0, let icon = NSImage(named: NSImage.applicationIconName) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: The copy next to the screenshot

    @MainActor
    private static func copyName(for url: URL) -> String {
        String(format: L("%@ with time stamp"), url.deletingPathExtension().lastPathComponent)
    }

    /// Writes the stamped copy next to the screenshot: a PNG that also
    /// carries the stamp's words in its description, and a PDF of the same
    /// picture whose address opens the page when clicked. Each is marked
    /// first and named last, so the folder never shows it as a new
    /// screenshot.
    private static func saveCopy(of url: URL, named name: String, _ mark: Mark, _ record: Record) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let withBand = stamped(image, mark) else { return }
        let folder = url.deletingLastPathComponent()
        // The picture and its PDF share one name, free for both.
        let base = freeName(name, in: folder)
        let words = mark.rows.map(\.text).joined(separator: "\n")

        let png = folder.appendingPathComponent(".snapfly-\(UUID().uuidString).png")
        if let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) {
            let properties: [CFString: Any] = [
                kCGImagePropertyPNGDescription: words,
                kCGImagePropertyPNGSoftware: "Snapfly",
                kCGImagePropertyPNGCreationTime: ISO8601DateFormatter().string(from: record.taken),
            ]
            CGImageDestinationAddImage(destination, withBand.image, [kCGImagePropertyPNGDictionary: properties] as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                place(png, at: folder.appendingPathComponent(base).appendingPathExtension("png"))
            } else {
                try? FileManager.default.removeItem(at: png)
            }
        }

        let pdf = folder.appendingPathComponent(".snapfly-\(UUID().uuidString).pdf")
        if writePDF(withBand, title: base, subject: words, to: pdf) {
            place(pdf, at: folder.appendingPathComponent(base).appendingPathExtension("pdf"))
        } else {
            try? FileManager.default.removeItem(at: pdf)
        }
    }

    /// The name, or the name with a number after it, that neither a picture
    /// nor a PDF in the folder has yet.
    static func freeName(_ name: String, in folder: URL) -> String {
        func taken(_ base: String) -> Bool {
            ["png", "pdf"].contains { ext in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(base).appendingPathExtension(ext).path)
            }
        }
        var base = name
        var n = 2
        while taken(base) {
            base = "\(name) \(n)"
            n += 1
        }
        return base
    }

    /// Marks a copy as Snapfly's own, then gives it its name.
    private static func place(_ hidden: URL, at target: URL) {
        setAttribute(copyMarker, Data([1]), on: hidden)
        if (try? FileManager.default.moveItem(at: hidden, to: target)) == nil {
            try? FileManager.default.removeItem(at: hidden)
        }
    }

    /// The longest side of a page that PDF readers take: 200 inches.
    static let largestPage: CGFloat = 14_400

    /// The stamped picture as a PDF of one page its size, a point for each
    /// pixel, so it stays as sharp as the picture, with a link over each
    /// line of the page's address. A whole page taller than a PDF page can
    /// be is set on a smaller page, with all its pixels still there.
    static func writePDF(_ stamped: Band, title: String, subject: String, to url: URL) -> Bool {
        let width = CGFloat(stamped.image.width), height = CGFloat(stamped.image.height)
        let scale = min(1, largestPage / max(width, height, 1))
        var box = CGRect(x: 0, y: 0, width: width * scale, height: height * scale)
        let info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly", kCGPDFContextTitle: title, kCGPDFContextSubject: subject]
        guard box.width > 0, box.height > 0,
              let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return false }
        context.beginPDFPage(nil)
        context.draw(stamped.image, in: box)
        for link in stamped.links {
            let place = CGRect(x: link.rect.minX * scale, y: link.rect.minY * scale,
                               width: link.rect.width * scale, height: link.rect.height * scale)
            context.setURL(link.url as CFURL, for: pageRect(place, height: box.height))
        }
        context.endPDFPage()
        context.closePDF()
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// A place on a picture, counted from its top left, as a PDF page of the
    /// picture's height counts it: from the bottom left.
    static func pageRect(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
