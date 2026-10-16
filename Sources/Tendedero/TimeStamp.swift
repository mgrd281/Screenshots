import AppKit
import CoreText

/// The date and time a screenshot was taken, with a word of the user's own
/// if they want one, stamped in its bottom corner. It is off until turned
/// on in Settings, and then marks screenshots of the whole screen, or every
/// screenshot. Like a covered detail, it is drawn on what leaves the line
/// and on the photo that hangs there; the file itself never changes.
enum TimeStamp {
    /// Which screenshots get the stamp.
    enum Scope: String, CaseIterable {
        case wholeScreen
        case all
    }

    /// What one stamp says and which corner it sits in. Made on the main
    /// thread, drawn on any.
    struct Mark: Equatable, Sendable {
        var label: String
        var rightToLeft: Bool

        /// Changes whenever the stamp would look different.
        var key: String { "\(label)|\(rightToLeft)" }
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

    /// The stamp for a screenshot, or nil when it gets none.
    @MainActor
    static func mark(for url: URL) -> Mark? {
        guard isOn, isImage(url), scope == .all || isWholeScreen(url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let taken = values?.creationDate ?? values?.contentModificationDate ?? Date()
        return Mark(label: label(text: text, date: taken, locale: .autoupdatingCurrent),
                    rightToLeft: rightToLeft)
    }

    /// The stamp goes in the trailing corner, away from the lock the line
    /// shows in the leading one.
    static var rightToLeft: Bool {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// Whether a screenshot shows a whole screen: macOS says so for its own,
    /// and a capture whose area is a whole screen is one too.
    @MainActor
    static func isWholeScreen(_ url: URL) -> Bool {
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
        let name = "com.apple.metadata:kMDItemScreenCaptureType"
        let data: Data? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let read = buffer.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            return read == size ? buffer : nil
        }
        guard let data else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? String
    }

    // MARK: The words

    /// The words on the stamp: the user's own, then the date and time in the
    /// Mac's own format.
    static func label(text: String, date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .medium
        format.timeStyle = .short
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = format.string(from: date)
        return words.isEmpty ? when : "\(words) · \(when)"
    }

    // MARK: Drawing

    /// The sizes of a stamp on an image, in its pixels: the text grows with
    /// the image, so it reads the same on any screen.
    struct Metrics: Equatable {
        var font: CGFloat
        var padding: CGFloat
        var height: CGFloat
        var margin: CGFloat
        var gap: CGFloat

        init(font: CGFloat) {
            self.font = font
            padding = (font * 0.8).rounded()
            height = (font * 2.1).rounded()
            margin = (font * 1.2).rounded()
            gap = (font * 0.45).rounded()
        }
    }

    static func metrics(width: Int, height: Int) -> Metrics {
        Metrics(font: max(12, (CGFloat(min(width, height)) * 0.016).rounded()))
    }

    /// Where the capsule goes: in the bottom trailing corner, inside the
    /// image. Nil when the image is too small to hold it.
    static func capsule(width: Int, height: Int, content: CGFloat, metrics m: Metrics, rightToLeft: Bool) -> CGRect? {
        let w = content + m.padding * 2
        guard w + m.margin * 2 <= CGFloat(width), m.height + m.margin * 2 <= CGFloat(height) else { return nil }
        let x = rightToLeft ? m.margin : CGFloat(width) - m.margin - w
        // Core Graphics counts from the bottom.
        return CGRect(x: x, y: m.margin, width: w, height: m.height)
    }

    /// Draws the stamp on an image the size of the context: a dark capsule,
    /// like the lock on a covered photo, with a clock and the words in white.
    static func draw(_ mark: Mark, in context: CGContext, width: Int, height: Int) {
        var m = metrics(width: width, height: height)
        var line = textLine(mark.label, size: m.font)
        var content: CGFloat = m.font + m.gap + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // A small image takes a smaller stamp, rather than none.
        let room = CGFloat(width) - (m.padding + m.margin) * 2
        if content > room, room > 0 {
            m = Metrics(font: max(8, (m.font * room / content).rounded(.down)))
            line = textLine(mark.label, size: m.font)
            content = m.font + m.gap + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        guard let box = capsule(width: width, height: height, content: content, metrics: m,
                                rightToLeft: mark.rightToLeft) else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: box, cornerWidth: box.height / 2, cornerHeight: box.height / 2,
                               transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fillPath()

        // The clock leads in the reading direction, then the words.
        let iconX = mark.rightToLeft ? box.maxX - m.padding - m.font : box.minX + m.padding
        let icon = CGRect(x: iconX, y: box.midY - m.font / 2, width: m.font, height: m.font)
        drawClock(in: icon, context: context)

        var ascent: CGFloat = 0, descent: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let textX = mark.rightToLeft ? icon.minX - m.gap - textWidth : icon.maxX + m.gap
        context.textPosition = CGPoint(x: textX, y: box.midY - (ascent - descent) / 2)
        CTLineDraw(line, context)
    }

    private static func textLine(_ text: String, size: CGFloat) -> CTLine {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let words = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        return CTLineCreateWithAttributedString(words)
    }

    private static func drawClock(in rect: CGRect, context: CGContext) {
        let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        // Kept to its own proportions, centred in the square.
        let size = symbol.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawn = CGRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                           width: size.width * scale, height: size.height * scale)
        symbol.draw(in: drawn)
        NSGraphicsContext.restoreGraphicsState()
    }
}
