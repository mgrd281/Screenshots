import Foundation

/// Pieces most films share, so the line, the menu bar and the cards sit in
/// the same places in all of them.
enum FilmScene {
    typealias Part = SettingFilm.Part
    typealias Box = SettingFilm.Box

    static let desktop = Part.show(.desktop, Box(0.5, 0.5, 1, 1))
    static let menuBar = Part.show(.menuBar, Box(0.5, 0.04, 1, 0.08))
    static let dock = Part.show(.dock, Box(0.5, 0.93, 0.62, 0.1))
    static let notch = Part.show(.notch, Box(0.5, 0.04, 0.22, 0.08))

    /// The rope under the menu bar: its ends at 0.14, its lowest point,
    /// in the middle, at 0.2.
    static let ropeBox = Box(0.5, 0.2, 1.04, 0.12)

    static func rope(from start: Double = 0) -> Part {
        Part.show(.line(.rope), ropeBox, from: start)
    }

    /// The size of a screenshot card on the line.
    static let cardSize = (w: 0.14, h: 0.17)

    /// Where the rope is at a point across.
    static func ropeY(_ x: Double) -> Double {
        let s = (x - (ropeBox.x - ropeBox.w / 2)) / ropeBox.w
        return 0.14 + 0.24 * s * (1 - s)
    }

    /// Where a card hangs on the rope, its top at the rope: the nth of
    /// `count`, spread across the middle.
    static func slot(_ n: Int, of count: Int = 3) -> Box {
        let x = count == 1 ? 0.5 : 0.24 + 0.52 * Double(n) / Double(count - 1)
        return Box(x, ropeY(x) + cardSize.h / 2 + 0.01, cardSize.w, cardSize.h)
    }

    /// How a card leans where it hangs, a little each way.
    static func tilt(_ n: Int) -> Double { [-4, 2, 5, -3, 3][n % 5] }

    /// Cards already hanging, from the first slots of `count`.
    static func hanging(_ cards: Int, of count: Int = 3, from start: Double = 0) -> [Part] {
        (0..<cards).map { n in Part.show(.card(n), slot(n, of: count), from: start, angle: tilt(n)) }
    }

    /// The line as a film opens on it: the wallpaper, the menu bar, the
    /// rope and cards on it.
    static func line(cards: Int = 2, of count: Int = 3) -> [Part] {
        [desktop, menuBar, rope()] + hanging(cards, of: count)
    }
}

// MARK: What windows draw inside

extension FilmScene {
    /// The size films are drawn at, in points. A window's title bar and its
    /// lines of text are sized in points, so where they fall on the stage
    /// depends on it.
    static let points = (w: 240.0, h: 150.0)

    /// In points, as `FilmDrawing` draws it: the area inside a window's
    /// title bar and margins, where its content goes.
    static func content(ofWindow r: Box) -> Box {
        let bar = min(10, r.h * 0.14)
        let height = r.h - bar - r.h * 0.16
        return Box(r.x, r.y - r.h / 2 + bar + r.h * 0.08 + height / 2, r.w * 0.84, height)
    }

    /// In points: where a PDF page's lines of text go, under its red title.
    static func content(ofPDF r: Box) -> Box {
        Box(r.x, r.y - r.h / 2 + r.h * 0.61, r.w * 0.76, r.h * 0.58)
    }

    /// In points: the nth of `count` lines of text drawn across an area,
    /// from its leading edge, every second and third a little shorter.
    static func textRow(_ n: Int, of count: Int, in area: Box) -> Box {
        let step = area.h / Double(max(1, count))
        let thickness = max(1, min(step * 0.42, 4))
        let width = area.w * (n % 3 == 2 ? 0.62 : (n % 2 == 1 ? 0.84 : 1))
        return Box(area.x - area.w / 2 + width / 2, area.y - area.h / 2 + step * (Double(n) + 0.5), width, thickness)
    }

    /// On the stage: the box a cover fits over the nth line of text a part
    /// shows, from the top, or `part` of that line from its start. A web
    /// page shows 4 lines, a document 6, an email its 2 header lines then
    /// 4, a PDF page 4 and `.text` its own number.
    static func cover(line n: Int, of kind: SettingFilm.Kind, at box: Box, part: Double = 1) -> Box {
        let r = Box(box.x * points.w, box.y * points.h, box.w * points.w, box.h * points.h)
        let row: Box
        switch kind {
        case .window(.browser):
            row = textRow(n, of: 4, in: content(ofWindow: r))
        case .window(.mail):
            let c = content(ofWindow: r)
            let top = c.y - c.h / 2
            row = n < 2
                ? textRow(n, of: 2, in: Box(c.x - c.w / 2 + c.w * 0.3, top + c.h * 0.125, c.w * 0.6, c.h * 0.25))
                : textRow(n - 2, of: 4, in: Box(c.x, top + c.h * 0.675, c.w, c.h * 0.65))
        case .pdf:
            row = textRow(n, of: 4, in: content(ofPDF: r))
        case .text(let lines):
            row = textRow(n, of: lines, in: r)
        default:
            row = textRow(n, of: 6, in: content(ofWindow: r))
        }
        let width = row.w * min(max(part, 0.05), 1), pad = 2.0
        return Box((row.x - row.w / 2 + width / 2) / points.w, row.y / points.h,
                   (width + pad * 2) / points.w, (row.h + pad * 2) / points.h)
    }

    /// On the stage: a chat window's bubbles, theirs at the top and yours
    /// under it on the trailing side, and its message box at the bottom.
    static func chat(_ piece: ChatPiece, in window: Box) -> Box {
        let c = content(ofWindow: Box(window.x * points.w, window.y * points.h, window.w * points.w,
                                      window.h * points.h))
        let left = c.x - c.w / 2, top = c.y - c.h / 2
        let b: Box
        switch piece {
        case .theirs: b = Box(left + c.w * 0.275, top + c.h * 0.08, c.w * 0.55, c.h * 0.16)
        case .mine: b = Box(left + c.w - c.w * 0.225, top + c.h * 0.34, c.w * 0.45, c.h * 0.16)
        case .messageBox: b = Box(c.x, top + c.h - c.h * 0.11, c.w, c.h * 0.22)
        }
        return Box(b.x / points.w, b.y / points.h, b.w / points.w, b.h / points.h)
    }

    enum ChatPiece { case theirs, mine, messageBox }
}
