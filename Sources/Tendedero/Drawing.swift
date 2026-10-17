import AppKit
import CoreText

/// Draw on Photo: arrows, boxes, highlights, numbered steps and words drawn
/// over a photo, and the part of it to keep. They are kept with the photo,
/// like the parts hidden by hand, and drawn on the copy that leaves the line;
/// the file itself stays as it is. A drawing explains a picture and never
/// hides anything in it, so nothing drawn counts as covered.
struct Drawing: Codable, Equatable, Sendable {
    /// In the order they were drawn.
    var marks: [Mark] = []
    /// The part to keep, from 0 to 1 from the bottom left; nil keeps it all.
    var crop: CGRect?

    static let empty = Drawing()

    var isEmpty: Bool { marks.isEmpty && crop == nil }

    struct Mark: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, CaseIterable, Sendable {
            case arrow, box, highlight, step, text
        }

        var id = UUID()
        var kind: Kind
        /// From 0 to 1 from the bottom left: where an arrow starts, the
        /// corner a box was drawn from, or the middle of a step or of words.
        var from: CGPoint
        /// Where an arrow points and a box's other corner; the same as
        /// `from` for a step or words.
        var to: CGPoint
        var ink: Ink
        var size: Size
        /// The words, for words.
        var text = ""

        /// A box's or a highlight's area, from 0 to 1.
        var rect: CGRect {
            CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
        }
    }

    /// The colours to draw in. They are fixed, so a drawing looks the same
    /// on every Mac and in light and dark.
    enum Ink: String, Codable, CaseIterable, Sendable {
        case red, yellow, green, blue, black, white

        var color: CGColor {
            switch self {
            case .red: return CGColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)
            case .yellow: return CGColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
            case .green: return CGColor(srgbRed: 0.204, green: 0.78, blue: 0.349, alpha: 1)
            case .blue: return CGColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)
            case .black: return CGColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)
            case .white: return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            }
        }

        /// Words and numbers on it: dark on the light inks, else white.
        var onColor: CGColor {
            switch self {
            case .yellow, .green, .white: return Ink.black.color
            case .red, .blue, .black: return Ink.white.color
            }
        }

        var title: String {
            switch self {
            case .red: return L("Red")
            case .yellow: return L("Yellow")
            case .green: return L("Green")
            case .blue: return L("Blue")
            case .black: return L("Black")
            case .white: return L("White")
            }
        }
    }

    enum Size: String, Codable, CaseIterable, Sendable {
        case thin, medium, thick

        /// A line's width, as a share of the picture's unit.
        var line: CGFloat {
            switch self {
            case .thin: return 0.0025
            case .medium: return 0.004
            case .thick: return 0.0065
            }
        }

        /// A step's circle across.
        var step: CGFloat {
            switch self {
            case .thin: return 0.02
            case .medium: return 0.028
            case .thick: return 0.038
            }
        }

        /// The words' size.
        var words: CGFloat {
            switch self {
            case .thin: return 0.016
            case .medium: return 0.022
            case .thick: return 0.03
            }
        }

        var title: String {
            switch self {
            case .thin: return L("Thin")
            case .medium: return L("Medium")
            case .thick: return L("Thick")
            }
        }
    }

    /// What a mark's sizes are measured in: about the picture's side, and at
    /// least a small one's, so marks keep their weight on a large screenshot
    /// and a small one alike.
    static func unit(width: CGFloat, height: CGFloat) -> CGFloat {
        max((width * height).squareRoot(), 640)
    }

    /// Every mark and the crop, so the copy is drawn again when either changes.
    var key: String {
        guard !isEmpty else { return "" }
        let drawn = marks.map {
            "\($0.kind.rawValue),\($0.from.x),\($0.from.y),\($0.to.x),\($0.to.y),\($0.ink.rawValue),\($0.size.rawValue),\($0.text)"
        }
        let kept = crop.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? ""
        return drawn.joined(separator: ";") + "/" + kept
    }

    /// The number a step shows: its place among the steps, from 1.
    func number(of mark: Mark) -> Int? {
        guard mark.kind == .step else { return nil }
        return marks.filter { $0.kind == .step }.firstIndex { $0.id == mark.id }.map { $0 + 1 }
    }

    /// Without words left empty, which draw nothing.
    var tidied: Drawing {
        var tidied = self
        tidied.marks.removeAll { $0.kind == .text && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return tidied
    }

    // MARK: Drawing

    /// The picture with the marks drawn over it, cut to the part kept.
    static func render(_ image: CGImage, _ drawing: Drawing) -> CGImage? {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGSize(width: width, height: height)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        draw(drawing.marks, in: context, size: size, unit: unit(width: size.width, height: size.height))
        guard let drawn = context.makeImage() else { return nil }
        guard let crop = drawing.crop, let kept = pixels(of: crop, width: width, height: height) else { return drawn }
        return drawn.cropping(to: kept) ?? drawn
    }

    /// The part kept, in the picture's pixels counted from the top left, as
    /// a picture is cut; nil when it keeps all of it.
    static func pixels(of crop: CGRect, width: Int, height: Int) -> CGRect? {
        let w = CGFloat(width), h = CGFloat(height)
        let minX = (max(0, crop.minX) * w).rounded(), maxX = (min(1, crop.maxX) * w).rounded()
        let minY = ((1 - min(1, crop.maxY)) * h).rounded(), maxY = ((1 - max(0, crop.minY)) * h).rounded()
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width >= 1, rect.height >= 1, rect != CGRect(x: 0, y: 0, width: w, height: h) else { return nil }
        return rect
    }

    /// Draws the marks in a context whose origin is the picture's bottom
    /// left, `size` large: highlights first, so they never dull what is drawn
    /// over them, then the rest in the order drawn.
    /// - Parameters:
    ///   - placeholder: shown dimmed for words not typed yet, as the window
    ///     shows them; the copy leaves them out.
    ///   - highlights: false where they are drawn apart, as the window does.
    static func draw(_ marks: [Mark], in context: CGContext, size: CGSize, unit: CGFloat, placeholder: String? = nil,
                     highlights: Bool = true) {
        var step = 0
        var numbers: [UUID: Int] = [:]
        for mark in marks where mark.kind == .step {
            step += 1
            numbers[mark.id] = step
        }
        for mark in marks where highlights && mark.kind == .highlight {
            drawHighlight(mark, in: context, size: size, unit: unit)
        }
        for mark in marks where mark.kind != .highlight {
            context.saveGState()
            switch mark.kind {
            case .arrow: drawArrow(mark, in: context, size: size, unit: unit)
            case .box: drawBox(mark, in: context, size: size, unit: unit)
            case .step: drawStep(mark, number: numbers[mark.id] ?? 1, in: context, size: size, unit: unit)
            case .text: drawWords(mark, in: context, size: size, unit: unit, placeholder: placeholder)
            case .highlight: break
            }
            context.restoreGState()
        }
    }

    static func point(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    static func rect(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    static func lineWidth(_ mark: Mark, unit: CGFloat) -> CGFloat {
        max(1, unit * mark.size.line)
    }

    /// An arrow that narrows towards where it starts, under a solid head.
    private static func drawArrow(_ mark: Mark, in context: CGContext, size: CGSize, unit: CGFloat) {
        let tail = point(mark.from, in: size), tip = point(mark.to, in: size)
        let width = lineWidth(mark, unit: unit)
        let length = hypot(tip.x - tail.x, tip.y - tail.y)
        guard length > 0.5 else { return }
        let ux = (tip.x - tail.x) / length, uy = (tip.y - tail.y) / length
        let nx = -uy, ny = ux
        let head = min(width * 4.5, length * 0.6)
        let spread = head * 0.6
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        // The shaft reaches a little into the head, so no seam shows.
        let shaftEnd = CGPoint(x: base.x + ux * head * 0.3, y: base.y + uy * head * 0.3)
        let narrow = width * 0.3, wide = width * 0.55

        context.setFillColor(mark.ink.color)
        let shaft = CGMutablePath()
        shaft.move(to: CGPoint(x: tail.x + nx * narrow, y: tail.y + ny * narrow))
        shaft.addLine(to: CGPoint(x: shaftEnd.x + nx * wide, y: shaftEnd.y + ny * wide))
        shaft.addLine(to: CGPoint(x: shaftEnd.x - nx * wide, y: shaftEnd.y - ny * wide))
        shaft.addLine(to: CGPoint(x: tail.x - nx * narrow, y: tail.y - ny * narrow))
        shaft.closeSubpath()
        shaft.addEllipse(in: CGRect(x: tail.x - narrow, y: tail.y - narrow, width: narrow * 2, height: narrow * 2))
        context.addPath(shaft)
        context.fillPath(using: .winding)

        let tipPath = CGMutablePath()
        tipPath.move(to: tip)
        tipPath.addLine(to: CGPoint(x: base.x + nx * spread, y: base.y + ny * spread))
        tipPath.addLine(to: CGPoint(x: base.x - nx * spread, y: base.y - ny * spread))
        tipPath.closeSubpath()
        // Softened corners, the way a pen leaves them.
        context.setStrokeColor(mark.ink.color)
        context.setLineWidth(width * 0.4)
        context.setLineJoin(.round)
        context.addPath(tipPath)
        context.drawPath(using: .fillStroke)
    }

    private static func drawBox(_ mark: Mark, in context: CGContext, size: CGSize, unit: CGFloat) {
        let width = lineWidth(mark, unit: unit)
        let box = rect(mark.rect, in: size)
        guard box.width > 0 || box.height > 0 else { return }
        let radius = min(width * 1.5, box.width / 2, box.height / 2)
        context.setStrokeColor(mark.ink.color)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
    }

    /// A highlighter's stroke: the ink multiplied in, so the words under it
    /// stay as dark as they were. White, which multiplies to nothing, lightens.
    private static func drawHighlight(_ mark: Mark, in context: CGContext, size: CGSize, unit: CGFloat) {
        let box = rect(mark.rect, in: size)
        guard box.width > 0, box.height > 0 else { return }
        let radius = highlightRadius(mark, box: box, unit: unit)
        let fill = highlightFill(mark.ink)
        context.saveGState()
        if fill.multiplies { context.setBlendMode(.multiply) }
        context.setFillColor(fill.color)
        context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    static func highlightRadius(_ mark: Mark, box: CGRect, unit: CGFloat) -> CGFloat {
        min(lineWidth(mark, unit: unit) * 0.6, box.width / 2, box.height / 2)
    }

    /// How a highlight's ink goes on: multiplied in, or for white laid over.
    static func highlightFill(_ ink: Ink) -> (color: CGColor, multiplies: Bool) {
        ink == .white
            ? (ink.color.copy(alpha: 0.5) ?? ink.color, false)
            : (ink.color.copy(alpha: 0.42) ?? ink.color, true)
    }

    /// Where a step's circle lies.
    static func stepCircle(_ mark: Mark, size: CGSize, unit: CGFloat) -> CGRect {
        let across = max(12, unit * mark.size.step)
        let middle = point(mark.from, in: size)
        return CGRect(x: middle.x - across / 2, y: middle.y - across / 2, width: across, height: across)
    }

    /// A numbered circle with a light rim, so it stands out on any picture.
    private static func drawStep(_ mark: Mark, number: Int, in context: CGContext, size: CGSize, unit: CGFloat) {
        let circle = stepCircle(mark, size: size, unit: unit)
        let rim = circle.width * 0.08
        context.setFillColor(mark.ink == .white ? Ink.black.color : Ink.white.color)
        context.fillEllipse(in: circle)
        context.setFillColor(mark.ink.color)
        context.fillEllipse(in: circle.insetBy(dx: rim, dy: rim))

        let digits = "\(number)"
        let fontSize = circle.width * (digits.count > 2 ? 0.4 : 0.52)
        let bold = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let font = bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? bold
        let line = textLine(digits, font: font, color: mark.ink.onColor)
        // Centred on the digits' own outline, not the line's.
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: circle.midX - bounds.midX, y: circle.midY - bounds.midY)
        CTLineDraw(line, context)
    }

    /// Words on a rounded label of the ink, centred on the mark.
    struct Label {
        var line: CTLine
        var frame: CGRect
        var baseline: CGPoint
    }

    static func label(_ mark: Mark, size: CGSize, unit: CGFloat, placeholder: String? = nil) -> Label? {
        let typed = mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : mark.text
        guard let text = typed ?? placeholder else { return nil }
        let fontSize = max(9, unit * mark.size.words)
        let color = typed == nil ? mark.ink.onColor.copy(alpha: 0.55) ?? mark.ink.onColor : mark.ink.onColor
        let line = textLine(text, font: .systemFont(ofSize: fontSize, weight: .semibold), color: color)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let across = fontSize * 0.45, up = fontSize * 0.22
        let middle = point(mark.from, in: size)
        let frame = CGRect(x: middle.x - width / 2 - across, y: middle.y - (ascent + descent) / 2 - up,
                           width: width + across * 2, height: ascent + descent + up * 2)
        return Label(line: line, frame: frame, baseline: CGPoint(x: frame.minX + across, y: frame.minY + up + descent))
    }

    private static func drawWords(_ mark: Mark, in context: CGContext, size: CGSize, unit: CGFloat, placeholder: String?) {
        guard let placed = Self.label(mark, size: size, unit: unit, placeholder: placeholder) else { return }
        let radius = min(placed.frame.height * 0.3, placed.frame.width / 2)
        context.setFillColor(mark.ink.color)
        context.addPath(CGPath(roundedRect: placed.frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        if mark.ink == .white {
            // A hairline keeps a white label apart from a white page.
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            context.setLineWidth(max(1, placed.frame.height / 40))
            context.addPath(CGPath(roundedRect: placed.frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        }
        context.textMatrix = .identity
        context.textPosition = placed.baseline
        CTLineDraw(placed.line, context)
    }

    private static func textLine(_ text: String, font: NSFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    // MARK: Finding a mark

    /// Where a mark lies, for choosing it and for its outline when chosen.
    static func frame(of mark: Mark, size: CGSize, unit: CGFloat, placeholder: String? = nil) -> CGRect {
        switch mark.kind {
        case .arrow:
            let a = point(mark.from, in: size), b = point(mark.to, in: size)
            let room = lineWidth(mark, unit: unit) * 2.5
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                .insetBy(dx: -room, dy: -room)
        case .box, .highlight:
            return rect(mark.rect, in: size)
        case .step:
            return stepCircle(mark, size: size, unit: unit)
        case .text:
            return label(mark, size: size, unit: unit, placeholder: placeholder)?.frame
                ?? CGRect(origin: point(mark.from, in: size), size: .zero)
        }
    }

    /// Whether a point, in the same space, falls on a mark: on an arrow's
    /// line or a box's edge, or anywhere on the rest.
    static func hits(_ mark: Mark, at p: CGPoint, size: CGSize, unit: CGFloat, slack: CGFloat,
                     placeholder: String? = nil) -> Bool {
        let width = lineWidth(mark, unit: unit)
        switch mark.kind {
        case .arrow:
            return distance(from: p, to: point(mark.from, in: size), point(mark.to, in: size)) <= width + slack
        case .box:
            let box = rect(mark.rect, in: size)
            let outer = box.insetBy(dx: -(width / 2 + slack), dy: -(width / 2 + slack))
            let inner = box.insetBy(dx: width / 2 + slack, dy: width / 2 + slack)
            return outer.contains(p) && (inner.isNull || !inner.contains(p))
        case .highlight, .text:
            return frame(of: mark, size: size, unit: unit, placeholder: placeholder).insetBy(dx: -slack, dy: -slack).contains(p)
        case .step:
            let circle = stepCircle(mark, size: size, unit: unit)
            return hypot(p.x - circle.midX, p.y - circle.midY) <= circle.width / 2 + slack
        }
    }

    /// The mark on top at a point: the last drawn, with highlights under the rest.
    func mark(at p: CGPoint, size: CGSize, unit: CGFloat, slack: CGFloat, placeholder: String? = nil) -> Mark? {
        let order = marks.filter { $0.kind == .highlight } + marks.filter { $0.kind != .highlight }
        return order.last { Self.hits($0, at: p, size: size, unit: unit, slack: slack, placeholder: placeholder) }
    }

    static func distance(from p: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// A mark moved by a distance from 0 to 1, kept on the picture.
    static func moved(_ mark: Mark, by delta: CGVector) -> Mark {
        let minX = min(mark.from.x, mark.to.x), maxX = max(mark.from.x, mark.to.x)
        let minY = min(mark.from.y, mark.to.y), maxY = max(mark.from.y, mark.to.y)
        let dx = max(-minX, min(1 - maxX, delta.dx)), dy = max(-minY, min(1 - maxY, delta.dy))
        var moved = mark
        moved.from = CGPoint(x: mark.from.x + dx, y: mark.from.y + dy)
        moved.to = CGPoint(x: mark.to.x + dx, y: mark.to.y + dy)
        return moved
    }

    /// The handles a chosen mark is reshaped by, from 0 to 1: an arrow's
    /// two ends, a box's four corners; none for a step or words.
    static func handles(of mark: Mark) -> [CGPoint] {
        switch mark.kind {
        case .arrow: return [mark.from, mark.to]
        case .box, .highlight: return corners(of: mark.rect)
        case .step, .text: return []
        }
    }

    static func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// A mark with one handle dragged to a point.
    static func reshaped(_ mark: Mark, handle: Int, to p: CGPoint) -> Mark {
        var reshaped = mark
        let kept = CGPoint(x: max(0, min(1, p.x)), y: max(0, min(1, p.y)))
        switch mark.kind {
        case .arrow:
            if handle == 0 { reshaped.from = kept } else { reshaped.to = kept }
        case .box, .highlight:
            reshaped.from = Self.corners(of: mark.rect)[(handle + 2) % 4]
            reshaped.to = kept
        case .step, .text:
            break
        }
        return reshaped
    }
}

/// The drawings on the photos on the line, kept under each file's path.
enum Drawings {
    private static let key = "drawings"

    static func saved(_ url: URL) -> Drawing {
        guard let data = UserDefaults.standard.dictionary(forKey: key)?[url.path] as? Data,
              let drawing = try? JSONDecoder().decode(Drawing.self, from: data) else { return .empty }
        return drawing
    }

    static func set(_ drawing: Drawing, for url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[url.path] = drawing.isEmpty ? nil : try? JSONEncoder().encode(drawing)
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Forgets the drawings on photos that have left the line.
    static func keep(only paths: Set<String>) {
        guard let all = UserDefaults.standard.dictionary(forKey: key),
              all.keys.contains(where: { !paths.contains($0) }) else { return }
        UserDefaults.standard.set(all.filter { paths.contains($0.key) }, forKey: key)
    }
}
