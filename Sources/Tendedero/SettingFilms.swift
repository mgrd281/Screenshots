import Foundation

extension SettingFilm {
    /// The settings that have a film, one for each row in Settings that
    /// turns on, chooses or does something.
    enum ID: String, CaseIterable {
        case handlesScreenshots, hangsCopiedImages, smartSelection, stampsTime
    }
}

/// Each setting's film. They follow one grammar: the scene as it is, the
/// pointer or a key doing what you would do, then what Snapfly does, held
/// still at the end for a moment.
enum SettingFilms {
    typealias Part = SettingFilm.Part
    typealias Box = SettingFilm.Box

    static func film(_ id: SettingFilm.ID) -> SettingFilm {
        switch id {
        case .handlesScreenshots:
            // ⌘⇧4, a drag over a page, and the screenshot flies to the line
            // instead of the Desktop.
            return SettingFilm("camera.viewfinder", FilmScene.line(cards: 2) + [
                .show(.window(.browser), Box(0.5, 0.64, 0.6, 0.56)),
                .show(.key("⌘"), Box(0.36, 0.5, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⇧"), Box(0.45, 0.5, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("4"), Box(0.54, 0.5, 0.07, 0.11), from: 0.4, to: 0.8),
                .move(.selection, Box(0.4, 0.62, 0.02, 0.03), Box(0.5, 0.66, 0.3, 0.3), start: 1.0, end: 1.4,
                      appear: 1.0, leave: 1.6),
                .cursor([(0.35, 0.51), (0.65, 0.81)], start: 0.9, each: 0.5),
                .move(.card(2), Box(0.5, 0.66, 0.3, 0.3), FilmScene.slot(2), start: 1.8, end: 2.4, appear: 1.7,
                      angles: (0, FilmScene.tilt(2))),
            ])
        case .hangsCopiedImages:
            // A picture copied with ⌘C hangs on the line too.
            return SettingFilm("doc.on.clipboard", FilmScene.line(cards: 1) + [
                .show(.window(.browser), Box(0.5, 0.64, 0.6, 0.56)),
                .show(.card(1), Box(0.42, 0.66, 0.2, 0.24), from: 0.1),
                .show(.outline, Box(0.42, 0.66, 0.22, 0.27), from: 0.6, to: 1.3),
                .show(.key("⌘"), Box(0.62, 0.62, 0.07, 0.11), from: 0.7, to: 1.3),
                .show(.key("C"), Box(0.71, 0.62, 0.07, 0.11), from: 0.8, to: 1.3),
                .move(.card(1), Box(0.42, 0.66, 0.2, 0.24), FilmScene.slot(1), start: 1.5, end: 2.1, appear: 1.4,
                      angles: (0, FilmScene.tilt(1))),
            ])
        case .smartSelection:
            // The part under the pointer is outlined, and a click takes just it.
            return SettingFilm("viewfinder", [FilmScene.desktop, FilmScene.menuBar,
                .show(.window(.browser), Box(0.5, 0.56, 0.72, 0.72)),
                .show(.card(0), Box(0.36, 0.56, 0.2, 0.26)),
                .show(.card(1), Box(0.64, 0.56, 0.2, 0.26)),
                .cursor([(0.2, 0.9), (0.38, 0.6), (0.66, 0.6)], start: 0.1, each: 0.6),
                .show(.outline, Box(0.36, 0.56, 0.22, 0.3), from: 0.7, to: 1.15),
                .show(.outline, Box(0.64, 0.56, 0.22, 0.3), from: 1.3),
                .click(0.66, 0.6, at: 2.0),
                .show(.selection, Box(0.64, 0.56, 0.22, 0.3), from: 2.1),
            ])
        case .stampsTime:
            // The screenshot gets the date and time on it, in a copy beside it.
            return SettingFilm("clock.badge.checkmark", FilmScene.line(cards: 1, of: 2) + [
                .show(.card(1), FilmScene.slot(1, of: 2), from: 0.1, angle: FilmScene.tilt(1)),
                .move(.stamp, Box(0.5, 0.75, 0.16, 0.09), Box(0.76, FilmScene.slot(1, of: 2).y - 0.05, 0.1, 0.05),
                      start: 0.7, end: 1.4, appear: 0.4),
                .show(.symbol("clock"), Box(0.5, 0.62, 0.1, 0.16), from: 0.2, to: 0.6),
            ])
        }
    }
}
