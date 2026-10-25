import Foundation

/// What is done with a page's text once it is read (`ScanReading`): a word
/// corrected by hand, a table handed to a spreadsheet, the text found by a
/// few letters, spoken block by block with the spoken word known in the shown
/// text, and where a block lies on the page, to check it against the page.
/// Pure, so it is checked on any machine. Nothing here reads, guesses or adds
/// a word: a correction is only what the person typed, and a cover stays a
/// mark in everything made of the text.
extension ScanReading {
    // MARK: Corrections

    /// The key a correction is kept under: the text as it was read, so it
    /// applies to the same text again and never to another block that a later
    /// reading numbers the same.
    static func editKey(of paragraph: Paragraph, rightToLeft: Bool) -> String {
        "p:" + runs(of: paragraph, rightToLeft: rightToLeft).map(\.text).joined()
    }

    static func editKey(ofCell words: [Word]) -> String {
        "c:" + line(of: words)
    }

    /// The page with its corrections made: a corrected paragraph or cell is
    /// one stretch of what was typed, no longer unsure. For the text that is
    /// copied, shared and spoken; never for the words laid in a PDF, which
    /// keep the places they were read in.
    static func applying(_ edits: [String: String], to page: Page) -> Page {
        guard !edits.isEmpty else { return page }
        var out = page
        out.blocks = page.blocks.map { block in
            switch block {
            case .paragraph(let paragraph):
                guard let typed = edits[editKey(of: paragraph, rightToLeft: page.rightToLeft)] else { return block }
                let whole = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                return .paragraph(Paragraph(lines: [[Word(text: whole, box: box(of: paragraph.lines.flatMap { $0 }))]],
                                            flows: false, heading: paragraph.heading))
            case .table(let table):
                return .table(Table(rows: table.rows.map { row in
                    row.map { cell -> [Word] in
                        guard let typed = edits[editKey(ofCell: cell)] else { return cell }
                        let one = typed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                        return [Word(text: one, box: box(of: cell))]
                    }
                }))
            }
        }
        return out
    }

    // MARK: Where things lie

    /// The smallest box holding the words, from 0 to 1 from the bottom left.
    static func box(of words: [Word]) -> CGRect {
        words.dropFirst().reduce(words.first?.box ?? .zero) { $0.union($1.box) }
    }

    static func box(of block: Block) -> CGRect {
        switch block {
        case .paragraph(let paragraph): box(of: paragraph.lines.flatMap { $0 })
        case .table(let table): box(of: table.rows.flatMap { $0.flatMap { $0 } })
        }
    }

    /// Where the reading was unsure, to check against the page.
    static func unsureBoxes(_ page: Page) -> [CGRect] {
        var found: [CGRect] = []
        func add(_ words: [Word]) {
            let unsure = words.filter { $0.unsure && !$0.covered }
            if !unsure.isEmpty { found.append(box(of: unsure)) }
        }
        for block in page.blocks {
            switch block {
            case .paragraph(let paragraph): paragraph.lines.forEach(add)
            case .table(let table): table.rows.forEach { $0.forEach(add) }
            }
        }
        return found
    }

    /// How many lines (a table's cells count one each) were read unsurely.
    static func unsureCount(_ pages: [Page]) -> Int {
        pages.reduce(0) { $0 + unsureBoxes($1).count }
    }

    // MARK: Tables

    /// A table as tab-separated rows, as Numbers and Excel take it pasted
    /// into cells: a tab or a line break inside a cell is a space.
    static func tsv(_ table: Table, mark: String = mark) -> String {
        table.rows.map { row in
            row.map { line(of: $0, mark: mark).replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// The list separator a spreadsheet expects: a semicolon where numbers are
    /// written with a decimal comma, as Excel does, else a comma.
    static func csvDelimiter(decimalSeparator: String?) -> Character {
        decimalSeparator == "," ? ";" : ","
    }

    /// A table as CSV (RFC 4180): cells holding the delimiter, a quote or a
    /// line break in quotes, a quote doubled, rows parted by CRLF. A cell a
    /// spreadsheet would run as a formula ("=...", "@...", "-A1") gets an
    /// apostrophe first; a number or a phone number is left as it is.
    static func csv(_ table: Table, mark: String = mark, delimiter: Character = ",") -> String {
        table.rows.map { row in
            row.map { cell in quoted(neutralized(line(of: cell, mark: mark)), delimiter: delimiter) }
                .joined(separator: String(delimiter))
        }.joined(separator: "\r\n")
    }

    private static func quoted(_ cell: String, delimiter: Character) -> String {
        let needs = cell.contains(delimiter) || cell.contains("\"") || cell.contains("\n") || cell.contains("\r")
        return needs ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
    }

    static func neutralized(_ cell: String) -> String {
        guard let first = cell.first else { return cell }
        if first == "=" || first == "@" || first == "\t" || first == "\r" { return "'" + cell }
        if first == "+" || first == "-" {
            // "-12,50", "+49 30 1234" and "- " are not formulas; "-A1" and "+SUM(" are.
            guard let second = cell.dropFirst().first else { return cell }
            if second.isNumber || second == " " || second == "." || second == "," { return cell }
            return "'" + cell
        }
        return cell
    }

    // MARK: Finding

    /// Where a few letters are in a text, as character offsets, with no regard
    /// to case or accents: "uber" finds "Über".
    static func find(_ query: String, in text: String) -> [Range<Int>] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return [] }
        var found: [Range<Int>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let hit = text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            found.append(text.distance(from: text.startIndex, to: hit.lowerBound)..<text.distance(from: text.startIndex, to: hit.upperBound))
            from = hit.upperBound > hit.lowerBound ? hit.upperBound : text.index(after: hit.upperBound)
        }
        return found
    }

    // MARK: Speaking

    /// One piece of speech: a paragraph, or a table's row, as it is shown and
    /// as it is said, with where each spoken unit is in what is shown.
    struct Utterance: Equatable, Sendable {
        /// Which page and block it is, and which row of a table.
        var page: Int
        var block: Int
        var row: Int?
        var shown: String
        var spoken: String
        /// For each UTF-16 unit of `spoken`: the stretch of `shown` it stands for.
        var from: [Int]
        var to: [Int]

        /// The shown text's range for a range of what is spoken.
        func shownRange(_ spokenRange: NSRange) -> NSRange? {
            guard spokenRange.length > 0, spokenRange.location >= 0, spokenRange.location < from.count else { return nil }
            let last = min(spokenRange.location + spokenRange.length, to.count) - 1
            guard last >= spokenRange.location else { return nil }
            return NSRange(location: from[spokenRange.location], length: max(0, to[last] - from[spokenRange.location]))
        }
    }

    /// The pages spoken in order, a paragraph at a time and a table a row at a
    /// time. A cover is said as `spokenMark` and what it hides is never in it;
    /// a line break or a cell's end is a pause.
    static func utterances(_ pages: [Page], spokenMark: String) -> [Utterance] {
        var out: [Utterance] = []
        for (pageIndex, page) in pages.enumerated() {
            for (blockIndex, block) in page.blocks.enumerated() {
                switch block {
                case .paragraph(let paragraph):
                    let shown = runs(of: paragraph, rightToLeft: page.rightToLeft).map(\.text).joined()
                    if let utterance = utterance(shown, page: pageIndex, block: blockIndex, row: nil, spokenMark: spokenMark) {
                        out.append(utterance)
                    }
                case .table(let table):
                    for (rowIndex, row) in table.rows.enumerated() {
                        let shown = row.map { line(of: $0) }.joined(separator: "\t")
                        if let utterance = utterance(shown, page: pageIndex, block: blockIndex, row: rowIndex, spokenMark: spokenMark) {
                            out.append(utterance)
                        }
                    }
                }
            }
        }
        return out
    }

    private static func utterance(_ shown: String, page: Int, block: Int, row: Int?, spokenMark: String) -> Utterance? {
        var spoken = ""
        var from: [Int] = [], to: [Int] = []
        var at = shown.startIndex
        var offset = 0
        func say(_ text: String, covering length: Int) {
            spoken += text
            let count = text.utf16.count
            from += [Int](repeating: offset, count: count)
            to += [Int](repeating: offset + length, count: count)
        }
        while at < shown.endIndex {
            if shown[at...].hasPrefix(mark) {
                say(spokenMark, covering: mark.utf16.count)
                at = shown.index(at, offsetBy: mark.count)
                offset += mark.utf16.count
                continue
            }
            let character = shown[at]
            let length = String(character).utf16.count
            switch character {
            case "\n", "\t":
                say(", ", covering: length)
            default:
                say(String(character), covering: length)
            }
            at = shown.index(after: at)
            offset += length
        }
        guard !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Utterance(page: page, block: block, row: row, shown: shown, spoken: spoken, from: from, to: to)
    }
}
