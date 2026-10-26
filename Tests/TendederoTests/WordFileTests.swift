import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import Tendedero

/// The pages' text as a Word document: a ZIP of its parts that any ZIP
/// reader opens, each part well-formed XML, and in it the text as the
/// scan's text shows it: a heading, a block of lines, a table, covers, a
/// page break and a page in Arabic. Made-up pages only.
final class WordFileTests: XCTestCase {
    private func uint16(_ data: Data, _ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
    private func uint32(_ data: Data, _ at: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[at + $1]) << (8 * UInt32($1)) }
    }

    /// The files the archive's directory lists, each read where its own
    /// header says and checked against its CRC.
    private func files(in zip: Data) throws -> [String: Data] {
        let zip = Data(zip)
        let end = zip.count - 22
        XCTAssertEqual(uint32(zip, end), 0x0605_4B50, "the end of the central directory")
        let count = uint16(zip, end + 10)
        var at = Int(uint32(zip, end + 16))
        var files: [String: Data] = [:]
        for _ in 0..<count {
            XCTAssertEqual(uint32(zip, at), 0x0201_4B50)
            XCTAssertEqual(uint16(zip, at + 10), 0, "stored")
            let crc = uint32(zip, at + 16), size = Int(uint32(zip, at + 20))
            let nameLength = uint16(zip, at + 28), extra = uint16(zip, at + 30), comment = uint16(zip, at + 32)
            let local = Int(uint32(zip, at + 42))
            let name = try XCTUnwrap(String(data: zip[(at + 46)..<(at + 46 + nameLength)], encoding: .utf8))
            XCTAssertEqual(uint32(zip, local), 0x0403_4B50, name)
            let start = local + 30 + uint16(zip, local + 26) + uint16(zip, local + 28)
            let data = zip[start..<(start + size)]
            XCTAssertEqual(Zip.crc32(Data(data)), crc, name)
            files[name] = Data(data)
            at += 46 + nameLength + extra + comment
        }
        return files
    }

    private func wellFormed(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), String(describing: parser.parserError), file: file, line: line)
    }

    private func word(_ text: String, covered: Bool = false) -> ScanReading.Word {
        covered ? .covered(.zero) : ScanReading.Word(text: text, box: .zero)
    }

    func testTheCRCIsZIPs() {
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(Zip.crc32(Data()), 0)
    }

    func testTheDocumentIsAZIPOfWellFormedParts() throws {
        let page = ScanReadingVisionTests.page(ScanReadingVisionTests.invoice)
        let files = try files(in: WordFile.data([page]))
        XCTAssertEqual(Set(files.keys), ["[Content_Types].xml", "_rels/.rels", "word/_rels/document.xml.rels",
                                         "word/styles.xml", "word/document.xml"])
        for (name, data) in files {
            wellFormed(data)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("<?xml"), name)
        }
    }

    func testTheInvoiceKeepsItsHeadingItsAddressAndItsTable() throws {
        let page = ScanReadingVisionTests.page(ScanReadingVisionTests.invoice)
        let xml = WordFile.document([page])
        XCTAssertTrue(xml.contains(#"<w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t xml:space="preserve">Rechnung</w:t>"#), xml)
        XCTAssertTrue(xml.contains(#"Erika Mustermann</w:t></w:r><w:r><w:br/></w:r><w:r><w:t xml:space="preserve">Musterstraße 12"#),
                      "an address's lines stay apart in one paragraph")
        let table = try XCTUnwrap(xml.range(of: "<w:tbl>.*?Druckpatronen Schwarz.*?</w:tbl>", options: .regularExpression))
        XCTAssertTrue(xml[table].contains("49,80 €"), "the row's cells in the same table")
        XCTAssertEqual(xml.components(separatedBy: "<w:tbl>").count - 1,
                       page.blocks.filter { if case .table = $0 { return true } else { return false } }.count)
    }

    func testTablesOneAfterAnotherStayApartAndTheDocumentEndsWithAParagraph() {
        let one = ScanReading.Table(rows: [[[word("Netto")], [word("310,70")]]])
        let xml = WordFile.document([ScanReading.Page(blocks: [.table(one), .table(one)], rightToLeft: false)])
        XCTAssertTrue(xml.contains("</w:tbl><w:p/><w:tbl>"), "Word would join them into one: \(xml)")
        XCTAssertTrue(xml.contains("</w:tbl><w:p/><w:sectPr>"), xml)
    }

    func testACoveredStretchIsTheMarkAndNeverWhatItHides() {
        let page = ScanReading.Page(blocks: [.paragraph(.init(lines: [[word("Patient:"), word("", covered: true)]],
                                                             flows: false, heading: false))], rightToLeft: false)
        let xml = WordFile.document([page])
        XCTAssertTrue(xml.contains("Patient: ███"), xml)
    }

    func testTextIsEscapedAndEveryRowAsWideAsTheWidest() throws {
        let table = ScanReading.Table(rows: [[[word("A"), word("&"), word("B")], [word("<C>")]], [[word("\"D\"")]]])
        let xml = WordFile.document([ScanReading.Page(blocks: [.table(table)], rightToLeft: false)])
        XCTAssertTrue(xml.contains("A &amp; B"), xml)
        XCTAssertTrue(xml.contains("&lt;C&gt;"), xml)
        XCTAssertTrue(xml.contains("&quot;D&quot;"), xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:tc>").count - 1, 4, "two rows of two cells")
        XCTAssertEqual(WordFile.escaped("a\u{0}b\u{1B}c\td"), "abc d", "no control characters in XML")
        wellFormed(Data(xml.utf8))
    }

    func testPagesArePartedAndArabicReadsFromTheRight() {
        let arabic = ScanReading.Page(blocks: [.paragraph(.init(lines: [[word("فاتورة")]], flows: true, heading: true))],
                                      rightToLeft: true)
        let german = ScanReading.Page(blocks: [.paragraph(.init(lines: [[word("Rechnung")]], flows: true, heading: false))],
                                      rightToLeft: false)
        let xml = WordFile.document([german, arabic])
        XCTAssertEqual(xml.components(separatedBy: #"<w:br w:type="page"/>"#).count - 1, 1)
        XCTAssertTrue(xml.contains(#"<w:pPr><w:pStyle w:val="Heading1"/><w:bidi/></w:pPr><w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space="preserve">فاتورة"#), xml)
        XCTAssertFalse(xml.contains(#"<w:bidi/></w:pPr><w:r><w:t xml:space="preserve">Rechnung"#))
    }

    func testNoPagesStillMakeADocument() throws {
        let files = try files(in: WordFile.data([]))
        let body = try XCTUnwrap(files["word/document.xml"])
        wellFormed(body)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("<w:body><w:p/><w:sectPr>"))
    }

    func testNothingSaysWhoMadeItOrWhen() throws {
        let data = WordFile.data([ScanReadingVisionTests.page(ScanReadingVisionTests.invoice)])
        let files = try files(in: data)
        XCTAssertNil(files["docProps/core.xml"], "no author, no dates")
        XCTAssertEqual(data, WordFile.data([ScanReadingVisionTests.page(ScanReadingVisionTests.invoice)]),
                       "the same pages, the same bytes")
    }
}
