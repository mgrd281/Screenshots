import XCTest
@testable import Tendedero

/// Scanned pages as one PDF, read back byte by byte: an A4 page for each, in
/// order, a picture of A4's shape filling it and any other within 10 mm,
/// the words read laid invisibly where they were, a word outside the
/// Western letters left out rather than changed, a table that says where
/// every object starts, and nothing said of who made it but "Snapfly".
final class ScanPDFTests: XCTestCase {
    private func jpeg(_ width: Int, _ height: Int, gray: Bool = false) -> ScanPDF.Page.Picture {
        .jpeg(Data([0xFF, 0xD8, 0xFF, 0xD9]), width: width, height: height, gray: gray)
    }

    /// The PDF's bytes as text, one character a byte.
    private func file(_ pages: [ScanPDF.Page]) throws -> String {
        String(try XCTUnwrap(ScanPDF.make(pages)).map { Character(Unicode.Scalar($0)) })
    }

    func testEveryPageIsA4WithItsPictureInOrder() throws {
        let pdf = try file([ScanPDF.Page(picture: jpeg(2480, 3508)), ScanPDF.Page(picture: jpeg(3000, 2000)),
                            ScanPDF.Page(picture: .bits(Data(count: 100 * 2600), width: 800, height: 2600))])
        XCTAssertTrue(pdf.hasPrefix("%PDF-1.7\n"))
        XCTAssertTrue(pdf.contains("/Type /Pages /Kids [4 0 R 7 0 R 10 0 R] /Count 3"))
        let boxes = Self.all(in: pdf, between: "/MediaBox [", and: "]")
        XCTAssertEqual(boxes, ["0 0 595.28 841.89", "0 0 841.89 595.28", "0 0 595.28 841.89"])
        // The A4 picture fills its page; the receipt stands 10 mm in, top and bottom.
        let draws = Self.all(in: pdf, between: "q\n", and: " cm").map { $0.split(separator: " ").compactMap { Double($0) } }
        XCTAssertEqual(draws.count, 3)
        XCTAssertEqual(draws[0][0], 595.28, accuracy: 0.2)
        XCTAssertEqual(draws[0][3], 841.89, accuracy: 0.01)
        XCTAssertEqual(draws[2][5], 28.35, accuracy: 0.01)
        XCTAssertEqual(draws[2][0] / draws[2][3], 800.0 / 2600, accuracy: 0.0005, "never stretched")
        XCTAssertTrue(pdf.contains("/Width 800 /Height 2600 /ColorSpace /DeviceGray /BitsPerComponent 1"))
        XCTAssertTrue(pdf.contains("/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode"))
    }

    func testTheFileSaysNothingButWhoMadeIt() throws {
        let pdf = try file([ScanPDF.Page(picture: jpeg(1000, 1414), words: [ScanPDF.Word(text: "Rechnung", box: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.03))])])
        XCTAssertTrue(pdf.contains("3 0 obj\n<< /Producer (Snapfly) >>\nendobj"))
        XCTAssertTrue(pdf.contains("/Info 3 0 R"))
        for key in ["/Title", "/Author", "/Subject", "/Keywords", "/Creator", "/CreationDate", "/ModDate", "/Metadata", "/ID"] {
            XCTAssertFalse(pdf.contains(key), "\(key) is in the PDF")
        }
    }

    func testWordsAreInvisibleWhereTheyWereRead() throws {
        let words = [ScanPDF.Word(text: "Gesamt ", box: CGRect(x: 0.5, y: 0.4, width: 0.1, height: 0.02)),
                     ScanPDF.Word(text: "369,73 €", box: CGRect(x: 0.62, y: 0.4, width: 0.12, height: 0.02))]
        let page = ScanPDF.Page(picture: jpeg(2480, 3508), words: words)
        let drawing = ScanPDF.drawing(page, on: CGRect(origin: .zero, size: ScanGeometry.a4))
        XCTAssertTrue(drawing.contains("BT\n3 Tr\n"), "invisible")
        XCTAssertTrue(drawing.contains("<476573616D7420>"), "Gesamt and its space")
        XCTAssertTrue(drawing.contains("<3336392C37332080>"), "the euro sign in WinAnsi")
        // The word's box: x at half the page, the line a little above its bottom.
        let first = try XCTUnwrap(drawing.split(separator: "\n").first { $0.contains("<4765") })
        let parts = first.split(separator: " ")
        let tm = try XCTUnwrap(parts.firstIndex(of: "Tm"))
        XCTAssertEqual(Double(parts[tm - 2])!, 297.64, accuracy: 0.01)
        let size = Double(parts[1])!
        let tall: Double = 0.02 * 841.89 / 0.925
        XCTAssertEqual(size, tall, accuracy: 0.01)
        let baseline: Double = 0.4 * 841.89 + 0.207 * size
        XCTAssertEqual(Double(parts[tm - 1])!, baseline, accuracy: 0.01)
        // As wide as the word was read, its space left out of the stretch.
        let stretch = Double(parts[3])!
        let units: Int = "Gesamt".utf8.reduce(0) { $0 + ScanPDF.width(of: $1) }
        let drawn: Double = Double(units) * size / 1000 * stretch / 100
        let read: Double = 0.1 * 595.28
        XCTAssertEqual(drawn, read, accuracy: 0.05)
        let pdf = try file([page])
        XCTAssertTrue(pdf.contains("/BaseFont /Helvetica /Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 255"))
        XCTAssertTrue(pdf.contains("/Resources << /XObject << /Im0 7 0 R >> /Font << /F1 4 0 R >> >>"))
    }

    func testAWordOutsideTheWesternLettersIsLeftOutNotChanged() {
        XCTAssertNotNil(ScanPDF.encoded("Straße Müller €"))
        XCTAssertEqual(ScanPDF.encoded("“Grüße”")?.first, 0x93)
        XCTAssertNil(ScanPDF.encoded("Doğan"), "ğ is not there")
        XCTAssertNil(ScanPDF.encoded("مرحبا"))
        XCTAssertNil(ScanPDF.encoded(""))
        let page = ScanPDF.Page(picture: jpeg(1000, 1414), words: [ScanPDF.Word(text: "Doğan", box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.02))])
        XCTAssertFalse(ScanPDF.drawing(page, on: CGRect(x: 0, y: 0, width: 595, height: 842)).contains("BT"))
    }

    func testWithoutWordsThereIsNoTextAndNoFont() throws {
        let pdf = try file([ScanPDF.Page(picture: jpeg(1000, 1414))])
        XCTAssertFalse(pdf.contains("/Font"))
        XCTAssertFalse(pdf.contains("BT"))
        XCTAssertTrue(pdf.contains("/Kids [4 0 R]"))
    }

    func testTheTableSaysWhereEachObjectStarts() throws {
        let data = try XCTUnwrap(ScanPDF.make([ScanPDF.Page(picture: jpeg(1000, 1414)), ScanPDF.Page(picture: jpeg(1414, 1000))]))
        let pdf = String(data.map { Character(Unicode.Scalar($0)) })
        let start = try XCTUnwrap(Int(Self.all(in: pdf, between: "startxref\n", and: "\n").first ?? ""))
        let bytes = [UInt8](data)
        XCTAssertEqual(String(bytes[start..<(start + 4)].map { Character(Unicode.Scalar($0)) }), "xref")
        let lines = pdf[pdf.index(pdf.startIndex, offsetBy: start)...].split(separator: "\n")
        XCTAssertEqual(lines[1], "0 10")
        for number in 1..<10 {
            let entry = lines[2 + number]
            XCTAssertEqual(entry.count, 19, "every entry is 20 bytes with its line's end")
            let offset = try XCTUnwrap(Int(entry.prefix(10)))
            let head = String(bytes[offset..<(offset + 8)].map { Character(Unicode.Scalar($0)) })
            XCTAssertTrue(head.hasPrefix("\(number) 0 obj"), "object \(number) at \(offset): \(head)")
        }
        XCTAssertTrue(pdf.contains("trailer\n<< /Size 10 /Root 1 0 R /Info 3 0 R >>"))
        XCTAssertTrue(pdf.hasSuffix("%%EOF\n"))
    }

    func testAJPEGLosesWhatItSaysAboutItselfAndKeepsThePicture() {
        func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
            let length: Int = body.count + 2
            let high: UInt8 = UInt8(length >> 8), low: UInt8 = UInt8(length & 0xFF)
            let head: [UInt8] = [0xFF, marker, high, low]
            return head + body
        }
        let tables: [UInt8] = segment(0xDB, [0, 1, 2, 3]) + segment(0xC0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0])
        let picture: [UInt8] = tables + segment(0xC4, [0, 5]) + segment(0xEE, Array("Adobe".utf8))
        let data: [UInt8] = [0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD9]
        let scan: [UInt8] = segment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + data
        let about: [UInt8] = segment(0xE0, Array("JFIF\0".utf8)) + segment(0xE1, Array("Exif\0\0Apple iPhone".utf8))
        let more: [UInt8] = segment(0xE2, Array("ICC_PROFILE".utf8)) + segment(0xFE, Array("made by".utf8))
        let start: [UInt8] = [0xFF, 0xD8]
        let jpeg: [UInt8] = start + about + more + picture + scan
        let stripped = [UInt8](ScanPDF.stripped(jpeg: Data(jpeg)))
        XCTAssertEqual(stripped, start + picture + scan)
        XCTAssertEqual(ScanPDF.stripped(jpeg: Data([1, 2, 3])), Data([1, 2, 3]), "not a JPEG: as it was")
    }

    func testBlackAndWhiteIsOneBitAPixelWhiteAsOne() {
        let brightness: [UInt8] = [255, 0, 255, 0, 255, 0, 255, 0, 255, 255,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 200]
        XCTAssertEqual([UInt8](ScanPDF.bits(from: brightness, width: 10, height: 2)), [0b1010_1010, 0b1100_0000, 0, 0b0100_0000])
    }

    func testAdler32IsZlibs() {
        XCTAssertEqual(ScanPDF.adler32(Data("Wikipedia".utf8)), 0x11E6_0398)
        XCTAssertEqual(ScanPDF.adler32(Data()), 1)
        let long = Data((0..<20000).map { UInt8($0 % 251) })
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in long {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        XCTAssertEqual(ScanPDF.adler32(long), b << 16 | a)
    }

    func testNumbersAreWrittenWithAPoint() {
        XCTAssertEqual(ScanPDF.text(595.28), "595.28")
        XCTAssertEqual(ScanPDF.text(28.346), "28.346")
        XCTAssertEqual(ScanPDF.text(100), "100")
        XCTAssertEqual(ScanPDF.text(0.0004), "0")
        XCTAssertEqual(ScanPDF.text(-3.5), "-3.5")
        XCTAssertEqual(ScanPDF.text(1.0005), "1.001")
    }

    func testNoPagesMakeNoPDF() {
        XCTAssertNil(ScanPDF.make([]))
    }

    /// Every text between two marks, in order.
    static func all(in text: String, between start: String, and end: String) -> [String] {
        var found: [String] = []
        var rest = text[...]
        while let open = rest.range(of: start), let close = rest[open.upperBound...].range(of: end) {
            found.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return found
    }
}
