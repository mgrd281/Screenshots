import AppKit

/// Copy Text from Screen, ⌃⌥C or from the menu: the words in a part of the
/// screen, read on this Mac and copied as they are, line by line, to paste
/// anywhere: an order number, a tracking number, an address, words in a
/// picture or a video. It is chosen as a screenshot is, but nothing hangs on
/// the line and no picture is kept. Like selecting words and pressing ⌘C,
/// nothing is covered: what you chose stays with you.
enum ScreenText {
    /// The lines read, in reading order: rows from the top; the parts of a
    /// row from the left, or from the right in Arabic or Hebrew; a blank
    /// line where a paragraph breaks.
    static func text(of lines: [(string: String, box: CGRect)]) -> String {
        let read = lines.filter { !$0.string.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        // Parts that share a row: their middles closer than half a line.
        var rows: [[(string: String, box: CGRect)]] = []
        for line in read {
            if let first = rows.last?.first,
               abs(first.box.midY - line.box.midY) < min(first.box.height, line.box.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        var text = ""
        var above: CGRect?
        for row in rows {
            let rightToLeft = isRightToLeft(row.map(\.string).joined())
            let parts = row.sorted { rightToLeft ? $0.box.maxX > $1.box.maxX : $0.box.minX < $1.box.minX }
            let box = parts.map(\.box).reduce(CGRect.null) { $0.union($1) }
            if let above {
                // More room than a line's height between two rows: a new paragraph.
                text += above.minY - box.maxY > max(above.height, box.height) * 0.9 ? "\n\n" : "\n"
            }
            text += parts.map { $0.string.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            above = box
        }
        return text
    }

    /// Whether most letters are written from the right, as Arabic's and Hebrew's are.
    static func isRightToLeft(_ text: String) -> Bool {
        var right = 0, left = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: right += 1
            default: left += 1
            }
        }
        return right > left
    }

    /// The start of what was copied, on one line, for the note.
    static func preview(_ text: String, longest: Int = 40) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard flat.count > longest else { return flat }
        return String(flat.prefix(longest)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Reads a picture of the screen in the background, then copies its
    /// words and says so, or says that none were found.
    @MainActor
    static func copy(from image: CGImage) {
        let note = Notice.show(L("Reading the text…"), working: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Self.text(of: Finder.textLines(in: image).map { (string: $0.string, box: $0.box) })
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Notice.end(note)
                    guard !text.isEmpty else {
                        Notice.show(L("No text found here."))
                        return
                    }
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.setString(text, forType: .string)
                    Notice.show(String(format: L("Copied: %@"), preview(text)), done: true)
                }
            }
        }
    }
}
