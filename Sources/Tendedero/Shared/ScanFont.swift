import Foundation

/// The font a scanned PDF's invisible words are set in, so they can be found
/// and copied in every script: a TrueType font of one empty glyph, as wide
/// as half its size, which every character is drawn with (and never seen,
/// as the words are invisible), while the PDF's ToUnicode map says which
/// character each one is. So Arabic, Turkish, Greek, Cyrillic, Chinese,
/// Japanese and Korean are found as Latin is, with nothing of a real
/// typeface in the file. Written here byte by byte, as TrueType lays a font
/// out, so nothing else is in it.
enum ScanFont {
    /// Its name, in the font and in the PDF.
    static let name = "SnapflyText"
    /// How wide each glyph is, in thousandths of the size.
    static let advance = 500
    /// How far it reaches above its baseline and below, in thousandths.
    static let ascent = 800, descent = 200

    /// The font file.
    static let file: Data = make()

    private static func make() -> Data {
        let tables: [(tag: String, data: [UInt8])] = [
            ("OS/2", os2), ("cmap", cmap), ("glyf", glyf), ("head", head(adjustment: 0)), ("hhea", hhea),
            ("hmtx", hmtx), ("loca", loca), ("maxp", maxp), ("name", names), ("post", post),
        ]
        var font = assembled(tables)
        // The whole file sums to 0xB1B0AFBA once head says how far it was
        // off; head's own checksum is taken as if it said nothing.
        let adjustment = 0xB1B0_AFBA &- checksum(font)
        if let at = offset(of: "head", in: font) {
            font.replaceSubrange((at + 8)..<(at + 12), with: u32(adjustment))
        }
        return Data(font)
    }

    /// Where a table starts, as the directory says.
    static func offset(of tag: String, in font: [UInt8]) -> Int? {
        guard font.count >= 12 else { return nil }
        let count = Int(font[4]) << 8 | Int(font[5])
        for index in 0..<count {
            let record = 12 + 16 * index
            guard record + 16 <= font.count else { return nil }
            if Array(font[record..<(record + 4)]) == Array(tag.utf8) {
                return font[(record + 8)..<(record + 12)].reduce(0) { $0 << 8 | Int($1) }
            }
        }
        return nil
    }

    /// The table directory, then each table on a four-byte boundary.
    private static func assembled(_ tables: [(tag: String, data: [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        let count = tables.count
        var power = 1, exponent = 0
        while power * 2 <= count {
            power *= 2
            exponent += 1
        }
        out += u32(0x0001_0000) + u16(count) + u16(power * 16) + u16(exponent) + u16(count * 16 - power * 16)
        var offset = 12 + 16 * count
        var body: [UInt8] = []
        for table in tables {
            out += Array(table.tag.utf8) + u32(checksum(table.data)) + u32(UInt32(offset)) + u32(UInt32(table.data.count))
            let padded = table.data + [UInt8](repeating: 0, count: (4 - table.data.count % 4) % 4)
            body += padded
            offset += padded.count
        }
        return out + body
    }

    /// TrueType's checksum: the sum of the big-endian 32-bit words, the last padded with zeros.
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var sum: UInt32 = 0
        var index = 0
        while index < bytes.count {
            var word: UInt32 = 0
            for shift in 0..<4 {
                let byte = index + shift < bytes.count ? UInt32(bytes[index + shift]) : 0
                word |= byte << UInt32(24 - 8 * shift)
            }
            sum = sum &+ word
            index += 4
        }
        return sum
    }

    // MARK: Tables

    private static func head(adjustment: UInt32) -> [UInt8] {
        u32(0x0001_0000) + u32(0x0001_0000) + u32(adjustment) + u32(0x5F0F_3CF5)
            + u16(0x0003) + u16(1000)
            + [UInt8](repeating: 0, count: 16)
            + i16(0) + i16(-descent) + i16(advance) + i16(ascent)
            + u16(0) + u16(8) + i16(2) + i16(0) + i16(0)
    }

    private static let hhea: [UInt8] = u32(0x0001_0000) + i16(ascent) + i16(-descent) + i16(0) + u16(advance)
        + i16(0) + i16(0) + i16(0) + i16(1) + i16(0) + i16(0)
        + i16(0) + i16(0) + i16(0) + i16(0) + i16(0) + u16(2)

    /// Both glyphs half an em wide.
    private static let hmtx: [UInt8] = u16(advance) + i16(0) + u16(advance) + i16(0)

    /// Glyph 0, .notdef, is empty; glyph 1 has no contours.
    private static let glyf: [UInt8] = i16(0) + i16(0) + i16(0) + i16(0) + i16(0) + u16(0)
    private static let loca: [UInt8] = u16(0) + u16(0) + u16(6)

    private static let maxp: [UInt8] = u32(0x0001_0000) + u16(2) + u16(0) + u16(0) + u16(0) + u16(0) + u16(2)
        + [UInt8](repeating: 0, count: 16)

    /// Windows Unicode, format 4, with only the segment every map ends with:
    /// no character comes here by its code, as the PDF names glyphs itself.
    private static let cmap: [UInt8] = {
        let subtable = u16(4) + u16(24) + u16(0) + u16(2) + u16(2) + u16(0) + u16(0)
            + u16(0xFFFF) + u16(0) + u16(0xFFFF) + i16(1) + u16(0)
        return u16(0) + u16(1) + u16(3) + u16(1) + u32(12) + subtable
    }()

    private static let names: [UInt8] = {
        let entries: [(id: Int, text: String)] = [(1, name), (2, "Regular"), (4, name), (6, name)]
        let strings = entries.map { entry in entry.text.utf16.flatMap { u16(Int($0)) } }
        var records: [UInt8] = []
        var offset = 0
        for (entry, string) in zip(entries, strings) {
            records += u16(3) + u16(1) + u16(0x0409) + u16(entry.id) + u16(string.count) + u16(offset)
            offset += string.count
        }
        return u16(0) + u16(entries.count) + u16(6 + 12 * entries.count) + records + strings.flatMap { $0 }
    }()

    private static let post: [UInt8] = u32(0x0003_0000) + u32(0) + i16(-100) + i16(50) + u32(1)
        + u32(0) + u32(0) + u32(0) + u32(0)

    private static let os2: [UInt8] = {
        var out = u16(4) + i16(advance) + u16(400) + u16(5) + u16(0)
        out += i16(650) + i16(600) + i16(0) + i16(75) + i16(650) + i16(600) + i16(0) + i16(350) + i16(50) + i16(300)
        out += i16(0) + [UInt8](repeating: 0, count: 10) + [UInt8](repeating: 0, count: 16) + Array("NONE".utf8)
        out += u16(0x0040) + u16(0xFFFF) + u16(0xFFFF)
        out += i16(ascent) + i16(-descent) + i16(0) + u16(ascent) + u16(descent)
        out += u32(0) + u32(0)
        out += i16(500) + i16(700) + u16(0) + u16(0x20) + u16(0)
        return out
    }()

    // MARK: Bytes

    static func u16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    static func i16(_ value: Int) -> [UInt8] {
        u16(Int(UInt16(bitPattern: Int16(value))))
    }

    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    // MARK: The map back to characters

    /// The PDF's ToUnicode map: every two-byte code is the UTF-16 unit it
    /// stands for, in ranges a high byte each, as the standard has them;
    /// the surrogates' halves are left out, as no word holds them.
    static var toUnicode: String {
        let highs = (0...0xFF).filter { !(0xD8...0xDF).contains($0) }
        var ranges: [String] = []
        for high in highs {
            let hex = String(format: "%02X", high)
            ranges.append("<\(hex)00> <\(hex)FF> <\(hex)00>")
        }
        var body = ""
        for start in stride(from: 0, to: ranges.count, by: 100) {
            let part = ranges[start..<min(start + 100, ranges.count)]
            body += "\(part.count) beginbfrange\n" + part.joined(separator: "\n") + "\nendbfrange\n"
        }
        return """
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /Adobe-Identity-UCS def
        /CMapType 2 def
        1 begincodespacerange
        <0000> <FFFF>
        endcodespacerange
        \(body)endcmap
        CMapName currentdict /CMap defineresource pop
        end
        end
        """
    }
}
