import AppKit
import UniformTypeIdentifiers

/// Send with Shop Header, from a photo's menu: the photo as it leaves the
/// line, under a band with the shop's name and logo, the order and the day,
/// so what a customer gets is clearly from the shop and still a screenshot.
/// The name and the logo are set in Settings › Line.
enum ShopHeader {
    static var name: String {
        get { UserDefaults.standard.string(forKey: "shopName") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "shopName") }
    }

    /// The logo, kept as a PNG of its own in Snapfly's Application Support
    /// folder, inside the sandbox for the App Store edition.
    static let logoFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snapfly", isDirectory: true)
        .appendingPathComponent("Shop logo.png")

    static var hasLogo: Bool { FileManager.default.fileExists(atPath: logoFile.path) }

    /// Whether there is anything to put in the band.
    static var isSet: Bool { !name.isEmpty || hasLogo }

    /// Asks for a picture and keeps it as the logo. Returns whether one was
    /// kept.
    @MainActor @discardableResult
    static func chooseLogo() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.message = L("Choose your shop's logo.")
        panel.prompt = L("Choose")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return keep(logo: url, at: logoFile)
    }

    /// A picture kept as a logo, at most 512 pixels across, upright.
    static func keep(logo url: URL, at target: URL) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return false }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    static func removeLogo() {
        try? FileManager.default.removeItem(at: logoFile)
    }

    // MARK: The band

    /// "Order 1024 · 17 October 2026", or the day alone.
    static func detail(order: String?, day: Date, locale: Locale = .autoupdatingCurrent,
                       timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .long
        let date = format.string(from: day)
        guard let order, !order.isEmpty else { return date }
        return L("Order") + " " + order + " · " + date
    }

    /// Sizes that grow with the picture, as the time stamp's do, so the band
    /// reads the same on any screenshot.
    struct Metrics: Equatable {
        var font: CGFloat
        var padding: CGFloat
        var gap: CGFloat

        init(width: Int) {
            font = max(13, (CGFloat(width) * 0.0125).rounded())
            padding = (font * 0.8).rounded()
            gap = (font * 0.7).rounded()
        }

        var nameSize: CGFloat { (font * 1.15).rounded() }
        var detailSize: CGFloat { (font * 0.86).rounded() }
        var nameHeight: CGFloat { (nameSize * 1.3).rounded() }
        var detailHeight: CGFloat { (detailSize * 1.4).rounded() }
        /// Room for the name over the detail, with padding round them.
        var height: CGFloat { padding * 2 + nameHeight + detailHeight }
    }

    /// The picture under the band: as wide, and taller by the band. The logo
    /// leads in the reading direction, then the name over the order and day.
    static func render(_ picture: CGImage, name: String, logo: CGImage?, detail: String,
                       rightToLeft: Bool) -> CGImage? {
        let m = Metrics(width: picture.width)
        let band = Int(m.height.rounded(.up))
        let width = picture.width, height = picture.height + band
        let space = picture.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Core Graphics counts from the bottom: the picture below, the band on top.
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        let top = CGRect(x: 0, y: CGFloat(picture.height), width: CGFloat(width), height: CGFloat(band))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(top)
        context.setFillColor(CGColor(gray: 0.86, alpha: 1))
        context.fill(CGRect(x: 0, y: top.minY, width: top.width, height: max(1, (m.font / 16).rounded())))

        var leading = m.padding
        var room = CGFloat(width) - m.padding * 2
        if let logo {
            let side = top.height - m.padding * 2
            let x = rightToLeft ? CGFloat(width) - m.padding - side : m.padding
            let square = CGRect(x: x, y: top.minY + m.padding, width: side, height: side)
            context.saveGState()
            context.addPath(CGPath(roundedRect: square, cornerWidth: side * 0.22, cornerHeight: side * 0.22, transform: nil))
            context.clip()
            // Filled and centred: a wide logo shows its middle.
            let scale = max(side / CGFloat(logo.width), side / CGFloat(logo.height))
            let size = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
            context.interpolationQuality = .high
            context.draw(logo, in: CGRect(x: square.midX - size.width / 2, y: square.midY - size.height / 2,
                                          width: size.width, height: size.height))
            context.restoreGState()
            leading += side + m.gap
            room -= side + m.gap
        }
        guard room > 0 else { return context.makeImage() }

        // The words, as one block in the band's middle.
        let rows = [(name, m.nameSize, NSFont.Weight.semibold, CGFloat(0.08), m.nameHeight),
                    (detail, m.detailSize, NSFont.Weight.regular, CGFloat(0.36), m.detailHeight)]
            .filter { !$0.0.isEmpty }
        var y = top.midY + rows.reduce(0) { $0 + $1.4 } / 2
        for (text, size, weight, gray, lineHeight) in rows {
            y -= lineHeight
            let line = textLine(text, size: size, weight: weight, gray: gray, room: room)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let x = rightToLeft ? CGFloat(width) - leading - textWidth : leading
            context.textPosition = CGPoint(x: x, y: y + (lineHeight - ascent - descent) / 2 + descent)
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }

    /// One line in its weight and grey, cut short with an ellipsis where the
    /// picture is too narrow for it.
    private static func textLine(_ text: String, size: CGFloat, weight: NSFont.Weight, gray: CGFloat,
                                 room: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): NSFont.systemFont(ofSize: size, weight: weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(room), .end, ellipsis) ?? line
    }

    /// The copy that leaves, under the band, as a PNG named as that copy is.
    /// Nil when the picture cannot be read.
    static func copy(of url: URL, name: String, logo: URL?, order: String?, day: Date, rightToLeft: Bool) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = Cover.upright(source) else { return nil }
        let mark = logo.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        guard let drawn = render(picture, name: name, logo: mark, detail: detail(order: order, day: day),
                                 rightToLeft: rightToLeft),
              let target = Cover.newCopy(of: url, ext: "png"),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, drawn, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return target
    }
}
