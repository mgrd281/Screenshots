import Foundation

/// Pages' text as a Word document (.docx, Office Open XML), to change in
/// Word, Pages or Google Docs: in reading order, as `ScanReading` reads it,
/// a heading as a heading, a block of short lines, as an address, as one
/// paragraph with its lines kept, a table as a table with its cells, every
/// covered stretch as the mark, a page break between pages, and a page in
/// Arabic or Hebrew from the right. Nothing in it says who made it or when.
/// Written by hand, its parts in a ZIP stored without compression.
enum WordFile {
    /// The document's bytes.
    static func data(_ pages: [ScanReading.Page], mark: String = ScanReading.mark) -> Data {
        Zip.archive([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(packageRelations.utf8)),
            ("word/_rels/document.xml.rels", Data(documentRelations.utf8)),
            ("word/styles.xml", Data(styles.utf8)),
            ("word/document.xml", Data(document(pages, mark: mark).utf8)),
        ])
    }

    /// The document's body as WordprocessingML.
    static func document(_ pages: [ScanReading.Page], mark: String = ScanReading.mark) -> String {
        var body = ""
        for (index, page) in pages.enumerated() {
            if index > 0 { body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            for block in page.blocks {
                switch block {
                case .paragraph(let paragraph):
                    let text = ScanReading.runs(of: paragraph, rightToLeft: page.rightToLeft, mark: mark).map(\.text).joined()
                    guard !text.isEmpty else { continue }
                    body += self.paragraph(text, heading: paragraph.heading, rightToLeft: page.rightToLeft)
                case .table(let table):
                    // An empty line after each table, as the text has one: Word
                    // would join two tables with nothing between into one, and
                    // a document ends with a paragraph.
                    let xml = self.table(table, rightToLeft: page.rightToLeft, mark: mark)
                    if !xml.isEmpty { body += xml + "<w:p/>" }
                }
            }
        }
        if body.isEmpty { body = "<w:p/>" }
        return header + #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>"#
            + body + section + "</w:body></w:document>"
    }

    /// A paragraph, its lines kept apart by line breaks.
    private static func paragraph(_ text: String, heading: Bool, rightToLeft: Bool) -> String {
        var properties = heading ? #"<w:pStyle w:val="Heading1"/>"# : ""
        if rightToLeft { properties += "<w:bidi/>" }
        let runs = text.components(separatedBy: "\n").map { run($0, rightToLeft: rightToLeft) }
            .joined(separator: rightToLeft ? "<w:r><w:rPr><w:rtl/></w:rPr><w:br/></w:r>" : "<w:r><w:br/></w:r>")
        return "<w:p>" + (properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>") + runs + "</w:p>"
    }

    private static func run(_ text: String, rightToLeft: Bool) -> String {
        "<w:r>" + (rightToLeft ? "<w:rPr><w:rtl/></w:rPr>" : "") + #"<w:t xml:space="preserve">"# + escaped(text) + "</w:t></w:r>"
    }

    /// A table, every row as wide as the widest, its columns as wide as
    /// their words want.
    private static func table(_ table: ScanReading.Table, rightToLeft: Bool, mark: String) -> String {
        let columns = table.rows.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        // The table's properties in the order the format sets.
        var xml = #"<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>"# + (rightToLeft ? "<w:bidiVisual/>" : "")
            + #"<w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>"#
            + String(repeating: "<w:gridCol/>", count: columns) + "</w:tblGrid>"
        for row in table.rows {
            xml += "<w:tr>"
            for column in 0..<columns {
                let text = column < row.count ? ScanReading.line(of: row[column], mark: mark) : ""
                xml += #"<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>"#
                    + (text.isEmpty ? "<w:p/>" : paragraph(text, heading: false, rightToLeft: rightToLeft)) + "</w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    /// Text as XML takes it: its five marks written out, and the control
    /// characters XML has no place for left out.
    static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t": out += " "
            default:
                let value = scalar.value
                guard value >= 0x20, !(0xFFFE...0xFFFF).contains(value) else { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: The parts

    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    /// An A4 page with margins of 2 cm.
    private static let section = #"<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>"#

    private static let contentTypes = header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>"#

    private static let packageRelations = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#

    private static let documentRelations = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#

    /// Plain text in 11 point, a heading in 14 point bold, a table with thin lines.
    private static let styles = header + #"<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style><w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/></w:tblBorders></w:tblPr></w:style></w:styles>"#
}

/// A ZIP archive of files stored as they are, without compression, as
/// a Word document's parts may be: each with its name, its CRC-32 and its
/// sizes, the time left at the format's first day, 1 January 1980, so the
/// archive says nothing about when it was made.
enum Zip {
    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var directory = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(out.count)
            // The local header.
            out.append(le32(0x0403_4B50))
            out.append(common(name: name, crc: crc, size: UInt32(file.data.count)))
            out.append(name)
            out.append(file.data)
            // Its entry in the central directory.
            directory.append(le32(0x0201_4B50))
            directory.append(le16(20)) // made by: version 2.0
            directory.append(common(name: name, crc: crc, size: UInt32(file.data.count)))
            directory.append(le16(0)) // no comment
            directory.append(le16(0)) // disk 0
            directory.append(le16(0)) // internal attributes
            directory.append(le32(0)) // external attributes
            directory.append(le32(offset))
            directory.append(name)
        }
        let start = UInt32(out.count)
        out.append(directory)
        // The end of the central directory.
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(files.count)))
        out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(directory.count)))
        out.append(le32(start))
        out.append(le16(0))
        return out
    }

    /// What a local header and a directory entry share, from the version
    /// needed on: stored, UTF-8 names, the first day, the sizes, the name's
    /// length and no extra field.
    private static func common(name: Data, crc: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.append(le16(20)) // needed: version 2.0
        data.append(le16(1 << 11)) // the name is UTF-8
        data.append(le16(0)) // stored
        data.append(le16(0)) // 00:00
        data.append(le16(1 << 5 | 1)) // 1 January 1980
        data.append(le32(crc))
        data.append(le32(size))
        data.append(le32(size))
        data.append(le16(UInt16(name.count)))
        data.append(le16(0))
        return data
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)])
    }

    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    /// The CRC-32 ZIP checks each file by.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
