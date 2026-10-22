import Foundation

/// Where things on a PDF page are once it is shown: the page's box turned
/// by its own rotation and by the quarter turns the owner gave it, then
/// measured from 0 to 1 from the bottom left, as Vision and the covers
/// measure a picture.
enum PDFPageGeometry {
    /// An affine map, as Core Graphics writes one: x' = a x + c y + tx, y' = b x + d y + ty.
    struct Map: Equatable, Sendable {
        var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

        func apply(_ point: CGPoint) -> CGPoint {
            CGPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
        }

        /// The smallest rectangle round a rectangle mapped.
        func apply(_ rect: CGRect) -> CGRect {
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map(apply)
            let xs = corners.map(\.x), ys = corners.map(\.y)
            guard let left = xs.min(), let right = xs.max(), let bottom = ys.min(), let top = ys.max() else { return .null }
            return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        }
    }

    /// Degrees clockwise, as a page's own rotation and quarter turns add up: 0, 90, 180 or 270.
    static func rotation(page degrees: Int, turns: Int) -> Int {
        let total = degrees + turns * 90
        return ((total % 360) + 360) % 360 / 90 * 90
    }

    /// The page's size as it is shown, turned.
    static func shown(_ box: CGRect, rotation: Int) -> CGSize {
        rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// From the page's own space to the picture of it, `scale` pixels a
    /// point, its bottom left at 0: turned clockwise by `rotation`.
    static func map(box: CGRect, rotation: Int, scale s: CGFloat) -> Map {
        let x0 = box.minX, y0 = box.minY, w = box.width, h = box.height
        switch rotation {
        case 90:
            // The left edge goes to the top: (x, y) to (y, w - x).
            return Map(a: 0, b: -s, c: s, d: 0, tx: -y0 * s, ty: s * (w + x0))
        case 180:
            return Map(a: -s, b: 0, c: 0, d: -s, tx: s * (w + x0), ty: s * (h + y0))
        case 270:
            // The left edge goes to the bottom: (x, y) to (h - y, x).
            return Map(a: 0, b: s, c: -s, d: 0, tx: s * (h + y0), ty: -x0 * s)
        default:
            return Map(a: s, b: 0, c: 0, d: s, tx: -x0 * s, ty: -y0 * s)
        }
    }

    /// A rectangle on the page, in the page's own space, from 0 to 1 from
    /// the bottom left of the page as it is shown.
    static func normalized(_ rect: CGRect, box: CGRect, rotation: Int) -> CGRect {
        let size = shown(box, rotation: rotation)
        guard size.width > 0, size.height > 0 else { return .null }
        let placed = map(box: box, rotation: rotation, scale: 1).apply(rect)
        return CGRect(x: placed.minX / size.width, y: placed.minY / size.height,
                      width: placed.width / size.width, height: placed.height / size.height)
    }

    /// A rectangle from 0 to 1 from the bottom left of a picture, after the
    /// picture is turned clockwise by quarter turns.
    static func turned(_ rect: CGRect, quarters: Int) -> CGRect {
        let box = CGRect(x: 0, y: 0, width: 1, height: 1)
        return map(box: box, rotation: rotation(page: 0, turns: quarters), scale: 1).apply(rect)
    }
}

/// The words a PDF page holds as text, in lines as the covers read them,
/// and what the page is: text that can be read straight from the file is
/// exact, where reading it from the picture may misread a letter.
enum PDFTextLayer {
    /// A line of the page's text and where it is, each word with its place
    /// in the line's text, in UTF-16 units, and on the page.
    struct Line: Equatable {
        let string: String
        let box: CGRect
        let words: [(range: NSRange, box: CGRect)]

        static func == (a: Line, b: Line) -> Bool {
            a.string == b.string && a.box == b.box && a.words.count == b.words.count
                && zip(a.words, b.words).allSatisfy { $0.range == $1.range && $0.box == $1.box }
        }
    }

    /// The page's text cut into lines and words: a line ends at a line
    /// break or where its words stand far apart, a word at a space. `box` gives where each UTF-16 unit of the
    /// text is, from 0 to 1 from the bottom left, or nil where a unit has
    /// no place, as a line break has none. Words without a place are left out.
    static func lines(_ text: String, box: (Int) -> CGRect?) -> [Line] {
        let units = Array(text.utf16)
        var lines: [Line] = []
        var start = 0
        func finish(_ end: Int) {
            defer { start = end + 1 }
            guard end > start else { return }
            let piece = Array(units[start..<end])
            let string = String(decoding: piece, as: UTF16.self)
            var words: [(range: NSRange, box: CGRect)] = []
            var wordStart: Int?
            var wordBox = CGRect.null
            for offset in 0...piece.count {
                let blank = offset == piece.count || isBlank(piece[offset])
                if blank {
                    if let first = wordStart, !wordBox.isNull {
                        words.append((NSRange(location: first, length: offset - first), wordBox))
                    }
                    wordStart = nil
                    wordBox = .null
                    continue
                }
                if wordStart == nil { wordStart = offset }
                if let place = box(start + offset), place.width > 0 || place.height > 0 {
                    wordBox = wordBox.union(place)
                }
            }
            guard !words.isEmpty else { return }
            for run in columns(words) {
                let first = run[0].range.location
                let end = run[run.count - 1].range.location + run[run.count - 1].range.length
                let shown = first == 0 && end == piece.count ? string : String(decoding: piece[first..<end], as: UTF16.self)
                let placed = run.map { (range: NSRange(location: $0.range.location - first, length: $0.range.length), box: $0.box) }
                let whole = run.dropFirst().reduce(run[0].box) { $0.union($1.box) }
                lines.append(Line(string: shown, box: whole, words: placed))
            }
        }
        for (index, unit) in units.enumerated() where unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 {
            finish(index)
        }
        finish(units.count)
        return lines
    }

    /// A line's words parted where they stand far apart, as a page's
    /// columns do on one row, so each part is a line of its own, as the
    /// lines read from a picture are: a gap wider than three times the
    /// line's height parts them.
    private static func columns(_ words: [(range: NSRange, box: CGRect)]) -> [[(range: NSRange, box: CGRect)]] {
        guard words.count > 1 else { return [words] }
        let whole = words.dropFirst().reduce(words[0].box) { $0.union($1.box) }
        // A line runs across the page, or up or down it on a page turned.
        let across = whole.width >= whole.height
        let height = words.map { across ? $0.box.height : $0.box.width }.max() ?? 0
        var runs = [[words[0]]]
        for (before, word) in zip(words, words.dropFirst()) {
            let gap = across ? max(word.box.minX - before.box.maxX, before.box.minX - word.box.maxX)
                : max(word.box.minY - before.box.maxY, before.box.minY - word.box.maxY)
            if height > 0, gap > height * 3 {
                runs.append([word])
            } else {
                runs[runs.count - 1].append(word)
            }
        }
        return runs
    }

    private static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x2007 || unit == 0x202F
    }

    /// Whether the page holds text worth reading straight from the file:
    /// some letters or digits, not only a page number.
    static func holdsText(_ text: String) -> Bool {
        text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 12
    }

    /// The lines read from the page's picture that its text does not hold
    /// already: a line mostly over a line of the text is the same line, and
    /// the text's is kept, letter for letter; any other, as in a photo
    /// pasted on the page, is kept as read.
    static func added(read: [CGRect], over text: [CGRect]) -> [Int] {
        read.indices.filter { index in
            let line = read[index]
            let area = line.width * line.height
            guard area > 0 else { return false }
            let covered = text.reduce(CGFloat(0)) { sum, other in
                let shared = line.intersection(other)
                return shared.isNull ? sum : sum + shared.width * shared.height
            }
            return covered < 0.5 * area
        }
    }
}

/// What a PDF file says about itself, read from its bytes.
enum PDFFacts {
    /// Whether the bytes start as a PDF does.
    static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    /// Whether the file is signed: a signature's value names the bytes it
    /// covers, with /ByteRange, and is never packed away, so it can be
    /// found in the bytes even where the rest is.
    static func isSigned(_ data: Data) -> Bool {
        guard data.range(of: Data("/ByteRange".utf8)) != nil else { return false }
        return data.range(of: Data("/Sig".utf8)) != nil || data.range(of: Data("/adbe.pkcs7".utf8)) != nil
    }
}
