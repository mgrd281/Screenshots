import XCTest
#if canImport(PDFKit) && canImport(CoreText)
import CoreText
import PDFKit
#endif
@testable import Tendedero

/// Scanned pages as one PDF, read back byte by byte: an A4 page for each, in
/// order, a picture of A4's shape filling it and any other within 10 mm,
/// the words read laid invisibly where they were in every script, with the
/// font and the map back to their characters, a word with a character
/// beyond UTF-16's units left out rather than changed, a table that says
/// where every object starts, and nothing said of who made it but "Snapfly".
final class ScanPDFTests: XCTestCase {
    private func jpeg(_ width: Int, _ height: Int, gray: Bool = false) -> ScanPDF.Page.Picture {
        .jpeg(Data([0xFF, 0xD8, 0xFF, 0xD9]), width: width, height: height, gray: gray)
    }

    /// The PDF's bytes as text, one character a byte, its packed streams
    /// unpacked as a reader unpacks them.
    private func file(_ pages: [ScanPDF.Page]) throws -> String {
        let data = try Self.unpacked(try XCTUnwrap(ScanPDF.make(pages)))
        return String(data.map { Character(Unicode.Scalar($0)) })
    }

    private struct Unreadable: Error {}

    /// The file with each FlateDecode stream inflated in its place. Only
    /// Apple's systems pack streams, so elsewhere the file is as it was.
    static func unpacked(_ file: Data) throws -> Data {
        #if canImport(Darwin)
        let bytes = [UInt8](file)
        let mark = Array("/Filter /FlateDecode /Length ".utf8), open = Array(" >>\nstream\n".utf8)
        var out = Data()
        var i = 0
        while let at = Self.index(of: mark, in: bytes, from: i) {
            var j = at + mark.count
            var length = 0
            while j < bytes.count, (0x30...0x39).contains(bytes[j]) {
                let digit: Int = Int(bytes[j]) - 0x30
                length = length * 10 + digit
                j += 1
            }
            guard j + open.count <= bytes.count, Array(bytes[j..<(j + open.count)]) == open else { throw Unreadable() }
            let start = j + open.count
            guard length > 6, start + length <= bytes.count else { throw Unreadable() }
            // zlib's frame: two bytes before the deflated ones, and their Adler-32 after.
            let deflated = Data(bytes[(start + 2)..<(start + length - 4)])
            let inflated = try (deflated as NSData).decompressed(using: .zlib) as Data
            out.append(contentsOf: bytes[i..<at])
            out.append(Data("/Length \(inflated.count) >>\nstream\n".utf8))
            out.append(inflated)
            i = start + length
        }
        out.append(contentsOf: bytes[i...])
        return out
        #else
        return file
        #endif
    }

    /// Where `part` first starts in `bytes`, from `start` on.
    static func index(of part: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        var i = start
        while i + part.count <= bytes.count {
            if bytes[i] == part[0], Array(bytes[i..<(i + part.count)]) == part { return i }
            i += 1
        }
        return nil
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
        XCTAssertTrue(drawing.contains("<0047006500730061006D00740020>"), "Gesamt and its space, a UTF-16 unit each")
        XCTAssertTrue(drawing.contains("<003300360039002C00370033002020AC>"), "the euro sign as itself")
        // The word's box: x at half the page, its height the font's size, the line a fifth of it up.
        let first = try XCTUnwrap(drawing.split(separator: "\n").first { $0.contains("<0047") })
        let parts = first.split(separator: " ")
        let tm = try XCTUnwrap(parts.firstIndex(of: "Tm"))
        XCTAssertEqual(Double(parts[tm - 2])!, 297.64, accuracy: 0.01)
        let size = Double(parts[1])!
        XCTAssertEqual(size, 0.02 * 841.89, accuracy: 0.01)
        XCTAssertEqual(Double(parts[tm - 1])!, 0.4 * 841.89 + 0.2 * size, accuracy: 0.01)
        // As wide as the word was read, its space left out of the stretch.
        let stretch = Double(parts[3])!
        let drawn: Double = Double("Gesamt".count * ScanFont.advance) * size / 1000 * stretch / 100
        XCTAssertEqual(drawn, 0.1 * 595.28, accuracy: 0.05)
        let pdf = try file([page])
        XCTAssertTrue(pdf.contains("/Subtype /Type0 /BaseFont /SnapflyText /Encoding /Identity-H /DescendantFonts [5 0 R] /ToUnicode 6 0 R"))
        XCTAssertTrue(pdf.contains("/Resources << /XObject << /Im0 12 0 R >> /Font << /F1 4 0 R >> >>"))
    }

    /// A right-to-left word is written as it stands from the left, as most
    /// PDFs hold such words and readers turn them back: its numbers and
    /// Latin letters read on as they are; every other word is as it reads.
    func testARightToLeftWordIsWrittenAsItStandsFromTheLeft() {
        func visual(_ word: String) -> String {
            String(decoding: ScanPDF.visual(Array(word.utf16)), as: UTF16.self)
        }
        XCTAssertEqual(visual("مرحبا"), "ابحرم")
        XCTAssertEqual(visual("שלום"), "םולש")
        XCTAssertEqual(visual("مرحبا "), " ابحرم", "the space after it stands left of it")
        XCTAssertEqual(visual("(مرحبا)،"), "،)ابحرم(")
        XCTAssertEqual(visual("عام2026"), "2026ماع", "a number reads on from the left")
        XCTAssertEqual(visual("٢٠٢٦م"), "م٢٠٢٦")
        XCTAssertEqual(visual("رقم:12"), "12:مقر")
        XCTAssertEqual(visual("PDF-ملف"), "فلم-PDF")
        let marked = "بِسْمِ"
        XCTAssertEqual(visual(marked), String(String.UnicodeScalarView(marked.unicodeScalars.reversed())), "marks with their letters")
        for word in ["Rechnung", "Größe ", "İstanbul", "Москва", "東京都", "서울", "हिन्दी", "2026", "١٢٣", "٥٠٪", "12,50€", "(Note)"] {
            XCTAssertEqual(visual(word), word, word)
        }
    }

    func testARightToLeftWordsSpaceStandsLeftOfItsBox() throws {
        let page = ScanPDF.Page(picture: jpeg(2480, 3508), words: [
            ScanPDF.Word(text: "مرحبا ", box: CGRect(x: 0.5, y: 0.4, width: 0.1, height: 0.02)),
            ScanPDF.Word(text: "Gesamt ", box: CGRect(x: 0.5, y: 0.3, width: 0.1, height: 0.02)),
        ])
        let lines = ScanPDF.drawing(page, on: CGRect(origin: .zero, size: ScanGeometry.a4)).split(separator: "\n")
        let arabic = try XCTUnwrap(lines.first { $0.contains("Tj") && $0.contains("<00200627") }, "the space first, then the word from the left")
        let latin = try XCTUnwrap(lines.first { $0.contains("<0047") })
        func numbers(_ line: Substring) throws -> (size: Double, stretch: Double, x: Double) {
            let parts = line.split(separator: " ")
            let tm = try XCTUnwrap(parts.firstIndex(of: "Tm"))
            return (Double(parts[1])!, Double(parts[3])!, Double(parts[tm - 2])!)
        }
        let (size, stretch, x) = try numbers(arabic)
        let space: Double = Double(ScanFont.advance) * size / 1000 * stretch / 100
        XCTAssertEqual(x + space, 297.64, accuracy: 0.01, "its letters from the box's left")
        XCTAssertEqual(Double("مرحبا".utf16.count * ScanFont.advance) * size / 1000 * stretch / 100, 0.1 * 595.28, accuracy: 0.05)
        XCTAssertEqual(try numbers(latin).x, 297.64, accuracy: 0.01, "a left-to-right word at its box")
    }

    func testEveryScriptIsKeptAndOnlyACharacterBeyondUTF16sUnitsIsLeftOut() {
        for word in ["Straße Müller €", "“Grüße”", "Doğan İstanbul", "مرحبا", "Ελλάδα", "Москва", "東京都", "서울", "हिन्दी"] {
            XCTAssertEqual(ScanPDF.units(word).map { String(decoding: $0, as: UTF16.self) }, word, word)
        }
        XCTAssertNil(ScanPDF.units("Danke 😀"), "an emoji is beyond the units")
        XCTAssertNil(ScanPDF.units("Tab\there"), "a control character")
        XCTAssertNil(ScanPDF.units(""))
        let page = ScanPDF.Page(picture: jpeg(1000, 1414), words: [ScanPDF.Word(text: "😀", box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.02))])
        XCTAssertFalse(ScanPDF.drawing(page, on: CGRect(x: 0, y: 0, width: 595, height: 842)).contains("BT"))
    }

    func testTheWordsFontAndItsMapBackToTheCharactersAreInTheFile() throws {
        let page = ScanPDF.Page(picture: jpeg(1000, 1414), words: [ScanPDF.Word(text: "مرحبا", box: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.03))])
        let data = try Self.unpacked(try XCTUnwrap(ScanPDF.make([page])))
        let pdf = String(data.map { Character(Unicode.Scalar($0)) })
        XCTAssertTrue(pdf.contains("/Subtype /CIDFontType2 /BaseFont /SnapflyText /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>"))
        XCTAssertTrue(pdf.contains("/FontDescriptor 7 0 R /DW 500 /CIDToGIDMap 8 0 R"))
        XCTAssertTrue(pdf.contains("/Type /FontDescriptor /FontName /SnapflyText /Flags 5"))
        XCTAssertTrue(pdf.contains("/Length1 \(ScanFont.file.count)"))
        XCTAssertTrue(pdf.contains("<0000> <FFFF>\nendcodespacerange"))
        XCTAssertTrue(pdf.contains("<0600> <06FF> <0600>"), "Arabic's units map to themselves")
        XCTAssertFalse(pdf.contains("<D800>"), "no surrogate halves")
        let ranges = ScanFont.toUnicode.split(separator: "\n").filter { $0.hasSuffix(" beginbfrange") }
            .compactMap { Int($0.split(separator: " ")[0]) }
        XCTAssertEqual(ranges, [100, 100, 48], "248 ranges, a hundred at most at a time")
        XCTAssertTrue(pdf.contains("<06270628062D06310645>"), "the word as its units, as it stands from the left")
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

    #if canImport(PDFKit) && canImport(CoreText)
    /// Read back by PDFKit as anyone's reader reads it: every script's
    /// words are found; and the font file itself opens as a font.
    func testPDFKitFindsTheWordsInEveryScript() throws {
        let words = ["Rechnung", "Größe", "İstanbul", "مرحبا", "Москва", "東京都", "서울"]
        var placed = words.enumerated().map { index, word in
            ScanPDF.Word(text: word, box: CGRect(x: 0.1, y: 0.9 - CGFloat(index) * 0.05, width: 0.3, height: 0.03))
        }
        // A right-to-left line of two words, the first on the right.
        placed += [ScanPDF.Word(text: "شكرا ", box: CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.03)),
                   ScanPDF.Word(text: "جزيلا", box: CGRect(x: 0.35, y: 0.4, width: 0.2, height: 0.03))]
        let page = ScanPDF.Page(picture: jpeg(1000, 1414), words: placed)
        let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(ScanPDF.make([page]))))
        let text = pdf.string ?? ""
        for word in words + ["شكرا", "جزيلا"] {
            XCTAssertTrue(text.contains(word), "\(word) in \(text)")
        }
        XCTAssertFalse(pdf.findString("Größe", withOptions: []).isEmpty, "found by search")
        XCTAssertFalse(pdf.findString("مرحبا", withOptions: []).isEmpty, "a right-to-left word found by search, \(text)")
        // How PDFKit orders the words of a right-to-left line, as a notice on the build.
        let line = text.split(separator: "\n").filter { $0.contains("شكرا") || $0.contains("جزيلا") }.joined(separator: " | ")
        let scalars = line.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
        print("::notice title=PDFKIT LINE::\(line) (\(scalars))")
        let provider = try XCTUnwrap(CGDataProvider(data: ScanFont.file as CFData))
        XCTAssertNotNil(CGFont(provider), "Core Graphics opens the font")
        XCTAssertNotNil(CTFontManagerCreateFontDescriptorFromData(ScanFont.file as CFData), "Core Text opens the font")
    }
    #endif

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
