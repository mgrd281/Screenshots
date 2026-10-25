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

    /// A place in the pages' text: the page, the block, and in a table the
    /// row and the column.
    struct Spot: Hashable, Sendable {
        var page: Int
        var block: Int
        var row: Int?
        var column: Int?

        init(page: Int, block: Int, row: Int? = nil, column: Int? = nil) {
            self.page = page
            self.block = block
            self.row = row
            self.column = column
        }
    }

    /// A line the reading was unsure of, and where it lies on the page.
    struct UnsureSpot: Equatable, Sendable, Identifiable {
        var spot: Spot
        /// Which line of a paragraph it is; 0 for a table's cell.
        var line: Int
        var box: CGRect

        var id: String { "\(spot.page)-\(spot.block)-\(spot.row ?? -1)-\(spot.column ?? -1)-\(line)" }
    }

    /// Where the reading was unsure, to check against the page.
    static func unsureSpots(_ page: Page, number: Int = 0) -> [UnsureSpot] {
        var found: [UnsureSpot] = []
        func add(_ words: [Word], _ spot: Spot, line: Int) {
            let unsure = words.filter { $0.unsure && !$0.covered }
            if !unsure.isEmpty { found.append(UnsureSpot(spot: spot, line: line, box: box(of: unsure))) }
        }
        for (blockIndex, block) in page.blocks.enumerated() {
            switch block {
            case .paragraph(let paragraph):
                for (line, words) in paragraph.lines.enumerated() { add(words, Spot(page: number, block: blockIndex), line: line) }
            case .table(let table):
                for (row, cells) in table.rows.enumerated() {
                    for (column, cell) in cells.enumerated() { add(cell, Spot(page: number, block: blockIndex, row: row, column: column), line: 0) }
                }
            }
        }
        return found
    }

    static func unsureBoxes(_ page: Page) -> [CGRect] {
        unsureSpots(page).map(\.box)
    }

    /// How many lines (a table's cells count one each) were read unsurely.
    static func unsureCount(_ pages: [Page]) -> Int {
        pages.enumerated().reduce(0) { $0 + unsureSpots($1.element, number: $1.offset).count }
    }

    /// The text of the paragraph or the cell at a spot, as it is shown.
    static func text(at spot: Spot, in pages: [Page]) -> String? {
        guard pages.indices.contains(spot.page), pages[spot.page].blocks.indices.contains(spot.block) else { return nil }
        let page = pages[spot.page]
        switch page.blocks[spot.block] {
        case .paragraph(let paragraph):
            return runs(of: paragraph, rightToLeft: page.rightToLeft).map(\.text).joined()
        case .table(let table):
            guard let row = spot.row, let column = spot.column, table.rows.indices.contains(row),
                  table.rows[row].indices.contains(column) else { return nil }
            return line(of: table.rows[row][column])
        }
    }

    /// The key a correction at a spot is kept under, from the pages as read.
    static func editKey(at spot: Spot, in pages: [Page]) -> String? {
        guard pages.indices.contains(spot.page), pages[spot.page].blocks.indices.contains(spot.block) else { return nil }
        let page = pages[spot.page]
        switch page.blocks[spot.block] {
        case .paragraph(let paragraph):
            return editKey(of: paragraph, rightToLeft: page.rightToLeft)
        case .table(let table):
            guard let row = spot.row, let column = spot.column, table.rows.indices.contains(row),
                  table.rows[row].indices.contains(column) else { return nil }
            return editKey(ofCell: table.rows[row][column])
        }
    }

    /// The box of a paragraph or a cell at a spot.
    static func box(at spot: Spot, in pages: [Page]) -> CGRect? {
        guard pages.indices.contains(spot.page), pages[spot.page].blocks.indices.contains(spot.block) else { return nil }
        switch pages[spot.page].blocks[spot.block] {
        case .paragraph(let paragraph):
            return box(of: paragraph.lines.flatMap { $0 })
        case .table(let table):
            guard let row = spot.row, let column = spot.column, table.rows.indices.contains(row),
                  table.rows[row].indices.contains(column) else { return box(of: pages[spot.page].blocks[spot.block]) }
            return box(of: table.rows[row][column])
        }
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

    /// A few letters found in a paragraph or a cell, and where.
    struct Match: Equatable, Sendable {
        var spot: Spot
        /// Character offsets in the text of that paragraph or cell.
        var range: Range<Int>
    }

    /// Every place in the pages that holds the letters, in reading order.
    static func matches(_ query: String, in pages: [Page]) -> [Match] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found: [Match] = []
        for (pageIndex, page) in pages.enumerated() {
            for (blockIndex, block) in page.blocks.enumerated() {
                switch block {
                case .paragraph(let paragraph):
                    let text = runs(of: paragraph, rightToLeft: page.rightToLeft).map(\.text).joined()
                    found += find(query, in: text).map { Match(spot: Spot(page: pageIndex, block: blockIndex), range: $0) }
                case .table(let table):
                    for (row, cells) in table.rows.enumerated() {
                        for (column, cell) in cells.enumerated() {
                            found += find(query, in: line(of: cell)).map {
                                Match(spot: Spot(page: pageIndex, block: blockIndex, row: row, column: column), range: $0)
                            }
                        }
                    }
                }
            }
        }
        return found
    }

    /// A range of UTF-16 units as character offsets in the text.
    static func characterRange(_ range: NSRange, in text: String) -> Range<Int>? {
        guard let found = Range(range, in: text) else { return nil }
        return text.distance(from: text.startIndex, to: found.lowerBound)..<text.distance(from: text.startIndex, to: found.upperBound)
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
