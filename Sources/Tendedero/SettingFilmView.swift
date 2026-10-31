import AppKit
import SwiftUI

/// A setting's label in Settings: the tile of its film, then its name and,
/// under it, what it does. The pointer resting on the tile, or a click on
/// it, shows the film.
struct SettingText: View {
    let id: SettingFilm.ID
    let title: String
    let subtitle: Text?

    init(_ id: SettingFilm.ID, _ title: String, _ subtitle: String? = nil) {
        self.init(id, title, subtitle: subtitle.map { Text($0) })
    }

    /// With a subtitle that holds more than words, like a symbol.
    init(_ id: SettingFilm.ID, _ title: String, subtitle: Text?) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FilmTile(id: id, title: title)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    subtitle
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension SettingFilm.ID {
    /// The film of a private detail's switch under Privacy.
    init(_ detail: PrivateDetail) {
        switch detail {
        case .names: self = .detailNames
        case .patientNames: self = .detailPatientNames
        case .otherPeople: self = .detailOtherPeople
        case .addresses: self = .detailAddresses
        case .birthDates: self = .detailBirthDates
        case .emails: self = .detailEmails
        case .phones: self = .detailPhones
        case .bank: self = .detailBank
        case .health: self = .detailHealth
        case .usernames: self = .detailUsernames
        case .faces: self = .detailFaces
        case .ipAddresses: self = .detailIpAddresses
        case .ids: self = .detailIds
        case .codes: self = .detailCodes
        case .keys: self = .detailKeys
        case .barcodes: self = .detailBarcodes
        case .orders: self = .detailOrders
        case .tracking: self = .detailTracking
        case .amounts: self = .detailAmounts
        case .dates: self = .detailDates
        case .links: self = .detailLinks
        case .organizations: self = .detailOrganizations
        }
    }
}

/// The 22 pt ink tile with the setting's symbol, as the sidebar's panes
/// have, that shows the film in a popover.
struct FilmTile: View {
    let id: SettingFilm.ID
    let title: String

    @State private var shown = false
    @State private var waiting: DispatchWorkItem?
    @State private var hovering = false

    /// How long the pointer rests on the tile before the film shows.
    static let delay: TimeInterval = 0.35

    var body: some View {
        let film = SettingFilms.film(id)
        Button {
            waiting?.cancel()
            shown.toggle()
        } label: {
            Image(systemName: film.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(InkTile.glyph)
                .frame(width: 22, height: 22)
                .background(InkTile.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(hovering && !Motion.reduced ? 1.08 : 1)
                .animation(Motion.spring(response: 0.3, damping: 0.8, reduced: Motion.reduced), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            waiting?.cancel()
            guard inside else {
                shown = false
                return
            }
            let work = DispatchWorkItem { shown = true }
            waiting = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        }
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            SettingFilmCard(film: film, title: title)
        }
        .accessibilityLabel(String(format: L("How %@ works"), title))
    }
}

/// The popover: the film, and the setting's name under it.
struct SettingFilmCard: View {
    let film: SettingFilm
    let title: String

    static let size = CGSize(width: 240, height: 150)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingFilmView(film: film)
                .frame(width: Self.size.width, height: Self.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .frame(width: Self.size.width, alignment: .leading)
        }
        .padding(12)
    }
}

/// A film played once from when it shows, resting on its last moment;
/// with Reduce Motion, only its last moment.
struct SettingFilmView: View {
    let film: SettingFilm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done || reduceMotion)) { timeline in
            let t = reduceMotion ? film.duration : min(film.duration, timeline.date.timeIntervalSince(start))
            Canvas { context, size in
                for part in film.parts {
                    guard let state = part.state(at: t), state.opacity > 0.001 else { continue }
                    var layer = context
                    layer.opacity = state.opacity
                    let box = state.box
                    layer.translateBy(x: box.x * size.width, y: box.y * size.height)
                    if state.angle != 0 { layer.rotate(by: .degrees(state.angle)) }
                    let rect = CGRect(x: -box.w * size.width / 2, y: -box.h * size.height / 2,
                                      width: box.w * size.width, height: box.h * size.height)
                    FilmDrawing.draw(part.kind, in: rect, age: part.age(at: t), context: &layer)
                }
            }
        }
        .onAppear {
            start = Date()
            done = false
            DispatchQueue.main.asyncAfter(deadline: .now() + film.duration + 0.1) { done = true }
        }
    }
}

/// How each part of a film is drawn: small and plain, in fixed colours, as
/// the line styles' tiles in Settings draw their wallpaper and cards.
enum FilmDrawing {
    static let wallpaper = Gradient(colors: [
        Color(red: 0.17, green: 0.30, blue: 0.62),
        Color(red: 0.36, green: 0.52, blue: 0.86),
        Color(red: 0.93, green: 0.62, blue: 0.45),
    ])
    static let accents: [Color] = [
        Color(red: 0.18, green: 0.62, blue: 0.36),
        Color(red: 0.48, green: 0.31, blue: 0.88),
        Color(red: 0.89, green: 0.51, blue: 0.17),
    ]
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let paper = Color.white
    static let line = Color(white: 0.86)
    static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)

    static func draw(_ kind: SettingFilm.Kind, in r: CGRect, age: Double, context c: inout GraphicsContext) {
        switch kind {
        case .desktop:
            c.fill(Path(r), with: .linearGradient(wallpaper, startPoint: CGPoint(x: r.minX, y: r.minY),
                                                  endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        case .menuBar:
            c.fill(Path(r), with: .color(.white.opacity(0.32)))
            let dot = r.height * 0.36
            for n in 0..<3 {
                c.fill(Path(roundedRect: CGRect(x: r.minX + 6 + CGFloat(n) * dot * 2.4, y: r.midY - dot / 2,
                                                width: dot * 1.6, height: dot), cornerRadius: dot / 2),
                       with: .color(.white.opacity(0.75)))
            }
            mark(in: CGRect(x: r.maxX - r.height * 2.2, y: r.minY + r.height * 0.15,
                            width: r.height * 1.4, height: r.height * 0.7), context: &c)
        case .dock:
            c.fill(Path(roundedRect: r, cornerRadius: r.height * 0.3, style: .continuous), with: .color(.white.opacity(0.35)))
            let side = r.height * 0.62
            let count = 6
            let gap = (r.width - side * CGFloat(count)) / CGFloat(count + 1)
            let colors: [Color] = [accents[0], blue, accents[1], .gray, accents[2], .red]
            for n in 0..<count {
                let x = r.minX + gap + CGFloat(n) * (side + gap)
                c.fill(Path(roundedRect: CGRect(x: x, y: r.midY - side / 2, width: side, height: side),
                            cornerRadius: side * 0.22, style: .continuous), with: .color(colors[n]))
            }
        case .notch:
            c.fill(Path(roundedRect: r, cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: r.height * 0.45,
                                                                       bottomTrailing: r.height * 0.45, topTrailing: 0)),
                   with: .color(.black))
        case .line(let style):
            drawLine(style, in: r, context: &c)
        case .card(let accent, let covered):
            card(in: r, accent: accents[((accent % 3) + 3) % 3], covered: covered, context: &c)
        case .window(let kind):
            window(kind, in: r, context: &c)
        case .text(let lines):
            textLines(lines, in: r, color: line, context: &c)
        case .cover:
            c.fill(Path(roundedRect: r, cornerRadius: min(2, r.height / 3)), with: .color(ink))
        case .outline:
            c.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(blue), lineWidth: 1.5)
            c.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(blue.opacity(0.08)))
        case .selection:
            // Seen on the wallpaper and on a white page alike.
            c.fill(Path(r), with: .color(blue.opacity(0.12)))
            c.stroke(Path(r), with: .color(blue), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .cursor:
            cursor(at: CGPoint(x: r.midX, y: r.midY), height: r.height, context: &c)
        case .click:
            let p = min(1, age / 0.45)
            let radius = max(r.width, r.height) / 2 * (0.4 + 0.6 * p)
            c.stroke(Path(ellipseIn: CGRect(x: r.midX - radius, y: r.midY - radius, width: radius * 2, height: radius * 2)),
                     with: .color(blue.opacity(1 - p)), lineWidth: 1.5)
        case .key(let glyph):
            var shadow = c
            shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 1, y: 1))
            shadow.fill(Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.22, style: .continuous),
                        with: .color(paper))
            c.draw(Text(verbatim: glyph).font(.system(size: max(6, r.height * 0.5), weight: .semibold))
                    .foregroundColor(ink), at: CGPoint(x: r.midX, y: r.midY))
        case .symbol(let name):
            // Ink, as the tile's, so it reads on the wallpaper and on a page.
            c.fill(Path(ellipseIn: r), with: .color(ink.opacity(0.88)))
            var image = c.resolve(Image(systemName: name))
            image.shading = .color(.white)
            c.draw(image, in: r.insetBy(dx: r.width * 0.22, dy: r.height * 0.22))
        case .note:
            c.fill(Path(roundedRect: r, cornerRadius: r.height / 2, style: .continuous), with: .color(.white.opacity(0.92)))
            let side = r.height * 0.6
            c.fill(Path(ellipseIn: CGRect(x: r.minX + r.height * 0.25, y: r.midY - side / 2, width: side, height: side)),
                   with: .color(accents[0]))
            textLines(1, in: CGRect(x: r.minX + r.height * 1.1, y: r.minY, width: r.width - r.height * 1.6,
                                    height: r.height), color: Color(white: 0.7), context: &c)
        case .toggle(let on):
            c.fill(Path(roundedRect: r, cornerRadius: r.height / 2, style: .continuous),
                   with: .color(on ? accents[0] : Color(white: 0.75)))
            let knob = r.height * 0.82
            let x = on ? r.maxX - knob - r.height * 0.09 : r.minX + r.height * 0.09
            c.fill(Path(ellipseIn: CGRect(x: x, y: r.midY - knob / 2, width: knob, height: knob)), with: .color(.white))
        case .phone:
            c.fill(Path(roundedRect: r, cornerRadius: r.width * 0.18, style: .continuous), with: .color(.black))
            let screen = r.insetBy(dx: r.width * 0.07, dy: r.width * 0.07)
            c.fill(Path(roundedRect: screen, cornerRadius: r.width * 0.13, style: .continuous), with: .color(paper))
            c.fill(Path(roundedRect: CGRect(x: r.midX - r.width * 0.15, y: screen.minY + 2, width: r.width * 0.3,
                                            height: max(2, r.width * 0.07)), cornerRadius: r.width * 0.035),
                   with: .color(.black))
        case .bubble(let mine):
            c.fill(Path(roundedRect: r, cornerRadius: min(r.height / 2, 6), style: .continuous),
                   with: .color(mine ? blue : Color(white: 0.9)))
        case .stamp:
            c.fill(Path(roundedRect: r, cornerRadius: r.height * 0.25, style: .continuous), with: .color(.black.opacity(0.7)))
            c.draw(Text(verbatim: "09:41").font(.system(size: max(5, r.height * 0.55), weight: .semibold).monospacedDigit())
                    .foregroundColor(.white), at: CGPoint(x: r.midX, y: r.midY))
        case .folder:
            var image = c.resolve(Image(systemName: "folder.fill"))
            image.shading = .color(Color(red: 0.36, green: 0.66, blue: 0.96))
            c.draw(image, in: r)
        case .pdf:
            var shadow = c
            shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 1))
            shadow.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(paper))
            c.fill(Path(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.1, width: r.width * 0.4,
                               height: r.height * 0.12)), with: .color(.red))
            textLines(4, in: rect(FilmScene.content(ofPDF: box(r))), color: line, context: &c)
        }
    }

    // MARK: Pieces

    /// Snapfly's mark, small: a line with a card on it.
    private static func mark(in r: CGRect, context c: inout GraphicsContext) {
        var rope = Path()
        rope.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.2))
        rope.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.2),
                          control: CGPoint(x: r.midX, y: r.minY + r.height * 0.45))
        c.stroke(rope, with: .color(.white), lineWidth: 0.8)
        c.fill(Path(roundedRect: CGRect(x: r.midX - r.width * 0.2, y: r.minY + r.height * 0.32, width: r.width * 0.4,
                                        height: r.height * 0.6), cornerRadius: 1), with: .color(.white))
    }

    private static func drawLine(_ style: SettingFilm.Line, in r: CGRect, context c: inout GraphicsContext) {
        switch style {
        case .rope:
            var rope = Path()
            rope.move(to: CGPoint(x: r.minX, y: r.minY))
            rope.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY))
            c.stroke(rope, with: .color(Color(white: 0.25, opacity: 0.8)), lineWidth: 1)
        case .wire:
            var wire = Path()
            wire.move(to: CGPoint(x: r.minX, y: r.midY))
            wire.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            c.stroke(wire, with: .color(Color(white: 0.15, opacity: 0.85)), lineWidth: 0.8)
        case .shelf:
            let path = Path(roundedRect: r, cornerRadius: r.height * 0.3, style: .continuous)
            c.fill(path, with: .color(.white.opacity(0.32)))
            c.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
        case .island:
            c.fill(Path(roundedRect: r, cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: r.height * 0.3,
                                                                       bottomTrailing: r.height * 0.3, topTrailing: 0)),
                   with: .color(.black))
        case .filmstrip:
            c.fill(Path(roundedRect: r, cornerRadius: r.height * 0.1, style: .continuous), with: .color(Color(white: 0.09)))
            let holes = 9
            for i in 0..<holes {
                let x = r.minX + r.width * (CGFloat(i) + 0.5) / CGFloat(holes) - 1.5
                for y in [r.minY + r.height * 0.06, r.maxY - r.height * 0.06 - 2] {
                    c.fill(Path(roundedRect: CGRect(x: x, y: y, width: 3, height: 2), cornerRadius: 0.5),
                           with: .color(Color(white: 0.85)))
                }
            }
        }
    }

    /// A screenshot: a white card, a coloured bar and two lines, black
    /// where it is covered.
    private static func card(in r: CGRect, accent: Color, covered: Bool, context c: inout GraphicsContext) {
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 1))
        shadow.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(paper))
        c.fill(Path(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.16, width: r.width * 0.5,
                           height: max(1.5, r.height * 0.12))), with: .color(accent))
        for row in 0..<2 {
            c.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * (0.42 + 0.2 * CGFloat(row)),
                                            width: r.width * (row == 0 ? 0.72 : 0.5), height: max(1, r.height * 0.1)),
                        cornerRadius: covered ? 1 : 0),
                   with: .color(covered ? ink : line))
        }
    }

    /// A window: its title bar with three dots, and what it shows.
    private static func window(_ kind: SettingFilm.Window, in r: CGRect, context c: inout GraphicsContext) {
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.28), radius: 3, y: 2))
        let shape = Path(roundedRect: r, cornerRadius: 5, style: .continuous)
        shadow.fill(shape, with: .color(paper))
        let bar = min(10, r.height * 0.14)
        c.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: bar),
                    cornerRadii: RectangleCornerRadii(topLeading: 5, bottomLeading: 0, bottomTrailing: 0, topTrailing: 5)),
               with: .color(Color(white: 0.93)))
        for (n, color) in [Color.red, .yellow, .green].enumerated() {
            let d = bar * 0.4
            c.fill(Path(ellipseIn: CGRect(x: r.minX + 4 + CGFloat(n) * d * 1.6, y: r.minY + bar / 2 - d / 2,
                                          width: d, height: d)), with: .color(color.opacity(0.85)))
        }
        let body = rect(FilmScene.content(ofWindow: box(r)))
        switch kind {
        case .browser:
            c.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.3, y: r.minY + bar * 0.2, width: r.width * 0.4,
                                            height: bar * 0.6), cornerRadius: bar * 0.3), with: .color(.white))
            textLines(4, in: body, color: line, context: &c)
        case .chat:
            c.fill(Path(roundedRect: CGRect(x: body.minX, y: body.minY, width: body.width * 0.55, height: body.height * 0.16),
                        cornerRadius: 4), with: .color(Color(white: 0.9)))
            c.fill(Path(roundedRect: CGRect(x: body.maxX - body.width * 0.45, y: body.minY + body.height * 0.26,
                                            width: body.width * 0.45, height: body.height * 0.16), cornerRadius: 4),
                   with: .color(blue.opacity(0.85)))
            let box = CGRect(x: body.minX, y: body.maxY - body.height * 0.22, width: body.width, height: body.height * 0.22)
            c.stroke(Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous),
                     with: .color(Color(white: 0.7)), lineWidth: 0.8)
        case .mail:
            textLines(2, in: CGRect(x: body.minX, y: body.minY, width: body.width * 0.6, height: body.height * 0.25),
                      color: Color(white: 0.75), context: &c)
            textLines(4, in: CGRect(x: body.minX, y: body.minY + body.height * 0.35, width: body.width,
                                    height: body.height * 0.65), color: line, context: &c)
        case .document:
            textLines(6, in: body, color: line, context: &c)
        case .finder:
            let side = min(body.width / 5, body.height / 2.6)
            for row in 0..<2 {
                for col in 0..<4 {
                    let x = body.minX + CGFloat(col) * (body.width / 4) + (body.width / 4 - side) / 2
                    let y = body.minY + CGFloat(row) * side * 1.3
                    var image = c.resolve(Image(systemName: (row + col) % 3 == 0 ? "folder.fill" : "doc.fill"))
                    image.shading = .color((row + col) % 3 == 0 ? Color(red: 0.36, green: 0.66, blue: 0.96)
                                                                 : Color(white: 0.75))
                    c.draw(image, in: CGRect(x: x, y: y, width: side, height: side))
                }
            }
        case .settings:
            for row in 0..<3 {
                let y = body.minY + CGFloat(row) * body.height / 3
                let h = body.height / 3
                textLines(1, in: CGRect(x: body.minX, y: y, width: body.width * 0.6, height: h), color: line, context: &c)
                let knob = CGRect(x: body.maxX - h * 1.3, y: y + h * 0.25, width: h * 1.1, height: h * 0.55)
                draw(.toggle(on: row != 1), in: knob, age: 0, context: &c)
            }
        }
    }

    /// Lines of text where `FilmScene.textRow` says, so a film's covers
    /// land on them.
    private static func textLines(_ count: Int, in r: CGRect, color: Color, context c: inout GraphicsContext) {
        guard count > 0 else { return }
        for n in 0..<count {
            let row = rect(FilmScene.textRow(n, of: count, in: box(r)))
            c.fill(Path(roundedRect: row, cornerRadius: row.height / 2), with: .color(color))
        }
    }

    private static func box(_ r: CGRect) -> SettingFilm.Box {
        SettingFilm.Box(r.midX, r.midY, r.width, r.height)
    }

    private static func rect(_ b: SettingFilm.Box) -> CGRect {
        CGRect(x: b.x - b.w / 2, y: b.y - b.h / 2, width: b.w, height: b.h)
    }

    /// The arrow pointer, its tip at the point.
    private static func cursor(at tip: CGPoint, height: CGFloat, context c: inout GraphicsContext) {
        let s = height / 16
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x, y: tip.y + 14 * s))
        arrow.addLine(to: CGPoint(x: tip.x + 3.6 * s, y: tip.y + 10.8 * s))
        arrow.addLine(to: CGPoint(x: tip.x + 6 * s, y: tip.y + 15.6 * s))
        arrow.addLine(to: CGPoint(x: tip.x + 8 * s, y: tip.y + 14.6 * s))
        arrow.addLine(to: CGPoint(x: tip.x + 5.6 * s, y: tip.y + 10 * s))
        arrow.addLine(to: CGPoint(x: tip.x + 10 * s, y: tip.y + 10 * s))
        arrow.closeSubpath()
        c.fill(arrow, with: .color(.black))
        c.stroke(arrow, with: .color(.white), lineWidth: max(0.6, s))
    }
}
