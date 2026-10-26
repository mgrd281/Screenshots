import XCTest
@testable import Tendedero

/// The font a scanned PDF's invisible words are set in (`ScanFont`), read
/// back as a TrueType reader reads it: its table directory in order and on
/// four-byte boundaries, every table's checksum right and the whole file
/// summing to 0xB1B0AFBA, two glyphs half an em wide, the first empty and
/// the second without contours, and its name.
final class ScanFontTests: XCTestCase {
    private let font = [UInt8](ScanFont.file)

    private func u16(_ at: Int) -> Int { Int(font[at]) << 8 | Int(font[at + 1]) }
    private func i16(_ at: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(at)))) }
    private func u32(_ at: Int) -> UInt32 { font[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }

    /// Each table's tag, where it starts and how long it is.
    private func tables() -> [(tag: String, checksum: UInt32, offset: Int, length: Int)] {
        (0..<u16(4)).map { index in
            let record = 12 + 16 * index
            let tag = String(decoding: font[record..<(record + 4)], as: UTF8.self)
            return (tag, u32(record + 4), Int(u32(record + 8)), Int(u32(record + 12)))
        }
    }

    private func table(_ tag: String) throws -> (offset: Int, length: Int) {
        let found = try XCTUnwrap(tables().first { $0.tag == tag }, tag)
        return (found.offset, found.length)
    }

    func testTheDirectoryIsInOrderAndEveryTableOnItsBoundary() {
        XCTAssertEqual(u32(0), 0x0001_0000, "TrueType outlines")
        let found = tables()
        XCTAssertEqual(found.map(\.tag), ["OS/2", "cmap", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "name", "post"])
        XCTAssertEqual(u16(6), 128, "search range")
        XCTAssertEqual(u16(8), 3, "entry selector")
        XCTAssertEqual(u16(10), 32, "range shift")
        for table in found {
            XCTAssertEqual(table.offset % 4, 0, table.tag)
            XCTAssertLessThanOrEqual(table.offset + table.length, font.count, table.tag)
        }
    }

    func testEveryChecksumIsRightAndTheWholeFileSumsAsTrueTypeAsks() throws {
        let head = try table("head")
        for table in tables() {
            var bytes = Array(font[table.offset..<(table.offset + table.length)])
            // head's own checksum is taken as if its adjustment said nothing.
            if table.tag == "head" { bytes.replaceSubrange(8..<12, with: [0, 0, 0, 0]) }
            XCTAssertEqual(ScanFont.checksum(bytes), table.checksum, table.tag)
        }
        XCTAssertEqual(ScanFont.checksum(font), 0xB1B0_AFBA)
        XCTAssertEqual(u32(head.offset + 12), 0x5F0F_3CF5, "head's magic number")
        XCTAssertEqual(u16(head.offset + 18), 1000, "units per em")
        XCTAssertEqual(i16(head.offset + 50), 0, "short offsets in loca")
    }

    func testTwoGlyphsHalfAnEmWideOneEmptyOneWithoutContours() throws {
        let maxp = try table("maxp"), hhea = try table("hhea"), hmtx = try table("hmtx")
        let loca = try table("loca"), glyf = try table("glyf")
        XCTAssertEqual(maxp.length, 32)
        XCTAssertEqual(u16(maxp.offset + 4), 2, "two glyphs")
        XCTAssertEqual(hhea.length, 36)
        XCTAssertEqual(u16(hhea.offset + 34), 2, "two horizontal metrics")
        XCTAssertEqual([u16(hmtx.offset), u16(hmtx.offset + 4)], [ScanFont.advance, ScanFont.advance])
        XCTAssertEqual([u16(loca.offset), u16(loca.offset + 2), u16(loca.offset + 4)], [0, 0, 6])
        XCTAssertEqual(glyf.length, 12)
        XCTAssertEqual(i16(glyf.offset), 0, "no contours")
        XCTAssertEqual(try table("OS/2").length, 96, "OS/2 version 4")
        XCTAssertEqual(try table("post").length, 32)
    }

    func testItsCharacterMapEndsAsEveryMapDoes() throws {
        let cmap = try table("cmap")
        XCTAssertEqual([u16(cmap.offset + 4), u16(cmap.offset + 6)], [3, 1], "Windows, Unicode")
        let subtable = cmap.offset + Int(u32(cmap.offset + 8))
        XCTAssertEqual(u16(subtable), 4, "format 4")
        XCTAssertEqual(u16(subtable + 14), 0xFFFF, "the last segment's end")
    }

    func testItsNameIsTheOneThePDFGives() throws {
        let name = try table("name")
        let count = u16(name.offset + 2), strings = name.offset + u16(name.offset + 4)
        var names: [String] = []
        for index in 0..<count {
            let record = name.offset + 6 + 12 * index
            let length = u16(record + 8), offset = u16(record + 10)
            let units = stride(from: 0, to: length, by: 2).map { UInt16(u16(strings + offset + $0)) }
            names.append(String(decoding: units, as: UTF16.self))
        }
        XCTAssertEqual(names, [ScanFont.name, "Regular", ScanFont.name, ScanFont.name])
    }
}
