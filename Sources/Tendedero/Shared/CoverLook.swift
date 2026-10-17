import CoreGraphics
import CoreText
import Foundation

/// How a covered place looks in what leaves the line, chosen under Privacy
/// in Settings. Every look hides for good: blur, pixels, dots and erased are
/// made from the colors around a place, never from what is in it, so
/// nothing covered can be brought back from a copy, as it can be from a real
/// blur or pixelation of text.
enum CoverStyle: String, CaseIterable, Identifiable {
    /// Opaque ink with softened corners, as covers have always been.
    case ink
    /// The ink, with what it hides named on it, like "Name".
    case label
    /// A soft blur, like words seen through frosted glass.
    case blur
    /// Large square tiles, like a pixelated picture.
    case pixels
    /// A row of dots, as a password field shows.
    case dots
    /// The background carried across, as if nothing had been there.
    case erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: L("Ink")
        case .label: L("Labelled")
        case .blur: L("Blur")
        case .pixels: L("Pixels")
        case .dots: L("Dots")
        case .erase: L("Erased")
        }
    }

    /// Ink unless chosen otherwise.
    static var current: CoverStyle {
        get { UserDefaults.standard.string(forKey: "coverStyle").flatMap(CoverStyle.init(rawValue:)) ?? .ink }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "coverStyle") }
    }

    /// Whether the look is made from the colors around a place.
    fileprivate var readsAround: Bool {
        switch self {
        case .ink, .label: false
        case .blur, .pixels, .dots, .erase: true
        }
    }
}

extension PrivateDetail {
    /// The word a labelled cover shows: short, so it fits a line of text.
    var label: String {
        switch self {
        case .names: L("Name")
        case .addresses: L("Address")
        case .emails: L("Email")
        case .phones: L("Phone")
        case .bank: L("Bank")
        case .health: L("Health")
        case .usernames: L("Username")
        case .faces: L("Face")
        case .ipAddresses: L("IP address")
        case .ids: L("ID")
        case .codes: L("Code")
        case .keys: L("Key")
        case .barcodes: L("QR code")
        case .orders: L("Order no.")
        case .tracking: L("Tracking")
        case .amounts: L("Amount")
        case .dates: L("Date")
        case .links: L("Link")
        }
    }
}

extension Finder {
    /// From Settings › Privacy: the last four digits of a long number stay
    /// readable, as on a bank statement, so it is still clear which card,
    /// account or phone it is. Off unless turned on.
    static var keepsLastDigits: Bool {
        get { UserDefaults.standard.bool(forKey: "keepLastDigits") }
        set { UserDefaults.standard.set(newValue, forKey: "keepLastDigits") }
    }

    /// The kinds whose numbers keep their last four digits.
    static let lastDigitKinds: Set<PrivateDetail> = [.bank, .phones, .ids, .orders, .tracking]

    /// What is covered of a number in its line, without its last four
    /// digits and the spaces before them, when it holds at least eight
    /// digits; a shorter one is covered whole. Nil, the whole line. Pure
    /// text, so it can be checked without a picture.
    static func keepingLastDigits(_ range: NSRange?, in line: String) -> NSRange? {
        let text = line as NSString
        let whole = range ?? NSRange(location: 0, length: text.length)
        guard whole.location >= 0, whole.length > 0, whole.location + whole.length <= text.length else { return range }
        let digits = (whole.location..<(whole.location + whole.length)).filter {
            (0x30...0x39).contains(text.character(at: $0))
        }
        guard digits.count >= 8 else { return range }
        var end = digits[digits.count - 4]
        let separators: Set<unichar> = [0x20, 0x2D, 0x2E, 0x2F, 0xA0]
        while end > whole.location, separators.contains(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: whole.location, length: end - whole.location)
    }

    /// What decides how covers are drawn, for telling copies apart.
    static var lookKey: String { "\(CoverStyle.current.rawValue),\(keepsLastDigits)" }

    /// The picture with the given places covered in the chosen look. Each
    /// place is from 0 to 1 from the bottom left; its kind, if any, names it
    /// on a labelled cover.
    static func cover(_ image: CGImage, areas: [Area], style: CoverStyle = .current) -> CGImage? {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        // In whole pixels, so none is left half covered.
        let places = merged(areas.map { area in
            Place(rect: CGRect(x: area.rect.minX * CGFloat(width), y: area.rect.minY * CGFloat(height),
                               width: area.rect.width * CGFloat(width), height: area.rect.height * CGFloat(height))
                    .integral.intersection(bounds),
                  kind: area.kind)
        })
        let rects = places.map(\.rect)
        let unit = (CGFloat(width) * CGFloat(height)).squareRoot()
        // Lines of one size get labels, dots and tiles of one size, though
        // some letters reach lower than others.
        let heights = places.filter { $0.isLine(in: bounds) }.map(\.rect.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        func letters(_ rect: CGRect) -> CGFloat {
            (typical > 0 && abs(rect.height - typical) <= typical * 0.35 ? typical : rect.height) / 1.4
        }
        // What is around each place, read before any is covered, and never
        // from inside one.
        let around: [Surroundings?] = places.map { place in
            guard style.readsAround else { return nil }
            return Surroundings(of: place.rect, sides: !place.isLine(in: bounds), apartFrom: rects, in: context)
        }
        for (place, read) in zip(places, around) {
            let rect = place.rect
            let line = place.isLine(in: bounds)
            let text = letters(rect)
            switch (style, read) {
            case (.label, _):
                drawInk(rect, in: context)
                drawLabel(place.kind?.label ?? L("Hidden"), in: rect, text: text, unit: unit, context: context)
            case (.blur, let colors?):
                drawField(rect, colors, space: space, context: context)
                drawSmear(rect, colors, line: line, text: text, unit: unit, space: space, context: context)
            case (.pixels, let colors?):
                drawPixels(rect, colors, line: line, text: text, unit: unit, space: space, context: context)
            case (.dots, let colors?):
                // Dots stand for letters; a face or a code is tiled instead.
                if line {
                    drawField(rect, colors, space: space, context: context)
                    drawDots(rect, colors, text: text, space: space, context: context)
                } else {
                    drawPixels(rect, colors, line: false, text: text, unit: unit, space: space, context: context)
                }
            case (.erase, let colors?):
                drawField(rect, colors, space: space, context: context)
            default:
                drawInk(rect, in: context)
            }
        }
        return context.makeImage()
    }

    // MARK: Places

    /// A place to cover, in pixels from the bottom left, and the kind it is
    /// covered as.
    private struct Place {
        var rect: CGRect
        let kind: PrivateDetail?

        /// A line of text, or part of one, rather than a face, a code or a
        /// part hidden by hand.
        func isLine(in bounds: CGRect) -> Bool {
            switch kind {
            case .some(.faces), .some(.barcodes): false
            case .some: true
            case .none: rect.width >= rect.height * 1.2 && rect.height <= bounds.height * 0.12
            }
        }
    }

    /// The places, with those that overlap on one line drawn as one, so a
    /// detail two kinds found gets one label or one row of dots.
    private static func merged(_ places: [Place]) -> [Place] {
        var kept: [Place] = []
        for var place in places where !place.rect.isEmpty {
            while let i = kept.firstIndex(where: { overlapOnALine($0.rect, place.rect) }) {
                place = Place(rect: kept[i].rect.union(place.rect), kind: kept[i].kind)
                kept.remove(at: i)
            }
            kept.append(place)
        }
        return kept
    }

    private static func overlapOnALine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        return overlap.width * overlap.height >= smaller * 0.5 && abs(a.midY - b.midY) < min(a.height, b.height) * 0.5
    }

    // MARK: The looks

    private static func corner(of place: CGRect) -> CGFloat {
        min(place.height / 4, place.width / 2, 8)
    }

    private static func clip(to place: CGRect, radius: CGFloat, in context: CGContext) {
        context.addPath(CGPath(roundedRect: place, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }

    private static func drawInk(_ place: CGRect, in context: CGContext) {
        let radius = corner(of: place)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.addPath(CGPath(roundedRect: place, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }

    /// The kind's word, centred on the ink, as large as the line allows and
    /// never larger than words on a screen; a place too small for it stays
    /// plain ink.
    /// - Parameter text: how tall the letters covered are.
    private static func drawLabel(_ word: String, in place: CGRect, text: CGFloat, unit: CGFloat,
                                  context: CGContext) {
        func line(_ size: CGFloat) -> (line: CTLine, width: CGFloat, capHeight: CGFloat) {
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.92),
            ]
            let made = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: attributes)
                                                            as CFAttributedString)
            return (made, CGFloat(CTLineGetTypographicBounds(made, nil, nil, nil)), CTFontGetCapHeight(font))
        }
        let first = min(text * 0.64, max(12, unit * 0.022))
        guard first >= 6 else { return }
        var size = first
        var fitted = line(size)
        let room = place.width - size * 1.2
        if fitted.width > room {
            guard room > 0 else { return }
            size *= room / fitted.width
            guard size >= max(6, first * 0.55) else { return }
            fitted = line(size)
        }
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: place.midX - fitted.width / 2, y: place.midY - fitted.capHeight / 2)
        CTLineDraw(fitted.line, context)
        context.restoreGState()
    }

    /// The colors around, carried smoothly across the place.
    private static func drawField(_ place: CGRect, _ around: Surroundings, space: CGColorSpace, context: CGContext) {
        guard let field = around.field(for: place.size, space: space) else { return drawInk(place, in: context) }
        context.saveGState()
        clip(to: place, radius: corner(of: place), in: context)
        context.interpolationQuality = .high
        context.draw(field, in: place)
        context.restoreGState()
    }

    /// Over the field, a soft smudge where words would be, word by word on a
    /// line, and a fine grain, as frosted glass has. The words are made up:
    /// as many and as long as chance has them, not as the words covered.
    private static func drawSmear(_ place: CGRect, _ around: Surroundings, line: Bool, text: CGFloat, unit: CGFloat,
                                  space: CGColorSpace, context: CGContext) {
        let tone = around.mean.contrasting
        var random = Seeded(place)
        context.saveGState()
        clip(to: place, radius: corner(of: place), in: context)
        if line {
            var x = place.minX + text * 0.3
            let end = place.maxX - text * 0.3
            while end - x > text * 0.4 {
                let word = min(end - x, text * (1.2 + random.unit() * 3))
                var spot = x + text * 0.3
                repeat {
                    blob(CGRect(x: spot - text * 0.6, y: place.midY - text * 0.6, width: text * 1.2,
                                height: text * 1.2),
                         tone, alpha: 0.22 * (0.85 + random.unit() * 0.3), space: space, context: context)
                    spot += text * 0.4
                } while spot < x + word - text * 0.3
                x += word + text * (0.2 + random.unit() * 0.18)
            }
        } else {
            blob(place.insetBy(dx: place.width * 0.12, dy: place.height * 0.12), tone, alpha: 0.3,
                 space: space, context: context)
        }
        let grain = max(1, (unit / 1600).rounded())
        let count = Int(min(2500, place.width * place.height / (40 * grain * grain)))
        for _ in 0..<count {
            let u = random.unit(), v = random.unit()
            let shade = around.color(u: u, v: v).lightened(by: random.unit() * 0.1 - 0.05)
            context.setFillColor(shade.cgColor(in: space, alpha: 0.2))
            context.fill(CGRect(x: (place.minX + u * place.width).rounded(.down),
                                y: (place.minY + v * place.height).rounded(.down), width: grain, height: grain))
        }
        context.restoreGState()
    }

    /// A soft round spot of the tone, fading to nothing at its edge.
    private static func blob(_ rect: CGRect, _ tone: RGB, alpha: CGFloat, space: CGColorSpace, context: CGContext) {
        guard rect.width > 0, rect.height > 0,
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [tone.cgColor(in: space, alpha: alpha),
                                                 tone.cgColor(in: space, alpha: alpha * 0.55),
                                                 tone.cgColor(in: space, alpha: 0)] as CFArray,
                                        locations: [0, 0.5, 1]) else { return }
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: rect.width / 2, y: rect.height / 2)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                                   options: [])
        context.restoreGState()
    }

    /// Square tiles in the colors around, darker toward the middle of a line
    /// as pixelated words are, each a little different. A tile is a third of
    /// a line's height; on a face or a code, about a fiftieth of the
    /// picture's side.
    private static func drawPixels(_ place: CGRect, _ around: Surroundings, line: Bool, text: CGFloat, unit: CGFloat,
                                   space: CGColorSpace, context: CGContext) {
        let side = line ? text * 1.4 : min(place.width, place.height)
        let tile = max(3, min(side / 3.2, max(12, unit * 0.02)).rounded())
        let columns = max(1, Int((place.width / tile).rounded(.up)))
        let rows = max(1, Int((place.height / tile).rounded(.up)))
        let tone = around.mean.contrasting
        var random = Seeded(place)
        context.saveGState()
        clip(to: place, radius: min(place.height / 6, place.width / 2, 4), in: context)
        for row in 0..<rows {
            for column in 0..<columns {
                let u = min(1, (CGFloat(column) + 0.5) * tile / place.width)
                let v = min(1, (CGFloat(row) + 0.5) * tile / place.height)
                let weight: CGFloat
                if line {
                    let middle = CGFloat(pow(Double(1 - abs(v - 0.5) * 2), 0.7))
                    let ends = min(1, (1 - abs(u - 0.5) * 2) * 4)
                    weight = 0.8 * middle * ends * (0.3 + 0.7 * random.unit())
                } else {
                    let middle = max(0, 1 - hypot(u - 0.5, v - 0.5) * 2)
                    weight = 0.45 * middle * (0.4 + 0.6 * random.unit())
                }
                let shade = around.color(u: u, v: v).mixed(with: tone, by: weight)
                    .lightened(by: random.unit() * 0.06 - 0.03)
                context.setFillColor(shade.cgColor(in: space))
                context.fill(CGRect(x: place.minX + CGFloat(column) * tile, y: place.minY + CGFloat(row) * tile,
                                    width: tile, height: tile))
            }
        }
        context.restoreGState()
    }

    /// A row of round dots across the field, dark on a light ground and
    /// light on a dark one, as a password field shows.
    private static func drawDots(_ place: CGRect, _ around: Surroundings, text: CGFloat, space: CGColorSpace,
                                 context: CGContext) {
        let diameter = max(2, (text * 0.46).rounded())
        let gap = diameter * 0.7
        let room = place.width - text * 0.5
        let count = max(1, Int((room + gap) / (diameter + gap)))
        let total = CGFloat(count) * diameter + CGFloat(count - 1) * gap
        let start = place.midX - total / 2
        let ink = around.mean.luminance > 0.55 ? RGB(gray: 0.18) : RGB(gray: 0.94)
        context.saveGState()
        clip(to: place, radius: corner(of: place), in: context)
        context.setFillColor(ink.cgColor(in: space, alpha: 0.92))
        for k in 0..<count {
            context.fillEllipse(in: CGRect(x: start + CGFloat(k) * (diameter + gap), y: place.midY - diameter / 2,
                                           width: diameter, height: diameter))
        }
        context.restoreGState()
    }
}

// MARK: The samples in Settings

extension CoverStyle {
    /// The sample's size, in points: a tile in Settings.
    static let sampleSize = CGSize(width: 132, height: 82.5)

    /// A little chat with a name and a phone number covered in this look,
    /// drawn by the same code as a copy, for Settings to show each look by.
    func sample(dark: Bool, scale: CGFloat = 2) -> CGImage? {
        let size = Self.sampleSize
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(dark ? CGColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        // From the bottom left: a grey bubble with a name, a blue one with a number.
        let incoming = CGRect(x: 8, y: 45.5, width: 84, height: 28)
        let outgoing = CGRect(x: size.width - 8 - 96, y: 9, width: 96, height: 28)
        let grey = dark ? CGColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)
            : CGColor(red: 0.914, green: 0.914, blue: 0.922, alpha: 1)
        for (bubble, fill) in [(incoming, grey), (outgoing, CGColor(red: 0, green: 0.478, blue: 1, alpha: 1))] {
            context.setFillColor(fill)
            context.addPath(CGPath(roundedRect: bubble, cornerWidth: 14, cornerHeight: 14, transform: nil))
            context.fillPath()
        }
        guard let picture = context.makeImage() else { return nil }
        // Where a line of text in each would be covered, with its margin.
        func area(_ rect: CGRect, _ kind: PrivateDetail) -> Finder.Area {
            Finder.Area(rect: CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                                     width: rect.width / size.width, height: rect.height / size.height), kind: kind)
        }
        return Finder.cover(picture, areas: [area(incoming.insetBy(dx: 9, dy: 5), .names),
                                             area(outgoing.insetBy(dx: 9, dy: 5), .phones)], style: self)
    }
}

// MARK: Colors around

/// A color, its parts from 0 to 1, in the picture's own color space.
private struct RGB: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(gray: CGFloat) {
        self.init(red: gray, green: gray, blue: gray)
    }

    /// Light grey, for a place with nothing around it to read.
    static let paper = RGB(gray: 0.93)

    var luminance: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// What words on it would be: darker on a light ground, lighter on a
    /// dark one.
    var contrasting: RGB {
        luminance > 0.5 ? mixed(with: RGB(gray: 0.1), by: 0.65) : mixed(with: RGB(gray: 0.95), by: 0.5)
    }

    func mixed(with other: RGB, by amount: CGFloat) -> RGB {
        let t = max(0, min(1, amount))
        return RGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                   blue: blue + (other.blue - blue) * t)
    }

    func lightened(by amount: CGFloat) -> RGB {
        RGB(red: red + amount, green: green + amount, blue: blue + amount).clamped
    }

    var clamped: RGB {
        RGB(red: max(0, min(1, red)), green: max(0, min(1, green)), blue: max(0, min(1, blue)))
    }

    static func + (a: RGB, b: RGB) -> RGB {
        RGB(red: a.red + b.red, green: a.green + b.green, blue: a.blue + b.blue)
    }

    static func - (a: RGB, b: RGB) -> RGB {
        RGB(red: a.red - b.red, green: a.green - b.green, blue: a.blue - b.blue)
    }

    static func average(_ colors: [RGB]) -> RGB? {
        guard !colors.isEmpty else { return nil }
        let n = CGFloat(colors.count)
        return RGB(red: colors.map(\.red).reduce(0, +) / n, green: colors.map(\.green).reduce(0, +) / n,
                   blue: colors.map(\.blue).reduce(0, +) / n)
    }

    func cgColor(in space: CGColorSpace, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [red, green, blue, alpha]) ?? CGColor(gray: luminance, alpha: alpha)
    }
}

/// The colors just outside a place, in stretches along each side, from the
/// picture as it was: above and below it, and for a face, a code or a part
/// hidden by hand, to its left and right too. Pixels inside any place that
/// is covered are left out, so nothing under one cover goes into another.
private struct Surroundings {
    var above: [RGB]
    var below: [RGB]
    var left: [RGB]?
    var right: [RGB]?

    init(of place: CGRect, sides: Bool, apartFrom places: [CGRect], in context: CGContext) {
        let picture = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        let band = max(2, min(6, (min(place.width, place.height) * 0.15).rounded()))
        let across = max(2, min(16, Int(place.width / 40)))
        let down = max(2, min(16, Int(place.height / 40)))
        func read(_ rect: CGRect, _ stretches: Int, along horizontal: Bool) -> [RGB?] {
            Self.read(rect.intersection(picture), stretches: stretches, horizontal: horizontal,
                      apartFrom: places, in: context)
        }
        var above = read(CGRect(x: place.minX, y: place.maxY, width: place.width, height: band), across, along: true)
        var below = read(CGRect(x: place.minX, y: place.minY - band, width: place.width, height: band), across,
                         along: true)
        // At the picture's edge, or between covers, one side stands for both.
        if above.allSatisfy({ $0 == nil }) { above = below }
        if below.allSatisfy({ $0 == nil }) { below = above }
        var left: [RGB?]?, right: [RGB?]?
        if sides {
            var west = read(CGRect(x: place.minX - band, y: place.minY, width: band, height: place.height), down,
                            along: false)
            var east = read(CGRect(x: place.maxX, y: place.minY, width: band, height: place.height), down, along: false)
            if west.allSatisfy({ $0 == nil }) { west = east }
            if east.allSatisfy({ $0 == nil }) { east = west }
            if !west.allSatisfy({ $0 == nil }) {
                left = west
                right = east
            }
        }
        let known = (above + below + (left ?? []) + (right ?? [])).compactMap { $0 }
        let fallback = RGB.average(known) ?? .paper
        func filled(_ side: [RGB?]) -> [RGB] {
            let mean = RGB.average(side.compactMap { $0 }) ?? fallback
            return side.map { $0 ?? mean }
        }
        self.above = filled(above)
        self.below = filled(below)
        self.left = left.map(filled)
        self.right = right.map(filled)
    }

    /// The color at a point of the place, from 0 to 1 across and from the
    /// bottom up: above and below blended between, and with the sides read,
    /// all four, as a Coons patch blends a surface between its edges.
    func color(u: CGFloat, v: CGFloat) -> RGB {
        let vertical = Self.along(below, u).mixed(with: Self.along(above, u), by: v)
        guard let left, let right, let b0 = below.first, let b1 = below.last,
              let a0 = above.first, let a1 = above.last else { return vertical }
        let horizontal = Self.along(left, v).mixed(with: Self.along(right, v), by: u)
        let corners = b0.mixed(with: b1, by: u).mixed(with: a0.mixed(with: a1, by: u), by: v)
        return (vertical + horizontal - corners).clamped
    }

    var mean: RGB {
        RGB.average(above + below + (left ?? []) + (right ?? [])) ?? .paper
    }

    /// The colors across the place as a picture a few pixels large, to be
    /// drawn stretched over it, smoothly.
    func field(for size: CGSize, space: CGColorSpace) -> CGImage? {
        let columns = max(2, min(32, Int(size.width / 8))), rows = max(2, min(16, Int(size.height / 8)))
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        for row in 0..<rows {
            for column in 0..<columns {
                let u = (CGFloat(column) + 0.5) / CGFloat(columns), v = (CGFloat(row) + 0.5) / CGFloat(rows)
                context.setFillColor(color(u: u, v: v).cgColor(in: space))
                context.fill(CGRect(x: column, y: row, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }

    private static func along(_ side: [RGB], _ t: CGFloat) -> RGB {
        guard let first = side.first else { return .paper }
        guard side.count > 1 else { return first }
        let position = max(0, min(CGFloat(side.count - 1), t * CGFloat(side.count) - 0.5))
        let lower = Int(position.rounded(.down)), upper = min(side.count - 1, lower + 1)
        return side[lower].mixed(with: side[upper], by: position - CGFloat(lower))
    }

    /// The color of each stretch of a band: the middle value of its pixels,
    /// so a letter reaching into it does not darken it; nil where none of
    /// them can be read.
    private static func read(_ band: CGRect, stretches: Int, horizontal: Bool, apartFrom places: [CGRect],
                             in context: CGContext) -> [RGB?] {
        guard !band.isNull, band.width >= 1, band.height >= 1, let data = context.data else {
            return Array(repeating: nil, count: stretches)
        }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = context.bytesPerRow, height = context.height
        let near = places.filter { $0.intersects(band) }
        let minX = Int(band.minX), maxX = Int(band.maxX), minY = Int(band.minY), maxY = Int(band.maxY)
        let span = max(1, horizontal ? maxX - minX : maxY - minY)
        // A hundred or so pixels along each band are enough to know its colors.
        let step = max(1, span / 120)
        var reds = Array(repeating: [UInt8](), count: stretches)
        var greens = reds, blues = reds
        for y in stride(from: minY, to: maxY, by: horizontal ? 1 : step) {
            for x in stride(from: minX, to: maxX, by: horizontal ? step : 1) {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                if near.contains(where: { $0.contains(point) }) { continue }
                // Rows are kept from the top down; the picture counts from the bottom up.
                let offset = (height - 1 - y) * rowBytes + x * 4
                let alpha = Int(pixels[offset + 3])
                guard alpha > 0 else { continue }
                let k = min(stretches - 1, (horizontal ? x - minX : y - minY) * stretches / span)
                reds[k].append(UInt8(min(255, Int(pixels[offset]) * 255 / alpha)))
                greens[k].append(UInt8(min(255, Int(pixels[offset + 1]) * 255 / alpha)))
                blues[k].append(UInt8(min(255, Int(pixels[offset + 2]) * 255 / alpha)))
            }
        }
        func middle(_ values: [UInt8]) -> CGFloat {
            CGFloat(values.sorted()[values.count / 2]) / 255
        }
        return (0..<stretches).map { k in
            reds[k].isEmpty ? nil : RGB(red: middle(reds[k]), green: middle(greens[k]), blue: middle(blues[k]))
        }
    }
}

/// The same few random numbers for the same place every time, so a copy
/// drawn again looks the same, and nothing of the picture goes in.
private struct Seeded {
    private var state: UInt64

    init(_ place: CGRect) {
        state = UInt64(bitPattern: Int64(place.minX)) &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(bitPattern: Int64(place.minY)) &* 0xBF58_476D_1CE4_E5B9
            ^ UInt64(bitPattern: Int64(place.width * 31 + place.height)) &+ 0x94D0_49BB_1331_11EB
    }

    /// From 0 up to 1.
    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
