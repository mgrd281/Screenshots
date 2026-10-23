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
            // A folded sheet is made flat part by part, from where its edges bend.
            let folds = Timing.measure("folds") { self.folds(in: source, quad: quad) }
            guard let cut = straightened(source, quad: quad, folds: folds, focal: focal) else { return nil }
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

    /// What is left bent, as a curl, once the parts are laid flat: the one
    /// long line of the page that still lies in the curl is found, its own
    /// height in each column is measured, and the pixels of the curl are
    /// moved up or down by whole rows so that line lies straight again,
    /// never redrawn and never re-sampled, so no mark is blurred.
    static func uncurled(_ page: CGImage, from start: Double = 0.84) -> CGImage? {
        guard let bitmap = bitmap(page) else { return page }
        let w = bitmap.width, h = bitmap.height
        let top = Int(Double(h) * start)
        guard w > 120, h > 120, top > h / 10, h - top > h / 40 else { return page }
        let plane = bitmap.brightness
        let most = max(4, h / 300)
        // The first long line in the curl: a row most of the width is dark on.
        var line = -1
        var row = top
        while row < h - h / 30, line < 0 {
            var dark = 0
            var x = 0
            while x < w { if plane[row * w + x] < 200 { dark += 1 }; x += 1 }
            if dark > w / 2 { line = row }
            row += 1
        }
        guard line >= 0 else { return page }
        // Each column's own height of that line, near where it mostly lies.
        var raw = [Double](repeating: 0, count: w)
        for x in 0..<w {
            var bestY = line, bestValue = 256.0
            var y = max(top, line - most)
            while y <= min(h - 1, line + most) {
                let value = Double(plane[y * w + x])
                if value < bestValue { bestValue = value; bestY = y }
                y += 1
            }
            raw[x] = Double(line - bestY)
        }
        // Smoothed and kept in whole rows, so a grain never bends a line.
        var smooth = [Int](repeating: 0, count: w)
        let reach = max(2, w / 60)
        for x in 0..<w {
            var sum = 0.0, n = 0
            var k = max(0, x - reach)
            while k <= min(w - 1, x + reach) { sum += raw[k]; n += 1; k += 1 }
            smooth[x] = n > 0 ? Int((sum / Double(n)).rounded()) : 0
        }
        var out = bitmap
        bitmap.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in top..<h {
                    for x in 0..<w {
                        let fromY = min(max(y - smooth[x], top), h - 1)
                        let o = (y * w + x) * 4
                        let s = (fromY * w + x) * 4
                        dst[o] = src[s]
                        dst[o + 1] = src[s + 1]
                        dst[o + 2] = src[s + 2]
                    }
                }
            }
        }
        return image(out, gray: false)
    }

    /// A page already flat and upright, cleaned in `mode` and checked, as
    /// when only its colours change.
    static func finished(_ straight: CGImage, turns: Int, skew: Double, mode: ScanColor, photo: CGImage?) async -> Prepared? {
        // Nothing of what the sheet lay on is left along its edges.
        let cut = trimmed(straight)
        // What is left bent, as a curl, is taken out after the edges are
        // cut, so its own shift never moves the page within the cut.
        let page = uncurled(cut) ?? cut
        // Read the page before it is cleaned, so the print's own darkness is
        // measured on the text it holds; the same reading then checks the
        // result, so nothing is read twice.
        let read = Finder.lines(in: page) ?? []
        guard let cleaned = cleaned(page, mode, printBoxes: read.map(\.box)) else { return nil }
        let checked = await check(before: page, after: cleaned, mode: mode, photo: photo, reading: read)
        return Prepared(straightened: page, cleaned: cleaned, turns: turns, skew: skew, checked: checked)
    }

    /// The page cut in from its edges where anything of what it lay on shows.
    static func trimmed(_ page: CGImage) -> CGImage {
        guard let bitmap = bitmap(page) else { return page }
        let cut = ScanSheet.inset(of: bitmap)
        guard cut != (0, 0, 0, 0), let cutPage = image(ScanSheet.cropped(bitmap, cut), gray: false) else { return page }
        return cutPage
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

    /// The sheet's outline in a photo, from the document's mask: down its
    /// left and its right edge, a point for each row of the mask, in the
    /// photo's pixels from its bottom left. Nil where Vision gives no mask.
    static func outline(in photo: CGImage) -> ScanOutline? {
        let request = VNDetectDocumentSegmentationRequest()
        guard (try? VNImageRequestHandler(cgImage: photo, options: [:]).perform([request])) != nil,
              let mask = request.results?.first?.globalSegmentationMask?.pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask), row = CVPixelBufferGetBytesPerRow(mask)
        func value(_ x: Int, _ y: Int) -> Float { base.advanced(by: y * row + x * 4).assumingMemoryBound(to: Float.self).pointee }
        let sx = CGFloat(photo.width) / CGFloat(w), sy = CGFloat(photo.height) / CGFloat(h)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for y in 0..<h {
            // The sheet's first and last pixel on the row, each to where the mask crosses a half.
            var first: CGFloat?, last: CGFloat?
            for x in 1..<w where value(x - 1, y) < 0.5 && value(x, y) >= 0.5 {
                let a = value(x - 1, y), b = value(x, y)
                first = CGFloat(x - 1) + CGFloat((0.5 - a) / max(1e-6, b - a)) + 0.5
                break
            }
            for x in stride(from: w - 1, to: 0, by: -1) where value(x, y) < 0.5 && value(x - 1, y) >= 0.5 {
                let a = value(x - 1, y), b = value(x, y)
                last = CGFloat(x - 1) + CGFloat((a - 0.5) / max(1e-6, a - b)) + 0.5
                break
            }
            guard let first, let last, last - first > CGFloat(w) / 8 else { continue }
            // The mask's rows go down from the top; the photo's pixels up from the bottom.
            let up = CGFloat(photo.height) - (CGFloat(y) + 0.5) * sy
            left.append(CGPoint(x: first * sx, y: up))
            right.append(CGPoint(x: last * sx, y: up))
        }
        return left.count >= 24 ? ScanOutline(left: left, right: right) : nil
    }

    /// The folds across the page in a photo, as both its edges bend, each
    /// from 0 to 1 from the bottom left, as the corners are; none for a
    /// page lying flat.
    static func folds(in photo: CGImage, quad: ScanQuad) -> [(left: CGPoint, right: CGPoint)] {
        guard let coarse = outline(in: photo), let pixels = bitmap(photo) else { return [] }
        let outline = ScanSheet.refined(coarse, in: pixels)
        let size = CGSize(width: photo.width, height: photo.height)
        let corners = quad.pixels(in: size)
        var found = ScanSheet.folds(ScanSheet.folds(of: outline), within: corners)
        // A sheet lying nearly flat hardly bends its outline, but the band
        // where its paper turns still shows; those folds are taken too,
        // where the outline shows none at that height.
        for band in ScanSheet.bands(of: pixels, within: outline) {
            let along = Double((band.left.y + band.right.y) / 2) / Double(size.height)
            let taken = found.contains { fold in
                abs(Double((fold.left.y + fold.right.y) / 2) / Double(size.height) - along) < 0.04
            }
            // The band's ends are points of the outline itself, so lie on the
            // sheet already; only one the outline does not show is added.
            if !taken { found.append(band) }
        }
        // Each end on the page's own side: the parts they make are cut by
        // the page's sides exactly, whole and to the page's own shape.
        return ScanSheet.folds(ScanSheet.seated(found, on: corners), within: corners)
            // From the top down, as the parts are laid: `panels` takes the
            // folds in this order.
            .sorted { ($0.left.y + $0.right.y) > ($1.left.y + $1.right.y) }
            .map { fold in
                (CGPoint(x: fold.left.x / size.width, y: fold.left.y / size.height),
                 CGPoint(x: fold.right.x / size.width, y: fold.right.y / size.height))
            }
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
        straightened(photo, quad: quad, folds: [], focal: focal, longest: longest)
    }

    /// The page made flat part by part where it is folded: each part
    /// between two folds cut by its own four corners and made flat with its
    /// own perspective, all as wide as the page and as tall as each part's
    /// own shape says, then laid one under the next, so every fold is one
    /// row and a line crossing it goes on without a step. The page's shape
    /// is the parts' together, A4 or Letter exactly where it is close. Only
    /// pixels moved, as for a flat page.
    static func straightened(_ photo: CGImage, quad: ScanQuad, folds: [(left: CGPoint, right: CGPoint)], focal: Double? = nil,
                             longest: Int = 4096) -> CGImage? {
        let panels = ScanSheet.panels(of: quad.clamped, folds: folds)
        guard panels.count > 1 else { return flat(photo, quad: quad, focal: focal, longest: longest) }
        let size = CGSize(width: photo.width, height: photo.height)
        // One lens for the page and all its parts: the page's own corners
        // tell it, where the photo does not.
        let lens = focal ?? ScanGeometry.focal(of: quad.clamped, in: size)
        // Each part's height for a width of 1, from its own shape.
        let parts = panels.map { 1 / max(ScanGeometry.aspect(of: $0, in: size, focal: lens), 1e-6) }
        // The page's own shape, from its four corners as for a page lying
        // flat: a part's own estimate is poor where a part is short.
        let aspect = ScanGeometry.snapped(ScanGeometry.aspect(of: quad.clamped, in: size, focal: lens))
        // As many pixels as the photo gives the page: its widest part across, its parts' sides down.
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(b.x - a.x, b.y - a.y)) }
        let pixels = panels.map { $0.pixels(in: size) }
        let across = pixels.map { max(distance($0.topLeft, $0.topRight), distance($0.bottomLeft, $0.bottomRight)) }.max() ?? 1
        let down = pixels.map { max(distance($0.topLeft, $0.bottomLeft), distance($0.topRight, $0.bottomRight)) }.reduce(0, +)
        var width = across, height = across / aspect
        if height < down {
            height = down
            width = down * aspect
        }
        let shrink = min(1, Double(longest) / max(width, height))
        let pageWidth = max(1, Int((width * shrink).rounded())), pageHeight = max(1, Int((height * shrink).rounded()))
        // Each part's rows, in proportion, the last taking what rounding leaves.
        let total = parts.reduce(0, +)
        var bounds = [0]
        for part in parts.dropLast() { bounds.append(bounds.last! + Int((Double(pageHeight) * part / total).rounded())) }
        bounds.append(pageHeight)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pageWidth, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        for (index, panel) in panels.enumerated() {
            let rows = bounds[index + 1] - bounds[index]
            guard rows > 0 else { return nil }
            // Each part reaches a few rows past each fold, cut away as it is
            // laid, so its edge, which the cut softens, never shows at a fold.
            let pad = 4
            let above = index > 0 ? pad : 0, below = index < panels.count - 1 ? pad : 0
            let corners = Self.extended(panel.pixels(in: size), rows: rows, above: above, below: below)
            guard let part = cut(photo, corners: corners, width: pageWidth, height: rows + above + below) else { return nil }
            // Core Graphics counts up from the bottom; the first part is the top.
            let place = CGRect(x: 0, y: pageHeight - bounds[index + 1], width: pageWidth, height: rows)
            context.saveGState()
            context.clip(to: place)
            context.draw(part, in: CGRect(x: 0, y: place.minY - CGFloat(below), width: CGFloat(pageWidth),
                                          height: CGFloat(rows + above + below)))
            context.restoreGState()
        }
        guard let laid = context.makeImage() else { return nil }
        // The parts are laid from corners a few pixels from where the sheet's
        // truly are; the print across each fold says by how much, and each
        // part below is moved that much, so no line steps at a fold.
        return aligned(laid, at: bounds.dropFirst().dropLast()) ?? laid
    }

    /// The page's parts moved to meet at each fold, as the print across the
    /// fold says they should: the rows just below it against the rows just
    /// above it, sideways and up or down, at points across the page, each a
    /// straight line, so a part is moved as a whole and nothing in it bends.
    static func aligned(_ page: CGImage, at seams: [Int]) -> CGImage? {
        guard !seams.isEmpty, let bitmap = bitmap(page) else { return page }
        let w = bitmap.width, h = bitmap.height, plane = bitmap.brightness
        guard w > 200, h > 200 else { return page }
        var shifts: [(seam: Int, across: (slope: Double, offset: Double), up: (slope: Double, offset: Double))] = []
        for seam in seams where seam > 80 && seam < h - 80 {
            guard let across = shift(of: plane, w, h, seam: seam, sideways: true),
                  let up = shift(of: plane, w, h, seam: seam, sideways: false) else { continue }
            shifts.append((seam, across, up))
        }
        guard !shifts.isEmpty else { return page }
        // Each row's part carries the shifts of every fold above it.
        var acrossAt = [(slope: Double, offset: Double)](repeating: (0, 0), count: h)
        var upAt = acrossAt
        var across = (slope: 0.0, offset: 0.0), up = (slope: 0.0, offset: 0.0), next = 0
        for y in 0..<h {
            while next < shifts.count, y >= shifts[next].seam {
                across.slope += shifts[next].across.slope
                across.offset += shifts[next].across.offset
                up.slope += shifts[next].up.slope
                up.offset += shifts[next].up.offset
                next += 1
            }
            acrossAt[y] = across
            upAt[y] = up
        }
        var out = bitmap
        bitmap.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in shifts[0].seam..<h {
                    let fromY = Double(y) + upAt[y].offset + upAt[y].slope * Double(y)
                    let y0 = min(max(Int(fromY.rounded(.down)), 0), h - 1), y1 = min(y0 + 1, h - 1)
                    let ty = min(max(fromY - Double(y0), 0), 1)
                    for x in 0..<w {
                        let fromX = Double(x) + acrossAt[y].offset + acrossAt[y].slope * Double(x)
                        let x0 = min(max(Int(fromX.rounded(.down)), 0), w - 1), x1 = min(x0 + 1, w - 1)
                        let tx = min(max(fromX - Double(x0), 0), 1)
                        let o = (y * w + x) * 4
                        for k in 0..<3 {
                            let top = Double(src[(y0 * w + x0) * 4 + k]) * (1 - tx) + Double(src[(y0 * w + x1) * 4 + k]) * tx
                            let low = Double(src[(y1 * w + x0) * 4 + k]) * (1 - tx) + Double(src[(y1 * w + x1) * 4 + k]) * tx
                            dst[o + k] = UInt8(min(255, max(0, top * (1 - ty) + low * ty + 0.5)))
                        }
                    }
                }
            }
        }
        return image(out, gray: false)
    }

    /// The shift that brings the edges of the print just below a fold into
    /// line with those just above it, as a line across the page: sideways,
    /// or up and down. Nil where the print there says too little to tell.
    static func shift(of plane: [UInt8], _ w: Int, _ h: Int, seam: Int,
                              sideways: Bool) -> (slope: Double, offset: Double)? {
        let band = 44, gap = 6, reach = 9
        let above = (seam - band)..<(seam - gap), below = (seam + gap)..<(seam + band)
        guard above.lowerBound > 2, below.upperBound < h - 2 else { return nil }
        var found: [(at: Double, by: Int, weight: Double)] = []
        let chunks = 9
        for chunk in 0..<chunks {
            let x0 = w / 10 + (w * 4 / 5) * chunk / chunks
            let x1 = w / 10 + (w * 4 / 5) * (chunk + 1) / chunks
            guard x1 - x0 > 40 else { continue }
            let a = profile(plane, w, h, rows: above, columns: x0..<x1, sideways: sideways)
            let b = profile(plane, w, h, rows: below, columns: x0..<x1, sideways: sideways)
            guard a.reduce(0, +) + b.reduce(0, +) > 2000, let best = alignment(a, b, reach: reach),
                  best.gain >= 1.1 else { continue }
            found.append((Double(x0 + x1) / 2, best.shift, best.gain - 1))
        }
        guard found.count >= 2 else { return nil }
        // A line through the shifts found, each weighed by how clearly it
        // was seen, so the part moves as a whole.
        let total = found.map(\.weight).reduce(0, +)
        let mx = found.map { $0.at * $0.weight }.reduce(0, +) / total
        let my = found.map { Double($0.by) * $0.weight }.reduce(0, +) / total
        let across = found.map { ($0.at - mx) * (Double($0.by) - my) * $0.weight }.reduce(0, +)
        let down = found.map { ($0.at - mx) * ($0.at - mx) * $0.weight }.reduce(0, +)
        let slope = down > 1e-9 ? across / down : 0
        return (slope, my - slope * mx)
    }

    /// Where the edges stand across a band: for each column of it, sideways,
    /// or each row of it, how much the brightness turns there. Only turns
    /// well above the paper's grain count, so print and rules tell, and the
    /// grain does not.
    private static func profile(_ plane: [UInt8], _ w: Int, _ h: Int, rows: Range<Int>, columns: Range<Int>,
                                sideways: Bool) -> [Double] {
        let least = 60.0
        func turn(_ value: Int) -> Double { max(0, Double(value) - least) }
        if sideways {
            return columns.map { x in
                rows.reduce(0.0) { $0 + turn(abs(Int(plane[$1 * w + x + 1]) - Int(plane[$1 * w + x - 1]))) }
            }
        }
        return rows.map { y in
            columns.reduce(0.0) { $0 + turn(abs(Int(plane[y * w + $1]) - Int(plane[min(h - 1, y + 2) * w + $1]))) }
        }
    }

    /// How far `b` stands from `a`, within `reach`, where the two are most
    /// alike, and how much better that is than no shift at all.
    private static func alignment(_ a: [Double], _ b: [Double], reach: Int) -> (shift: Int, gain: Double)? {
        var best = 0, bestScore = 0.0, atZero = 0.0
        for d in -reach...reach {
            var score = 0.0, count = 0
            for i in a.indices {
                let j = i + d
                guard j >= 0, j < b.count else { continue }
                score += a[i] * b[j]
                count += 1
            }
            guard count >= a.count / 2 else { continue }
            let normal = score / Double(count)
            if d == 0 { atZero = normal }
            if normal > bestScore { bestScore = normal; best = d }
        }
        guard bestScore > 0 else { return nil }
        return (best, bestScore / max(1e-9, atZero))
    }

    /// A part's corners moved up its sides by `above` of its `rows`, and
    /// down them by `below`, as the part would go on past a fold.
    private static func extended(_ quad: ScanQuad, rows: Int, above: Int, below: Int) -> ScanQuad {
        func moved(_ point: CGPoint, away from: CGPoint, by share: CGFloat) -> CGPoint {
            CGPoint(x: point.x + (point.x - from.x) * share, y: point.y + (point.y - from.y) * share)
        }
        let up = CGFloat(above) / CGFloat(max(1, rows)), down = CGFloat(below) / CGFloat(max(1, rows))
        return ScanQuad(topLeft: moved(quad.topLeft, away: quad.bottomLeft, by: up),
                        topRight: moved(quad.topRight, away: quad.bottomRight, by: up),
                        bottomRight: moved(quad.bottomRight, away: quad.topRight, by: down),
                        bottomLeft: moved(quad.bottomLeft, away: quad.topLeft, by: down))
    }

    /// The part of a photo inside four corners, in its pixels from the
    /// bottom left, made flat at the size asked for.
    private static func cut(_ photo: CGImage, corners: ScanQuad, width: Int, height: Int) -> CGImage? {
        guard let perspective = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        perspective.setValue(CIImage(cgImage: photo), forKey: kCIInputImageKey)
        perspective.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
        perspective.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")
        perspective.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")
        guard let flat = perspective.outputImage, flat.extent.width >= 1, flat.extent.height >= 1 else { return nil }
        let origin = flat.transformed(by: CGAffineTransform(translationX: -flat.extent.minX, y: -flat.extent.minY))
        let scale = CGFloat(height) / flat.extent.height
        let stretch = (CGFloat(width) / flat.extent.width) / scale
        guard let resize = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        resize.setValue(origin, forKey: kCIInputImageKey)
        resize.setValue(scale, forKey: kCIInputScaleKey)
        resize.setValue(stretch, forKey: kCIInputAspectRatioKey)
        guard let sized = resize.outputImage else { return nil }
        return render(sized, width: width, height: height)
    }

    /// A page lying flat, cut by its four corners.
    private static func flat(_ photo: CGImage, quad: ScanQuad, focal: Double?, longest: Int) -> CGImage? {
        let size = CGSize(width: photo.width, height: photo.height)
        let aspect = ScanGeometry.snapped(ScanGeometry.aspect(of: quad, in: size, focal: focal))
        let target = ScanGeometry.size(of: quad, in: size, aspect: aspect, longest: longest)
        return cut(photo, corners: quad.clamped.pixels(in: size), width: target.width, height: target.height)
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
    static func cleaned(_ page: CGImage, _ mode: ScanColor, printBoxes: [CGRect] = []) -> CGImage? {
        guard let bitmap = bitmap(page) else { return nil }
        return image(edgeCleaned(ScanClean.clean(bitmap, mode, printBoxes: printBoxes)), gray: mode.isGray)
    }

    /// Nothing of what the sheet lay on stays dark along the page's own
    /// edge: the outermost band, where a page keeps its margin, is made
    /// white. A dark page — a screen photographed — keeps its own edges.
    static func edgeCleaned(_ bitmap: ScanBitmap) -> ScanBitmap {
        let w = bitmap.width, h = bitmap.height
        guard w > 80, h > 80 else { return bitmap }
        var column: [UInt8] = []
        let step = max(1, h / 80)
        var y = 0
        while y < h { column.append(bitmap.brightness(x: w / 2, y: y)); y += step }
        column.sort()
        guard column[column.count / 2] > 128 else { return bitmap }
        let bandX = max(2, w / 80), bandY = max(2, h / 80)
        var out = bitmap
        for y in 0..<h {
            for x in 0..<w where x < bandX || x >= w - bandX || y < bandY || y >= h - bandY {
                let i = (y * w + x) * 4
                out.pixels[i] = 255
                out.pixels[i + 1] = 255
                out.pixels[i + 2] = 255
            }
        }
        return out
    }

    // MARK: Checking

    /// What is wrong with a page: how it was taken, measured on `before`,
    /// the page straightened, before cleaning; a smudged lens, from the
    /// photo where there is one, from iOS 26; and whether `after`, the
    /// cleaned page, reads every number and line `before` does.
    static func check(before: CGImage, after: CGImage, mode: ScanColor, photo: CGImage?,
                      reading known: [Finder.TextLine]? = nil) async -> Checked {
        var issues: [ScanIssue] = []
        if let measured = smaller(before, longest: 2400).flatMap(bitmap) {
            issues += ScanQuality.issues(in: measured, dpi: ScanGeometry.dpi(width: before.width, height: before.height))
        }
        if await smudged(photo ?? before) { issues.append(ScanIssue(.smudge)) }
        let read = known ?? Finder.lines(in: before) ?? []
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
