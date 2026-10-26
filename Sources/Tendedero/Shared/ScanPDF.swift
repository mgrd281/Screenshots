import Foundation

/// Scanned pages as one PDF to send or keep: each page a picture on an A4
/// page (`ScanGeometry.layout`), or on a page of its own size, with, where asked, the words read on it laid
/// invisibly over it in reading order, so they can be found and copied; and
/// nothing said of who made it but "Snapfly", no title, author, dates or
/// other metadata. It is written here byte by byte, so nothing else is added.
///
/// The words are set in `ScanFont`, a font of one empty glyph, each
/// character by its UTF-16 unit, with a map back to the characters, so they
/// are found in every script: German, Turkish, Arabic, Chinese alike, a
/// right-to-left word in the order it stands from the left (`visual`). A word
/// with a character beyond those units (an emoji) is left out of the text,
/// never written changed, and stays in the picture.
enum ScanPDF {
    struct Page: Equatable {
        enum Picture: Equatable {
            /// A JPEG, in colour or in greys, with no metadata in it (`stripped`).
            case jpeg(Data, width: Int, height: Int, gray: Bool)
            /// One bit a pixel, rows from the top, each row whole bytes, 1 for white (`bits`).
            case bits(Data, width: Int, height: Int)

            var size: (width: Int, height: Int) {
                switch self {
                case .jpeg(_, let width, let height, _), .bits(_, let width, let height): (width, height)
                }
            }
        }

        var picture: Picture
        /// Words laid invisibly over the picture, in reading order.
        var words: [Word] = []
        /// The page's size and where the picture goes on it; nil for an A4
        /// page laid out as a scanned page is (`ScanGeometry.layout`).
        var frame: Frame? = nil
    }

    /// A page's size and the picture's place on it, in points from the bottom left.
    struct Frame: Equatable, Sendable {
        var page: CGSize
        var picture: CGRect
    }

    /// A word read on a page, and where.
    struct Word: Equatable, Sendable {
        /// With a space after it when another word follows on its line.
        let text: String
        /// From 0 to 1 from the bottom left of the picture.
        let box: CGRect
    }

    /// One PDF of the pages, in their order; nil without pages.
    static func make(_ pages: [Page]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let hasText = pages.contains { page in page.words.contains { units($0.text) != nil } }
        // 1 the catalogue, 2 the pages, 3 what says who made it; with words,
        // 4 to 9 their font; then each page, its contents and its picture.
        let first = hasText ? 10 : 4
        var file = Writer(objects: first + pages.count * 3)
        file.add(1, "<< /Type /Catalog /Pages 2 0 R >>")
        let kids = pages.indices.map { "\(first + $0 * 3) 0 R" }.joined(separator: " ")
        file.add(2, "<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
        file.add(3, "<< /Producer (Snapfly) >>")
        if hasText { addFont(to: &file) }
        for (index, page) in pages.enumerated() {
            let number = first + index * 3
            let size = page.picture.size
            let layout = page.frame.map { (page: $0.page, picture: $0.picture) }
                ?? ScanGeometry.layout(width: size.width, height: size.height)
            let font = hasText ? " /Font << /F1 4 0 R >>" : ""
            file.add(number, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(text(layout.page.width)) "
                + "\(text(layout.page.height))] /Resources << /XObject << /Im0 \(number + 2) 0 R >>\(font) >> "
                + "/Contents \(number + 1) 0 R >>")
            let contents = Data(drawing(page, on: layout.picture).utf8)
            if let packed = zlib(contents) {
                file.add(number + 1, stream: "/Filter /FlateDecode", packed)
            } else {
                file.add(number + 1, stream: "", contents)
            }
            switch page.picture {
            case .jpeg(let data, let width, let height, let gray):
                file.add(number + 2, stream: "/Type /XObject /Subtype /Image /Width \(width) /Height \(height) "
                    + "/ColorSpace /\(gray ? "DeviceGray" : "DeviceRGB") /BitsPerComponent 8 /Filter /DCTDecode", data)
            case .bits(let data, let width, let height):
                let head = "/Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceGray "
                    + "/BitsPerComponent 1"
                if let packed = zlib(data) {
                    file.add(number + 2, stream: head + " /Filter /FlateDecode", packed)
                } else {
                    file.add(number + 2, stream: head, data)
                }
            }
        }
        return file.finished()
    }

    /// The words' font as objects 4 to 9: the font, its glyphs' font with
    /// every code its own UTF-16 unit, the map back to the characters, the
    /// font's description, which glyph each code is drawn with (the one
    /// empty glyph), and the font file itself (`ScanFont`).
    private static func addFont(to file: inout Writer) {
        let name = ScanFont.name
        file.add(4, "<< /Type /Font /Subtype /Type0 /BaseFont /\(name) /Encoding /Identity-H "
            + "/DescendantFonts [5 0 R] /ToUnicode 6 0 R >>")
        file.add(5, "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /\(name) "
            + "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
            + "/FontDescriptor 7 0 R /DW \(ScanFont.advance) /CIDToGIDMap 8 0 R >>")
        file.add(6, packed: Data(ScanFont.toUnicode.utf8))
        file.add(7, "<< /Type /FontDescriptor /FontName /\(name) /Flags 5 "
            + "/FontBBox [0 -\(ScanFont.descent) \(ScanFont.advance) \(ScanFont.ascent)] /ItalicAngle 0 "
            + "/Ascent \(ScanFont.ascent) /Descent -\(ScanFont.descent) /CapHeight \(ScanFont.ascent) /StemV 80 "
            + "/FontFile2 9 0 R >>")
        // Every code to glyph 1, two bytes a code.
        file.add(8, packed: Data([UInt8](repeating: 0, count: 0x20000).enumerated().map { $0.offset % 2 == 1 ? 1 : 0 }))
        file.add(9, packed: ScanFont.file, "/Length1 \(ScanFont.file.count)")
    }

    /// The file as it is written: numbered objects, then the table of where
    /// each starts, then the trailer that names the catalogue and the Producer.
    private struct Writer {
        var data = Data("%PDF-1.7\n".utf8) + Data([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets: [Int]

        init(objects: Int) {
            offsets = [Int](repeating: 0, count: objects)
        }

        mutating func add(_ number: Int, _ body: String) {
            add(number, Data(body.utf8))
        }

        mutating func add(_ number: Int, stream dictionary: String, _ bytes: Data) {
            let head = dictionary.isEmpty ? "" : dictionary + " "
            var body = Data("<< \(head)/Length \(bytes.count) >>\nstream\n".utf8)
            body.append(bytes)
            body.append(Data("\nendstream".utf8))
            add(number, body)
        }

        /// A stream packed where it can be, else as it is.
        mutating func add(_ number: Int, packed bytes: Data, _ dictionary: String = "") {
            let head = dictionary.isEmpty ? "" : " " + dictionary
            if let packed = ScanPDF.zlib(bytes) {
                add(number, stream: "/Filter /FlateDecode" + head, packed)
            } else {
                add(number, stream: dictionary, bytes)
            }
        }

        mutating func add(_ number: Int, _ body: Data) {
            offsets[number] = data.count
            data.append(Data("\(number) 0 obj\n".utf8))
            data.append(body)
            data.append(Data("\nendobj\n".utf8))
        }

        func finished() -> Data {
            var out = data
            var table = "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
            for number in 1..<offsets.count {
                let offset = String(offsets[number])
                let padding = String(repeating: "0", count: max(0, 10 - offset.count))
                table += padding + offset + " 00000 n \n"
            }
            table += "trailer\n<< /Size \(offsets.count) /Root 1 0 R /Info 3 0 R >>\nstartxref\n\(data.count)\n%%EOF\n"
            out.append(Data(table.utf8))
            return out
        }
    }

    /// What a page draws: its picture where the layout puts it, then each
    /// word, invisible (render mode 3), as wide and as high as it was read.
    static func drawing(_ page: Page, on picture: CGRect) -> String {
        var lines = ["q", "\(text(picture.width)) 0 0 \(text(picture.height)) \(text(picture.minX)) \(text(picture.minY)) cm",
                     "/Im0 Do", "Q"]
        let placed = page.words.compactMap { word -> String? in
            guard let units = units(word.text) else { return nil }
            // As the word stands from the left: a right-to-left word's space comes first.
            let codes = visual(units)
            let before = codes.prefix { $0 == 0x20 }.count
            let shown = codes.count - before - codes.reversed().prefix { $0 == 0x20 }.count
            let left: CGFloat = picture.minX + word.box.minX * picture.width
            let bottom: CGFloat = picture.minY + word.box.minY * picture.height
            let across: CGFloat = word.box.width * picture.width, high: CGFloat = word.box.height * picture.height
            guard shown > 0, across > 0, high > 0 else { return nil }
            // The font reaches 0.8 of its size up from the line and 0.2 down: the word's height is its size.
            let size: CGFloat = high
            let natural: CGFloat = CGFloat(shown * ScanFont.advance) * size / 1000
            let stretch: CGFloat = min(max(across / natural * 100, 10), 1000)
            // A space before the word stands left of its box.
            let start: CGFloat = left - CGFloat(before * ScanFont.advance) * size / 1000 * stretch / 100
            let baseline: CGFloat = bottom + CGFloat(ScanFont.descent) / 1000 * size
            let hex = codes.map { String(format: "%04X", $0) }.joined()
            return "/F1 \(text(size)) Tf \(text(stretch)) Tz 1 0 0 1 \(text(start)) \(text(baseline)) Tm <\(hex)> Tj"
        }
        if !placed.isEmpty {
            lines += ["BT", "3 Tr"] + placed + ["ET"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Text

    /// A word as the font's codes, its UTF-16 units; nil when it is empty
    /// or holds a character beyond them or a control character.
    static func units(_ text: String) -> [UInt16]? {
        guard !text.isEmpty else { return nil }
        var out: [UInt16] = []
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFFFF, scalar.value >= 0x20, !(0x7F...0x9F).contains(scalar.value) else { return nil }
            out.append(UInt16(scalar.value))
        }
        return out
    }

    // MARK: Right to left

    /// A word's codes in the order they stand on the page from the left, as
    /// most PDFs hold right-to-left text and readers turn it back (PDFKit,
    /// poppler, pypdf): a word with Arabic or Hebrew letters as the Unicode
    /// bidirectional algorithm lays it out in a right-to-left line, its
    /// letters from the left, its numbers and Latin letters reading on as
    /// they do; any other word as it is.
    static func visual(_ units: [UInt16]) -> [UInt16] {
        var kinds = units.map(direction(of:))
        guard kinds.contains(where: { $0 == .right || $0 == .arabicLetter }) else { return units }
        // A mark is of the kind of the letter it is on (W1).
        for index in kinds.indices where kinds[index] == .mark {
            kinds[index] = index == 0 ? .right : kinds[index - 1]
        }
        // A European number after Arabic letters is an Arabic one (W2);
        // Arabic letters run right to left (W3).
        var strong = Direction.right
        for index in kinds.indices {
            switch kinds[index] {
            case .left, .right, .arabicLetter: strong = kinds[index]
            case .european where strong == .arabicLetter: kinds[index] = .arabicNumber
            default: break
            }
            if kinds[index] == .arabicLetter { kinds[index] = .right }
        }
        // One separator between two numbers of a kind is theirs (W4), a
        // sign such as % or € beside a European number is its (W5), and the
        // rest are neutral (W6).
        for index in kinds.indices.dropFirst().dropLast() {
            let previous = kinds[index - 1], next = kinds[index + 1]
            switch kinds[index] {
            case .separator where previous == .european && next == .european:
                kinds[index] = .european
            case .common where previous == next && (previous == .european || previous == .arabicNumber):
                kinds[index] = previous
            default:
                break
            }
        }
        for index in kinds.indices where kinds[index] == .european {
            var other = index - 1
            while other >= 0, kinds[other] == .terminator {
                kinds[other] = .european
                other -= 1
            }
            other = index + 1
            while other < kinds.count, kinds[other] == .terminator {
                kinds[other] = .european
                other += 1
            }
        }
        kinds = kinds.map { [.separator, .terminator, .common].contains($0) ? .neutral : $0 }
        // A European number after Latin letters runs as they do (W7).
        strong = .right
        for index in kinds.indices {
            switch kinds[index] {
            case .left, .right: strong = kinds[index]
            case .european where strong == .left: kinds[index] = .left
            default: break
            }
        }
        // Neutrals between two of one direction take it, numbers counting as
        // right to left; any others the line's, right to left (N1, N2).
        var index = 0
        while index < kinds.count {
            guard kinds[index] == .neutral else {
                index += 1
                continue
            }
            var end = index
            while end < kinds.count, kinds[end] == .neutral { end += 1 }
            let previous: Direction = index == 0 || kinds[index - 1] != .left ? .right : .left
            let next: Direction = end == kinds.count || kinds[end] != .left ? .right : .left
            for neutral in index..<end { kinds[neutral] = previous == next ? previous : .right }
            index = end
        }
        // What runs left to right keeps its order, and the whole is turned round (L2).
        var out = units
        index = 0
        while index < out.count {
            guard kinds[index] != .right else {
                index += 1
                continue
            }
            var end = index
            while end < out.count, kinds[end] != .right { end += 1 }
            out[index..<end].reverse()
            index = end
        }
        return out.reversed()
    }

    /// Which way a character runs, as the bidirectional algorithm says, for
    /// what scanned words hold.
    enum Direction: Equatable {
        /// L, R and AL: letters left to right, right to left, and Arabic ones.
        case left, right, arabicLetter
        /// EN and AN: European numbers and Arabic ones.
        case european, arabicNumber
        /// ES, ET and CS: a plus or minus; a currency or percent sign; a comma, point, slash or colon.
        case separator, terminator, common
        /// NSM: a mark on the letter before it.
        case mark
        /// Spaces and the other signs.
        case neutral
    }

    static func direction(of unit: UInt16) -> Direction {
        switch unit {
        case 0x30...0x39, 0xB2, 0xB3, 0xB9, 0x06F0...0x06F9, 0x2070, 0x2074...0x2079, 0x2080...0x2089, 0xFF10...0xFF19:
            return .european
        case 0x0600...0x0605, 0x0660...0x0669, 0x066B, 0x066C, 0x06DD, 0x08E2:
            return .arabicNumber
        case 0x2B, 0x2D, 0x207A, 0x207B, 0x208A, 0x208B, 0x2212, 0xFB29, 0xFE62, 0xFE63, 0xFF0B, 0xFF0D:
            return .separator
        case 0x23...0x25, 0xA2...0xA5, 0xB0, 0xB1, 0x0609, 0x060A, 0x066A, 0x2030...0x2034, 0x20A0...0x20CF, 0x2213,
             0xFE5F, 0xFE69, 0xFE6A, 0xFF03...0xFF05, 0xFFE0, 0xFFE1, 0xFFE5, 0xFFE6:
            return .terminator
        case 0x2C, 0x2E, 0x2F, 0x3A, 0xA0, 0x060C, 0x202F, 0x2044, 0xFE50, 0xFE52, 0xFE55, 0xFF0C, 0xFF0E, 0xFF0F, 0xFF1A:
            return .common
        case 0x200E:
            return .left
        case 0x200F:
            return .right
        default:
            break
        }
        guard let scalar = Unicode.Scalar(unit) else { return .neutral }
        let category = scalar.properties.generalCategory
        if category == .nonspacingMark || category == .enclosingMark { return .mark }
        switch unit {
        case 0x0590...0x05FF, 0x07C0...0x085F, 0xFB1D...0xFB4F:
            return .right
        case 0x0600...0x07BF, 0x0860...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFE:
            return .arabicLetter
        default:
            break
        }
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .spacingMark,
             .decimalNumber, .letterNumber:
            return .left
        default:
            return .neutral
        }
    }

    // MARK: Pictures

    /// A JPEG without what it says about itself: its JFIF, Exif, XMP and
    /// ICC parts and comments are left out, the picture is kept as it is.
    /// Anything that does not read as a JPEG is given back unchanged.
    static func stripped(jpeg: Data) -> Data {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return jpeg }
        var out: [UInt8] = [0xFF, 0xD8]
        var i = 2
        while i + 1 < bytes.count {
            guard bytes[i] == 0xFF else { return jpeg }
            let marker = bytes[i + 1]
            if marker == 0xFF {
                i += 1
                continue
            }
            if marker == 0xDA {
                // The picture itself, to the end.
                out.append(contentsOf: bytes[i...])
                return Data(out)
            }
            if marker == 0xD9 {
                out.append(contentsOf: [0xFF, 0xD9])
                return Data(out)
            }
            guard i + 3 < bytes.count else { return jpeg }
            let high = Int(bytes[i + 2]), low = Int(bytes[i + 3])
            let length: Int = high << 8 | low
            guard length >= 2, i + 2 + length <= bytes.count else { return jpeg }
            // APP0 to APP15 and comments say things about the picture; APP14
            // (Adobe) says how its colours are stored, so it stays.
            let aboutItself = ((0xE0...0xEF).contains(marker) && marker != 0xEE) || marker == 0xFE
            if !aboutItself { out.append(contentsOf: bytes[i..<(i + 2 + length)]) }
            i += 2 + length
        }
        return jpeg
    }

    /// A page in black and white as one bit a pixel: rows from the top,
    /// each row whole bytes, a 1 for white, where the brightness is 128 or more.
    static func bits(from brightness: [UInt8], width: Int, height: Int) -> Data {
        let rowBytes = (width + 7) / 8
        var out = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            for x in 0..<width where brightness[y * width + x] >= 128 {
                let bit: UInt8 = 0x80 >> UInt8(x % 8)
                out[y * rowBytes + x / 8] |= bit
            }
        }
        return Data(out)
    }

    // MARK: Packing

    /// Data packed as PDF's FlateDecode reads it: zlib's header, the
    /// deflated bytes and their Adler-32. Nil where it cannot be packed here,
    /// and the stream is then written as it is.
    static func zlib(_ data: Data) -> Data? {
        #if canImport(Darwin)
        // Apple's zlib gives the deflated bytes alone, without zlib's frame.
        guard let deflated = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        var out = Data([0x78, 0x9C])
        out.append(deflated)
        let check: UInt32 = adler32(data)
        let shifts: [UInt32] = [24, 16, 8, 0]
        let bytes: [UInt8] = shifts.map { shift -> UInt8 in UInt8(truncatingIfNeeded: check >> shift) }
        out.append(contentsOf: bytes)
        return out
        #else
        return nil
        #endif
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var count = 0
        for byte in data {
            a += UInt32(byte)
            b += a
            count += 1
            // Kept small enough not to overflow, as zlib does.
            if count == 5552 {
                a %= 65521
                b %= 65521
                count = 0
            }
        }
        let high: UInt32 = b % 65521, low: UInt32 = a % 65521
        return high << 16 | low
    }

    /// A number as PDF writes it: a point, at most three decimals, no
    /// trailing zeros, whatever the device's language.
    static func text(_ value: CGFloat) -> String {
        let scaled: Double = Double(value) * 1000
        let thousandths = Int(scaled.rounded())
        let sign = thousandths < 0 ? "-" : ""
        let whole = abs(thousandths) / 1000, part = abs(thousandths) % 1000
        guard part != 0 else { return sign + String(whole) }
        var decimals = String(part)
        let padding = String(repeating: "0", count: 3 - decimals.count)
        decimals = padding + decimals
        while decimals.hasSuffix("0") { decimals.removeLast() }
        return "\(sign)\(whole).\(decimals)"
    }
}
