#if DEBUG && canImport(CoreText) && canImport(CoreImage)
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A made-up sick note to scan, as a real one comes: an
/// Arbeitsunfähigkeitsbescheinigung's kind of form, filled in on a
/// typewriter in light, uneven print on pink carbon-copy paper, signed in a
/// ballpoint's blue across the fax number, folded at a little over half its
/// height so its lower part lies at another angle, curling at the bottom,
/// and photographed at an angle on a grey floor with a phone. Its people,
/// numbers and places are all made up. In debug builds only, for the tests
/// and the pictures made in CI; never a real document.
enum ScanForm {
    /// A4 at 300 dots an inch.
    static let width = 2480
    static let height = 3508
    /// The photo, as a phone's 12 megapixels upright.
    static let photoWidth = 3024
    static let photoHeight = 4032

    static let name = "Mustermann, Erika"
    static let birthDate = "01.01.1980"
    static let street = "Musterweg 1"
    static let town = "12345 Musterstadt"
    static let insurance = "X123456789"
    static let diagnosis = "Z00.0"
    static let phone = "040-7654321"
    static let fax = "040-1234567"

    /// The paper and what happened to it.
    enum Variant: String, CaseIterable, Sendable {
        /// Pink, folded once, curling at the bottom: the photo of the report.
        case pink
        /// The same on white paper, and on yellow.
        case white
        case yellow
        /// Pink, folded twice, as a letter is.
        case twoFolds
        /// Pink, folded once, a hand's shadow over the bottom right corner.
        case handShadow

        var paper: (red: CGFloat, green: CGFloat, blue: CGFloat) {
            switch self {
            case .white: (0.97, 0.97, 0.96)
            case .yellow: (1.0, 0.95, 0.72)
            case .pink, .twoFolds, .handShadow: (1.0, 0.84, 0.87)
            }
        }

        /// Where it is folded, as a share of its height from the top, and the
        /// angle the part below each fold turns by, in degrees.
        var folds: [(at: Double, angle: Double)] {
            switch self {
            case .twoFolds: [(1.0 / 3, 11), (2.0 / 3, -10)]
            default: [(0.55, 12)]
            }
        }
    }

    /// A photo of the form and what is known of it.
    struct Photo {
        let image: CGImage
        /// The sheet's four corners, from 0 to 1 from the bottom left.
        let quad: ScanQuad
        /// Each fold's ends in the photo, left then right, as the corners are.
        let folds: [(left: CGPoint, right: CGPoint)]
    }

    /// The grey header across the top, printed with the form, from the
    /// page's top left: it stays grey.
    static let header = CGRect(x: 160, y: 140, width: 2160, height: 180)
    /// A grey photo-like patch, printed in a box at the right: it stays grey.
    static let patch = CGRect(x: 1900, y: 1140, width: 360, height: 300)
    /// Long lines across the whole page, pixels down: above the fold, below
    /// it, and in the curl.
    static let ruledLines = [1500, 2400, 3100]
    /// The box the fold crosses, top and bottom, pixels down.
    static let foldBox = (top: 1600, bottom: 2300)

    /// Every word and number printed on it, line by line.
    static var text: [String] { lines.map(\.text) }

    // MARK: What it says

    /// A line of the form: preprinted, as its labels are, or typed.
    struct Line {
        let text: String
        let x: Int
        /// Its top, pixels down the page.
        let top: Int
        let typed: Bool
        let size: CGFloat
    }

    static let lines: [Line] = {
        func label(_ text: String, _ x: Int, _ top: Int) -> Line { Line(text: text, x: x, top: top, typed: false, size: 34) }
        func typed(_ text: String, _ x: Int, _ top: Int) -> Line { Line(text: text, x: x, top: top, typed: true, size: 46) }
        return [
            label("Krankenkasse bzw. Kostenträger", 200, 400),
            typed("AOK Musterland", 200, 450),
            label("Name, Vorname des Versicherten", 200, 540),
            label("geb. am", 1700, 540),
            typed(name, 200, 592),
            typed(birthDate, 1700, 592),
            typed("\(street), \(town)", 200, 664),
            label("Kostenträgerkennung", 200, 790),
            label("Versicherten-Nr.", 900, 790),
            label("Status", 1700, 790),
            typed("101234567", 200, 842),
            typed(insurance, 900, 842),
            typed("1000000", 1700, 842),
            label("Betriebsstätten-Nr.", 200, 920),
            label("Arzt-Nr.", 900, 920),
            label("Datum", 1700, 920),
            typed("123456789", 200, 972),
            typed("987654321", 900, 972),
            typed("14.10.2026", 1700, 972),
            label("Erstbescheinigung", 200, 1158),
            label("arbeitsunfähig seit", 200, 1240),
            typed("13.10.2026", 900, 1232),
            label("voraussichtlich arbeitsunfähig bis", 200, 1320),
            typed("17.10.2026", 900, 1312),
            label("festgestellt am", 200, 1400),
            typed("14.10.2026", 900, 1392),
            label("AU-begründende Diagnose(n) (ICD-10)", 200, 1630),
            typed("\(diagnosis) G", 200, 1700),
            typed("Untersuchung ohne Befund", 200, 1772),
            label("Arbeitsunfall", 1290, 1630),
            typed("nein", 1290, 1700),
            label("Hinweis für den Arbeitgeber", 200, 2040),
            typed("Wiedervorstellung am 17.10.2026", 200, 2112),
            typed("Dr. med. Max Beispiel", 200, 2500),
            typed("Praxis Beispiel, Beispielstraße 5", 200, 2572),
            typed("20095 Hamburg", 200, 2644),
            typed("Tel. \(phone)  Fax \(fax)", 200, 2716),
            label("Unterschrift und Stempel des Arztes", 200, 2860),
            label("Ausfertigung zur Vorlage beim Arbeitgeber", 200, 3200),
            label("Muster 1b", 200, 3290),
        ]
    }()

    // MARK: The page

    /// The form as printed and typed on: the paper's colour, a grey header
    /// and a grey patch, ruled lines and boxes, labels in the form's print,
    /// the details in a typewriter's light, uneven print, and a signature
    /// in blue across the fax number.
    static func page(_ variant: Variant = .pink) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let paper = variant.paper
        context.setFillColor(CGColor(red: paper.red, green: paper.green, blue: paper.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let printed = CGColor(red: 0.3, green: 0.28, blue: 0.31, alpha: 1)
        // The grey header and patch, laid over the paper as ink is, with sharp edges.
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(box(header))
        context.setFillColor(CGColor(red: 0.66, green: 0.66, blue: 0.66, alpha: 1))
        context.fill(box(patch))
        context.restoreGState()
        write("Arbeitsunfähigkeitsbescheinigung", in: context, x: 200, top: 196, size: 66, font: "Helvetica-Bold", color: printed)
        // The boxes and the long lines.
        context.setFillColor(printed)
        func rule(_ x: Int, _ top: Int, _ w: Int, _ h: Int) { context.fill(box(CGRect(x: x, y: top, width: w, height: h))) }
        for (top, bottom) in [(380, 1080), (foldBox.top, foldBox.bottom)] {
            rule(160, top, 2160, 4)
            rule(160, bottom, 2164, 4)
            rule(160, top, 4, bottom - top)
            rule(2320, top, 4, bottom - top)
        }
        rule(160, 760, 2160, 3)
        rule(1240, foldBox.top, 3, foldBox.bottom - foldBox.top)
        for top in ruledLines { rule(160, top, 2164, 4) }
        rule(200, 2840, 1000, 3)
        // The words: the form's in its print, the details as a typewriter strikes them.
        var seed: UInt32 = 5
        func next() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        for line in lines {
            if line.typed {
                typewrite(line.text, in: context, x: line.x, top: line.top, size: line.size, strike: next)
            } else {
                write(line.text, in: context, x: line.x, top: line.top, size: line.size, font: "Helvetica", color: printed)
            }
        }
        // The signature, a ballpoint's blue, across the fax number.
        context.setStrokeColor(CGColor(red: 0.13, green: 0.24, blue: 0.66, alpha: 1))
        context.setLineWidth(6)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let start = CGPoint(x: 700, y: CGFloat(height - 2800))
        context.move(to: start)
        for step in 1...220 {
            let t = CGFloat(step)
            let x: CGFloat = start.x + t * 3.9
            let y: CGFloat = start.y + t * 0.5 + 44 * sin(t / 11) + 16 * sin(t / 3.1)
            context.addLine(to: CGPoint(x: x, y: y))
        }
        context.strokePath()
        return context.makeImage()
    }

    /// A rectangle given from the page's top left, as Core Graphics draws it.
    private static func box(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(height) - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    private static func write(_ text: String, in context: CGContext, x: Int, top: Int, size: CGFloat, font name: String,
                              color: CGColor) {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(height - top) - CTFontGetAscent(font))
        CTLineDraw(line, context)
    }

    /// Typed: each letter struck a little harder or softer and a hair
    /// higher or lower, in a carbon copy's light grey-blue.
    private static func typewrite(_ text: String, in context: CGContext, x: Int, top: Int, size: CGFloat,
                                  strike: () -> CGFloat) {
        let font = CTFontCreateWithName("Courier" as CFString, size, nil)
        let advance: CGFloat = size * 0.6
        let baseline: CGFloat = CGFloat(height - top) - CTFontGetAscent(font)
        for (index, character) in text.enumerated() where character != " " {
            let ink: CGFloat = 0.55 + 0.3 * strike()
            let lift: CGFloat = (strike() - 0.5) * 2.4
            let color = CGColor(red: 0.2, green: 0.21, blue: 0.3, alpha: ink)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
            context.textPosition = CGPoint(x: CGFloat(x) + CGFloat(index) * advance, y: baseline + lift)
            CTLineDraw(line, context)
        }
    }

    // MARK: The photo

    /// The form folded, lying on a grey floor, photographed at an angle with
    /// a phone, 3024 by 4032 pixels, a little soft and grainy.
    static func photographed(_ variant: Variant = .pink) -> Photo? {
        guard let page = page(variant) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: photoWidth, height: photoHeight)
        let sheet = Sheet(variant: variant)
        let shaded = CIImage(cgImage: page).applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: light(variant),
        ])
        // The sheet in strips down its length, each a flat piece of paper as
        // the camera sees it, every fold at a strip's edge. Each reaches a
        // little into the next, which is laid over it, so no seam shows.
        var photo = floor(canvas)
        var cuts: Set<Double> = Set((0..<64).map { Double($0) / 64 })
        for fold in variant.folds { cuts.insert(fold.at) }
        let edges = cuts.sorted() + [1]
        for (top, bottom) in zip(edges, edges.dropFirst()) {
            let v0 = top * Double(height), v1 = min(Double(height), bottom * Double(height) + 2)
            let strip = CGRect(x: 0, y: Double(height) - v1, width: Double(width), height: v1 - v0)
            let piece = shaded.cropped(to: strip)
                .transformed(by: CGAffineTransform(translationX: 0, y: -strip.minY))
                .applyingFilter("CIPerspectiveTransform", parameters: [
                    "inputTopLeft": CIVector(cgPoint: sheet.point(u: 0, v: v0)),
                    "inputTopRight": CIVector(cgPoint: sheet.point(u: Double(width), v: v0)),
                    "inputBottomRight": CIVector(cgPoint: sheet.point(u: Double(width), v: v1)),
                    "inputBottomLeft": CIVector(cgPoint: sheet.point(u: 0, v: v1)),
                ])
            photo = piece.composited(over: photo)
        }
        // A little soft, as a phone's photo is, and its grain.
        photo = photo.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.1]).cropped(to: canvas)
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let grain = random.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.05, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.05, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.05, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.475, y: 0.475, z: 0.475, w: 1),
            ]).cropped(to: canvas)
            photo = grain.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: photo])
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let image = context.createCGImage(photo.cropped(to: canvas), from: canvas, format: .RGBA8,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        func share(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x / canvas.width, y: point.y / canvas.height) }
        let w = Double(width), h = Double(height)
        let quad = ScanQuad(topLeft: share(sheet.point(u: 0, v: 0)), topRight: share(sheet.point(u: w, v: 0)),
                            bottomRight: share(sheet.point(u: w, v: h)), bottomLeft: share(sheet.point(u: 0, v: h)))
        let folds = variant.folds.map { fold in
            (left: share(sheet.point(u: 0, v: fold.at * h)), right: share(sheet.point(u: w, v: fold.at * h)))
        }
        return Photo(image: image, quad: quad, folds: folds)
    }

    /// How the light falls on the sheet, over the page as printed: a lamp
    /// brighter at the top left, a soft grey band along each fold, the part
    /// below a little darker for its angle, the curl darker still, the
    /// paper's colour deeper towards the bottom and the edges, and where
    /// asked a hand's shadow. Worked out on a small grid and drawn larger,
    /// so it is smooth.
    private static func light(_ variant: Variant) -> CIImage {
        let step = 8
        let columns = width / step + 1, rows = height / step + 1
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        func level(_ value: Double) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        for row in 0..<rows {
            let v = Double(row * step) / Double(height)
            for column in 0..<columns {
                let u = Double(column * step) / Double(width)
                var shade = 1.0 - 0.1 * (u + v) / 2
                for (index, fold) in variant.folds.enumerated() {
                    let off = (v - fold.at) / 0.011
                    shade *= 1 - 0.3 * exp(-off * off / 2)
                    let below = 1 / (1 + exp(-(v - fold.at) / 0.008))
                    shade *= 1 - (index % 2 == 0 ? 0.07 : -0.03) * below
                }
                let curl = max(0, v - 0.88) / 0.12
                shade *= 1 - 0.12 * curl * curl
                if variant == .handShadow {
                    let dx = (u - 0.95) / 0.28, dy = (v - 0.93) / 0.22
                    shade *= 1 - 0.4 * exp(-(dx * dx + dy * dy))
                }
                // The paper's colour deeper near the edges and the bottom.
                let edge = max(max(0, 0.12 - u), max(0, u - 0.88), max(0, v - 0.8) * 0.6) / 0.12
                let deeper = variant == .white ? 0 : 0.07 * min(1, edge)
                let i = (row * columns + column) * 4
                pixels[i] = level(shade)
                pixels[i + 1] = level(shade * (1 - deeper))
                pixels[i + 2] = level(shade * (1 - deeper * 0.8))
            }
        }
        // Row 0 of the data is the top of the picture, as for the page drawn.
        let grid = CIImage(bitmapData: Data(pixels), bytesPerRow: columns * 4, size: CGSize(width: columns, height: rows),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // Laid so its last row meets the page's bottom, as its first meets the top.
        let lift = CGFloat(height) - CGFloat(rows * step)
        return grid.samplingLinear().transformed(by: CGAffineTransform(scaleX: CGFloat(step), y: CGFloat(step)))
            .transformed(by: CGAffineTransform(translationX: 0, y: lift))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// A grey floor with a texture: a fleck at every other pixel, and
    /// broad patches a little darker or lighter. Made the same each time.
    private static func floor(_ canvas: CGRect) -> CIImage {
        let step = 2
        let columns = Int(canvas.width) / step, rows = Int(canvas.height) / step
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        var seed: UInt32 = 17
        for row in 0..<rows {
            let v = Double(row) / Double(rows)
            for column in 0..<columns {
                let u = Double(column) / Double(columns)
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let fleck = Double(seed >> 24) / 255 - 0.5
                let patch = 0.05 * sin(u * 9.1 + 1.3) * sin(v * 7.3 + 0.4) + 0.03 * sin(u * 23 + v * 17)
                let value = 0.45 + 0.12 * fleck + patch
                let level = UInt8(max(0, min(255, (value * 255).rounded())))
                let i = (row * columns + column) * 4
                pixels[i] = level
                pixels[i + 1] = level
                pixels[i + 2] = UInt8(min(255, Int(level) + 3))
            }
        }
        let small = CIImage(bitmapData: Data(pixels), bytesPerRow: columns * 4, size: CGSize(width: columns, height: rows),
                            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return small.samplingLinear().transformed(by: CGAffineTransform(scaleX: CGFloat(step), y: CGFloat(step)))
            .cropped(to: canvas)
    }

    /// The sheet in space: flat to its first fold, each part below a fold
    /// turned about it, the last curling up towards the bottom; laid before
    /// a phone tipped back and turned a little, and seen through its lens.
    struct Sheet {
        private var profile: [(y: Double, z: Double)] = []
        private let focal = 3030.0, distance = 3700.0
        private let tilt = 17 * Double.pi / 180, yaw = -4 * Double.pi / 180, roll = 2.2 * Double.pi / 180

        init(variant: Variant) {
            let steps = 2048
            var y = Double(ScanForm.height) / 2, z = 0.0
            profile.append((y, z))
            for k in 1...steps {
                let v = Double(k) / Double(steps)
                var angle = 0.0
                for fold in variant.folds where v > fold.at { angle += fold.angle }
                let curl = max(0, v - 0.86) / 0.14
                angle += 9 * curl * curl
                let radians = angle * .pi / 180
                let length = Double(ScanForm.height) / Double(steps)
                y -= length * cos(radians)
                z += length * sin(radians)
                profile.append((y, z))
            }
        }

        /// Where a point of the page, `u` across and `v` down in its pixels,
        /// lands in the photo, from its bottom left.
        func point(u: Double, v: Double) -> CGPoint {
            let along = v / Double(ScanForm.height) * Double(profile.count - 1)
            let index = min(profile.count - 2, max(0, Int(along)))
            let t = min(1, max(0, along - Double(index)))
            var x = u - Double(ScanForm.width) / 2
            var y = profile[index].y + (profile[index + 1].y - profile[index].y) * t
            var z = profile[index].z + (profile[index + 1].z - profile[index].z) * t
            (y, z) = (y * cos(tilt) - z * sin(tilt), y * sin(tilt) + z * cos(tilt))
            (x, z) = (x * cos(yaw) + z * sin(yaw), -x * sin(yaw) + z * cos(yaw))
            (x, y) = (x * cos(roll) - y * sin(roll), x * sin(roll) + y * cos(roll))
            let depth = distance + z
            let across = Double(ScanForm.photoWidth) / 2 + focal * x / depth
            let up = Double(ScanForm.photoHeight) / 2 - 40 + focal * y / depth
            return CGPoint(x: across, y: up)
        }
    }
}
#endif
