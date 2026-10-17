import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// A month's receipts in one PDF, to hand to the tax advisor: a page that
/// lists them, then each receipt on a page of its own, the covered copy
/// saved for the books. It helps hand them on; it is not an archive of
/// record.
enum ReceiptsPack {
    /// A receipt as the folder's table lists it.
    struct Row: Equatable {
        var day: String
        var file: String
        var order = ""
        var total = ""

        /// Its month, like "2026-10".
        var month: String { String(day.prefix(7)) }
    }

    // MARK: The table, read back

    /// The table's receipts, in its order. Its lines are split the way they
    /// were written, and the apostrophe that keeps a spreadsheet from taking
    /// a field for a formula comes off again. Lines without a day, like the
    /// headings, are left out.
    static func rows(fromTable text: String) -> [Row] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return records(in: text, separator: separator(of: text)).compactMap { fields in
            guard fields.count >= 2, isDay(fields[0]), !fields[1].isEmpty else { return nil }
            return Row(day: fields[0], file: fields[1],
                       order: fields.count > 2 ? fields[2] : "",
                       total: fields.count > 3 ? fields[3] : "")
        }
    }

    /// The months there are receipts for, newest first, like "2026-10".
    static func months(in rows: [Row]) -> [String] {
        Set(rows.map(\.month)).sorted(by: >)
    }

    /// A semicolon where the first line has more of them than commas, as
    /// tables are written where numbers use a decimal comma.
    static func separator(of text: String) -> Character {
        let first = text.prefix { !$0.isNewline }
        return first.filter { $0 == ";" }.count > first.filter { $0 == "," }.count ? ";" : ","
    }

    /// The fields of each line, with quotes taken off and doubled quotes
    /// made single.
    static func records(in text: String, separator: Character) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var wasQuoted = false
        var characters = text.makeIterator()
        var held: Character?
        while let c = held ?? characters.next() {
            held = nil
            if quoted {
                if c == "\"" {
                    if let next = characters.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; held = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"", field.isEmpty, !wasQuoted {
                quoted = true
                wasQuoted = true
            } else if c == separator {
                fields.append(unguarded(field))
                field = ""
                wasQuoted = false
            } else if c.isNewline {
                fields.append(unguarded(field))
                records.append(fields)
                fields = []
                field = ""
                wasQuoted = false
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !fields.isEmpty || wasQuoted {
            fields.append(unguarded(field))
            records.append(fields)
        }
        return records
    }

    /// A field as it was before an apostrophe went in front of a leading
    /// = + - or @.
    private static func unguarded(_ field: String) -> String {
        guard field.first == "'", let next = field.dropFirst().first, "=+-@".contains(next) else { return field }
        return String(field.dropFirst())
    }

    private static func isDay(_ text: String) -> Bool {
        let characters = Array(text)
        guard characters.count == 10, characters[4] == "-", characters[7] == "-" else { return false }
        return characters.enumerated().allSatisfy { $0.offset == 4 || $0.offset == 7 || $0.element.isASCII && $0.element.isNumber }
    }

    // MARK: The sum

    /// The totals added up and written the way the first one is, when they
    /// are all in one currency; nil when there are none, or they mix.
    static func sum(of totals: [String]) -> String? {
        let totals = totals.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = totals.first else { return nil }
        let currency = currencyMark(of: first)
        guard totals.allSatisfy({ currencyMark(of: $0) == currency }) else { return nil }
        var cents = 0
        for total in totals {
            guard let value = OrderCard.value(of: total) else { return nil }
            let negative = total.prefix { !$0.isNumber }.contains { $0 == "-" || $0 == "−" }
            cents += Int((value * 100).rounded()) * (negative ? -1 : 1)
        }
        let decimal = decimalMark(of: first) ?? (Locale.current.decimalSeparator == "," ? "," : ".")
        let grouping: Character = decimal == "," ? "." : ","
        var grouped = ""
        for (i, digit) in String(abs(cents) / 100).reversed().enumerated() {
            if i > 0, i % 3 == 0 { grouped.append(grouping) }
            grouped.append(digit)
        }
        let number = (cents < 0 ? "-" : "") + String(grouped.reversed()) + String(decimal)
            + String(format: "%02d", abs(cents) % 100)
        let prefix = first.prefix { !$0.isNumber }.filter { $0 != "-" && $0 != "−" && $0 != "'" }
        let suffix = String(first.reversed().prefix { !$0.isNumber }.reversed())
        return String(prefix) + number + suffix
    }

    /// What says the currency, like "€", "$" or "EUR".
    private static func currencyMark(of amount: String) -> String {
        amount.filter { !$0.isNumber && !$0.isWhitespace && !",.-−'".contains($0) }.uppercased()
    }

    /// The comma or point before the cents, as `OrderCard.value` reads it.
    private static func decimalMark(of amount: String) -> Character? {
        let digits = amount.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard let mark = digits.lastIndex(where: { $0 == "," || $0 == "." }) else { return nil }
        return (1...2).contains(digits[digits.index(after: mark)...].count) ? digits[mark] : nil
    }

    // MARK: Words

    /// The language Snapfly speaks, for the month's and the day's names.
    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The month as people say it, like "October 2026".
    static func title(month: String, locale: Locale = appLocale) -> String {
        let read = DateFormatter()
        read.locale = Locale(identifier: "en_US_POSIX")
        read.dateFormat = "yyyy-MM"
        guard let date = read.date(from: month) else { return month }
        let write = DateFormatter()
        write.locale = locale
        write.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return write.string(from: date)
    }

    /// A file's SHA-256, so anyone can check a receipt in the folder is the
    /// one in the pack.
    static func fingerprint(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The PDF

    /// A4, in points, as a tax advisor prints it.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 48
    private static let rowHeight: CGFloat = 18
    /// Receipts listed on the first page, under the title, and on each one
    /// after it.
    static let rowsOnFirstPage = 30
    static let rowsPerPage = 36

    /// How many pages the list takes.
    static func listPages(for count: Int) -> Int {
        count <= rowsOnFirstPage ? 1 : 1 + (count - rowsOnFirstPage + rowsPerPage - 1) / rowsPerPage
    }

    /// Writes the month's pack into the folder, beside its receipts, and
    /// says where. A receipt missing from the folder stays on the list,
    /// without a page.
    static func make(month: String, rows: [Row], in folder: URL, made: Date = Date(),
                     locale: Locale = appLocale, rightToLeft: Bool = false) -> URL? {
        let rows = rows.filter { $0.month == month }
        guard !rows.isEmpty else { return nil }
        let title = String(format: L("Receipts %@"), Self.title(month: month, locale: locale))
        let target = unique(String(format: L("Receipts %@"), month), in: folder)
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Snapfly"]
        guard let context = CGContext(target as CFURL, mediaBox: &box, info as CFDictionary) else { return nil }

        // Each receipt found gets a page after the list.
        let files = rows.map { folder.appendingPathComponent($0.file) }
        let readable = files.map { url in
            CGImageSourceCreateWithURL(url as CFURL, nil).map {
                CGImageSourceGetStatus($0) == .statusComplete && CGImageSourceGetCount($0) > 0
            } ?? false
        }
        let list = listPages(for: rows.count)
        var pages: [Int?] = []
        var next = list + 1
        for found in readable {
            pages.append(found ? next : nil)
            if found { next += 1 }
        }
        let total = next - 1

        let day = DateFormatter()
        day.locale = locale
        day.dateStyle = .long
        var start = 0
        for page in 1...list {
            context.beginPDFPage(nil)
            var top = pageSize.height - margin
            if page == 1 {
                draw(title, in: CGRect(x: margin, y: top - 28, width: pageSize.width - 2 * margin, height: 28),
                     size: 20, weight: .semibold, rightToLeft: rightToLeft, in: context)
                top -= 34
                let note = String(format: L("Put together by Snapfly on %@ to hand to your tax advisor. Each receipt is the covered copy saved for the books."),
                                  day.string(from: made))
                draw(note, in: CGRect(x: margin, y: top - 30, width: pageSize.width - 2 * margin, height: 30),
                     size: 9.5, gray: 0.4, wraps: true, rightToLeft: rightToLeft, in: context)
                top -= 46
            }
            let count = page == 1 ? rowsOnFirstPage : rowsPerPage
            let end = min(rows.count, start + count)
            top = drawTable(rows[start..<end].map { $0 }, files: Array(files[start..<end]), pages: Array(pages[start..<end]),
                            top: top, rightToLeft: rightToLeft, in: context)
            start = end
            if page == list {
                var lines = [String(format: L("Receipts: %ld"), rows.count)]
                if let added = sum(of: rows.map(\.total)) { lines.append(String(format: L("Sum of the totals: %@"), added)) }
                let missing = pages.filter { $0 == nil }.count
                if missing > 0 { lines.append(String(format: L("Not found in the folder: %ld"), missing)) }
                for line in lines {
                    draw(line, in: CGRect(x: margin, y: top - 26, width: pageSize.width - 2 * margin, height: 16),
                         size: 10, weight: .medium, rightToLeft: rightToLeft, in: context)
                    top -= 16
                }
            }
            drawNumber(page, of: total, in: context)
            context.endPDFPage()
        }

        for (i, row) in rows.enumerated() {
            guard let page = pages[i], let image = pageImage(of: files[i]) else { continue }
            context.beginPDFPage(nil)
            let caption = [row.day, row.order.isEmpty ? "" : L("Order") + " " + row.order, row.total]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            draw(caption, in: CGRect(x: margin, y: pageSize.height - margin - 14, width: pageSize.width - 2 * margin, height: 14),
                 size: 9, gray: 0.4, rightToLeft: rightToLeft, in: context)
            let room = CGRect(x: margin, y: margin + 18, width: pageSize.width - 2 * margin,
                              height: pageSize.height - 2 * margin - 18 - 24)
            let scale = min(room.width / CGFloat(image.width), room.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: room.midX - size.width / 2, y: room.maxY - size.height,
                                           width: size.width, height: size.height))
            drawNumber(page, of: total, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return target
    }

    /// The list's headings and a line a receipt, from the top given; returns
    /// where the table ends.
    private static func drawTable(_ rows: [Row], files: [URL], pages: [Int?], top: CGFloat,
                                  rightToLeft: Bool, in context: CGContext) -> CGFloat {
        // Day, order, total, page and fingerprint, across the page.
        let width = pageSize.width - 2 * margin
        let widths: [CGFloat] = [76, width - 76 - 92 - 44 - 112, 92, 44, 112]
        func cell(_ column: Int, _ y: CGFloat) -> CGRect {
            var x = margin + widths[..<column].reduce(0, +)
            if rightToLeft { x = pageSize.width - x - widths[column] }
            return CGRect(x: x, y: y, width: widths[column] - 6, height: rowHeight - 4)
        }
        let numbers: CTTextAlignment = rightToLeft ? .left : .right
        var y = top - rowHeight
        let headings = [L("Date"), L("Order"), L("Total"), L("Page"), L("Fingerprint")]
        for (column, heading) in headings.enumerated() {
            draw(heading, in: cell(column, y), size: 8.5, weight: .semibold, gray: 0.4,
                 alignment: column == 2 || column == 3 ? numbers : .natural, rightToLeft: rightToLeft, in: context)
        }
        rule(at: y - 2, in: context)
        for (i, row) in rows.enumerated() {
            y -= rowHeight
            let found = pages[i] != nil
            let gray: CGFloat = found ? 0 : 0.55
            let mark = found ? fingerprint(of: files[i]).map { String($0.prefix(16)) } ?? "" : ""
            let cells = [row.day, row.order, row.total, pages[i].map { String($0) } ?? "—", mark]
            for (column, text) in cells.enumerated() {
                draw(text, in: cell(column, y), size: column == 4 ? 8 : 10, gray: gray,
                     alignment: column == 2 || column == 3 ? numbers : .natural, mono: column == 4,
                     rightToLeft: rightToLeft, in: context)
            }
            rule(at: y - 2, gray: 0.9, in: context)
        }
        return y - 6
    }

    private static func rule(at y: CGFloat, gray: CGFloat = 0.75, in context: CGContext) {
        context.setStrokeColor(CGColor(gray: gray, alpha: 1))
        context.setLineWidth(0.5)
        context.strokeLineSegments(between: [CGPoint(x: margin, y: y), CGPoint(x: pageSize.width - margin, y: y)])
    }

    private static func drawNumber(_ page: Int, of total: Int, in context: CGContext) {
        draw("\(page) / \(total)", in: CGRect(x: margin, y: margin - 30, width: pageSize.width - 2 * margin, height: 12),
             size: 8, gray: 0.55, alignment: .center, rightToLeft: false, in: context)
    }

    /// Text in a box, on one line cut short with an ellipsis unless it wraps.
    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                             gray: CGFloat = 0, alignment: CTTextAlignment = .natural, mono: Bool = false,
                             wraps: Bool = false, rightToLeft: Bool, in context: CGContext) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        var alignment = alignment
        var breaking: CTLineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        var direction: CTWritingDirection = alignment == .natural && rightToLeft ? .rightToLeft : .natural
        let style = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &breaking) { b in
                withUnsafeBytes(of: &direction) { d in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                        CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: b.count, value: b.baseAddress!),
                        CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: d.count, value: d.baseAddress!),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ]
        let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    /// A receipt as its page shows it: at most 2000 pixels across, on white,
    /// kept as a JPEG, so a month of them stays small enough to mail.
    static func pageImage(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2000,
        ]
        guard let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let canvas = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let whole = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
        canvas.setFillColor(CGColor(gray: 1, alpha: 1))
        canvas.fill(whole)
        canvas.draw(picture, in: whole)
        guard let flat = canvas.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return flat }
        CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                 intent: .defaultIntent) else { return flat }
        return jpeg
    }

    private static func unique(_ name: String, in folder: URL) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension("pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)").appendingPathExtension("pdf")
            n += 1
        }
        return url
    }
}
