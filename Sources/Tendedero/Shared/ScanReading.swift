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
        /// The reading was not sure of the line this word is on, so it is
        /// shown with a mark to check against the page; never changed.
        var unsure = false

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
        /// Cells set close, as a receipt's items and their prices: white space
        /// this narrow down rows of them parts them, with numbers in a column.
        static let cellGap: CGFloat = 0.4
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
        /// Print this much smaller than the page's usual line, or smaller, is
        /// small print: a letter's foot, a sender's line.
        static let smallPrint: CGFloat = 0.8
        /// A column of words set this much smaller than the one beside it, or
        /// smaller, is a letterhead down the page's side, read on its own.
        static let sidebar: CGFloat = 0.7
        /// Rows of a table end where the space between lines is more than twice
        /// its usual, and at least this many usual lines.
        static let rowPace: CGFloat = 0.8
        /// Columns of small print are a table only with numbers in one column
        /// at least: this share of its cells.
        static let tableNumbers: CGFloat = 0.6
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
        let items = kept.flatMap { parted($0, aspect: aspect, usual: usual) }.enumerated()
            .map { Item(id: $0.offset, segment: $0.element, aspect: aspect) }
        let layout = Layout(usual: usual, width: aspect, rightToLeft: rightToLeft)
        return Page(blocks: layout.cut(items), rightToLeft: rightToLeft)
    }

    /// A line Vision read whole that holds a table's cells, their words far
    /// apart, as the stretches between those gaps, so the cells can be told
    /// apart; stretches of one row are read as the one line they were again.
    private static func parted(_ segment: Segment, aspect: CGFloat, usual: CGFloat) -> [Segment] {
        guard !segment.covered, segment.words.count > 1 else { return [segment] }
        let reach = Tuning.columnGap * max(usual, segment.box.height)
        var out: [Segment] = []
        var current: [Word] = []
        for word in segment.words {
            if let last = current.last, aspect * max(word.box.minX - last.box.maxX, last.box.minX - word.box.maxX) >= reach {
                out.append(Segment(words: current))
                current = []
            }
            current.append(word)
        }
        if !current.isEmpty { out.append(Segment(words: current)) }
        return out
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
            // A column of smaller print down the side of the text, as a
            // letterhead beside a letter, is read on its own, not band by band
            // with the text.
            let down = gaps(items.map { ($0.left, $0.right) }).filter { $0.size >= Tuning.columnGap * usual }
            if !down.isEmpty, rows(items).count > 1, hasSidebar(split(items, at: down) { $0.left }) {
                return columns(items, at: down)
            }
            let least = bandGap(items)
            // White space between the rows of a table is no band, however wide.
            let spans = rowSpans(items)
            let across = gaps(items.map { ($0.top, $0.bottom) }).filter { gap in
                gap.size >= least && !spans.contains { gap.start >= $0.top && gap.start + gap.size <= $0.bottom }
            }
            if !across.isEmpty {
                return split(items, at: across) { $0.top }.flatMap(cut)
            }
            if !down.isEmpty {
                return columns(items, at: down)
            }
            // Rows of cells set close among lines that are not, as a receipt's
            // items under its address, are a band of their own.
            let lines = rows(items)
            if let run = cellRun(lines), run.count < lines.count {
                return [lines[..<run.lowerBound], lines[run], lines[run.upperBound...]]
                    .map { $0.flatMap { $0 } }.filter { !$0.isEmpty }.flatMap(cut)
            }
            if let table = closeTable(items) { return [.table(table)] }
            return leaf(items)
        }

        /// Whether a column of words, not numbers, is set in print well
        /// smaller than the one beside it, each of three lines or more.
        private func hasSidebar(_ columns: [[Item]]) -> Bool {
            let sizes = columns.compactMap { column -> (size: CGFloat, words: Bool)? in
                guard rows(column).count >= 3 else { return nil }
                let heights = column.filter { !$0.segment.covered }.map(\.height).sorted()
                return heights.isEmpty ? nil : (heights[heights.count / 2], !hasNumbers([column]))
            }
            guard let largest = sizes.map(\.size).max() else { return false }
            return sizes.contains { $0.words && $0.size <= Tuning.sidebar * largest }
        }

        /// Two lines or more one after another, each of cells, down which a
        /// narrow corridor of white runs, with numbers in a column: a
        /// receipt's items and their prices.
        private func cellRun(_ lines: [[Item]]) -> Range<Int>? {
            var start = 0
            while start < lines.count {
                var end = start
                while end < lines.count, lines[end].count >= 2 { end += 1 }
                if end - start >= 2, closeColumns(lines[start..<end].flatMap { $0 }) != nil { return start..<end }
                start = max(end, start + 1)
            }
            return nil
        }

        /// The columns a narrow corridor parts items into, where one holds numbers.
        private func closeColumns(_ items: [Item]) -> [[Item]]? {
            let narrow = gaps(items.map { ($0.left, $0.right) }).filter { $0.size >= Tuning.cellGap * usual }
            guard !narrow.isEmpty else { return nil }
            let parts = split(items, at: narrow) { $0.left }
            return hasNumbers(parts) ? parts : nil
        }

        /// Rows of cells set close, as a receipt's, as a table.
        private func closeTable(_ items: [Item]) -> Table? {
            guard rows(items).count >= 2, let parts = closeColumns(items) else { return nil }
            return table(items, parts)
        }

        /// Where rows of cells stand, from the top of the first to the bottom
        /// of the last: three lines or more at an even pace, two of them in
        /// cells, that share a corridor of white running down through all of
        /// them; a line of one cell close under a row is a cell that wrapped,
        /// and the rows end with the last line of cells.
        private func rowSpans(_ items: [Item]) -> [(top: CGFloat, bottom: CGFloat)] {
            let lines = rows(items)
            guard lines.count >= 3 else { return [] }
            func top(_ line: [Item]) -> CGFloat { line.map(\.top).min() ?? 0 }
            func bottom(_ line: [Item]) -> CGFloat { line.map(\.bottom).max() ?? 0 }
            func corridor(_ lines: ArraySlice<[Item]>) -> Bool {
                !gaps(lines.flatMap { $0 }.map { ($0.left, $0.right) }).filter { $0.size >= Tuning.columnGap * usual }.isEmpty
            }
            var spans: [(top: CGFloat, bottom: CGFloat)] = []
            var start = 0
            while start < lines.count {
                guard lines[start].count >= 2 else {
                    start += 1
                    continue
                }
                var end = start
                while end + 1 < lines.count, corridor(lines[start...(end + 1)]) { end += 1 }
                // The pace of the lines: a break in it, as between an address and its table, ends the rows.
                let between = (start..<end).map { max(0, top(lines[$0 + 1]) - bottom(lines[$0])) }.sorted()
                let reach = between.isEmpty ? usual : max(2 * between[between.count / 2], Tuning.rowPace * usual)
                var from = start
                for line in start...end {
                    let breaks = line > start && top(lines[line]) - bottom(lines[line - 1]) > reach
                    if breaks || line == end {
                        var last = breaks ? line - 1 : line
                        while last > from, lines[last].count < 2 { last -= 1 }
                        if last - from + 1 >= 3, lines[from...last].filter({ $0.count >= 2 }).count >= 2 {
                            spans.append((top(lines[from]), bottom(lines[last])))
                        }
                        from = line
                    }
                }
                start = end + 1
            }
            return spans
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
            let reading = rightToLeft ? Array(parts.reversed()) : parts
            // An address shares no table's rows with what stands beside it,
            // as a letter's details do: it is read whole, then the rest.
            if reading.count >= 2, isAddress(reading[0]) {
                return cut(reading[0]) + cut(reading.dropFirst().flatMap { $0 })
            }
            if let table = table(items, parts) { return [.table(table)] }
            return reading.flatMap(cut)
        }

        /// An address: two to six lines, the last a postcode and a place ("20095 Hamburg", "D-20095 Hamburg").
        private func isAddress(_ items: [Item]) -> Bool {
            let lines = rows(items)
            guard (2...6).contains(lines.count), let last = lines.last else { return false }
            let words = last.flatMap(\.segment.words).filter { !$0.covered }.map(\.text)
            guard words.count >= 2, let place = words[1].first, place.isUppercase else { return false }
            let code = words[0].split(separator: "-").last.map(String.init) ?? words[0]
            let country = words[0].dropLast(code.count)
            return (4...5).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
                && (country.isEmpty || (country.count <= 3 && country.dropLast().allSatisfy(\.isUppercase)))
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
            // Small print in columns of words alone, as a letter's foot, is read
            // a column at a time, as it was set; a table of it has numbers.
            let heights = items.filter { !$0.segment.covered }.map(\.height).sorted()
            if let middle = heights.isEmpty ? nil : heights[heights.count / 2], middle <= Tuning.smallPrint * usual,
               !hasNumbers(columns) {
                return nil
            }
            var columnOf: [Int: Int] = [:]
            for (index, column) in columns.enumerated() {
                for item in column { columnOf[item.id] = index }
            }
            let lines = logicalRows(rows(items), columnOf: columnOf)
            let spanning = lines.filter { Set($0.flatMap { $0 }.compactMap { columnOf[$0.id] }).count >= 2 }.count
            guard lines.count >= 2, spanning >= 2, CGFloat(spanning) >= Tuning.tableRows * CGFloat(lines.count) else { return nil }
            let order = rightToLeft ? Array(columns.indices.reversed()) : Array(columns.indices)
            let rows = lines.map { row -> [[Word]] in
                order.map { column in
                    row.flatMap { line in line.filter { columnOf[$0.id] == column }.flatMap(\.segment.words) }
                }
            }
            return Table(rows: rows)
        }

        /// The lines of a table candidate as its rows: a line in one column
        /// that goes on a cell of the row above, close under it (nearer than
        /// the rows are to each other) or starting in small letters, a
        /// description that wraps ("Beratung und Einrichtung" / "inklusive
        /// Schulung"), belongs to that row; a title standing over its rows
        /// ("Hardware") does not.
        private func logicalRows(_ lines: [[Item]], columnOf: [Int: Int]) -> [[[Item]]] {
            func columnSet(_ line: [Item]) -> Set<Int> { Set(line.compactMap { columnOf[$0.id] }) }
            func top(_ line: [Item]) -> CGFloat { line.map(\.top).min() ?? 0 }
            func bottom(_ line: [Item]) -> CGFloat { line.map(\.bottom).max() ?? 0 }
            // How far apart two lines of cells standing one under the other are.
            var gaps: [CGFloat] = []
            for (line, next) in zip(lines, lines.dropFirst()) where columnSet(line).count >= 2 && columnSet(next).count >= 2 {
                gaps.append(top(next) - bottom(line))
            }
            let rowGap = gaps.isEmpty ? nil : gaps.sorted()[gaps.count / 2]
            var rows: [[[Item]]] = []
            for line in lines {
                let columns = columnSet(line)
                if columns.count == 1, let column = columns.first, let current = rows.last, let head = current.first, let above = current.last,
                   columnSet(head).count >= 2, columnSet(head).contains(column) {
                    let tight = rowGap.map { top(line) - bottom(above) <= 0.75 * $0 } ?? false
                    let small = !(line.first?.segment.words.first?.text.first?.isUppercase ?? true)
                    if tight || small {
                        rows[rows.count - 1].append(line)
                        continue
                    }
                }
                rows.append([line])
            }
            return rows
        }

        /// Whether a column of the candidate holds numbers: quantities, prices,
        /// dates; at least two cells, and this share of the cells read.
        private func hasNumbers(_ columns: [[Item]]) -> Bool {
            columns.contains { column in
                let read = column.filter { !$0.segment.covered }
                guard read.count >= 2 else { return false }
                let numbers = read.filter { Self.numeric($0.segment.words.map(\.text).joined(separator: " ")) }.count
                return CGFloat(numbers) >= Tuning.tableNumbers * CGFloat(read.count)
            }
        }

        /// A cell with a digit in it and hardly a letter: "85,00 €", "2 Std.", "14.10.", "RE-2026-0417".
        static func numeric(_ text: String) -> Bool {
            var digits = 0, letters = 0
            for character in text {
                if character.isNumber { digits += 1 } else if character.isLetter { letters += 1 }
            }
            return digits > 0 && letters <= 3
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
            // Short lines over a paragraph's first full one, as a subject line
            // and a salutation over a letter's text, stand on their own.
            var parted: [[[Item]]] = []
            for group in groups {
                if let first = group.firstIndex(where: { span($0) >= Tuning.fill * blockWidth }), first > 0,
                   group.count - first >= 3, flows(Array(group[first...]), blockWidth: blockWidth) {
                    parted += [Array(group[..<first]), Array(group[first...])]
                } else {
                    parted.append(group)
                }
            }
            return parted.map { group -> Block in
                let words = group.map { $0.flatMap(\.segment.words) }
                let heights = group.map(height).sorted()
                let middle = heights[heights.count / 2]
                // Larger than the page's usual print, and than the lines around it.
                let own = Set(group.flatMap { $0.map(\.id) })
                let around = lines.filter { !own.contains($0[0].id) }.map(height).sorted()
                let heading = group.count <= 2 && middle >= Tuning.heading * usual
                    && (around.isEmpty || middle >= Tuning.heading * around[around.count / 2])
                return .paragraph(Paragraph(lines: words, flows: flows(group, blockWidth: blockWidth), heading: heading))
            }
        }

        /// Prose: two lines or more, the lines before the last filling the
        /// block, in a block wide on the page or of long lines.
        private func flows(_ lines: [[Item]], blockWidth: CGFloat) -> Bool {
            guard lines.count >= 2 else { return false }
            // A line that names what follows ("Anwesend: …", "IBAN: …") or is
            // a number alone (a date, a time) stands on its own.
            if lines.dropFirst().contains(where: startsWithLabel) || lines.contains(where: isNumber) { return false }
            let counts = lines.map { $0.reduce(0) { $0 + $1.characters } }.sorted()
            guard blockWidth >= Tuning.proseWidth * width || counts[counts.count / 2] >= Tuning.proseCharacters else { return false }
            let before = lines.dropLast()
            let full = before.filter { span($0) >= Tuning.fill * blockWidth }.count
            return CGFloat(full) >= 0.7 * CGFloat(before.count)
        }

        /// "Anwesend: Max Muster", "Nächster Termin: 28.10.2026": a line that
        /// starts by naming what follows, in up to three words and a colon.
        private func startsWithLabel(_ line: [Item]) -> Bool {
            let words = Array(line.flatMap(\.segment.words).prefix(3))
            guard words.first?.text.first?.isUppercase == true,
                  let colon = words.firstIndex(where: { $0.text.hasSuffix(":") }) else { return false }
            return words[...colon].allSatisfy { !$0.covered && !$0.text.contains(where: \.isNumber) }
        }

        /// A line of a number alone, as a date, a time or an amount.
        private func isNumber(_ line: [Item]) -> Bool {
            let words = line.flatMap(\.segment.words)
            return !words.contains(where: \.covered) && Self.numeric(words.map(\.text).joined(separator: " "))
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
                return runs(of: paragraph, rightToLeft: page.rightToLeft, mark: mark).map(\.text).joined()
            case .table(let table):
                return table.rows.map { row in row.map { line(of: $0, mark: mark) }.joined(separator: "\t") }
                    .joined(separator: "\n")
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Words as they stand on a line, every covered stretch as one mark.
    static func line(of words: [Word], mark: String = mark) -> String {
        tokens(of: words, mark: mark).map(\.text).joined(separator: " ")
    }

    /// A stretch of a block's text and whether the reading was unsure of it.
    struct Run: Equatable, Sendable {
        var text: String
        var unsure: Bool
    }

    /// A paragraph as the text it makes, in stretches that are sure or unsure.
    /// Their texts together are what `text` gives for it.
    static func runs(of paragraph: Paragraph, rightToLeft: Bool, mark: String = mark) -> [Run] {
        let lines = paragraph.lines.map { tokens(of: $0, mark: mark) }.filter { !$0.isEmpty }
        if paragraph.flows && !rightToLeft {
            return joined([runOn(tokens: lines)])
        }
        return joined(lines, between: paragraph.flows ? " " : "\n")
    }

    /// A table's cell as the text it makes.
    static func runs(ofCell words: [Word], mark: String = mark) -> [Run] {
        joined([tokens(of: words, mark: mark)])
    }

    /// Words one by one, every covered stretch one token, the mark.
    private static func tokens(of words: [Word], mark: String) -> [Run] {
        var out: [Run] = []
        var inCover = false
        for word in words {
            if word.covered {
                if !inCover { out.append(Run(text: mark, unsure: false)) }
                inCover = true
            } else if !word.text.isEmpty {
                out.append(Run(text: word.text, unsure: word.unsure))
                inCover = false
            }
        }
        return out
    }

    /// Lines of tokens as stretches: a space between tokens, `between` between
    /// lines; the space goes to the side that is sure, so a mark never
    /// underlines the gap beside it.
    private static func joined(_ lines: [[Run]], between: String = " ") -> [Run] {
        var out: [Run] = []
        for (index, line) in lines.enumerated() {
            for (at, token) in line.enumerated() {
                let separator = at > 0 ? " " : (index > 0 ? between : "")
                guard let last = out.last else {
                    out.append(token)
                    continue
                }
                if last.unsure == token.unsure {
                    out[out.count - 1].text += separator + token.text
                } else if token.unsure {
                    out[out.count - 1].text += separator
                    out.append(token)
                } else {
                    out.append(Run(text: separator + token.text, unsure: false))
                }
            }
        }
        return out
    }

    /// Lines of prose run on into one: a word broken over two lines with a
    /// hyphen made whole again where the next line goes on in small letters
    /// ("Bildschirm-" "foto"), a hyphen kept where it goes on with a capital
    /// ("E-" "Mail") or the word is short, and "Haus- und Gartenbedarf" kept
    /// as it is.
    static func runOn(_ lines: [String]) -> String {
        let tokens = lines.map { $0.split(separator: " ").map { Run(text: String($0), unsure: false) } }
        return runOn(tokens: tokens).map(\.text).joined(separator: " ")
    }

    private static func runOn(tokens lines: [[Run]]) -> [Run] {
        var out: [Run] = []
        for line in lines where !line.isEmpty {
            guard let last = out.last else {
                out = line
                continue
            }
            let next = line[0].text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let hyphen = last.text.last.map { ["-", "\u{00AD}", "\u{2010}"].contains($0) } ?? false
            guard hyphen, last.text.count >= 2, let first = line[0].text.first, first.isLetter else {
                out += line
                continue
            }
            if first.isLowercase, joiners.contains(next) {
                out += line
            } else {
                // Made whole where it goes on in small letters and the word is
                // long enough; else the hyphen stays, a plain one.
                let whole = first.isLowercase && last.text.count >= 3
                out[out.count - 1] = Run(text: String(last.text.dropLast()) + (whole ? "" : "-") + line[0].text,
                                         unsure: last.unsure || line[0].unsure)
                out += line.dropFirst()
            }
        }
        return out
    }

    /// Words a hyphen before them leaves standing: "Haus- und Gartenbedarf".
    private static let joiners: Set<String> = ["und", "oder", "bzw", "sowie", "bis", "and", "or", "to", "et", "ou",
                                               "y", "o", "e", "ve", "veya", "und/oder"]

    /// What the pages say, for the words laid invisibly in a PDF: in
    /// reading order, each with a space after it where another follows on
    /// its line or in its row, so a table's cells are never copied run
    /// together; nothing covered.
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
                for row in table.rows { add(row.flatMap { $0 }) }
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
