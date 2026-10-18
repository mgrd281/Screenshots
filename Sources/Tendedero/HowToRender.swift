import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A guide drawn as it leaves: each step's screenshot with its private
/// details covered, cut to the part around its click and marked in red ink,
/// under its number and its sentence. As A4 pages for a PDF, or one tall
/// picture for a chat. The colours are fixed, like Draw on Photo's inks, so
/// it reads the same wherever it is opened.
enum HowToRender {
    // MARK: A step's picture

    /// The step's screenshot with the details chosen under Privacy and the
    /// owner's own rules covered, written once beside it. Off the main
    /// thread: covering reads the picture.
    static func prepare(_ step: HowToStep, in folder: URL, chosen: Set<PrivateDetail>) -> Bool {
        let covered = folder.appendingPathComponent(HowToStore.coveredName(of: step))
        if FileManager.default.fileExists(atPath: covered.path) { return true }
        guard let image = load(folder.appendingPathComponent(step.file)),
              let made = Finder.covered(image, chosen) else { return false }
        return Capture.write(made.image, to: covered)
    }

    /// Whether a step's covered screenshot is ready.
    static func isPrepared(_ step: HowToStep, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(HowToStore.coveredName(of: step)).path)
    }

    /// What a step shows: its covered screenshot, cut to its part and
    /// marked. Nil until it is covered, so nothing uncovered ever leaves.
    /// - Parameter maxPixels: the longer side at most, for a preview or a page.
    static func picture(_ step: HowToStep, in folder: URL, maxPixels: CGFloat? = nil) -> CGImage? {
        guard let image = load(folder.appendingPathComponent(HowToStore.coveredName(of: step))),
              step.width > 0, step.height > 0 else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let part = HowToFrame.focus(of: step)
        let cut = CGRect(x: (part.minX * width).rounded(), y: (part.minY * height).rounded(),
                         width: (part.width * width).rounded(), height: (part.height * height).rounded())
        guard cut.width >= 1, cut.height >= 1, let piece = image.cropping(to: cut) else { return nil }
        let scale = min(1, (maxPixels ?? .greatestFiniteMagnitude) / max(cut.width, cut.height))
        let w = max(1, Int((cut.width * scale).rounded())), h = max(1, Int((cut.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        // The mark is measured in the step's pixels from the part's top left;
        // the context counts from the bottom.
        let k = scale * width / CGFloat(step.width)
        let unit = max((width * height).squareRoot(), 640) * scale
        let line = max(2, unit * Drawing.Size.medium.line)
        let red = Drawing.Ink.red.color
        context.setStrokeColor(red)
        context.setLineWidth(line)
        context.setLineJoin(.round)
        switch HowToFrame.mark(of: step, in: part) {
        case let .box(box):
            let rect = CGRect(x: box.minX * k, y: CGFloat(h) - box.maxY * k, width: box.width * k, height: box.height * k)
            let radius = min(line * 1.5, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        case let .ring(center, radius):
            let middle = CGPoint(x: center.x * k, y: CGFloat(h) - center.y * k)
            let r = radius * k
            let circle = CGRect(x: middle.x - r, y: middle.y - r, width: 2 * r, height: 2 * r)
            context.setFillColor(red.copy(alpha: 0.18) ?? red)
            context.fillEllipse(in: circle)
            context.strokeEllipse(in: circle)
        }
        return context.makeImage()
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: The document

    /// The look of what leaves, in points.
    enum Look {
        static let page = CGSize(width: 595, height: 842)
        static let pageMargin = CGSize(width: 48, height: 52)
        static let imageWidth: CGFloat = 600
        static let imageMargin: CGFloat = 32
        static let badge: CGFloat = 22
        /// From the number to the sentence beside it.
        static let indent: CGFloat = 32
        static let underText: CGFloat = 10
        static let betweenSteps: CGFloat = 28
        static let underHeader: CGFloat = 24
        static let corner: CGFloat = 8
        static let ink = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)
        static let quiet = CGColor(gray: 0.42, alpha: 1)
        static let edge = CGColor(gray: 0.84, alpha: 1)
    }

    /// One step on paper: its number, its sentence and its picture.
    private struct Block {
        let number: Int
        let text: NSAttributedString
        let textHeight: CGFloat
        let picture: CGImage?
        let pictureSize: CGSize

        var height: CGFloat {
            max(Look.badge, textHeight) + (picture == nil ? 0 : Look.underText + pictureSize.height)
        }
    }

    private struct Header {
        let title: NSAttributedString
        let titleHeight: CGFloat
        let note: NSAttributedString
        let noteHeight: CGFloat

        var height: CGFloat { titleHeight + 4 + noteHeight + Look.underHeader }
    }

    /// The name a guide goes by: its title, or "Guide" with the day.
    static func name(of guide: HowToGuide) -> String {
        let title = guide.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(L("Guide")) \(formatter.string(from: guide.created))"
    }

    private static func paragraph(_ size: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.baseWritingDirection = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = size * 0.15
        return style
    }

    private static func words(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color) ?? .black,
            .paragraphStyle: paragraph(size),
        ])
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    private static func heading(_ guide: HowToGuide, width: CGFloat) -> Header {
        let trimmed = guide.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = words(trimmed.isEmpty ? L("Guide") : trimmed, size: 20, weight: .semibold, color: Look.ink)
        let day = DateFormatter.localizedString(from: guide.created, dateStyle: .long, timeStyle: .none)
        let count = guide.steps.count == 1 ? L("1 step") : String(format: L("%d steps"), guide.steps.count)
        let note = words("\(count) · \(day)", size: 11, weight: .regular, color: Look.quiet)
        return Header(title: title, titleHeight: measure(title, width: width),
                      note: note, noteHeight: measure(note, width: width))
    }

    /// Every step on paper; nil while one is not covered yet.
    /// - Parameter compress: as JPEG, which a PDF keeps as it is, so a guide
    ///   is a few hundred kilobytes a page instead of megabytes.
    private static func layOut(_ guide: HowToGuide, in folder: URL, width: CGFloat, tallest: CGFloat,
                               pixels: CGFloat, compress: Bool) -> [Block]? {
        var laid: [Block] = []
        for (index, step) in guide.steps.enumerated() {
            let text = words(step.text.trimmingCharacters(in: .whitespacesAndNewlines), size: 13, weight: .regular,
                             color: Look.ink)
            guard let shown = picture(step, in: folder, maxPixels: pixels) else { return nil }
            var size = CGSize(width: width, height: width * CGFloat(shown.height) / CGFloat(max(shown.width, 1)))
            if size.height > tallest {
                size = CGSize(width: size.width * tallest / size.height, height: tallest)
            }
            laid.append(Block(number: index + 1, text: text, textHeight: measure(text, width: width - Look.indent),
                              picture: compress ? compressed(shown) ?? shown : shown, pictureSize: size))
        }
        return laid
    }

    private static func compressed(_ image: CGImage) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Draws in a context flipped to count down from the top, as the words do.
    private static func draw(_ header: Header, at top: CGFloat, left: CGFloat, width: CGFloat) {
        header.title.draw(with: CGRect(x: left, y: top, width: width, height: header.titleHeight),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        header.note.draw(with: CGRect(x: left, y: top + header.titleHeight + 4, width: width, height: header.noteHeight),
                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func draw(_ block: Block, at top: CGFloat, left: CGFloat, width: CGFloat, fit: CGFloat,
                             rightToLeft: Bool, in context: CGContext) {
        // The number: white on ink, on the reading side.
        let badge = CGRect(x: rightToLeft ? left + width - Look.badge : left, y: top, width: Look.badge, height: Look.badge)
        context.setFillColor(Look.ink)
        context.fillEllipse(in: badge)
        let digits = NSAttributedString(string: "\(block.number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let digitsSize = digits.size()
        digits.draw(at: CGPoint(x: badge.midX - digitsSize.width / 2, y: badge.midY - digitsSize.height / 2))

        let textLeft = rightToLeft ? left : left + Look.indent
        let lineUp = max(0, (Look.badge - 17) / 2)
        block.text.draw(with: CGRect(x: textLeft, y: top + lineUp, width: width - Look.indent, height: block.textHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        guard let picture = block.picture else { return }
        var size = block.pictureSize
        if size.height > fit {
            size = CGSize(width: size.width * fit / size.height, height: fit)
        }
        let y = top + max(Look.badge, block.textHeight) + Look.underText
        let x = rightToLeft ? left + width - size.width : left
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        let shape = CGPath(roundedRect: frame, cornerWidth: Look.corner, cornerHeight: Look.corner, transform: nil)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        // Pictures are drawn upright in the flipped context.
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()
        context.setStrokeColor(Look.edge)
        context.setLineWidth(0.75)
        context.addPath(shape)
        context.strokePath()
    }

    /// The guide as a PDF of A4 pages, page numbers at the foot. Nil until
    /// every step is covered.
    static func pdf(_ guide: HowToGuide, in folder: URL, to url: URL, rightToLeft: Bool) -> Bool {
        let page = Look.page, margin = Look.pageMargin
        let width = page.width - 2 * margin.width
        let foot: CGFloat = 24
        let room = page.height - 2 * margin.height - foot
        let header = heading(guide, width: width)
        guard let blocks = layOut(guide, in: folder, width: width, tallest: room * 0.62, pixels: 1600, compress: true)
        else { return false }
        let pages = HowToPages.paginate(heights: blocks.map(\.height), firstRoom: room - header.height, room: room,
                                        gap: Look.betweenSteps)
        var box = CGRect(origin: .zero, size: page)
        let info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly", kCGPDFContextTitle: name(of: guide)]
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return false }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        for (number, steps) in pages.enumerated() {
            context.beginPage(mediaBox: &box)
            context.saveGState()
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            var top = margin.height
            if number == 0 {
                draw(header, at: top, left: margin.width, width: width)
                top += header.height
            }
            for index in steps {
                let block = blocks[index]
                // Alone and too tall, a step is drawn smaller to fit.
                let fit = page.height - margin.height - foot - top - max(Look.badge, block.textHeight) - Look.underText
                draw(block, at: top, left: margin.width, width: width, fit: max(80, fit), rightToLeft: rightToLeft,
                     in: context)
                top += block.height + Look.betweenSteps
            }
            if pages.count > 1 {
                let numbering = words("\(number + 1) / \(pages.count)", size: 11, weight: .regular, color: Look.quiet)
                let size = numbering.size()
                numbering.draw(at: CGPoint(x: (page.width - size.width) / 2, y: page.height - margin.height + 8))
            }
            context.restoreGState()
            context.endPage()
        }
        context.closePDF()
        return true
    }

    /// The guide as one tall picture, 600 points wide at twice the
    /// resolution, for a chat that shows pictures inline. Nil until every
    /// step is covered.
    static func image(_ guide: HowToGuide, in folder: URL, rightToLeft: Bool) -> CGImage? {
        let margin = Look.imageMargin
        let width = Look.imageWidth - 2 * margin
        let header = heading(guide, width: width)
        guard let blocks = layOut(guide, in: folder, width: width, tallest: 520, pixels: 1400, compress: false)
        else { return nil }
        let all = blocks.map(\.height).reduce(0, +) + Look.betweenSteps * CGFloat(max(0, blocks.count - 1))
        let height = ceil(2 * margin + header.height + all)
        // Twice as sharp, unless that makes it larger than a picture can be.
        let scale = min(2, 30_000 / height)
        let pixels = CGSize(width: (Look.imageWidth * scale).rounded(), height: (height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixels))
        context.translateBy(x: 0, y: pixels.height)
        context.scaleBy(x: scale, y: -scale)
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        var top = margin
        draw(header, at: top, left: margin, width: width)
        top += header.height
        for block in blocks {
            draw(block, at: top, left: margin, width: width, fit: block.pictureSize.height, rightToLeft: rightToLeft,
                 in: context)
            top += block.height + Look.betweenSteps
        }
        return context.makeImage()
    }

    /// The picture as PNG, for the pasteboard or a file.
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
