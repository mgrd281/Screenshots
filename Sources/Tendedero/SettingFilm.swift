import Foundation

/// The short wordless film a setting shows when the pointer rests on its
/// symbol in Settings: a few things on a small stage, each coming in,
/// moving and going at set times, played once. `SettingFilmView` draws it
/// on the Mac; it is kept here as plain values, so every film can be
/// checked on any machine (`SettingFilmTests`).
///
/// The stage is 1 wide and 1 tall whatever its size on screen, its origin
/// at the top left. It shows at 16:10, so a box's `h` is `w * 1.6` for a
/// square. A part's box is its middle and its size, in those units.
struct SettingFilm: Equatable {
    /// The SF Symbol on the row's tile.
    let symbol: String
    let parts: [Part]

    init(_ symbol: String, _ parts: [Part]) {
        self.symbol = symbol
        self.parts = parts
    }

    /// When the last thing has happened: the film rests there.
    var duration: Double { parts.flatMap(\.keys).map(\.t).max() ?? 0 }

    /// Where a box sits on the stage: its middle, then its width and
    /// height, all in stage units.
    struct Box: Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double

        init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    /// One moment of a part: where it is, how much of it shows and how it
    /// leans, in degrees clockwise.
    struct Key: Equatable {
        var t: Double
        var box: Box
        var opacity: Double
        var angle: Double

        init(_ t: Double, _ box: Box, opacity: Double = 1, angle: Double = 0) {
            self.t = t
            self.box = box
            self.opacity = opacity
            self.angle = angle
        }
    }

    /// One thing on the stage and its moments, eased from one to the next.
    /// Before its first moment it is not there; after its last it stays.
    struct Part: Equatable {
        let kind: Kind
        let keys: [Key]

        /// Its place and look at a time, or nil before it comes.
        func state(at t: Double) -> Key? {
            guard let first = keys.first, t >= first.t else { return nil }
            guard let next = keys.firstIndex(where: { $0.t > t }) else { return keys.last }
            let a = keys[next - 1], b = keys[next]
            let span = b.t - a.t
            let p = span <= 0 ? 1 : SettingFilm.ease((t - a.t) / span)
            func mix(_ u: Double, _ v: Double) -> Double { u + (v - u) * p }
            return Key(t, Box(mix(a.box.x, b.box.x), mix(a.box.y, b.box.y), mix(a.box.w, b.box.w),
                              mix(a.box.h, b.box.h)),
                       opacity: mix(a.opacity, b.opacity), angle: mix(a.angle, b.angle))
        }

        /// How long it has been there, for what moves by itself, like a
        /// click's ring spreading.
        func age(at t: Double) -> Double {
            guard let first = keys.first else { return 0 }
            return max(0, t - first.t)
        }
    }

    /// What a part is. Each is drawn small and plain, in the look of the
    /// line styles' tiles in Settings: no words, so a film needs no
    /// translating.
    enum Kind: Equatable {
        /// The wallpaper, filling the stage.
        case desktop
        /// The menu bar along the top, with Snapfly's mark on its right.
        case menuBar
        /// The Dock along the bottom.
        case dock
        /// The black island in the middle of the menu bar.
        case notch
        /// What the photos hang on.
        case line(Line)
        /// A screenshot: a white card with a coloured bar (0, 1 or 2 for
        /// green, purple and orange) and grey lines; covered, its lines
        /// are black.
        case card(Int, covered: Bool = false)
        /// A window of a kind, its content drawn inside.
        case window(Window)
        /// Lines of grey text.
        case text(lines: Int)
        /// A black cover over a private detail.
        case cover
        /// The accent outline smart selection draws round a part.
        case outline
        /// The dashed area a drag chooses.
        case selection
        /// The pointer.
        case cursor
        /// A click's ring, spreading as it fades.
        case click
        /// A key on the keyboard, with its glyph: "⌃", "⌥", "S", "⌘".
        case key(String)
        /// An SF Symbol.
        case symbol(String)
        /// The note above the Dock, a capsule with a check.
        case note
        /// A switch, on or off.
        case toggle(on: Bool)
        /// An iPhone.
        case phone
        /// A chat bubble, yours on the trailing side.
        case bubble(mine: Bool)
        /// The date and time stamped on a screenshot.
        case stamp
        /// A folder.
        case folder
        /// A PDF page.
        case pdf
    }

    enum Line: Equatable {
        case rope, wire, shelf, island, filmstrip
    }

    enum Window: Equatable {
        /// A web page.
        case browser
        /// An AI chat, with its message box at the bottom.
        case chat
        /// An email being written.
        case mail
        /// A letter or a form.
        case document
        /// A Finder window of files.
        case finder
        /// A window of switches, like Settings.
        case settings
    }

    /// Smooth start and end, as the line's own movements have.
    static func ease(_ p: Double) -> Double {
        let p = min(max(p, 0), 1)
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }
}

// MARK: Writing films

extension SettingFilm.Part {
    /// There from `start`, fading in over 0.2 s, until `end`, when it fades
    /// out; without an end it stays.
    static func show(_ kind: SettingFilm.Kind, _ box: SettingFilm.Box, from start: Double = 0,
                     to end: Double? = nil, angle: Double = 0) -> Self {
        var keys = start == 0
            ? [SettingFilm.Key(0, box, angle: angle)]
            : [SettingFilm.Key(start, box, opacity: 0, angle: angle), SettingFilm.Key(start + 0.2, box, angle: angle)]
        if let end, end > start + 0.2 {
            keys.append(SettingFilm.Key(end, box, angle: angle))
            keys.append(SettingFilm.Key(end + 0.2, box, opacity: 0, angle: angle))
        }
        return Self(kind: kind, keys: keys)
    }

    /// From one box to another between two times; it is there, still, from
    /// `appear` (at once by default), and fades out at `leave`.
    static func move(_ kind: SettingFilm.Kind, _ from: SettingFilm.Box, _ to: SettingFilm.Box,
                     start: Double, end: Double, appear: Double? = nil, leave: Double? = nil,
                     angles: (Double, Double) = (0, 0)) -> Self {
        let shown = appear ?? start
        var keys: [SettingFilm.Key] = []
        if shown > 0 {
            keys.append(SettingFilm.Key(shown, from, opacity: 0, angle: angles.0))
            keys.append(SettingFilm.Key(min(shown + 0.2, start), from, angle: angles.0))
        } else {
            keys.append(SettingFilm.Key(0, from, angle: angles.0))
        }
        if start > keys.last!.t { keys.append(SettingFilm.Key(start, from, angle: angles.0)) }
        keys.append(SettingFilm.Key(end, to, angle: angles.1))
        if let leave, leave > end {
            keys.append(SettingFilm.Key(leave, to, angle: angles.1))
            keys.append(SettingFilm.Key(leave + 0.2, to, opacity: 0, angle: angles.1))
        }
        return Self(kind: kind, keys: keys)
    }

    /// The pointer going through points, one move after another, `each`
    /// seconds apart, from `start`.
    static func cursor(_ points: [(Double, Double)], start: Double, each: Double = 0.5) -> Self {
        let size = (0.05, 0.08)
        var keys: [SettingFilm.Key] = []
        for (n, point) in points.enumerated() {
            let box = SettingFilm.Box(point.0, point.1, size.0, size.1)
            let t = start + Double(n) * each
            if n == 0 {
                keys.append(SettingFilm.Key(t, box, opacity: 0))
                keys.append(SettingFilm.Key(t + 0.15, box))
            } else {
                keys.append(SettingFilm.Key(t, box))
            }
        }
        return Self(kind: .cursor, keys: keys)
    }

    /// A click at a point and a time.
    static func click(_ x: Double, _ y: Double, at t: Double) -> Self {
        let box = SettingFilm.Box(x, y, 0.08, 0.128)
        return Self(kind: .click, keys: [SettingFilm.Key(t, box), SettingFilm.Key(t + 0.45, box, opacity: 0)])
    }
}
