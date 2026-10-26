import Foundation

/// A page's words as a reader takes them in, from Vision's reading of it: a
/// column to its end before the next, a table row by row, the lines of a
/// paragraph run on where they run on, a word broken over two lines made
/// whole again, and every place a cover hides as a mark that says only that
/// something is there. Nothing is read or guessed here: only the words read,
/// put in order. Pure, so it is checked on any machine.
///
/// The page is cut where white space runs through all of it, as a reader's
/// eye parts it (a recursive XY cut): into bands where space runs right
/// across it, as a page is read from the top down, then each band into
/// columns where space runs down it. Columns whose lines stand side by side,
/// nearly all of them, are a table, unless one of them is prose or a column
/// after the first names its own values ("Datum: 14.10.2026"), as a
/// letter's information block beside its address does.
enum ScanReading {
    /// A word read on the page, or a place a cover hides.
    struct Word: Equatable, Sendable {
        var text: String
        /// From 0 to 1 from the bottom left of the page, as Vision measures.
        var box: CGRect
        /// A cover lies here: what it hides is not known here and never shown.
        var covered = false

        static func covered(_ box: CGRect) -> Word {
            Word(text: "", box: box, covered: true)
        }
    }

    /// Words read as one stretch of a line, in their order.
    struct Segment: Equatable, Sendable {
        var words: [Word]

        var box: CGRect {
            words.dropFirst().reduce(words.first?.box ?? .zero) { $0.union($1.box) }
        }

        var covered: Bool { words.allSatisfy(\.covered) }
    }

    /// A paragraph, a block of short lines such as an address, or a heading.
    struct Paragraph: Equatable, Sendable {
        /// Its lines in order, each its words in order.
        var lines: [[Word]]
        /// The lines run on into each other, as prose does; otherwise each
        /// line stands on its own.
        var flows: Bool
        /// Set larger than the page's usual print, a line or two.
        var heading: Bool
    }

    /// Rows of cells, each cell its words.
    struct Table: Equatable, Sendable {
        var rows: [[[Word]]]
    }

    enum Block: Equatable, Sendable {
        case paragraph(Paragraph)
        case table(Table)
    }

    struct Page: Equatable, Sendable {
        var blocks: [Block]
        /// Read from the right, as Arabic and Hebrew are.
        var rightToLeft: Bool
    }

    /// Where the cuts fall, in the height of the page's usual line.
    enum Tuning {
        /// White space running across everything that parts it into bands:
        /// at least this, and wider than the space between its lines by half
        /// again and a quarter of a line, so a page set at one and a half or
        /// double spacing keeps its paragraphs whole.
        static let bandGap: CGFloat = 0.6
        /// White space running down everything that parts it into columns.
        static let columnGap: CGFloat = 1.2
        /// A line at least this share of its block's width runs on.
        static let fill: CGFloat = 0.7
        /// Lines run on only in a block at least this share of the page's
        /// width, or with this many characters a line as a median: an
        /// address's short lines each stand on their own.
        static let proseWidth: CGFloat = 0.45
        static let proseCharacters = 32
        /// A column with this many lines of this many characters as a median
        /// is prose, never a table's column.
        static let proseLines = 4
        static let proseColumnCharacters = 30
        /// A table's rows: this share of them with cells in two columns or more.
        static let tableRows: CGFloat = 0.75
        /// A heading is set this much larger than the usual line; print this
        /// much larger or smaller than the line before starts a paragraph.
        static let heading: CGFloat = 1.3
        /// A cover at most this many usual lines tall hides words; a taller
        /// one hides a picture, a face or a code, and is left out of the text.
        static let coverLines: CGFloat = 2.5
    }

    // MARK: Reading order

    /// The page in reading order. `aspect` is its width over its height.
    static func page(_ segments: [Segment], aspect: CGFloat) -> Page {
        let read = segments.filter { !$0.words.isEmpty && !$0.covered }
        let heights = read.map(\.box.height).sorted()
        guard !heights.isEmpty, aspect > 0 else { return Page(blocks: [], rightToLeft: false) }
        let usual = max(heights[heights.count / 2], 0.0001)
        let rightToLeft = rightToLeft(read.flatMap(\.words).map(\.text).joined())
        let kept = segments.filter { segment in
            !segment.words.isEmpty && (!segment.covered || segment.box.height <= usual * Tuning.coverLines)
        }
        let items = kept.enumerated().map { Item(id: $0.offset, segment: $0.element, aspect: aspect) }
        let layout = Layout(usual: usual, width: aspect, rightToLeft: rightToLeft)
        return Page(blocks: layout.cut(items), rightToLeft: rightToLeft)
    }

    /// Whether most letters are written from the right.
    static func rightToLeft(_ text: String) -> Bool {
        var right = 0, left = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if isRightToLeft(scalar) { right += 1 } else { left += 1 }
        }
        return right > left
    }

    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: true
        default: false
        }
    }

    /// A segment where it lies, in the page's heights from the top left.
    private struct Item {
        let id: Int
        let segment: Segment
        let left, right, top, bottom: CGFloat

        init(id: Int, segment: Segment, aspect: CGFloat) {
            self.id = id
            self.segment = segment
            let box = segment.box
            left = box.minX * aspect
            right = box.maxX * aspect
            top = 1 - box.maxY
            bottom = 1 - box.minY
        }

        var height: CGFloat { bottom - top }
        var middle: CGFloat { (top + bottom) / 2 }
        /// A cover counts as a short word.
        var characters: Int {
            segment.covered ? 6 : segment.words.reduce(0) { $0 + $1.text.count + 1 }
        }
    }

    /// White space between intervals that overlap no other: where it starts and how wide.
    private struct Gap {
        let start: CGFloat
        let size: CGFloat
    }

    private struct Layout {
        let usual: CGFloat
        /// The page's width, in its heights.
        let width: CGFloat
        let rightToLeft: Bool

        /// Cut into bands where white space runs right across, else into
        /// columns where it runs right down, then each part again, until
        /// nothing parts them.
        func cut(_ items: [Item]) -> [Block] {
            guard items.count > 1 else { return leaf(items) }
            let least = bandGap(items)
            let across = gaps(items.map { ($0.top, $0.bottom) }).filter { $0.size >= least }
            if !across.isEmpty {
                return split(items, at: across) { $0.top }.flatMap(cut)
            }
            let down = gaps(items.map { ($0.left, $0.right) }).filter { $0.size >= Tuning.columnGap * usual }
            if !down.isEmpty {
                return columns(items, at: down)
            }
            return leaf(items)
        }

        /// The white space a band needs: wider than the space between the
        /// lines of a paragraph here (the middle of the spaces under a line
        /// and a half), so a paragraph is never parted line by line, even
        /// set at double spacing.
        private func bandGap(_ items: [Item]) -> CGFloat {
            let lines = rows(items)
            var spaces: [CGFloat] = []
            for (line, next) in zip(lines, lines.dropFirst()) {
                let space = (next.map(\.top).min() ?? 0) - (line.map(\.bottom).max() ?? 0)
                if space > 0, space < 1.5 * usual { spaces.append(space) }
            }
            let between = spaces.isEmpty ? 0.25 * usual : spaces.sorted()[spaces.count / 2]
            return max(Tuning.bandGap * usual, 1.5 * between + 0.25 * usual)
        }

        /// Columns side by side: a table where most rows have cells in two
        /// of them and none is prose; else each column read to its end, from
        /// the reading side.
        private func columns(_ items: [Item], at gaps: [Gap]) -> [Block] {
            // One line across them all is read as one line.
            if rows(items).count == 1 { return leaf(items) }
            let parts = split(items, at: gaps) { $0.left }
            if let table = table(items, parts) { return [.table(table)] }
            return (rightToLeft ? parts.reversed() : parts).flatMap(cut)
        }

        private func table(_ items: [Item], _ columns: [[Item]]) -> Table? {
            for column in columns {
                let read = column.filter { !$0.segment.covered }
                guard read.count >= Tuning.proseLines else { continue }
                let counts = read.map(\.characters).sorted()
                if counts[counts.count / 2] >= Tuning.proseColumnCharacters { return nil }
            }
            // A column that names its own values stands on its own.
            let reading = rightToLeft ? Array(columns.reversed()) : columns
            for column in reading.dropFirst() {
                let read = column.filter { !$0.segment.covered }.map { $0.segment.words.map(\.text).joined(separator: " ") }
                let named = read.filter(Self.namesItsValue).count
                if !read.isEmpty, 2 * named >= read.count { return nil }
            }
            var columnOf: [Int: Int] = [:]
            for (index, column) in columns.enumerated() {
                for item in column { columnOf[item.id] = index }
            }
            let lines = rows(items)
            let spanning = lines.filter { Set($0.compactMap { columnOf[$0.id] }).count >= 2 }.count
            guard lines.count >= 2, spanning >= 2, CGFloat(spanning) >= Tuning.tableRows * CGFloat(lines.count) else { return nil }
            let order = rightToLeft ? Array(columns.indices.reversed()) : Array(columns.indices)
            let rows = lines.map { line -> [[Word]] in
                order.map { column in
                    line.filter { columnOf[$0.id] == column }.flatMap(\.segment.words)
                }
            }
            return Table(rows: rows)
        }

        /// "Datum: 14.10.2026": a label, a colon and its value after it.
        static func namesItsValue(_ text: String) -> Bool {
            guard let colon = text.firstIndex(of: ":") else { return false }
            let label = text[..<colon], value = text[text.index(after: colon)...]
            return label.contains { $0.isLetter } && value.contains { !$0.isWhitespace }
        }

        /// Lines in order, then parted into paragraphs where the print grows
        /// or shrinks, or a short line ends a sentence.
        private func leaf(_ items: [Item]) -> [Block] {
            let lines = rows(items)
            guard !lines.isEmpty else { return [] }
            let left = items.map(\.left).min() ?? 0, right = items.map(\.right).max() ?? 0
            let blockWidth = max(right - left, 0.0001)
            var groups: [[[Item]]] = []
            var current: [[Item]] = []
            for line in lines {
                if let last = current.last {
                    let grows = max(height(line), height(last)) > Tuning.heading * min(height(line), height(last))
                    let ended = span(last) < Tuning.fill * blockWidth && endsSentence(last)
                    if grows || ended {
                        groups.append(current)
                        current = []
                    }
                }
                current.append(line)
            }
            if !current.isEmpty { groups.append(current) }
            return groups.map { group -> Block in
                let words = group.map { $0.flatMap(\.segment.words) }
                let heights = group.map(height).sorted()
                let heading = group.count <= 2 && heights[heights.count / 2] >= Tuning.heading * usual
                return .paragraph(Paragraph(lines: words, flows: flows(group, blockWidth: blockWidth), heading: heading))
            }
        }

        /// Prose: two lines or more, the lines before the last filling the
        /// block, in a block wide on the page or of long lines.
        private func flows(_ lines: [[Item]], blockWidth: CGFloat) -> Bool {
            guard lines.count >= 2 else { return false }
            let counts = lines.map { $0.reduce(0) { $0 + $1.characters } }.sorted()
            guard blockWidth >= Tuning.proseWidth * width || counts[counts.count / 2] >= Tuning.proseCharacters else { return false }
            let before = lines.dropLast()
            let full = before.filter { span($0) >= Tuning.fill * blockWidth }.count
            return CGFloat(full) >= 0.7 * CGFloat(before.count)
        }

        /// The items that lie on one line together, top to bottom, each line
        /// from the reading side.
        func rows(_ items: [Item]) -> [[Item]] {
            var lines: [(middle: CGFloat, height: CGFloat, items: [Item])] = []
            for item in items.sorted(by: { $0.middle < $1.middle }) {
                if let index = lines.lastIndex(where: { abs(item.middle - $0.middle) <= 0.5 * min(item.height, $0.height) }) {
                    lines[index].items.append(item)
                } else {
                    lines.append((item.middle, item.height, [item]))
                }
            }
            return lines.map { line in
                line.items.sorted { rightToLeft ? $0.right > $1.right : $0.left < $1.left }
            }
        }

        private func height(_ line: [Item]) -> CGFloat {
            let heights = line.filter { !$0.segment.covered }.map(\.height).sorted()
            return heights.isEmpty ? usual : heights[heights.count / 2]
        }

        private func span(_ line: [Item]) -> CGFloat {
            (line.map(\.right).max() ?? 0) - (line.map(\.left).min() ?? 0)
        }

        private func endsSentence(_ line: [Item]) -> Bool {
            guard let last = line.last?.segment.words.last, !last.covered,
                  let end = last.text.last else { return false }
            return ".!?".contains(end)
        }

        /// White space between the intervals, wherever none of them reaches.
        private func gaps(_ spans: [(CGFloat, CGFloat)]) -> [Gap] {
            let sorted = spans.sorted { $0.0 < $1.0 }
            guard var reach = sorted.first?.1 else { return [] }
            var found: [Gap] = []
            for (start, end) in sorted.dropFirst() {
                if start > reach { found.append(Gap(start: reach, size: start - reach)) }
                reach = max(reach, end)
            }
            return found
        }

        /// The items parted at the gaps, in order along the cut.
        private func split(_ items: [Item], at gaps: [Gap], by place: (Item) -> CGFloat) -> [[Item]] {
            let cuts = gaps.map { $0.start + $0.size / 2 }.sorted()
            var parts = [[Item]](repeating: [], count: cuts.count + 1)
            for item in items {
                let index = cuts.firstIndex { place(item) < $0 } ?? cuts.count
                parts[index].append(item)
            }
            return parts.filter { !$0.isEmpty }
        }
    }

    // MARK: Text

    /// The mark a covered stretch is written as: a bar that says only that
    /// something is there.
    static let mark = "███"

    /// What the pages say, as plain text: blocks parted by an empty line, a
    /// table's cells by tabs, its rows by lines, every covered stretch as
    /// `mark`, however many words it hides.
    static func text(_ pages: [Page], mark: String = mark) -> String {
        pages.map { text($0, mark: mark) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func text(_ page: Page, mark: String = mark) -> String {
        page.blocks.map { block -> String in
            switch block {
            case .paragraph(let paragraph):
                let lines = paragraph.lines.map { line(of: $0, mark: mark) }
                return paragraph.flows && !page.rightToLeft ? runOn(lines) : lines.joined(separator: paragraph.flows ? " " : "\n")
            case .table(let table):
                return table.rows.map { row in row.map { line(of: $0, mark: mark) }.joined(separator: "\t") }
                    .joined(separator: "\n")
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Words as they stand on a line, every covered stretch as one mark.
    static func line(of words: [Word], mark: String = mark) -> String {
        var parts: [String] = []
        var inCover = false
        for word in words {
            if word.covered {
                if !inCover { parts.append(mark) }
                inCover = true
            } else if !word.text.isEmpty {
                parts.append(word.text)
                inCover = false
            }
        }
        return parts.joined(separator: " ")
    }

    /// Lines of prose run on into one: a word broken over two lines with a
    /// hyphen made whole again where the next line goes on in small letters
    /// ("Bildschirm-" "foto"), a hyphen kept where it goes on with a capital
    /// ("E-" "Mail") or the word is short, and "Haus- und Gartenbedarf" kept
    /// as it is.
    static func runOn(_ lines: [String]) -> String {
        var out = ""
        for line in lines where !line.isEmpty {
            guard !out.isEmpty else {
                out = line
                continue
            }
            let lastWord = out.split(separator: " ").last.map(String.init) ?? ""
            let next = line.split(separator: " ").first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
            let hyphen = out.last.map { ["-", "\u{00AD}", "\u{2010}"].contains($0) } ?? false
            guard hyphen, lastWord.count >= 2, let first = line.first, first.isLetter else {
                out += " " + line
                continue
            }
            if first.isLowercase, joiners.contains(next) {
                out += " " + line
            } else if first.isLowercase, lastWord.count >= 3 {
                out.removeLast()
                out += line
            } else {
                // The hyphen stays, a plain one.
                out.removeLast()
                out += "-" + line
            }
        }
        return out
    }

    /// Words a hyphen before them leaves standing: "Haus- und Gartenbedarf".
    private static let joiners: Set<String> = ["und", "oder", "bzw", "sowie", "bis", "and", "or", "to", "et", "ou",
                                               "y", "o", "e", "ve", "veya", "und/oder"]

    /// What the pages say, for the words laid invisibly in a PDF: in
    /// reading order, each with a space after it where another follows on
    /// its line or in its cell; nothing covered.
    static func words(_ page: Page) -> [ScanPDF.Word] {
        var out: [ScanPDF.Word] = []
        func add(_ words: [Word]) {
            let read = words.filter { !$0.covered && !$0.text.isEmpty }
            for (index, word) in read.enumerated() {
                out.append(ScanPDF.Word(text: index < read.count - 1 ? word.text + " " : word.text, box: word.box))
            }
        }
        for block in page.blocks {
            switch block {
            case .paragraph(let paragraph):
                paragraph.lines.forEach(add)
            case .table(let table):
                for row in table.rows { row.forEach(add) }
            }
        }
        return out
    }

    /// A line read whole made into the stretches its covers part: a word
    /// under a cover is left out, and the stretch goes on after it as
    /// another, so the cover's mark stands between them where it lies.
    static func segments(_ words: [Word], hiding places: [CGRect]) -> [Segment] {
        var segments: [Segment] = []
        var current: [Word] = []
        for word in words {
            let hidden = places.contains { place in
                let shared = place.intersection(word.box)
                return !shared.isNull && shared.width * shared.height > 0.05 * word.box.width * word.box.height
            }
            if hidden {
                if !current.isEmpty { segments.append(Segment(words: current)) }
                current = []
            } else {
                current.append(word)
            }
        }
        if !current.isEmpty { segments.append(Segment(words: current)) }
        return segments
    }

    /// The covers as marks, each its own stretch.
    static func marks(_ places: [CGRect]) -> [Segment] {
        places.map { Segment(words: [.covered($0)]) }
    }
}
