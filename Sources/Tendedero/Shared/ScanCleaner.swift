#if canImport(Vision) && canImport(CoreImage)
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The steps a scanned page takes before it is covered, with Apple's
/// frameworks around the engine: the page found in a photo and made flat,
/// turned the right way up and level, cleaned (`ScanClean`), and checked:
/// how it was taken (`ScanQuality`), a smudged lens, and whether its text
/// reads as much after cleaning as before (`ScanContent`). Then what
/// leaves: PNGs, and the PDF (`ScanPDF`). Nothing here is drawn onto a
/// page or guessed: pixels are moved by geometry and made lighter or
/// darker, never made up.
enum ScanCleaner {
    /// A page made ready to cover.
    struct Prepared {
        /// The page flat, upright and level, before its light is cleaned:
        /// what Before shows.
        let straightened: CGImage
        /// The page cleaned in the colours asked for: what is covered and leaves.
        let cleaned: CGImage
        /// Quarter turns clockwise, and the lean taken away, in radians.
        let turns: Int
        let skew: Double
        let checked: Checked
    }

    /// What the checks found.
    struct Checked {
        /// Most important first (`ScanIssue.ordered`).
        let issues: [ScanIssue]
        /// Whether every number read before cleaning was read after, and
        /// the lines were too; nil where no text was read before.
        let textKept: Bool?
        /// The cleaned page as it was read, for the PDF's text.
        let reading: [Finder.TextLine]
    }

    /// The page cut from its picture by `quad` (none for a page as the
    /// camera gave it), turned (`way`, or as it reads best when nil),
    /// cleaned in `mode` and checked. Nil when the picture could not be read.
    static func prepare(_ source: CGImage, quad: ScanQuad?, way: (turns: Int, skew: Double?)? = nil, focal: Double? = nil,
                        mode: ScanColor) async -> Prepared? {
        guard let straight = flattened(source, quad: quad, way: way, focal: focal) else { return nil }
        return await finished(straight.image, turns: straight.turns, skew: straight.skew, mode: mode,
                              photo: quad == nil ? nil : source)
    }

    /// The page cut from its picture, flat, upright and level, and how it
    /// was turned: as `way` says, its lean measured again where it gives
    /// none, as for a page cut again; as it reads best without one.
    static func flattened(_ source: CGImage, quad: ScanQuad?, way: (turns: Int, skew: Double?)? = nil,
                          focal: Double? = nil) -> (image: CGImage, turns: Int, skew: Double)? {
        let flat: CGImage
        if let quad {
            guard let cut = straightened(source, quad: quad, focal: focal) else { return nil }
            flat = cut
        } else {
            flat = source
        }
        let found: (turns: Int, skew: Double)
        if let way, let skew = way.skew {
            found = (way.turns, skew)
        } else {
            let turns = way?.turns ?? upright(flat)
            guard let standing = turned(flat, quarterTurns: turns, skew: 0) else { return nil }
            found = (turns, lean(of: standing))
        }
        guard let straight = turned(flat, quarterTurns: found.turns, skew: found.skew) else { return nil }
        return (straight, found.turns, found.skew)
    }

    /// A page already flat and upright, cleaned in `mode` and checked, as
    /// when only its colours change.
    static func finished(_ straight: CGImage, turns: Int, skew: Double, mode: ScanColor, photo: CGImage?) async -> Prepared? {
        guard let cleaned = cleaned(straight, mode) else { return nil }
        let checked = await check(before: straight, after: cleaned, mode: mode, photo: photo)
        return Prepared(straightened: straight, cleaned: cleaned, turns: turns, skew: skew, checked: checked)
    }

    // MARK: Finding the page

    /// Where a page is in a photo, and how sure Vision is of it, from 0 to
    /// 1; nil where it finds none.
    static func page(in photo: CGImage) -> (quad: ScanQuad, confidence: Float)? {
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try VNImageRequestHandler(cgImage: photo, options: [:]).perform([request])
        } catch {
            log.error("Could not find the page: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let found = request.results?.first else { return nil }
        let quad = ScanQuad(topLeft: found.topLeft, topRight: found.topRight, bottomRight: found.bottomRight,
                            bottomLeft: found.bottomLeft)
        return quad.isUsable ? (quad, found.confidence) : nil
    }

    /// The lens's focal length in pixels, from the photo's own notes, for a
    /// page's true shape (`ScanGeometry.aspect`); nil where it does not say.
    static func focalLength(of data: Data, width: Int, height: Int) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let equivalent = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double, equivalent > 0 else { return nil }
        // 35 mm film's diagonal is 43.27 mm.
        return equivalent / 43.27 * Double(hypot(CGFloat(width), CGFloat(height)))
    }

    /// The page cut from the photo by its corners and made flat, of its true
    /// shape (A4 or Letter exactly where it is close), with as many pixels
    /// as the photo gives it and no more.
    static func straightened(_ photo: CGImage, quad: ScanQuad, focal: Double? = nil, longest: Int = 4096) -> CGImage? {
        let size = CGSize(width: photo.width, height: photo.height)
        let aspect = ScanGeometry.snapped(ScanGeometry.aspect(of: quad, in: size, focal: focal))
        let target = ScanGeometry.size(of: quad, in: size, aspect: aspect, longest: longest)
        let corners = quad.clamped.pixels(in: size)
        guard let perspective = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        perspective.setValue(CIImage(cgImage: photo), forKey: kCIInputImageKey)
        perspective.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
        perspective.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")
        guard let flat = perspective.outputImage, flat.extent.width >= 1, flat.extent.height >= 1 else { return nil }
        let origin = flat.transformed(by: CGAffineTransform(translationX: -flat.extent.minX, y: -flat.extent.minY))
        let scale = CGFloat(target.height) / flat.extent.height
        let stretch = (CGFloat(target.width) / flat.extent.width) / scale
        guard let resize = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        resize.setValue(origin, forKey: kCIInputImageKey)
        resize.setValue(scale, forKey: kCIInputScaleKey)
        resize.setValue(stretch, forKey: kCIInputAspectRatioKey)
        guard let sized = resize.outputImage else { return nil }
        return render(sized, width: target.width, height: target.height)
    }

    // MARK: Upright and level

    /// Which way up a page reads, in quarter turns clockwise, from a quick
    /// reading at a smaller size: upright first, and the other ways only
    /// when upright reads little.
    static func upright(_ page: CGImage) -> Int {
        guard let small = smaller(page, longest: 1400) else { return 0 }
        let ways: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        var scores = [Double](repeating: 0, count: 4)
        for turns in 0..<4 {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: small, orientation: ways[turns], options: [:]).perform([request])
            let found = request.results ?? []
            scores[turns] = found.reduce(0) { sum, line in
                guard let best = line.topCandidates(1).first else { return sum }
                return sum + Double(best.confidence) * Double(best.string.filter(\.isLetter).count)
            }
            // Upright and read well: no need to read it the other ways.
            if turns == 0, scores[0] >= 60, found.count >= 4 { break }
        }
        return ScanGeometry.upright(scores)
    }

    /// How far a page's lines lean, in radians, as it stands: from where
    /// its print lies (`ScanGeometry.lean`), with no reading needed.
    static func lean(of page: CGImage) -> Double {
        guard let small = smaller(page, longest: 1200), let bitmap = bitmap(small) else { return 0 }
        return ScanGeometry.lean(of: bitmap)
    }

    /// The page turned clockwise by quarter turns, then by `skew` back to
    /// level about its middle, the same size, its corners filled with its
    /// paper's colour. The page itself where there is nothing to turn.
    static func turned(_ page: CGImage, quarterTurns: Int, skew: Double) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 || skew != 0 else { return page }
        let width = turns % 2 == 0 ? page.width : page.height
        let height = turns % 2 == 0 ? page.height : page.width
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let paper = paperColor(of: page)
        context.setFillColor(CGColor(red: paper.red, green: paper.green, blue: paper.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // Clockwise is negative here, where up is up.
        context.rotate(by: -CGFloat(turns) * .pi / 2 - CGFloat(skew))
        context.draw(page, in: CGRect(x: -CGFloat(page.width) / 2, y: -CGFloat(page.height) / 2,
                                      width: CGFloat(page.width), height: CGFloat(page.height)))
        return context.makeImage()
    }

    /// The colour along a page's edges, as its paper is there.
    static func paperColor(of page: CGImage) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let small = smaller(page, longest: 200), let bitmap = bitmap(small) else { return (1, 1, 1) }
        var reds: [UInt8] = [], greens: [UInt8] = [], blues: [UInt8] = []
        for x in 0..<bitmap.width {
            for y in [0, bitmap.height - 1] {
                let color = bitmap.color(x: x, y: y)
                reds.append(color.red)
                greens.append(color.green)
                blues.append(color.blue)
            }
        }
        for y in 0..<bitmap.height {
            for x in [0, bitmap.width - 1] {
                let color = bitmap.color(x: x, y: y)
                reds.append(color.red)
                greens.append(color.green)
                blues.append(color.blue)
            }
        }
        func middle(_ values: [UInt8]) -> CGFloat { CGFloat(values.sorted()[values.count / 2]) / 255 }
        return (middle(reds), middle(greens), middle(blues))
    }

    // MARK: Cleaning

    /// The page cleaned in the colours asked for (`ScanClean`), in greys
    /// with one channel where they are grey.
    static func cleaned(_ page: CGImage, _ mode: ScanColor) -> CGImage? {
        guard let bitmap = bitmap(page) else { return nil }
        return image(ScanClean.clean(bitmap, mode), gray: mode.isGray)
    }

    // MARK: Checking

    /// What is wrong with a page: how it was taken, measured on `before`,
    /// the page straightened, before cleaning; a smudged lens, from the
    /// photo where there is one, from iOS 26; and whether `after`, the
    /// cleaned page, reads every number and line `before` does.
    static func check(before: CGImage, after: CGImage, mode: ScanColor, photo: CGImage?) async -> Checked {
        var issues: [ScanIssue] = []
        if let measured = smaller(before, longest: 2400).flatMap(bitmap) {
            issues += ScanQuality.issues(in: measured, dpi: ScanGeometry.dpi(width: before.width, height: before.height))
        }
        if await smudged(photo ?? before) { issues.append(ScanIssue(.smudge)) }
        let read = Finder.lines(in: before) ?? []
        let reading = Finder.reading(of: after) ?? []
        let asLines = { (lines: [Finder.TextLine]) -> [ScanContent.Line] in
            lines.map { ScanContent.Line(text: $0.string, box: $0.box) }
        }
        let readBefore = asLines(read)
        var kept: Bool?
        if readBefore.contains(where: { ScanContent.letters(in: $0.text) >= ScanContent.shortest }) {
            let lost = ScanContent.lost(before: readBefore, after: asLines(reading))
            issues += lost.map { ScanIssue(.lessText, area: $0) }
            kept = lost.isEmpty
        }
        return Checked(issues: ScanIssue.ordered(issues), textKept: kept, reading: reading)
    }

    /// Whether the camera's lens looks smudged in a picture, as Vision tells
    /// from iOS 26 and macOS 26 on: only when it is quite sure, as Apple
    /// suggests, since a blurred subject can look smudged too.
    static func smudged(_ picture: CGImage) async -> Bool {
        if #available(iOS 26, macOS 26, *) {
            guard let observation = try? await DetectLensSmudgeRequest().perform(on: picture, orientation: nil)
            else { return false }
            return observation.confidence >= 0.9
        }
        return false
    }

    // MARK: Leaving

    /// The words read on a page for the PDF's text, each with a space after
    /// it when another follows on its line, none inside `hidden`: the
    /// covered places, from 0 to 1 from the bottom left.
    static func words(in reading: [Finder.TextLine], hiding hidden: [CGRect] = []) -> [ScanPDF.Word] {
        reading.flatMap { line -> [ScanPDF.Word] in
            let words = line.words.compactMap { word -> (text: String, box: CGRect)? in
                guard let range = Range(word.range, in: line.string) else { return nil }
                let covered = hidden.contains { place in
                    let shared = place.intersection(word.box)
                    return !shared.isNull && shared.width * shared.height > 0.05 * word.box.width * word.box.height
                }
                return covered ? nil : (String(line.string[range]), word.box)
            }
            return words.enumerated().map { index, word in
                ScanPDF.Word(text: index < words.count - 1 ? word.text + " " : word.text, box: word.box)
            }
        }
    }

    /// A page as the PDF holds it: drawn larger or smaller first to about
    /// 300 dots an inch (`ScanGeometry.printScale`), and in greys when they
    /// are asked for, as a covered page, drawn in colour, is not yet;
    /// colour and greys as a JPEG at 0.9 without what it says about itself,
    /// black and white as one bit a pixel. Nil when it could not be made.
    static func pdfPage(_ page: CGImage, mode: ScanColor, words: [ScanPDF.Word]) -> ScanPDF.Page? {
        let scale = ScanGeometry.printScale(width: page.width, height: page.height)
        let width = max(1, Int((Double(page.width) * scale).rounded()))
        let height = max(1, Int((Double(page.height) * scale).rounded()))
        let inColor = mode.isGray && page.colorSpace?.model != .monochrome
        guard let printed = scale == 1 && !inColor ? page : resized(page, width: width, height: height, gray: mode.isGray)
        else { return nil }
        if mode == .blackAndWhite {
            guard let bitmap = bitmap(printed) else { return nil }
            let bits = ScanPDF.bits(from: bitmap.brightness, width: bitmap.width, height: bitmap.height)
            return ScanPDF.Page(picture: .bits(bits, width: bitmap.width, height: bitmap.height), words: words)
        }
        guard let jpeg = jpeg(printed, quality: 0.9) else { return nil }
        // The PDF says greys only where the JPEG holds them.
        return ScanPDF.Page(picture: .jpeg(ScanPDF.stripped(jpeg: jpeg), width: printed.width, height: printed.height,
                                           gray: printed.colorSpace?.model == .monochrome), words: words)
    }

    /// A JPEG of a picture, with nothing but the picture asked for.
    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Pixels

    /// A picture's pixels, drawn in sRGB on white, rows from the top.
    static func bitmap(_ image: CGImage) -> ScanBitmap? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ScanBitmap(width: width, height: height, pixels: pixels) : nil
    }

    /// The pixels as a picture: in sRGB colour, or in greys, one channel.
    static func image(_ bitmap: ScanBitmap, gray: Bool) -> CGImage? {
        let data: Data
        let space: CGColorSpace?
        let bytesPerPixel: Int
        let info: CGBitmapInfo
        if gray {
            data = Data(bitmap.brightness)
            space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            bytesPerPixel = 1
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        } else {
            data = Data(bitmap.pixels)
            space = CGColorSpace(name: CGColorSpace.sRGB)
            bytesPerPixel = 4
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let space, let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 8 * bytesPerPixel,
                       bytesPerRow: bitmap.width * bytesPerPixel, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The picture no larger than `longest` pixels on its longer side.
    static func smaller(_ image: CGImage, longest: Int) -> CGImage? {
        let side = max(image.width, image.height)
        guard side > longest else { return image }
        let scale = Double(longest) / Double(side)
        return resized(image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)),
                       gray: false)
    }

    /// The picture drawn at another size, smoothly, on white.
    static func resized(_ image: CGImage, width: Int, height: Int, gray: Bool) -> CGImage? {
        let space = gray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) : CGColorSpace(name: CGColorSpace.sRGB)
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let space, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        context.setFillColor(gray ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// One context for Core Image, made once: they are slow to make and
    /// safe to share.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private static func render(_ image: CIImage, width: Int, height: Int) -> CGImage? {
        context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
#endif
