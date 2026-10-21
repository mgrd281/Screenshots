import Foundation

/// Scanned pages as one PDF to send or keep: each page a picture on an A4
/// page (`ScanGeometry.layout`), with, where asked, the words read on it laid
/// invisibly over it, so they can be found and copied; and nothing said of
/// who made it but "Snapfly", no title, author, dates or other metadata. It
/// is written here byte by byte, so nothing else is added.
///
/// The words are in Helvetica's Western encoding (WinAnsi), which every
/// reader knows; a word with a letter outside it is left out of the text,
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
        let hasText = pages.contains { page in page.words.contains { encoded($0.text) != nil } }
        // 1 the catalogue, 2 the pages, 3 what says who made it, 4 the font;
        // then each page, its contents and its picture.
        let first = hasText ? 5 : 4
        var file = Writer(objects: first + pages.count * 3)
        file.add(1, "<< /Type /Catalog /Pages 2 0 R >>")
        let kids = pages.indices.map { "\(first + $0 * 3) 0 R" }.joined(separator: " ")
        file.add(2, "<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
        file.add(3, "<< /Producer (Snapfly) >>")
        if hasText {
            let widths = (32...255).map { String(width(of: UInt8($0))) }.joined(separator: " ")
            file.add(4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding "
                + "/FirstChar 32 /LastChar 255 /Widths [\(widths)] >>")
        }
        for (index, page) in pages.enumerated() {
            let number = first + index * 3
            let size = page.picture.size
            let layout = ScanGeometry.layout(width: size.width, height: size.height)
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
                table += String(repeating: "0", count: max(0, 10 - offset.count)) + offset + " 00000 n \n"
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
            guard let bytes = encoded(word.text) else { return nil }
            let shown = bytes.reversed().drop { $0 == 0x20 }.reversed()
            let units = shown.reduce(0) { $0 + width(of: $1) }
            let box = CGRect(x: picture.minX + word.box.minX * picture.width, y: picture.minY + word.box.minY * picture.height,
                             width: word.box.width * picture.width, height: word.box.height * picture.height)
            guard units > 0, box.width > 0, box.height > 0 else { return nil }
            // Helvetica reaches 0.718 of its size up from the line and 0.207 down.
            let size = box.height / 0.925
            let stretch = min(max(box.width / (CGFloat(units) * size / 1000) * 100, 10), 1000)
            let hex = bytes.map { String(format: "%02X", $0) }.joined()
            return "/F1 \(text(size)) Tf \(text(stretch)) Tz 1 0 0 1 \(text(box.minX)) \(text(box.minY + 0.207 * size)) Tm <\(hex)> Tj"
        }
        if !placed.isEmpty {
            lines += ["BT", "3 Tr"] + placed + ["ET"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Text

    /// A word in the Western encoding, or nil when a letter of it is not there.
    static func encoded(_ text: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x20...0x7E).contains(value) || (0xA0...0xFF).contains(value) {
                bytes.append(UInt8(value))
            } else if let code = windows[value] {
                bytes.append(code)
            } else {
                return nil
            }
        }
        return bytes.isEmpty ? nil : bytes
    }

    /// The letters WinAnsi keeps between 0x80 and 0x9F.
    private static let windows: [UInt32: UInt8] = [
        0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87,
        0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91,
        0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98,
        0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    ]

    /// How wide a letter of the Western encoding is in Helvetica, in
    /// thousandths of its size, as Adobe's metrics give it.
    static func width(of code: UInt8) -> Int {
        switch code {
        case 0x20...0x7E: return ascii[Int(code) - 0x20]
        case 0xA0...0xFF: return latin[Int(code) - 0xA0]
        case 0x80: return 556
        case 0x82, 0x91, 0x92: return 222
        case 0x84, 0x88, 0x8B, 0x93, 0x94, 0x98, 0x9B: return 333
        case 0x85, 0x89, 0x8C, 0x97, 0x99: return 1000
        case 0x8A, 0x9F: return 667
        case 0x8E: return 611
        case 0x95: return 350
        case 0x9A, 0x9E: return 500
        case 0x9C: return 944
        default: return 556
        }
    }

    private static let ascii = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
    ]

    private static let latin = [
        278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
        400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
        667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
        556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
    ]

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
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
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
                out[y * rowBytes + x / 8] |= 0x80 >> UInt8(x % 8)
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
        let check = adler32(data)
        out.append(contentsOf: [UInt8(check >> 24), UInt8((check >> 16) & 0xFF), UInt8((check >> 8) & 0xFF),
                                UInt8(check & 0xFF)])
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
        return (b % 65521) << 16 | (a % 65521)
    }

    /// A number as PDF writes it: a point, at most three decimals, no
    /// trailing zeros, whatever the device's language.
    static func text(_ value: CGFloat) -> String {
        let thousandths = Int((Double(value) * 1000).rounded())
        let sign = thousandths < 0 ? "-" : ""
        let whole = abs(thousandths) / 1000, part = abs(thousandths) % 1000
        guard part != 0 else { return sign + String(whole) }
        var decimals = String(part)
        decimals = String(repeating: "0", count: 3 - decimals.count) + decimals
        while decimals.hasSuffix("0") { decimals.removeLast() }
        return "\(sign)\(whole).\(decimals)"
    }
}
