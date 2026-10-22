#if DEBUG && canImport(CoreText) && canImport(PDFKit)
import CoreGraphics
import CoreText
import Foundation

/// Made-up files to put a PDF together from, without a real document: a
/// three-page invoice with real text in it, the same locked with a
/// password, a signed contract, a PDF of 300 pages, and photos of a narrow
/// receipt and of a page lying sideways. Every company, person, address and
/// IBAN on them is made up; the IBAN is the one banks use as an example. In
/// debug builds only, for the tests and the pictures made in CI.
enum PDFFixtures {
    static let customer = "Erika Mustermann"
    static let iban = "DE89 3704 0044 0532 0130 00"
    static let street = "Musterstraße 12"
    static let town = "20095 Hamburg"
    /// The locked PDF's password, made up too.
    static let password = "Muster-2026"

    // MARK: PDFs

    /// Three A4 pages with real text: an invoice to the made-up customer,
    /// its terms, and a page of payment details with the IBAN again.
    static func invoice(password: String? = nil) -> Data {
        pdf(pages: 3, password: password) { context, page in
            switch page {
            case 0:
                write("Musterfirma GmbH", context, x: 56, top: 60, size: 22, bold: true)
                write("Beispielweg 5 · 10115 Berlin", context, x: 56, top: 90, size: 10)
                for (line, text) in [customer, street, town].enumerated() {
                    write(text, context, x: 56, top: 150 + CGFloat(line) * 16, size: 11)
                }
                write("Rechnungsnr. RE-2026-0412", context, x: 360, top: 150, size: 10)
                write("Datum 21.10.2026", context, x: 360, top: 166, size: 10)
                write("Rechnung", context, x: 56, top: 240, size: 20, bold: true)
                let rows = [("1", "Beratung", "2 Std.", "180,00 €"), ("2", "Einrichtung", "1", "90,00 €"),
                            ("3", "Lizenz", "1", "49,90 €")]
                for (index, row) in rows.enumerated() {
                    let top = 290 + CGFloat(index) * 22
                    write(row.0, context, x: 56, top: top, size: 10)
                    write(row.1, context, x: 90, top: top, size: 10)
                    write(row.2, context, x: 330, top: top, size: 10)
                    write(row.3, context, x: 470, top: top, size: 10)
                }
                write("Gesamt 380,68 €", context, x: 420, top: 380, size: 11, bold: true)
                write("Bitte bis 04.11. überweisen.", context, x: 56, top: 440, size: 11)
                write("IBAN \(iban) · BIC COBADEFFXXX", context, x: 56, top: 470, size: 10)
            case 1:
                write("Zahlungsbedingungen", context, x: 56, top: 60, size: 16, bold: true)
                let terms = ["Zahlbar innerhalb von 14 Tagen ohne Abzug.", "Bei Fragen erreichen Sie uns unter 030 1234567.",
                             "Rechnungsempfängerin: \(customer)", "Lieferanschrift: \(street), \(town)"]
                for (line, text) in terms.enumerated() { write(text, context, x: 56, top: 100 + CGFloat(line) * 18, size: 11) }
            default:
                write("Zahlungsdaten", context, x: 56, top: 60, size: 16, bold: true)
                write("Kontoinhaberin: \(customer)", context, x: 56, top: 100, size: 11)
                write("IBAN: \(iban)", context, x: 56, top: 118, size: 11)
                write("Verwendungszweck: RE-2026-0412", context, x: 56, top: 136, size: 11)
            }
        }
    }

    /// The invoice, opened only with `password`.
    static func locked() -> Data {
        invoice(password: password)
    }

    /// Pages numbered "Seite 1 von 300" and on, a few lines each.
    static func long(pages count: Int = 300) -> Data {
        pdf(pages: count, password: nil) { context, page in
            write("Seite \(page + 1) von \(count)", context, x: 56, top: 60, size: 18, bold: true)
            for line in 0..<6 {
                write("Abschnitt \(page + 1).\(line + 1): Musterfirma GmbH, Protokoll und Anlagen.", context, x: 56,
                      top: 100 + CGFloat(line) * 18, size: 11)
            }
        }
    }

    /// A contract signed with a digital signature: written by hand, with a
    /// signature field whose value names the bytes it covers, as a signed
    /// PDF's does. The signature itself is made up and checks nothing.
    static func signed() -> Data {
        let lines = [("Mietvertrag", 24, 760), ("Mieterin: \(customer)", 12, 720), ("Wohnung: \(street), \(town)", 12, 700),
                     ("Digital unterschrieben von Max Muster am 20.10.2026.", 10, 150)]
        let content = lines.map { text, size, y in
            "BT /F1 \(size) Tf 60 \(y) Td (\(text)) Tj ET"
        }.joined(separator: "\n")
        let stream = latin(content)
        var contents = Data("<< /Length \(stream.count) >>\nstream\n".utf8)
        contents.append(stream)
        contents.append(Data("\nendstream".utf8))
        let objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] /SigFlags 3 >> >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
            Data(("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 4 0 R >> >> "
                + "/Contents 7 0 R /Annots [5 0 R] >>").utf8),
            Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".utf8),
            Data("<< /Type /Annot /Subtype /Widget /FT /Sig /T (Unterschrift) /Rect [60 80 260 130] /F 132 /P 3 0 R /V 6 0 R >>".utf8),
            Data(("<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 0 0 0] "
                + "/Contents <\(String(repeating: "0", count: 64))> /M (D:20261020120000+02'00') /Name (Max Muster) >>").utf8),
            contents,
        ]
        var file = Data("%PDF-1.7\n".utf8) + Data([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(file.count)
            file.append(Data("\(index + 1) 0 obj\n".utf8))
            file.append(body)
            file.append(Data("\nendobj\n".utf8))
        }
        let start = file.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            let digits = String(offset)
            table += String(repeating: "0", count: 10 - digits.count) + digits + " 00000 n \n"
        }
        table += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
        file.append(Data(table.utf8))
        return file
    }

    /// Text in PDF's Western encoding, as a page's contents hold it.
    private static func latin(_ text: String) -> Data {
        text.data(using: .isoLatin1) ?? Data(text.utf8)
    }

    /// A4 pages drawn with real text, as a word processor writes them.
    private static func pdf(pages: Int, password: String?, draw: (CGContext, Int) -> Void) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        var info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly fixtures"]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password + "-owner"
        }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        for page in 0..<pages {
            context.beginPDFPage(nil)
            draw(context, page)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Words with their top `top` points down an A4 page.
    private static func write(_ text: String, _ context: CGContext, x: CGFloat, top: CGFloat, size: CGFloat,
                              bold: Bool = false, height: CGFloat = 841.89) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: height - top - CTFontGetAscent(font))
        CTLineDraw(line, context)
    }

    // MARK: Photos

    /// A till receipt as a photo would show it flat: long and narrow, 640 by 2200 pixels.
    static func receipt() -> CGImage? {
        let width = 640, height = 2200
        guard let context = PictureTools.context(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let lines: [(String, CGFloat, Bool)] = [
            ("Bäckerei Muster", 44, true), ("Hauptstraße 1 · 10115 Berlin", 24, false), ("21.10.2026 08:14", 24, false),
            ("2 × Brötchen      1,20 €", 28, false), ("1 × Kaffee        2,80 €", 28, false),
            ("1 × Croissant     1,90 €", 28, false), ("Summe             5,90 €", 32, true),
            ("Kartenzahlung", 24, false), ("Vielen Dank!", 28, false),
        ]
        var top: CGFloat = 120
        for (text, size, bold) in lines {
            write(text, context, x: 48, top: top, size: size, bold: bold, height: CGFloat(height))
            top += size * 2.2
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        for bar in 0..<40 where bar % 3 != 1 {
            context.fill(CGRect(x: 120 + bar * 10, y: 160, width: bar % 2 == 0 ? 6 : 3, height: 120))
        }
        return context.makeImage()
    }

    /// A printed page photographed lying sideways, 2000 by 1414 pixels.
    static func sideways() -> CGImage? {
        let width = 2000, height = 1414
        guard let context = PictureTools.context(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let lines = ["Protokoll der Sitzung vom 14.10.2026", "Anwesend: Max Muster, \(customer)",
                     "Nächster Termin: 28.10.2026"]
        for (index, text) in lines.enumerated() {
            write(text, context, x: 120, top: 160 + CGFloat(index) * 90, size: 52, bold: index == 0, height: CGFloat(height))
        }
        return context.makeImage()
    }
}
#endif
