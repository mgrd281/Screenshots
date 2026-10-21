#if DEBUG && canImport(CoreText) && canImport(CoreImage)
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A made-up invoice to try scanning without a camera or a real document:
/// drawn here as a page is printed, then photographed: laid at an angle on
/// a table, lit unevenly by a lamp with a warm cast and a soft shadow, with
/// a camera's grain; where asked, blurred at the bottom or with a
/// reflection, or turned. Its company, people, IBAN and numbers are all
/// made up; the IBAN is the one banks use as an example. In debug builds
/// only, for the tests and the pictures made in CI.
enum ScanSample {
    /// A4 at 200 dots an inch.
    static let width = 1654
    static let height = 2339
    /// Every amount on it, as printed, for the reading check.
    static let amounts = ["255,00", "49,80", "5,90", "310,70", "59,03", "369,73"]
    static let customer = "Erika Mustermann"
    static let iban = "DE89 3704 0044 0532 0130 00"
    static let email = "buchhaltung@musterfirma.de"

    /// What can go wrong as it is photographed.
    enum Flaw: String, CaseIterable, Sendable {
        case none
        /// The camera focused on the top: the bottom third and more is blurred.
        case blurredBottom
        /// A lamp's reflection whitens part of the top.
        case glare
    }

    /// A photo of the page and where the page is in it.
    struct Photo {
        let image: CGImage
        /// From 0 to 1 from the bottom left, as Vision gives it.
        let quad: ScanQuad
    }

    // MARK: The page

    /// The invoice as printed: white paper, black print, a teal logo, a
    /// table with a grey header, a pale red stamp and a blue signature.
    static func page() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let ink = CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        let quiet = CGColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1)
        context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The logo and the company.
        let logo = box(120, 110, 108, 108)
        context.setFillColor(CGColor(red: 0.07, green: 0.47, blue: 0.43, alpha: 1))
        context.addPath(CGPath(roundedRect: logo, cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.fillPath()
        write("M", in: context, x: 146, top: 128, size: 72, bold: true, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        write("Musterfirma GmbH", in: context, x: 255, top: 122, size: 54, bold: true, color: ink)
        write("Beispielweg 5 · 10115 Berlin", in: context, x: 258, top: 190, size: 27, color: quiet)
        // Who it is for, and the invoice's numbers.
        for (line, text) in [customer, "Musterstraße 12", "20095 Hamburg"].enumerated() {
            write(text, in: context, x: 120, top: 350 + line * 48, size: 34, color: ink)
        }
        for (line, pair) in [("Rechnungsnr.", "RE-2026-0417"), ("Datum", "14.10.2026"), ("Kundennr.", "48213")].enumerated() {
            write(pair.0, in: context, x: 1010, top: 350 + line * 48, size: 29, color: quiet)
            write(pair.1, in: context, x: 1240, top: 350 + line * 48, size: 29, color: ink)
        }
        write("Rechnung", in: context, x: 120, top: 610, size: 60, bold: true, color: ink)
        // The table, its header on light grey.
        context.setFillColor(CGColor(red: 0.89, green: 0.9, blue: 0.91, alpha: 1))
        context.fill(box(120, 720, 1414, 66))
        for (x, text) in [(134, "Pos"), (226, "Beschreibung"), (850, "Menge"), (1040, "Einzelpreis"), (1330, "Betrag")] {
            write(text, in: context, x: x, top: 736, size: 29, bold: true, color: ink)
        }
        let rows = [("1", "Beratung (Stunden)", "3", "85,00 €", "255,00 €"),
                    ("2", "Druckpatronen Schwarz", "2", "24,90 €", "49,80 €"),
                    ("3", "Versandpauschale", "1", "5,90 €", "5,90 €")]
        for (index, row) in rows.enumerated() {
            let top = 812 + index * 66
            for (x, text) in zip([134, 226, 880, 1065, 1345], [row.0, row.1, row.2, row.3, row.4]) {
                write(text, in: context, x: x, top: top, size: 29, color: ink)
            }
            context.setFillColor(CGColor(red: 0.78, green: 0.79, blue: 0.8, alpha: 1))
            context.fill(box(120, top + 54, 1414, 3))
        }
        for (index, pair) in [("Netto", "310,70 €"), ("MwSt. 19 %", "59,03 €"), ("Gesamt", "369,73 €")].enumerated() {
            write(pair.0, in: context, x: 1040, top: 1052 + index * 54, size: 32, bold: index == 2, color: ink)
            write(pair.1, in: context, x: 1345, top: 1052 + index * 54, size: 32, bold: index == 2, color: ink)
        }
        write("Bitte überweisen Sie den Betrag bis zum 28.10.2026.", in: context, x: 120, top: 1310, size: 29, color: ink)
        write("IBAN: \(iban) · BIC: COBADEFFXXX", in: context, x: 120, top: 1362, size: 29, color: ink)
        write("Telefon: 030 1234567 · E-Mail: \(email)", in: context, x: 120, top: 1414, size: 29, color: ink)
        // A pale stamp, turned a little, and a signature in a ballpoint's blue.
        context.saveGState()
        context.translateBy(x: 1180, y: CGFloat(height - 1640))
        context.rotate(by: 0.14)
        let red = CGColor(red: 0.8, green: 0.25, blue: 0.25, alpha: 0.55)
        context.setStrokeColor(red)
        context.setLineWidth(8)
        context.addPath(CGPath(roundedRect: CGRect(x: -270, y: -95, width: 540, height: 190), cornerWidth: 18,
                               cornerHeight: 18, transform: nil))
        context.strokePath()
        writeAt("BEZAHLT", in: context, x: -220, baseline: 0, size: 76, bold: true, color: red)
        writeAt("16.10.2026", in: context, x: -220, baseline: -64, size: 40, color: red)
        context.restoreGState()
        context.setStrokeColor(CGColor(red: 0.17, green: 0.27, blue: 0.63, alpha: 1))
        context.setLineWidth(5)
        context.setLineCap(.round)
        let start = CGPoint(x: 190, y: CGFloat(height - 1720))
        context.move(to: start)
        for step in 1...140 {
            let t = CGFloat(step)
            context.addLine(to: CGPoint(x: start.x + t * 3.4, y: start.y + 34 * sin(t / 9) + 12 * sin(t / 2.6)))
        }
        context.strokePath()
        write("Max Muster, Buchhaltung", in: context, x: 120, top: 1800, size: 26, color: quiet)
        write("Musterfirma GmbH · Amtsgericht Berlin HRB 123456 · USt-IdNr. DE123456789", in: context, x: 120,
              top: 2215, size: 20, color: quiet)
        return context.makeImage()
    }

    /// A rectangle given from the page's top left.
    private static func box(_ x: Int, _ top: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: x, y: height - top - h, width: w, height: h)
    }

    /// Words with their top `top` pixels down the page.
    private static func write(_ text: String, in context: CGContext, x: Int, top: Int, size: CGFloat, bold: Bool = false,
                              color: CGColor) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        writeAt(text, in: context, x: CGFloat(x), baseline: CGFloat(height - top) - CTFontGetAscent(font), size: size,
                bold: bold, color: color)
    }

    /// Words on a baseline, where the context is.
    private static func writeAt(_ text: String, in context: CGContext, x: CGFloat, baseline: CGFloat, size: CGFloat,
                                bold: Bool = false, color: CGColor) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
    }

    // MARK: The photo

    /// The page photographed on a table with a phone, 3024 by 4032 pixels.
    static func photographed(_ page: CGImage, flaw: Flaw = .none, quarterTurns: Int = 0) -> Photo? {
        let canvas = CGRect(x: 0, y: 0, width: 3024, height: 4032)
        // Where the page's corners land, from the bottom left: farther away at its top.
        let corners = ScanQuad(topLeft: CGPoint(x: 520, y: 3610), topRight: CGPoint(x: 2560, y: 3540),
                               bottomRight: CGPoint(x: 2790, y: 470), bottomLeft: CGPoint(x: 250, y: 600))
        guard let perspective = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        perspective.setValue(CIImage(cgImage: page), forKey: kCIInputImageKey)
        perspective.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
        perspective.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")
        guard var photo = perspective.outputImage else { return nil }
        // A dark table under it.
        let table = CIImage(color: CIColor(red: 0.27, green: 0.23, blue: 0.2)).cropped(to: canvas)
        photo = photo.composited(over: table)
        // The lamp: bright at the top left, dimmer towards the bottom right, warm.
        if let lamp = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 600, y: 3700), "inputRadius0": 300, "inputRadius1": 4600,
            "inputColor0": CIColor(red: 1, green: 0.95, blue: 0.84), "inputColor1": CIColor(red: 0.6, green: 0.56, blue: 0.48),
        ])?.outputImage {
            photo = photo.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: lamp.cropped(to: canvas)])
        }
        // The phone's soft shadow over the bottom right.
        if let shadow = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 1900, y: 1300), "inputPoint1": CIVector(x: 2050, y: 1150),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0.72, green: 0.72, blue: 0.72),
        ])?.outputImage {
            photo = photo.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: shadow.cropped(to: canvas)])
        }
        switch flaw {
        case .none:
            break
        case .blurredBottom:
            if let mask = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 1500), "inputPoint1": CIVector(x: 0, y: 2100),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
            ])?.outputImage {
                photo = photo.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
                    "inputMask": mask.cropped(to: canvas), kCIInputRadiusKey: 9,
                ]).cropped(to: canvas)
            }
        case .glare:
            if let spot = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 1900, y: 3050), "inputRadius0": 120, "inputRadius1": 420,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            ])?.outputImage {
                photo = spot.cropped(to: canvas).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: photo])
            }
        }
        // A camera's grain: a mid grey a little lighter or darker here and
        // there, laid over the photo, which mid grey leaves as it is.
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let grain = random.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.06, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.06, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.06, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.47, y: 0.47, z: 0.47, w: 1),
            ]).cropped(to: canvas)
            photo = grain.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: photo])
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(photo.cropped(to: canvas), from: canvas, format: .RGBA8,
                                                   colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        var quad = corners
        quad.corners = corners.corners.map { CGPoint(x: $0.x / canvas.width, y: $0.y / canvas.height) }
        return turned(Photo(image: rendered, quad: quad), quarterTurns: quarterTurns)
    }

    /// The photo turned clockwise by quarter turns, as if the phone was
    /// held sideways, and the page's corners with it.
    private static func turned(_ photo: Photo, quarterTurns: Int) -> Photo? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return photo }
        guard let image = ScanCleaner.turned(photo.image, quarterTurns: turns, skew: 0) else { return nil }
        var quad = photo.quad
        // A quarter turn clockwise takes a point (x, y), from the bottom left, to (y, 1 - x).
        quad.corners = photo.quad.corners.map { point in
            var p = point
            for _ in 0..<turns { p = CGPoint(x: p.y, y: 1 - p.x) }
            return p
        }
        // The same corners, named from where they now are.
        let points = quad.corners
        let byTop = points.sorted { $0.y > $1.y }
        let top = byTop.prefix(2).sorted { $0.x < $1.x }, bottom = byTop.suffix(2).sorted { $0.x < $1.x }
        return Photo(image: image, quad: ScanQuad(topLeft: top[0], topRight: top[1], bottomRight: bottom[1],
                                                  bottomLeft: bottom[0]))
    }
}
#endif
